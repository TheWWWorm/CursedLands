extends Node
var view: SubViewport
var camera: Camera3D
var rows := []
var failures := 0
var prior := ""
## Real authored surfaces. Use --before-water=<saved shader> for the baseline;
## --hd mounts an already installed HD Lands 1.5.0 package in a disposable profile.
func frames(n := 12) -> void:
	for i in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
func capture() -> Image:
	await frames()
	return view.get_texture().get_image()
func scene(label: String, name_: String, point: Vector2) -> void:
	var world:=GameWorld.new();view.add_child(world);world.set_process(false);world.set_physics_process(false)
	var map:=EIMapScene.new();world.add_child(map);world.map=map
	var t:=EITerrain.load_map(name_);map.add_child(t);map.terrain=t;world.terrain=t;t.set_process(false)
	# Loading terrain sets border fog again. Suppress it after the load so
	# the near-edge swamp fixture shows the liquid rather than the sky tint.
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	var level:=t.water_at(point.x,point.y);var focus:=Vector3(point.x,level,-point.y)
	t._waves.advance(6.0);t._update_wave_parameters()
	camera.position=focus+Vector3(4,7,7);camera.look_at(focus)
	await frames(40)
	t._water_mat.shader=Gfx.make_shader(prior,true,true)
	var before:=await capture();before.save_png("user://"+label+"-before.png")
	t.apply_gfx()
	var after:=await capture();after.save_png("user://"+label+"-after.png")
	var repeat:=await capture()
	var same:=before.get_data()==after.get_data();var stable:=after.get_data()==repeat.get_data()
	# Frozen game clocks must yield identical frames; advancing the same
	# terrain clock must animate both the ripples and the molten patches.
	t._waves.advance(2.0);t._update_wave_parameters()
	var animated:=await capture()
	var changed_in_time:=after.get_data()!=animated.get_data()
	var ok:=stable and not same and changed_in_time
	if not ok: failures+=1
	rows.append({"scene":label,"map":name_,"point":[point.x,point.y],"water":level,"ground":t.height_at(point.x,point.y),"liquid_type":int(t.liquid_ground[int(point.y)*t.sectors_x*32+int(point.x)]),"atlas_size":t._atlases.get_width(),"identical":same,"stable_repeat":stable,"animated":changed_in_time,"ok":ok})
	print("SURFACE ",JSON.stringify(rows[-1]))
	world.free();await frames(2)
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-water="): prior=FileAccess.get_file_as_string(arg.trim_prefix("--before-water="))
	if prior.is_empty(): printerr("Supply --before-water=<baseline shader>");get_tree().quit(1);return
	if "--hd" in OS.get_cmdline_user_args():
		var error:=ModStore.create_profile("Liquid surface comparison",false,["community.hd-lands-textures@1.5.0"])
		if not error.is_empty():printerr(error);get_tree().quit(1);return
		if not GameData.open(GameData.root).is_empty():get_tree().quit(1);return
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_water":1,"gfx_water_reflections":1,"gfx_water_caustics":1,"gfx_terrain":1,"auto_graphics":0,"q_aa":0,"vsync":0,"confine_mouse":0},true)
	Engine.time_scale=0;Engine.max_fps=120
	Gfx.ensure_globals();Gfx.apply_surface_options();Gfx.set_surface_weather(0,0)
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	view=SubViewport.new();view.size=Vector2i(1280,960);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(view)
	var env:=WorldEnvironment.new();env.environment=Environment.new();Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0.14,0.28,0.36);view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(200,300,0))
	RenderingServer.global_shader_parameter_set(&"ei_sky",Vector3(0.25,0.55,0.7))
	camera=Camera3D.new();camera.far=300;camera.fov=65;view.add_child(camera);camera.current=true
	await scene("swamp-zone1","zone1",Vector2(159.5,12.5))
	await scene("swamp-zone2","zone2",Vector2(87.5,83.5))
	await scene("swamp-zone7","zone7",Vector2(26.5,260.5))
	await scene("swamp-zone9","zone9",Vector2(74.5,218.5))
	await scene("lava-zone10","zone10",Vector2(72.5,75.5))
	await scene("lava-zone16","zone16",Vector2(162.5,14.5))
	await scene("river-zone8","zone8",Vector2(160,142))
	await scene("coast-zone1","zone1",Vector2(89.4,24.14))
	FileAccess.open("user://liquid-surfaces.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"\t"))
	print("LIQUID_SURFACES ",rows.size()," cases ",failures," failures")
	view.free();TexUpscale.shutdown();await frames(3);get_tree().quit(1 if failures else 0)
