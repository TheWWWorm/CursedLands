extends Node
## Revisit the same saved maps/camera after warming other maps. GPU Lab heavy.
## Live separate-authority frontend, fixed camera, no claim of player replay.
## Per-frame wall times are measured without image readbacks or GPU queries;
## the final completed render timing and screenshot are collected afterward.
var config := {"zones":["gz1h","gz2h","bz5h","gz2h","bz2h","gz1h","gz1d1","gz1h"],
	"width":3840,"height":2160,"warmup_s":3.0,"sample_s":8.0,"options":{}}
var rows := []
var failures := []
var session: Session
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func wall(seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < until: await get_tree().process_frame

func stats(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*.95)],
		"p99":values[int(values.size()*.99)],"max":values.back()}

func persist() -> void:
	var report := {"rows":rows,"failures":failures,"config":config,
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"scope":"Live separate-authority frontend with authored test saves; fixed camera per map, loading/warm-up/readback excluded. No player save, camera route, laptop or native Windows timing equivalence."}
	FileAccess.open("user://pacing-reloads.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func run() -> void:
	if OS.get_cmdline_user_args().has("--validate-only"): get_tree().quit(); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pacing-config="):
			config.merge(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--pacing-config="))),true)
	if GameData.campaign_id != CampaignProfile.ASTRAL or DisplayServer.get_name() == "headless":
		printerr("Requires rendered Lost in Astral"); get_tree().quit(2); return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge(config.options,true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_voice":0,"volume_stream":0,"display_mode":0,
		"fps_limit":0,"vsync":0,"scroll_border":0,"pt_mode":0,"rtx_upscaling":0,"rtx_frame_generation":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"pad_enabled":0},true)
	GameData._apply_window(); Gfx.apply_quality(get_viewport()); Engine.max_fps=0
	await wall(0.5)
	GameData._window_gen += 1
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(config.width,config.height)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	TutorialPanel.auto_show=false
	session=Session.new();get_parent().add_child(session)
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	for cycle in config.zones.size():
		var zone: String = config.zones[cycle]
		var previous: WeakRef = weakref(session.world) if session.world else null
		if not await session.load_game_shown("descriptor-"+zone):
			failures.append("load "+zone); break
		while session.world==null or session._remote_loading or session.loading_game or ShaderCompilationScreen.active():
			await get_tree().process_frame
		# Same world-space view on every visit to this map; presentation remains live.
		game.rig.set_process(false)
		var extent := game.world.terrain.size_ei()
		var at := extent * Vector2(0.22,0.45)
		var focus := Vector3(at.x,game.world.ground_at(at.x,at.y),-at.y)
		game.rig.global_position=focus
		game.rig.camera.global_position=focus+Vector3(0,34,24)
		game.rig.camera.look_at(focus)
		game.set_speed(2)
		await wall(float(config.warmup_s))
		if previous and previous.get_ref()!=null: failures.append("old world retained "+str(cycle))
		var pipelines := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
		var start := Time.get_ticks_usec()
		var last := start
		var frames := []
		while last-start < int(float(config.sample_s)*1000000):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-last)/1000.0)
			last=now
		var row := {"cycle":cycle,"zone":zone,"fps":frames.size()*1000000.0/(last-start),"frames":frames.size(),
			"frame_ms":stats(frames),"over_25ms":frames.filter(func(t):return t>25).size(),
			"over_50ms":frames.filter(func(t):return t>50).size(),"over_100ms":frames.filter(func(t):return t>100).size(),
			"new_draw_pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)-pipelines,
			"worlds":get_tree().get_nodes_in_group(GameWorld.DIAGNOSTIC_GROUP).size(),"old_world_freed":previous==null or previous.get_ref()==null,
			"diagnostics":CrashReport.instance._performance.snapshot("pacing")}
		await RenderingServer.frame_post_draw
		row.last_gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		row.last_render_cpu_ms=RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		row.camera=str(game.rig.camera.global_transform)
		get_viewport().get_texture().get_image().save_png("user://pacing-%02d-%s.png"%[cycle,zone])
		rows.append(row);persist();print("RELOAD_PACING ",JSON.stringify(row))
	await session.local_host.stop()
	game.queue_free();session.queue_free()
	await wall(0.5)
	TexUpscale.shutdown();persist()
	print("RELOAD_PACING_DONE ",rows.size()," loads; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
