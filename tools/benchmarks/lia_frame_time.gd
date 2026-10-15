extends Node
var session: Session
var game: Game
var rows := []
func distribution(a: Array) -> Dictionary:
	a.sort()
	return {"median":a[a.size()/2],"p95":a[int(a.size()*.95)],"p99":a[int(a.size()*.99)],"max":a.back()}
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	seed(151031)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"vsync":0,"fps_limit":0,"confine_mouse":0,"scroll_border":0,"village_start_view":0,"camera_style":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_HIGH),true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	session=Session.new();add_child(session)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=13.0
	var zone := "gz2h"
	var warm_seconds:=60.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-zone="): zone=arg.trim_prefix("--probe-zone=")
		if arg.begins_with("--warm-seconds="): warm_seconds=float(arg.trim_prefix("--warm-seconds="))
	await session.enter_zone(zone,1,false)
	get_tree().paused=false
	var warm_sim_goal:=session.world.time+warm_seconds
	print("PROFILE_ENTERED ",zone)
	if session.world==null: get_tree().quit(1);return
	var hero:GameUnit=session.party_units(0)[0]
	game.rig.focus(hero.global_position);game.rig.distance=8.0;game.rig.pitch=deg_to_rad(-25)
	game.rig.set_process(false);game.rig._apply()
	Gfx.apply_quality(get_viewport())
	get_window().content_scale_size=Vector2i(2560,1440)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	var vp:=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp,true)
	for frame in 120:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	game.rig.held=false;game.rig._opening_view=null;game.rig.distance=8.0;game.rig.pitch=deg_to_rad(-25);game.rig.yaw=0;game.rig._apply()
	for frame in 30:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	while session.world.time<warm_sim_goal or not game.get_node("SurfaceWeather")._cover_ready:
		await get_tree().process_frame
	var profiler = null
	for mode in ["stationary","orbit"]:
		if profiler: profiler.rows.clear();profiler.enabled=true
		session.world.profile_us.clear();session.world.profile_counts.clear();session.world.profile_slow.clear()
		session.world.profile_simulation=false
		var start:=Time.get_ticks_usec();var last:=start;var sim:=session.world.time
		var wall:=[];var gpu:=[];var cpu:=[];var stalls:=[]
		while Time.get_ticks_usec()-start<10000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec();var elapsed:=(now-last)/1000.0;wall.append(elapsed);last=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			if elapsed>40: stalls.append({"at":(now-start)/1000000.0,"ms":elapsed,"gpu_ms":gpu.back()})
			if mode=="orbit":game.rig.yaw+=elapsed/1000.0*.24;game.rig._apply()
		var row:={"sim_start":sim,"warm_sim_goal":warm_sim_goal,"viewport":str(get_viewport().get_visible_rect().size),"camera":str(game.rig.camera.global_transform),"mode":mode,"zone":zone,"units":session.world.units.size(),"objects":session.world.objects.size(),"hero_dead":hero.dead,"weather_cover_ready":game.get_node("SurfaceWeather")._cover_ready,"weather_cover_cursor":game.get_node("SurfaceWeather")._cover_cursor,"fps":wall.size()*1000000.0/(last-start),"wall_ms":distribution(wall),"gpu_ms":distribution(gpu),"render_cpu_ms":distribution(cpu),"sim_seconds":session.world.time-sim,"profile":profiler.rows.duplicate(true) if profiler else {},"simulation_us":session.world.profile_us.duplicate(),"simulation_slow":session.world.profile_slow.duplicate(),"stalls":stalls}
		if profiler:profiler.enabled=false
		session.world.profile_simulation=false
		rows.append(row);print("LIA_PROFILE ",JSON.stringify(row))
	FileAccess.open("user://lia-profile.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"adapter":RenderingServer.get_video_adapter_name()},"  "))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://scene.png")
	game.queue_free();session.queue_free();await get_tree().process_frame
	get_tree().quit()
