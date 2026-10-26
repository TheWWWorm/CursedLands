extends "path_trace_performance.gd"
func run() -> void:
	out="user://lia-cliffs-dlss";DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"autosave":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"display_mode":0,"q_aa":0,"q_shadows":3,"gfx_terrain":1,"gfx_water_reflections":0,"pt_mode":0,"pt_sharc":1,"q_rt_lighting":0,"rtx_upscaling":4,"rtx_frame_generation":0,"net_lan":0,"net_upnp":0,"net_directory":0,"show_tutorial":0},true)
	RenderingServer.set_render_loop_enabled(true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0));s._enter_zone("gz2h",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.set_process(false);g.rig.set_process(false);g.direct.set_process(false);g.hud.hide();g.hud.process_mode=Node.PROCESS_MODE_DISABLED
	g._update_daylight(false);t=s.world.terrain
	for u:GameUnit in s.world.units.values():u.hide();u.set_process(false);u.set_physics_process(false)
	camera=Camera3D.new();g.add_child(camera);camera.current=true;camera.fov=75
	camera.global_position=Vector3(160.3204,11.8627,-233.2127);camera.rotation=Vector3(-0.1725,-0.18657,0)
	get_window().min_size=Vector2i.ONE;get_window().borderless=true;get_window().size=Vector2i(1920,1080)
	await frames(30)
	GameData._window_gen+=1;get_window().size=Vector2i(1920,1080)
	Engine.max_fps=30
	RtxGraphics.apply_upscaling(get_viewport())
	print("E2_RTX ",JSON.stringify(RtxGraphics.facts()))
	var rt:Node=g.get_node("SceneRaytrace");rt._profile_cpu=true
	var measurements:=[]
	for mode in [1]:
		GameData.options.pt_mode=mode;t.apply_gfx();Gfx.apply_env(g._env);await frames(90)
		if mode:check(await ready_snapshot(rt),"LiA initial PT scene")
		for i in 240:
			camera.rotation=Vector3(-0.1725,sin(i*0.04)*0.45-0.18657,0)
			camera.global_position=Vector3(160.3204+sin(i*0.02)*15,11.8627,-233.2127-cos(i*0.02)*15)
			var start:=Time.get_ticks_usec();await frames(1);await RenderingServer.frame_post_draw
			measurements.append({"mode":mode,"i":i,"ms":(Time.get_ticks_usec()-start)/1000.0,"stats":rt.stats.duplicate(),"rtx":RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}})
			get_viewport().get_texture().get_image().save_jpg(out.path_join("mode%d-%03d.jpg"%[mode,i]),0.92)
	FileAccess.open(out.path_join("probe.json"),FileAccess.WRITE).store_string(JSON.stringify(measurements))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();print("LIA_CLIFF_PROBE complete");get_tree().quit()
