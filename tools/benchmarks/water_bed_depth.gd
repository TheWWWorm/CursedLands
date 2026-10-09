extends Node
## Falsify conservative coverage/depth before using it to light the bed.
## Oracle: actual original land triangles and the validated deformed-water query.
const Field = preload("res://src/game/fx/water_caustics.gd")
const Surface = preload("res://src/game/fx/water_surface.gd")
const SIZE := 96
var rows := []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 8) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func focus(t: EITerrain, slope: bool) -> Vector3:
	var best := Vector3.INF; var score := -INF; var width := t.sectors_x*32
	for i in t.water.size():
		if not is_finite(t.water[i]) or t.liquid_ground[i] in [13,14,255]: continue
		var p := Vector2(i%width+0.5,i/width+0.5)
		if t.water[i] < t.height_at(p.x,p.y)+0.15: continue
		var candidate := -p.distance_squared_to(t.size_ei()*0.5)
		if slope:
			var a := t.water_at(p.x+1.0,p.y); var b := t.water_at(p.x,p.y+1.0)
			if not is_finite(a) or not is_finite(b): continue
			candidate = maxf(absf(a-t.water[i]),absf(b-t.water[i]))
		if candidate > score: score = candidate; best = Vector3(p.x,t.water[i],-p.y)
	return best

func ground_copy(t: EITerrain) -> EITerrain:
	var ground := EITerrain.new(); ground.sectors_x = t.sectors_x; ground.sectors_y = t.sectors_y
	add_child(ground); ground.set_process(false); ground.visible = false
	for sector in t.get_children():
		if not sector is EITerrainSector: continue
		var node := MeshInstance3D.new(); node.name = String(sector.name).replace("Sector_","Water_")
		node.mesh = sector._parts[0].mesh; ground.add_child(node)
	return ground

