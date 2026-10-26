extends "path_trace_performance.gd"
func run() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	await frames(2)
	var lia:=GameData.campaign_id==CampaignProfile.ASTRAL
	var visual:=OS.get_cmdline_user_args().has("--e2-visual")
	out="user://live-probe";DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"autosave":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"display_mode":0,"q_aa":0,"q_shadows":2,"gfx_terrain":1,"gfx_ground_contact":0,"gfx_soft_ground":0,"gfx_water_reflections":2,"gfx_depth_of_field":0,"pt_mode":1,"pt_sharc":1,"q_rt_lighting":0,"rtx_upscaling":0,"rtx_frame_generation":0,"net_lan":0,"net_upnp":0,"net_directory":0,"show_tutorial":0},true)
	GameData.resolution_size="1920x1080";get_window().size=Vector2i(1920,1080)
	RenderingServer.set_render_loop_enabled(true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0));s.state.world_time=12;s.state.god_modes[0]=1
	await s.enter_zone("gz2h" if lia else "gz1g",1,false)
	var load_deadline:=Time.get_ticks_msec()+180000
	await frames(4)
	while (ShaderCompilationScreen.active() or ShaderWarmup.last_count==0) and Time.get_ticks_msec()<load_deadline:
		await frames(1)
	check(not ShaderCompilationScreen.active() and ShaderWarmup.last_count>0,"production loading preparation completes before the probe camera")
	g.set_speed(1);t=s.world.terrain;s.world.profile_simulation=true
	g.rig.set_process(false);g.direct.set_process(false);g.hud.hide()
	camera=Camera3D.new();g.add_child(camera);camera.current=true;camera.fov=75
	camera.global_position=Vector3(160.3204,11.8627,-233.2127) if lia else Vector3(90.1453,4.6948,-33.6656)
	camera.rotation=Vector3(-0.1725,-0.18657,0) if lia else Vector3(-0.23,-2.04,0)
	get_window().min_size=Vector2i.ONE;get_window().borderless=true;get_window().size=Vector2i(1920,1080)
	await frames(30);GameData._window_gen+=1;get_window().size=Vector2i(1920,1080);Engine.max_fps=30
	var rt:Node=g.get_node("SceneRaytrace");rt._profile_cpu=true
	check(await ready_snapshot(rt),"live initial PT scene")
	var hero:GameUnit=s.party_heroes()[0]
	var points:=[Vector2(90.1453,33.6656),Vector2(104.22,16.9),Vector2(106.006,20.93),Vector2(126.67,39.748),Vector2(101.64,41.422)]
	var rows:=[];var previous:=Time.get_ticks_usec();var count:=360 if visual else 1800
	for i in count:
		if lia:
			camera.rotation=Vector3(-0.1725,sin(i*0.04)*0.45-0.18657,0)
			camera.global_position=Vector3(160.3204+sin(i*0.02)*15,11.8627,-233.2127-cos(i*0.02)*15)
		else:
			var section:=int(i/450);var p:Vector2=points[section].lerp(points[section+1],float(i%450)/450.0)
			if i%450==0:hero.move_to(points[section+1])
			camera.global_position=Vector3(p.x,t.height_at(p.x,p.y)+1.7,-p.y)
			camera.rotation.y=-2.04+sin(i*0.02)*0.55
		await frames(1);await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();var ms:=(now-previous)/1000.0;previous=now
		var row:={"i":i,"unix_s":Time.get_unix_time_from_system(),"effects":ParticleFx.of(s.world).effects.map(func(e):return e.e.type),"bolts":ParticleFx.of(s.world).bolts.size(),"particle_materials":ParticleFx.of(s.world)._mats.keys(),"sky_flash":Gfx._sky_flash,"color_built":t.color_cache.built if t.color_cache else -1,"ms":ms,"world_time":s.world.time,"position":str(camera.global_position),"hero":str(hero.pos),"stats":rt.stats.duplicate(),"sim":s.world.profile_us.duplicate(),"slow":s.world.profile_slow.duplicate(true),"pipelines":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"textures":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"clouds":str(Gfx._cloud_frame)}
		rows.append(row);s.world.profile_us.clear();s.world.profile_counts.clear();s.world.profile_slow.clear()
		if ms>250:print("E2_LIVE_HITCH ",JSON.stringify(row))
		if visual and i%2==0:
			get_viewport().get_texture().get_image().save_jpg(out.path_join("frame-%04d.jpg"%i),0.92);previous=Time.get_ticks_usec()
		if i%150==0:print("E2_LIVE_PROGRESS ",i," ",s.world.time)
	FileAccess.open(out.path_join("probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"options":GameData.options,"lia":lia,"visual":visual}))
	get_viewport().get_texture().get_image().save_png(out.path_join("final.png"))
	g.queue_free();s.queue_free();await frames(16);TexUpscale.shutdown();print("E2_LIVE complete");get_tree().quit()
