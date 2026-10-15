extends Node
## Swamp material review in complete authored scenes, using the campaign's
## daylight/night lighting and both the tactical and low camera angles.
var rows := []
var failures := 0
var prior := ""

func frames(n := 12) -> void:
	for i in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func capture(name_: String) -> Image:
	await frames()
	var result := get_viewport().get_texture().get_image()
	if result.save_png("user://" + name_ + ".png") != OK: failures += 1
	return result

func _ready() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-water="): prior = FileAccess.get_file_as_string(arg.trim_prefix("--before-water="))
	if prior.is_empty(): printerr("Supply --before-water=<baseline shader>"); get_tree().quit(1); return
	if "--hd" in OS.get_cmdline_user_args():
		var error := ModStore.create_profile("Swamp water review", false, ["community.hd-lands-textures@1.5.0"])
		if not error.is_empty() or not GameData.open(GameData.root).is_empty(): get_tree().quit(1); return
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH), true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"q_aa":0,"vsync":0,"gfx_water_reflections":2,"gfx_clouds":0,"gfx_weather_mist":0},true)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(1280,960)
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	for site: Array in [["gz1g",Vector2(159.5,12.5)],["gz2g",Vector2(87.5,83.5)]]:
		Engine.time_scale = 1.0
		await s.enter_zone(site[0],1,false)
		s.set_physics_process(false); g.set_process(false); g.world.set_process(false); g.world.set_physics_process(false)
		g.world.vm.briefings._check = INF; g.hud.process_mode=Node.PROCESS_MODE_DISABLED;g.hud.hide(); g.rig.set_process(false)
		var t := g.world.terrain; t.set_process(false)
		var at: Vector2 = site[1]
		var focus := Vector3(at.x,t.water_at(at.x,at.y),-at.y)
		t._waves.advance(6.0); t._update_wave_parameters()
		Engine.time_scale = 0.0
		var camera := g.rig.camera
		for hour in [12,0]:
			s.state.world_time = hour; g._update_daylight(false)
			RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
			for angle in ["overhead","low"]:
				camera.global_position = focus + (Vector3(16,24,20) if angle == "overhead" else Vector3(4,5,8))
				camera.look_at(focus); camera.current = true
				g._update_daylight(false)
				var label: String = "swamp-"+site[0]+"-"+str(hour)+"-"+angle
				RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
				t._water_mat.shader = Gfx.make_shader(prior,true,true)
				var before := await capture(label+"-before")
				t.apply_gfx()
				var after := await capture(label+"-after")
				var changed := before.get_data() != after.get_data()
				if not changed: failures += 1
				rows.append({"scene":label,"hour":hour,"angle":angle,"changed":changed,"objects":g.world.map.object_nodes.size(),"atlas_size":t._atlases.get_width(),"mirror_active":bool(t._water_mat.get_shader_parameter("planar_enabled"))})
				print("SWAMP_SCENE ",JSON.stringify(rows[-1]))
	FileAccess.open("user://swamp-water-scene.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"\t"))
	g.queue_free(); s.queue_free(); await frames(2); TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