func probe(map_name: String) -> void:
	var view := SubViewport.new(); view.size = Vector2i(SIZE,SIZE); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(view)
	var t := EITerrain.load_map(map_name); view.add_child(t); t.set_process(false)
	var started := Time.get_ticks_usec(); var field := Field.new(t); var field_us := Time.get_ticks_usec()-started
	check(field.tiles > 0,"real water metadata is present")
	var ground := ground_copy(t)
	var land := Surface.new(ground); var water := Surface.new(t)
	var shader_source := EITerrain.TERRAIN_SHADER.get_slice("void fragment() {",0)
	shader_source = shader_source.replace("render_mode cull_disabled, ambient_light_disabled;","render_mode unshaded, cull_disabled, fog_disabled;")
	shader_source = shader_source.replace("void vertex() {",Field.SOURCE+"\nvarying vec3 bed_normal;\nvoid vertex() {")
	shader_source = shader_source.replace("\tei_e = COLOR.rgb;","\tbed_normal = MODEL_NORMAL_MATRIX*NORMAL;\n\tei_e = COLOR.rgb;")
	shader_source += """
uniform sampler2D expected_depth : filter_nearest, repeat_disable;
vec3 output_colour(vec3 c) {
	return OUTPUT_IS_SRGB ? c : mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(0.04045,c));
}
void fragment() {
	float expected = texture(expected_depth,SCREEN_UV).r;
	vec2 bed = terrain_bed(wpos);
	float amount = bed.x*smoothstep(0.6,0.85,normalize(bed_normal).y);
	float lit = amount > 0.02 ? 1.0 : 0.0;
	float leak = lit > 0.5 && expected <= 0.0 ? 1.0 : 0.0;
	float error = bed.y > -1000.0 && expected > -1000.0 ? min(abs(bed.y-expected)*4.0,1.0) : 0.0;
	ALBEDO = output_colour(vec3(leak,lit,error));
}
"""
	var shader := Gfx.make_shader(shader_source,false,true)
	var material := ShaderMaterial.new(); material.shader = shader
	for u: Dictionary in shader.get_shader_uniform_list():
		var value: Variant = t._land_mat.get_shader_parameter(u.name)
		if value != null: material.set_shader_parameter(u.name,value)
	material.set_shader_parameter("caustic_bed",field.texture)
	for node in t.get_children():
		if node is EITerrainSector: node.set_surface_override_material(0,material)
		if node is MeshInstance3D and String(node.name).begins_with("Water_"): node.visible = false
	var env := WorldEnvironment.new(); env.environment = Environment.new(); view.add_child(env)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.BLACK
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 12.0; camera.far = 200
	view.add_child(camera); camera.current = true
	var foci := [focus(t,false),focus(t,true)]
	for steep: bool in [false,true]:
		var centre: Vector3 = foci[int(steep)]; check(centre.is_finite(),"eligible focus exists")
		if not centre.is_finite(): continue
		camera.position = centre+Vector3.UP*80; camera.look_at(centre,Vector3.FORWARD)
		for mode: String in ["rest","wind","raised","lowered"]:
			t._waves = EIWaterWaves.new()
			if mode != "rest": t._waves.set_wind(Vector3(1,1,1),1.0); t._waves.advance(9.17 if mode != "lowered" else 27.42)
			for m in t.materials.size(): t.set_water_offset(m,0.65 if mode == "raised" else (-0.65 if mode == "lowered" else 0.0))
			material.set_shader_parameter("level",t._level)
			water.begin_frame(); land.begin_frame()
			var expected := PackedFloat32Array(); expected.resize(SIZE*SIZE)
			for y in SIZE:
				for x in SIZE:
					var origin := camera.project_ray_origin(Vector2(x+0.5,y+0.5))
					var p := Vector2(origin.x,origin.z); var bed := land.sample(p); var top := water.sample(p)
					expected[y*SIZE+x] = float(top.height)-float(bed.height) if not top.is_empty() and not bed.is_empty() else -10000.0
			material.set_shader_parameter("expected_depth",ImageTexture.create_from_image(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RF,expected.to_byte_array())))
			for conservative: bool in [true]:
				await frames(12)
				var image := view.get_texture().get_image(); var leaks := 0; var lit := 0; var worst_dry := 0.0; var max_error := 0.0
				for y in range(1,SIZE-1):
					for x in range(1,SIZE-1):
						var c := image.get_pixel(x,y)
						lit += int(c.g > 0.5); leaks += int(c.r > 0.5)
						if c.r > 0.5: worst_dry = minf(worst_dry,expected[y*SIZE+x])
						max_error = maxf(max_error,c.b*0.25)
				var label := "%s-%s-%s-%s" % [map_name,"slope" if steep else "centre",mode,str(conservative)]
				image.save_png("user://bed-depth-"+label+".png")
				rows.append({"label":label,"lit_pixels":lit,"dry_leaks":leaks,"most_negative_receiver_depth":worst_dry,
					"max_depth_error_m_capped":max_error,"focus":str(centre),"field_bytes":field.bytes,"field_tiles":field.tiles,"field_admitted":field.admitted,"field_build_us":field_us})
				print("BED_DEPTH ",JSON.stringify(rows.back()))
				check(lit > 20,"depth diagnostic is not empty "+label)
				check(leaks == 0,"no light reaches dry receivers "+label)
	view.free(); ground.free(); field = null; await frames(8)

func _ready() -> void:
	var map_name := "zone1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bed-map="): map_name = a.trim_prefix("--bed-map=")
	for k: String in ["gfx_hd_textures","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_terrain","confine_mouse","gfx_volumetric","gfx_ssao","gfx_bloom","gfx_water_interaction","gfx_water_caustics","vsync"]: GameData.options[k] = 0
	GameData.options["fps_limit"] = 3; Engine.max_fps = 120; Engine.time_scale = 0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	await probe(map_name)
	TexUpscale.shutdown(); await frames(16)
	FileAccess.open("user://water-bed-depth.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")+"\n")
	get_tree().quit(1 if failures else 0)
