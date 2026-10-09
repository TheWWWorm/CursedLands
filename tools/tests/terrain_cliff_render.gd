extends Node
const Field = preload("res://src/game/fx/terrain_cliff.gd")
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 4) -> void:
	for n in count: await get_tree().process_frame

func snap(view: SubViewport, label: String) -> Image:
	await frames(6); await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8) # Vulkan readbacks can be RGB8.
	image.save_png("user://terrain-cliffs-"+label+".png")
	return image

func difference(a: Image,b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	if aa==bb: return {"changed_pixels":0,"peak_byte_delta":0,"sum":0}
	var changed := 0; var peak := 0; var sum := 0
	for i in range(0,aa.size(),4):
		var delta := 0
		for k in 3: delta = maxi(delta,absi(int(aa[i+k])-int(bb[i+k])))
		if delta: changed += 1
		peak = maxi(peak,delta); sum += delta
	return {"changed_pixels":changed,"peak_byte_delta":peak,"sum":sum}

func site(terrain: EITerrain, field: Field) -> Dictionary:
	var best := -1.0
	var result := {"point":Vector3(terrain.sectors_x*16,10,-terrain.sectors_y*16),"normal":Vector3(0,0,1)}
	if field.admitted==0: return result
	for y in range(8,field.tile_size.y-8):
		for x in range(8,field.tile_size.x-8):
			if field.eligible[y*field.tile_size.x+x]==0: continue
			var i := (y*2+1)*terrain.grid_w+x*2+1
			var normal := terrain.land_n[i]
			var weight := Field.side_weight(normal,field.guards[i]/255.0)
			if weight<0.5: continue
			var coherence := 0.0
			for dy in range(-2,3):
				for dx in range(-2,3):
					if field.eligible[(y+dy)*field.tile_size.x+x+dx]>0:
						var at := ((y+dy)*2+1)*terrain.grid_w+(x+dx)*2+1
						coherence+=Field.side_weight(terrain.land_n[at],field.guards[at]/255.0)
			var score := coherence*weight
			if score>best:
				best=score
				result={"point":field._point(terrain,i),"normal":normal,"tile":Vector2i(x,y),"score":score}
	return result

func scenery(terrain: EITerrain, focus: Vector3, normal: Vector3) -> MeshInstance3D:
	var root := Node3D.new(); terrain.add_child(root)
	var mesh := BoxMesh.new(); mesh.size=Vector3(1.8,1.8,1.8)
	var node := MeshInstance3D.new(); node.mesh=mesh; root.add_child(node)
	node.position=focus+Vector3(normal.x,0,normal.z).normalized()*0.35+Vector3(0,0.7,0)
	var material := ShaderMaterial.new(); material.shader=Gfx.make_shader(EIFigure.OBJECT_SHADER)
	material.set_meta("ground_contact_source",EIFigure.OBJECT_SHADER)
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color(0.45,0.23,0.12))
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(image))
	node.material_override=material
	GroundContact.attach(root,terrain)
	return node

