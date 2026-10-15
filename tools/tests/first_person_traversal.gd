extends Node
var s:Session
var g:Game
var cfg:={"save":"","seconds":12.0,"warmup":10.0,"width":3840,"height":2160,"clouds":true}
var rows:=[]
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=100 if "--disable-render-loop" in OS.get_cmdline_args() else -10
	_run.call_deferred()
func _process(_dt:float)->void:
	if g and g.rig:g.rig._window_focused=true
	if "--disable-render-loop" in OS.get_cmdline_args():RenderingServer.force_draw(false)
func key(code:int,on:bool)->void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=on;Input.parse_input_event(e)
func distribution(values:Array)->Dictionary:
	values.sort();var total:=0.0
	for v:float in values:total+=v
	return {"mean":total/values.size(),"p50":values[values.size()/2],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back()}
func seconds(n:float)->void:await get_tree().create_timer(n,true,false,true).timeout
func _run()->void:
	for a:String in OS.get_cmdline_user_args():
		if a.begins_with("--config="):cfg.merge(JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--config="))),true)
	GameData.options.merge(GfxPresets.values(7),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"control_mode":3,"gfx_cloud_shadows":int(cfg.clouds),"gfx_cloud_reflections":int(cfg.clouds)},true)
	GameData.options.merge(cfg.get("options",{}),true)
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var input := FileAccess.open(SaveInfo.path("traversal"),FileAccess.WRITE)
	input.store_buffer(FileAccess.get_file_as_bytes(cfg.save))
	input.close()
	s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	if not await s.load_game_shown("traversal"):printerr("LOAD FAILED");get_tree().quit(1);return
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(cfg.width,cfg.height)
	Gfx.apply_quality(get_viewport())
	var hero:GameUnit=s.party_units(0)[0]
	g.selected.assign([hero]);g.rig.held=false;g.rig._window_focused=true
	var start:=hero.pos;var destination:=Vector2.INF
	for distance:float in [45.0,30.0,20.0,12.0]:
		for angle in 32:
			var p:=start+Vector2.from_angle(float(angle)*TAU/32.0)*distance
			if s.world.nav.direct_line(hero,p):destination=p;break
		if destination!=Vector2.INF:break
	if destination==Vector2.INF:printerr("NO ROUTE");await s.local_host.stop();get_tree().quit(1);return
	await seconds(1.0)
	g.direct.heading=(destination-start).angle();g.direct.tilt=-0.1
	print("TRAVERSAL_ROUTE ",start," ",destination," local=",s.local_host.frontend)
	await seconds(float(cfg.warmup))
	var viewport:=get_viewport().get_viewport_rid();print("BENCH_FRAME_STATE ",Engine.max_fps," ",get_tree().physics_interpolation)
	for phase:String in ["stationary","outward","return"]:
		if phase=="outward":key(KEY_W,true)
		elif phase=="return":key(KEY_W,false);key(KEY_S,true)
		var profiler=load("res://pan_profile.gd") if ResourceLoader.exists("res://pan_profile.gd") else null
		if profiler:profiler.clear()
		var began:=Time.get_ticks_usec();var previous:=began;var wall:=[];var process:=[];var motion:=[];var stalls:=[]
		var origin:=hero.pos;var prevdraw:=hero._drawn
		var pipeline:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
		while previous-began<int(float(cfg.seconds)*1000000):
			await get_tree().process_frame
			var now:=Time.get_ticks_usec();var elapsed:=(now-previous)/1000.0
			wall.append(elapsed);process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0);motion.append(hero._drawn.distance_to(prevdraw))
			if elapsed>25.0:stalls.append({"at":(now-began)/1000000.0,"ms":elapsed,"cpu":process.back()})
			previous=now;prevdraw=hero._drawn
		await RenderingServer.frame_post_draw
		var row:={"phase":phase,"frames":wall.size(),"fps":wall.size()*1000000.0/(previous-began),"frame_ms":distribution(wall),"process_ms":distribution(process),"motion":distribution(motion),"stalls":stalls,"distance":hero.pos.distance_to(origin),"from":str(origin),"to":str(hero.pos),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)-pipeline,"position":str(g.rig.camera.global_position),"camera_active":g.direct.usable(),"viewport":str(get_viewport().get_visible_rect().size)}
		if profiler:row.profile=profiler.snapshot()
		rows.append(row);print("TRAVERSAL ",JSON.stringify(row))
	# Readback is deliberately outside the timed movement phases.
	get_viewport().get_texture().get_image().save_png("user://traversal.png")
	key(KEY_W,false);key(KEY_S,false)
	FileAccess.open("user://traversal.json",FileAccess.WRITE).store_string(JSON.stringify({"config":cfg,"rows":rows,"options":GameData.options,"mods":s.mod_config,"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	g.direct.stop_move();g.direct.set_process(false);g.direct._control_id=-1
	await s.local_host.stop()
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit()
