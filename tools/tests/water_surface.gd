extends Node
## Compare the CPU visual query with the actual water vertex shader, not a
## second interpolation implementation. Original assets remain read-only.
const Surface = preload("res://src/game/fx/water_surface.gd")
const SIZE := 64
var checks := 0
var failures := 0
var rows := []
var _linear := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 6) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func colour_source() -> String:
	return """
vec3 output_colour(vec3 c) {
	return OUTPUT_IS_SRGB ? c : mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(0.04045,c));
}
"""

func fixture(terrain: EITerrain, centre: Vector3) -> Dictionary:
	var view := SubViewport.new(); view.size = Vector2i(SIZE,SIZE); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view); view.add_child(terrain); terrain.set_process(false)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(camera); camera.position = centre+Vector3.UP*60
	camera.look_at(centre,Vector3.FORWARD); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.BLACK
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR; view.add_child(env)
	return {"view":view,"camera":camera}

func focus(terrain: EITerrain) -> Vector3:
	var best := Vector3.INF; var score := INF
	var width := terrain.sectors_x*32
	for i in terrain.water.size():
		var h := terrain.water[i]
		if not is_finite(h) or terrain.liquid_ground[i] in [13,14,255]: continue
		var p := Vector2(i%width+0.5,i/width+0.5)
		if h < terrain.height_at(p.x,p.y)+0.15: continue
		var d := p.distance_squared_to(terrain.size_ei()*0.5)
		if d < score: score = d; best = Vector3(p.x,h,-p.y)
	return best

func synthetic() -> void:
	var t := EITerrain.new(); t.sectors_x = 1; t.sectors_y = 1
	t.materials = [{"type":4,"wave":0.0}]
	add_child(t); t.set_process(false)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(1,1,-1),Vector3(3,2,-1),Vector3(1,3,-3),
		Vector3(1,4,-1),Vector3(3,4,-1),Vector3(1,4,-3)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,3,4,5])
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name = "Water_0_0"; node.mesh = mesh; t.add_child(node)
	var surface := Surface.new(t); surface.begin_frame()
	check(is_equal_approx(surface.sample(Vector2(1.5,-1.5)).height,4.0),"highest overlapping triangle owns the surface")
	check(surface.sample(Vector2(4,-4)).is_empty(),"water triangle hole stays empty")
	check(surface.sample(Vector2(-0.2,-0.2)).is_empty(),"negative coordinate is not truncated into cell zero")
	t.water_offsets[0] = 0.75; surface.begin_frame()
	check(is_equal_approx(surface.sample(Vector2(1.5,-1.5)).height,4.75),"scripted offset applied before interpolation")
	var replaced := ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	replaced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); node.mesh = replaced
	surface.begin_frame(); surface.sample(Vector2(1.5,-1.5)) # stale weak source is discarded
	check(is_equal_approx(surface.sample(Vector2(1.5,-1.5)).height,2.5),"replaced water mesh cannot reuse stale triangles")
	t._lava = PackedFloat32Array([1]); surface.begin_frame()
	check(surface.sample(Vector2(1.5,-1.5)).lava,"lava ownership is reported")
	node.mesh = null; replaced = null; mesh = null; surface.begin_frame()
	check(surface.sample(Vector2(1.5,-1.5)).is_empty(),"removed mesh cannot leave a cached water surface")
	surface.clear(); check(surface._sectors.is_empty(),"surface cache is releasable")
	t.free()

