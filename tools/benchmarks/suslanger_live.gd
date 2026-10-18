extends Node
## 4K Ultra first-person frontend with the ordinary separate solo authority.
## Run --prepare headlessly once in the same isolated user-data directory.
## GPU queries are optional and excluded from FPS acceptance runs.
## --root-viewport draws directly in the normal game window; --onscreen keeps
## the earlier SubViewport/presentation-copy harness for matched comparisons.
var session: Session
var game: Game
var zone := "gz17h"
var seconds := 30.0
var gpu_queries := false
var onscreen := false
var root_viewport := false
var turn := false
var process_at := 0
var draw_at := 0
var done_at := 0
var frame_parts := {"process_ms":[],"draw_ms":[],"between_ms":[]}
var measuring := false

func process_started() -> void:
	process_at = Time.get_ticks_usec()
	if measuring and done_at > 0: frame_parts.between_ms.append((process_at-done_at)/1000.0)

func draw_started() -> void:
	draw_at = Time.get_ticks_usec()
	if measuring and process_at > 0: frame_parts.process_ms.append((draw_at-process_at)/1000.0)

func draw_finished() -> void:
	done_at = Time.get_ticks_usec()
	if measuring and draw_at > 0: frame_parts.draw_ms.append((done_at-draw_at)/1000.0)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate(); sorted.sort()
	return {"median":sorted[sorted.size()/2], "p95":sorted[int(sorted.size()*0.95)], "p99":sorted[int(sorted.size()*0.99)], "max":sorted.back()}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="): zone = arg.trim_prefix("--zone=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg == "--gpu-queries": gpu_queries = true
		if arg == "--onscreen": onscreen = true
		if arg == "--root-viewport": root_viewport = true; onscreen = true
		if arg == "--turn": turn = true
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"net_websocket":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"control_mode":3,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	if OS.get_cmdline_user_args().has("--prepare"):
		for map: String in ["gz17h","bz14h","bz15h"]:
			seed(15418)
			var source := Session.new(); add_child(source)
			var source_game := Game.new(); source_game.session = source; source.game = source_game; add_child(source_game)
			source.state.ensure_hero(0,"Human Hero"); source.state.world_time = 12
			source._enter_zone(map,1,false)
			source._capture_save_state()
			var slot := "benchmark-"+map
			var error := source.state.save(SaveInfo.path(slot))
			if error != OK: push_error("Fixture save failed: "+str(error)); get_tree().quit(1); return
			SaveInfo.write(slot,source.state.get_var(0,"gtime"),source._allod_id(),map,"Performance fixture")
			source_game.queue_free(); source.queue_free(); await frames(2)
		print("SUSLANGER_LIVE_PREPARED")
		get_tree().quit(); return
	var main := get_parent()
	var target_size := Vector2i(3840,2160)
	var view: Viewport = get_viewport()
	if not root_viewport:
		var offscreen := SubViewport.new(); offscreen.size = target_size; offscreen.own_world_3d = true
		offscreen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		main.add_child(offscreen); reparent(offscreen); view = offscreen
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = target_size if onscreen else Vector2i(320,320)
	if onscreen and not root_viewport:
		var display := TextureRect.new(); display.texture = view.get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main.add_child(display); display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# RPC paths must match the normal worker's /root/Main/Session.
	session = Session.new(); main.add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	var loaded := await session.load_game_shown("benchmark-"+zone)
	var deadline := Time.get_ticks_msec()+60000
	while (session.world == null or session._remote_loading or session.loading_game) and Time.get_ticks_msec() < deadline: await frames(1)
	if not loaded or session.world == null or session._remote_loading or not session.local_host.frontend:
		push_error("Live solo worker did not load the fixture"); await session.local_host.stop(); get_tree().quit(1); return
	var hero: GameUnit = session.world.party_units()[0]
	hero.blocked = false; game.selected.assign([hero]); game.rig.release()
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = target_size if onscreen else Vector2i(320,320)
	game.direct.pointer = false; game.rig._window_focused = true
	var aim := session.world.terrain.size_ei()*0.5-hero.pos
	game.direct.heading = atan2(aim.y,aim.x); game.direct.tilt = -0.12
	game.direct.apply_camera()
	Gfx.apply_quality(view)
	await frames(90)
	get_tree().process_frame.connect(process_started)
	RenderingServer.frame_pre_draw.connect(draw_started)
	RenderingServer.frame_post_draw.connect(draw_finished)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),gpu_queries)
	var intervals := []; var gpu := []; var render_cpu := []; var census := []
	var started := Time.get_ticks_usec(); var previous := started; var next_census := started
	var start_sim := session.world.time
	var start_heading := game.direct.heading
	measuring = true
	while Time.get_ticks_usec()-started < int(seconds*1000000):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if turn: game.direct.heading = start_heading+TAU*(now-started)/float(seconds*1000000)
		intervals.append((now-previous)/1000.0); previous = now
		if gpu_queries:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		if now >= next_census:
			census.append({"wall":(now-started)/1000000.0,"sim":session.world.time,"actors":session.world.units.size(),"hero":str(hero.pos),"dead":hero.dead,"heading":game.direct.heading,"camera":str(game.rig.camera.global_transform.basis)})
			var cache := session.world.terrain.color_cache
			if is_instance_valid(cache):
				census.back().color_cache = {"bytes":cache._bytes,"resident":cache._resident.size(),"jobs":cache._jobs.size(),"built":cache.built,"discarded":cache.discarded}
			print("SUSLANGER_LIVE_CENSUS ",JSON.stringify(census.back()))
			next_census = now+1000000
	var report := {"zone":zone,"options":GameData.options,"size":str(view.get_visible_rect().size),"camera":str(game.rig.camera.global_transform),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"worker":session.local_host.frontend,"gpu_queries":gpu_queries,"wall_seconds":(previous-started)/1000000.0,"start_sim":start_sim,"end_sim":session.world.time,"frame_ms":distribution(intervals),"gpu_ms":distribution(gpu),"render_cpu_ms":distribution(render_cpu),"frames":intervals.size(),"census":census}
	measuring = false
	report.onscreen = onscreen
	report.root_viewport = root_viewport
	report.turn = turn
	report.msaa = view.msaa_3d
	report.render_scale = view.scaling_3d_scale
	report.render_thread = "safe" if RenderingServer.is_on_render_thread() else "separate"
	report.display = OS.get_environment("DISPLAY")
	report.frame_parts = {}
	for part in frame_parts: report.frame_parts[part] = distribution(frame_parts[part])
	FileAccess.open("user://suslanger-live-"+zone+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SUSLANGER_LIVE_RESULT ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("user://suslanger-live-"+zone+".png")
	# Stop command-producing callbacks before the worker disconnects.
	game.direct.set_process(false); game.rig.set_process(false)
	game.set_process(false); session.set_physics_process(false)
	game.direct.stop_move()
	if game.direct._control_id >= 0:
		session.submit({"t":"direct_control","leader":-1})
		game.direct._control_id = -1
	await session.local_host.stop()
	game.free(); session.free(); await frames(4); TexUpscale.shutdown(); get_tree().quit()
