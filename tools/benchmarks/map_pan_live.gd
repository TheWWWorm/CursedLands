extends Node
## Live top-down pacing through the production camera controller. Synthetic
## bound pan keys retain smoothing, terrain clearance and scenery fading.
## World/session physics remain active; this is not deterministic replay.
var config := {"zone":"gz1g", "preset":7, "seconds":12.0, "warmup":12.0, "width":3840, "height":2160}
var rows := []
var session: Session
var game: Game

func distribution(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for v: float in values: total += v
	return {"mean":total/values.size(), "median":values[values.size()/2], "p95":values[int(values.size()*.95)], "p99":values[int(values.size()*.99)], "max":values.back()}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

var pressed_key := 0
func key(action: String) -> void:
	var code := 0
	EIKeymap._tables()
	for scan: int in EIKeymap._active_map():
		if EIKeymap._active_map()[scan] == action: code = int(EIKeymap._code_of.get(scan,0)); break
	if code == pressed_key: return
	for pair in [[pressed_key,false],[code,true]]:
		if not pair[0]: continue
		var event := InputEventKey.new()
		event.keycode = pair[0]; event.physical_keycode = pair[0]; event.pressed = pair[1]
		Input.parse_input_event(event)
	pressed_key = code

func reset_camera() -> void:
	key("")
	var extent := game.world.terrain.size_ei()
	var at := Vector2(extent.x*.22,extent.y*.45)
	game.rig._free = true; game.rig.distance = 42.0; game.rig.yaw = 0.0
	game.rig.focus(Vector3(at.x,game.world.ground_at(at.x,at.y),-at.y))
	game.rig._window_focused = true

func pose(phase: String, seconds: float) -> void:
	game.rig._window_focused = true
	key("" if phase == "stationary" else ("camera_right" if fmod(seconds,8.0)<4.0 else "camera_left"))

func frames(seconds: float) -> void:
	var end := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec()<end: await get_tree().process_frame

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pan-config="):
			config.merge(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--pan-config="))),true)
	seed(151015)
	GameData.options.merge(GfxPresets.values(int(config.preset)),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"village_start_view":0},true)
	GameData.options.merge(config.get("options",{}),true)
	Engine.max_fps=0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(config.width,config.height)
	session=Session.new(); add_child(session)
	game=Game.new(); game.session=session; session.game=game; add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0)); session.state.world_time=12.0
	await session.enter_zone(String(config.zone),1,false)
	game.world.vm.briefings._check=INF
	game.rig.set_process(true)
	if config.get("hide_hud",false): game.hud.hide();game.hud.process_mode=Node.PROCESS_MODE_DISABLED
	if config.get("terrain_shadows",true)==false: game.sun.shadow_caster_mask &= ~EITerrain.SHADOW_RECEIVER_LAYER
	Gfx.apply_quality(get_viewport())
	reset_camera()
	pose("stationary",0.0)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp,true)
	await frames(float(config.warmup))
	for phase: String in config.get("phases",["stationary","first_pan","repeat_pan"]):
		reset_camera()
		pose("stationary",0.0)
		await frames(1.0)
		var profiler = load("res://pan_profile.gd") if ResourceLoader.exists("res://pan_profile.gd") else null
		if profiler: profiler.clear()
		var pipelines := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
		var mesh_pipelines := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
		var world_start := game.world.time
		var low := game.rig.global_position; var high := low
		var start := Time.get_ticks_usec(); var previous := start
		var walls := [];var processes := [];var physics := [];var stalls := []
		while previous-start < int(float(config.seconds)*1000000):
			pose(phase,(previous-start)/1000000.0)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var elapsed := (now-previous)/1000.0
			walls.append(elapsed)
			var cpu := Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
			processes.append(cpu);physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
			if elapsed>25.0: stalls.append({"at":(now-start)/1000000.0,"ms":elapsed,"process_ms":cpu})
			low = low.min(game.rig.global_position); high = high.max(game.rig.global_position)
			previous=now
		await RenderingServer.frame_post_draw
		var row := {"phase":phase,"frames":walls.size(),"fps":walls.size()*1000000.0/(previous-start),"frame_ms":distribution(walls),"process_ms":distribution(processes),"physics_ms":distribution(physics),"stalls_over_25ms":stalls,"draw_pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)-pipelines,"mesh_pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)-mesh_pipelines,"last_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"last_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"draw_calls":RenderingServer.viewport_get_render_info(vp,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		row["simulated_seconds"] = game.world.time-world_start
		row["camera_extent"] = str(high-low)
		row["fade_meshes"] = game.rig._fade._faces.size() if game.rig._fade else 0
		if profiler: row["profile"] = profiler.snapshot()
		rows.append(row); print("MAP_PAN ",JSON.stringify(row))
		get_viewport().get_texture().get_image().save_png("user://"+phase+".png")
	var report := {"config":config,"version":ProjectSettings.get_setting("application/config/version"),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport().get_visible_rect().size),"render_scale":get_viewport().scaling_3d_scale,"options":GameData.options,"units":game.world.units.size(),"objects":game.world.objects.size(),"rows":rows,"scope":"live v1: world/session physics active; production camera controller driven by synthetic bound pan key presses, including smoothing, ground clearance and camera fading"}
	FileAccess.open("user://map-pan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_PAN_DONE")
	key("")
	game.queue_free();session.queue_free();await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit()