func rendered() -> void:
	var t := EITerrain.load_map("zone1")
	check(t != null,"authored zone1 terrain exists")
	if t == null: return
	t.set_process(false)
	var centre := focus(t); check(centre.is_finite(),"exposed non-swamp water found")
	var f := fixture(t,centre)
	var camera: Camera3D = f.camera
	for child in t.get_children():
		if child is EITerrainSector: child.visible = false
	var source := EITerrain.WATER_FX_SHADER.get_slice("vec2 tile_turn",0)
	source = source.replace("render_mode cull_disabled, blend_mix, ambient_light_disabled, depth_draw_always;",
		"render_mode unshaded, cull_disabled, fog_disabled;")
	source += colour_source()+"""
uniform sampler2D expected_height : filter_nearest, repeat_disable;
uniform bool calibration = false;
void fragment() {
	if (calibration) { ALBEDO = output_colour(vec3(0.25,0.5,0.75)); }
	else {
		float h = texture(expected_height,SCREEN_UV).r;
		ALBEDO = output_colour(vec3(min(abs(h-wpos.y)*100.0,1.0),h < -10000.0 ? 1.0 : 0.0,1.0));
	}
}
"""
	var shader := Shader.new(); shader.code = source
	var material := ShaderMaterial.new(); material.shader = shader
	for uniform: Dictionary in shader.get_shader_uniform_list():
		var value: Variant = t._water_mat.get_shader_parameter(uniform.name)
		if value != null: material.set_shader_parameter(uniform.name,value)
	for child in t.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Water_"):
			child.material_override = material
	material.set_shader_parameter("calibration",true); await frames(10)
	var image: Image = f.view.get_texture().get_image()
	var col := image.get_pixel(SIZE/2,SIZE/2)
	_linear = absf(col.r-Color(0.25,0.5,0.75).srgb_to_linear().r)<0.002
	var adjusted := col.linear_to_srgb() if _linear else col
	check(absf(adjusted.r-0.25)<0.003,"capture colour space calibrated")
	material.set_shader_parameter("calibration",false)
	var surface := Surface.new(t)
	var initial_heights := PackedFloat32Array()
	t._water_mat.set_shader_parameter("waves",1.0)
	for mode in ["base","moving","waves-off","offset"]:
		if mode == "moving": t._waves.advance(7.37)
		if mode == "waves-off": t._water_mat.set_shader_parameter("waves",0.0)
		if mode == "offset":
			t._water_mat.set_shader_parameter("waves",1.0)
			for m in t.materials.size(): t.set_water_offset(m,0.35+float(m)*0.08)
		t._update_wave_parameters()
		for name: String in ["wave_phase","wave_ticks","wave_amplitude","wave_gradient","wind","level","waves"]:
			var value: Variant = t._water_mat.get_shader_parameter(name)
			if value != null: material.set_shader_parameter(name,value)
		var held_clock := t._waves.time_ticks()
		surface.begin_frame()
		var expected := PackedFloat32Array(); var present := PackedByteArray()
		var cpu_started := Time.get_ticks_usec()
		for y in SIZE:
			for x in SIZE:
				var ray := camera.project_ray_origin(Vector2(x+0.5,y+0.5))
				var result: Dictionary = surface.sample(Vector2(ray.x,ray.z))
				expected.append(result.get("height",-1000000.0)); present.append(int(not result.is_empty()))
		var query_us := Time.get_ticks_usec()-cpu_started
		var moved_samples := 0
		if mode == "base": initial_heights = expected.duplicate()
		if mode == "moving":
			for i in expected.size():
				if expected[i] > -10000 and initial_heights[i] > -10000 and absf(expected[i]-initial_heights[i]) > 0.00001: moved_samples += 1
			check(moved_samples > 0,"authored wave clock changes the sampled surface")
		material.set_shader_parameter("expected_height",ImageTexture.create_from_image(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RF,expected.to_byte_array())))
		await frames(6); image = f.view.get_texture().get_image()
		check(t._waves.time_ticks() == held_clock,"capture retains the explicit wave clock "+mode)
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(expected.to_byte_array())
		var max_error := 0.0; var missing := 0; var holes := 0; var covered := 0
		for y in range(1,SIZE-1):
			for x in range(1,SIZE-1):
				var c := image.get_pixel(x,y)
				if _linear: c = c.linear_to_srgb()
				if c.b < 0.5:
					holes += int(present[y*SIZE+x]); continue
				covered += 1; missing += int(c.g>0.5); max_error = maxf(max_error,c.r*0.01)
		check(covered > 250,"water pixels rasterized "+mode)
		check(missing == 0 and holes == 0,"query and raster coverage agree "+mode)
		check(max_error < 0.002,"wave/offset surface agrees within 2 mm "+mode)
		rows.append({"mode":mode,"max_height_error_m":max_error,"missing":missing,"holes":holes,"covered":covered,
			"4096_query_us":query_us,"moved_height_samples":moved_samples,"wave_ticks":held_clock,"height_sha256":digest.finish().hex_encode(),"cache_sectors":surface._sectors.size(),"focus":str(centre)})
		image.save_png("user://water-surface-"+mode+".png")
		print("WATER_SURFACE_VIEW ",JSON.stringify(rows.back()))
	f.view.free(); surface = null; await frames(8)

func _ready() -> void:
	Engine.time_scale = 0; process_mode = Node.PROCESS_MODE_ALWAYS
	for key: String in ["gfx_hd_textures","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_terrain","confine_mouse","gfx_volumetric","gfx_ssao","gfx_bloom","vsync"]:
		GameData.options[key] = 0
	GameData.options["gfx_water"] = 1; Gfx.ensure_globals()
	synthetic()
	if DisplayServer.get_name() != "headless":
		Engine.max_fps = 120; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		RenderingServer.set_render_loop_enabled(true)
		await rendered()
	TexUpscale.shutdown(); await get_tree().process_frame
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	FileAccess.open("user://water-surface.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WATER_SURFACE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