func case(map: String, positive := true) -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	GameData.options.gfx_terrain=1; GameData.options.gfx_terrain_cliffs=0; GameData.options.gfx_ground_contact=1
	var terrain := EITerrain.load_map(map); world.add_child(terrain); world.terrain=terrain; terrain.set_process(false)
	# load_map() builds before the node enters the tree. Install the optional
	# native colour cache now, so both sides compare the same settled backend.
	terrain.apply_gfx()
	if TerrainColorCache.available(): check(is_instance_valid(terrain.color_cache),"cached backend installed before baseline "+map)
	check(terrain._cliffs==null,"disabled option creates no owner "+map)
	var probe := Field.new(terrain)
	check((probe.admitted>0)==positive,"real map identity/slope admission "+map)
	var selected := site(terrain,probe)
	var focus: Vector3=selected.point; var normal: Vector3=selected.normal
	if not positive:
		var x := terrain.sectors_x*16; var y := terrain.sectors_y*16
		focus=Vector3(x,terrain.heights[y*terrain.grid_w+x],-y)
	var direction := Vector3(normal.x,0,normal.z).normalized()
	var camera := Camera3D.new(); view.add_child(camera)
	camera.position=focus+direction*14.0+Vector3(0,7,0); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-30,0); view.add_child(sun)
	Gfx.set_light(Color(0.65,0.65,0.65),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var figure := scenery(terrain,focus,normal)
	var heights := terrain.heights.duplicate(); var xy := terrain.land_xy.duplicate(); var normals := terrain.land_n.duplicate()
	if is_instance_valid(terrain.color_cache): terrain.color_cache.prepare(camera); terrain.color_cache.set_process(false)
	# Native Vulkan specialization of the combined water program is async.
	# Compare settled programs while retaining exact image assertions.
	await frames(180 if "--cliff-composed" in OS.get_cmdline_user_args() else 60)
	var off := await snap(view,map+"-off")
	var draws := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	GameData.options.gfx_terrain_cliffs=1; terrain.apply_gfx(); await frames()
	check(terrain._cliffs!=null,"opt-in creates world-scoped field "+map)
	if terrain._cliffs==null: view.free(); return
	var on := await snap(view,map+"-on")
	var diff := difference(off,on)
	if "--cliff-composed" in OS.get_cmdline_user_args():
		check(terrain._land_mat.shader.code.contains("ei_cloud_sun") and terrain._land_mat.shader.code.contains("caustic_bed"),"cliff source composes with clouds and admitted caustics")
		check(terrain._water_mat.shader.code.contains("water_current") and terrain._water_mat.shader.code.contains("water_wave_field"),"water current and wave combination remains installed")
		check(figure.material_override.shader.code.contains("ei_cloud_sun") and Gfx.on("gfx_materials"),"contact projection composes with cloud and material lighting")
	check(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)==draws,"cliff projection adds no draw calls "+map)
	check(terrain.heights==heights and terrain.land_xy==xy and terrain.land_n==normals,"rendering does not move geometry "+map)
	if positive:
		check(diff.changed_pixels>40 and diff.peak_byte_delta>8,"side projection visible on verified steep rock "+map)
		check(figure.material_override.shader.code.contains("#define EI_TERRAIN_CLIFFS"),"rigid scenery contact compiles shared cliff sampling "+map)
		check(figure.material_override.get_shader_parameter("cliff_tiles")==terrain._cliffs.tiles,"land and contact share same eligibility field "+map)
		var empty := Image.create(terrain._cliffs.tile_size.x,terrain._cliffs.tile_size.y,false,Image.FORMAT_R8)
		terrain._cliffs.tiles.update(empty)
		check(difference(off,await snap(view,map+"-unclassified")).changed_pixels==0,"unsupported tiles preserve exact pixels in enabled source "+map)
		terrain._cliffs.tiles.update(Image.create_from_data(terrain._cliffs.tile_size.x,terrain._cliffs.tile_size.y,false,Image.FORMAT_R8,terrain._cliffs.eligible))
		check(difference(on,await snap(view,map+"-restored")).changed_pixels==0,"restoring static eligibility restores exact pixels "+map)
	else:
		check(diff.changed_pixels==0 and terrain._cliffs.tiles==null and terrain._cliffs.flatness==null,"unverified map remains pixel exact without GPU fields "+map)
		check(not figure.material_override.shader.code.contains("#define EI_TERRAIN_CLIFFS"),"unverified world retains original contact source "+map)
	var cache_count := 0
	if is_instance_valid(terrain.color_cache):
		cache_count=terrain.color_cache._resident.size()
		check(cache_count>0,"native colour cache active in this view "+map)
		for entry: Dictionary in terrain.color_cache._resident.values():
			check(entry.material.shader.code.contains("#define EI_TERRAIN_CLIFFS")==positive,"cached terrain uses matching optional source "+map)
			if positive: check(entry.material.get_shader_parameter("cliff_tiles")==terrain._cliffs.tiles,"cached land shares live projection fields "+map)
	var retired := weakref(terrain._cliffs)
	GameData.options.gfx_terrain_cliffs=0; terrain.apply_gfx(); await frames()
	check(terrain._cliffs==null and retired.get_ref()==null,"disable releases world projection helper "+map)
	check(not figure.material_override.shader.code.contains("#define EI_TERRAIN_CLIFFS"),"disable retires contact shader variants "+map)
	check(difference(off,await snap(view,map+"-disabled")).changed_pixels==0,"disable restores exact original terrain/contact pixels "+map)
	if is_instance_valid(terrain.color_cache):
		for entry: Dictionary in terrain.color_cache._resident.values():
			check(entry.material.get_shader_parameter("cliff_tiles")==null and entry.material.get_shader_parameter("cliff_flatness")==null,"cached material releases old projection textures "+map)
	GameData.options.gfx_terrain=0; terrain.apply_gfx(); await frames()
	var original := await snap(view,map+"-original")
	GameData.options.gfx_terrain_cliffs=1; terrain.apply_gfx()
	check(terrain._cliffs==null,"terrain details dependency suppresses owner "+map)
	check(difference(original,await snap(view,map+"-dependency")).changed_pixels==0,"disabled terrain dependency is pixel exact "+map)
	GameData.options.gfx_terrain=1; terrain.apply_gfx(); await frames()
	var weak := weakref(terrain._cliffs)
	records.append({"map":map,"positive":positive,"site":selected,"difference":diff,"cached_sectors":cache_count,"renderer":RenderingServer.get_current_rendering_method()})
	view.free(); await frames()
	check(weak.get_ref()==null,"world retirement releases projection field "+map)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"gfx_terrain_cliffs":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	if "--cliff-composed" in OS.get_cmdline_user_args():
		for key in ["gfx_materials","gfx_clouds","gfx_weather_surfaces","gfx_water","gfx_water_caustics","gfx_water_current","gfx_water_interaction","gfx_water_waves"]:
			GameData.options[key]=1
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	Gfx.apply_surface_options()
	if "--cliff-compile" in OS.get_cmdline_user_args():
		var land := Gfx.make_shader(Field.CliffShader.source(EITerrain.TERRAIN_SHADER),true,true)
		var contact := Gfx.make_shader(GroundContactShader.source(EIFigure.OBJECT_SHADER,true))
		var caustic := Field.CliffShader.source(EITerrain.WaterCaustics.source(EITerrain.TERRAIN_SHADER))
		var live := Gfx.make_shader(caustic,true,true)
		var cached := Gfx.make_shader(caustic.replace("shader_type spatial;","shader_type spatial;\n#define EI_BAKED_TERRAIN"),true,true)
		check(not land.get_shader_uniform_list().is_empty(),"projected land shader compiles")
		check(not contact.get_shader_uniform_list().is_empty(),"projected contact shader compiles")
		check(not live.get_shader_uniform_list().is_empty(),"projected land with caustics compiles")
		check(not cached.get_shader_uniform_list().is_empty(),"cached projected land with caustics compiles")
		print("CLIFF_COMPILE ",checks," checks ",failures," failures")
		get_tree().quit(1 if failures else 0); return
	RenderingServer.set_render_loop_enabled(true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	if "--cliff-composed" in OS.get_cmdline_user_args():
		await case("zone11")
	elif "--cliff-astral" in OS.get_cmdline_user_args():
		await case("zone26"); await case("zone6",false)
	else:
		await case("zone1"); await case("zone11"); await case("zone15")
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://terrain-cliffs-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":records},"\t"))
	print("TERRAIN_CLIFF_RENDER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
