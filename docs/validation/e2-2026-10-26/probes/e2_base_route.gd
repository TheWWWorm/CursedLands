extends "path_trace_performance.gd"
func run() -> void:
	GameData.options.merge({"hd_textures": 1, "gfx_materials": 1, "gfx_sharp_units": 1, "gfx_detailed_heads": 1, "gfx_sky": 1, "gfx_far_view": 1, "gfx_terrain": 1, "gfx_wind": 1, "gfx_grass": 1, "gfx_biome_cover": 1, "gfx_vegetation_interaction": 1, "gfx_soft_ground": 0, "gfx_ground_contact": 0, "gfx_terrain_cliffs": 1, "gfx_firelight": 1, "gfx_torch_glow": 1, "gfx_lava_light": 1, "gfx_foliage_light": 1, "gfx_volumetric": 1, "gfx_ssao": 1, "gfx_contact_shadows": 1, "gfx_bloom": 1, "gfx_depth_of_field": 0, "gfx_water": 1, "gfx_water_reflections": 2, "gfx_water_interaction": 1, "gfx_water_caustics": 1, "gfx_water_current": 1, "gfx_water_waves": 1, "gfx_waterfalls": 1, "gfx_ambient_wildlife": 1, "gfx_ambient_particles": 1, "gfx_clouds": 3, "gfx_cloud_shadows": 1, "gfx_cloud_reflections": 1, "gfx_weather_mist": 1, "gfx_weather_surfaces": 1, "gfx_heat_haze": 1, "gfx_soft_particles": 1, "gfx_lit_particles": 1, "gfx_severed_limbs": 1, "gfx_rain_puddles": 1, "q_aa": 0, "q_shadows": 2, "q_aniso": 4, "render_scale": 4, "display_mode": 0, "resolution": 0, "fps_limit": 0, "vsync": 0, "auto_graphics": 0, "fsr_frame_generation": 0, "fsr_quality": 3, "fsr_upscaling": 0, "pt_accumulation": 0, "pt_mode": 1, "pt_sharc": 1, "pt_target_fps": 0, "rtx_frame_generation": 0, "rtx_upscaling": 4, "q_rt_lighting": 0, "confine_mouse": 0, "show_fps": 1, "volume_sfx": 0, "volume_stream": 0, "volume_voice": 0, "autosave": 0, "net_lan": 0, "net_upnp": 0, "net_directory": 0, "show_tutorial": 0},true)
	RenderingServer.set_render_loop_enabled(true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0));s._enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.set_process(false);g.rig.set_process(false);g.direct.set_process(false);g.hud.hide()
	for u:GameUnit in s.world.units.values():u.set_process(false);u.set_physics_process(false)
	g._update_daylight(false);t=s.world.terrain
	camera=Camera3D.new();g.add_child(camera);camera.current=true;camera.fov=75
	camera.global_position=Vector3(90.1453,4.6948,-33.6656);camera.rotation=Vector3(-0.23,-2.04,0)
	await frames(30);GameData._window_gen+=1;get_window().min_size=Vector2i.ONE;get_window().size=Vector2i(1920,1080);Engine.max_fps=30
	RtxGraphics.apply_upscaling(get_viewport());t.apply_gfx();Gfx.apply_env(g._env)
	var rt:Node=g.get_node("SceneRaytrace");rt._profile_cpu=true
	check(await ready_snapshot(rt),"route initial PT scene ready")
	await frames(120)
	var points:=[camera.global_position,Vector3(104.22,4.20,-16.9),Vector3(106.006,3.752,-20.93),Vector3(126.67,7.934,-39.748),Vector3(101.64,5.728,-41.422)]
	var rows:=[];var previous:=Time.get_ticks_usec()
	for section in range(1,points.size()):
		for i in 150:
			camera.global_position=points[section-1].lerp(points[section],(i+1)/150.0)
			camera.rotation.y=-2.04+sin((section*150+i)*0.02)*0.55
			await frames(1);await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();var ms:=(now-previous)/1000.0;previous=now
			var row:={"section":section,"i":i,"ms":ms,"position":str(camera.global_position),"stats":rt.stats.duplicate(),"pipelines":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"textures":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"objects":Performance.get_monitor(Performance.OBJECT_COUNT)}
			rows.append(row)
			if ms>250:print("E2_ROUTE_HITCH ",JSON.stringify(row))
	FileAccess.open("user://e2-route.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"options":GameData.options,"rtx":RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}}))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();print("E2_ROUTE complete");get_tree().quit()
