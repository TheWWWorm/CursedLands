extends Node
## Native DLSS-G regression: copied campaign save, real simulation worker,
## automatic gameplay gating, reload, pause and resume. Use an isolated profile.
var slot := "pt-save-load"
var cycles := 3
var timeout_seconds := 300.0
var output := "user://dlss-framegen-save-load.json"
var session: Session
var game: Game
var phase := "startup"
var started := 0
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var finishing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not finishing and Time.get_ticks_msec() - started > timeout_seconds * 1000.0:
		_check(false, "wall-time limit exceeded in " + phase)
		finishing = true
		_persist()
		get_tree().quit(1)

func _status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}

func _check(ok: bool, label: String) -> bool:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _persist(blocked := false) -> void:
	var result := {"checks":checks, "failures":failures, "blocked":blocked, "rows":rows,
		"phase":phase, "gpu":RenderingServer.get_video_adapter_name(), "facts":RtxGraphics.facts(),
		"status":_status(), "elapsed_ms":Time.get_ticks_msec() - started}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("DLSS_FRAMEGEN_SAVE_LOAD ", JSON.stringify(result))

func _settle(frames: int) -> void:
	for frame in frames: await RenderingServer.frame_post_draw

func _sample(label: String, enabled: bool) -> void:
	phase = label
	# Exercise the autoload's normal pause/campaign gate; never enable the native
	# bridge directly. Allow pending presents and compilation screens to settle.
	await _settle(90)
	var before := _status()
	await _settle(180)
	var after := _status()
	var rendered := int(after.get("game_presents", 0)) - int(before.get("game_presents", 0))
	var presented := int(after.get("presented_frames", 0)) - int(before.get("presented_frames", 0))
	var evaluated := int(after.get("dlss_evaluations", 0)) - int(before.get("dlss_evaluations", 0))
	_check(get_window().has_focus(), label + ": game window has focus")
	_check(rendered >= 175 and rendered <= 185, label + ": game presents continue")
	_check(evaluated >= 175, label + ": DLSS SR continues")
	_check(int(after.get("last_error", -1)) == 0, label + ": SDK reports no error")
	_check(bool(after.get("frame_generation_active", false)) == enabled, label + ": expected DLSS-G activity")
	_check(after.get("present_count_available", false), label + ": SDK presentation count available")
	if enabled:
		_check(presented >= 330 and presented <= 390, label + ": generated frames presented at 2x")
	else:
		_check(presented <= rendered + 5, label + ": paused gameplay produces no extra frames")
	rows.append({"label":label, "enabled":enabled, "game_presents":rendered,
		"presented_frames":presented, "dlss_evaluations":evaluated, "zone":session.zone_id,
		"gate":FsrGraphics.campaign_gate(get_tree(), get_tree().root.get_camera_3d()), "status":after})
	_persist()

func _finish() -> void:
	finishing = true
	phase = "cleanup"
	get_tree().paused = false
	GameData.options.rtx_frame_generation = 0
	await _settle(12)
	if is_instance_valid(session): await session.local_host.stop()
	if is_instance_valid(game): game.queue_free()
	if is_instance_valid(session): session.queue_free()
	await _settle(12)
	_persist()
	get_tree().quit(0 if failures.is_empty() else 1)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-slot="): slot = arg.trim_prefix("--save-slot=")
		elif arg.begins_with("--cycles="): cycles = arg.trim_prefix("--cycles=").to_int()
		elif arg.begins_with("--timeout-seconds="): timeout_seconds = arg.trim_prefix("--timeout-seconds=").to_float()
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	GameData.options.merge({"confine_mouse":0, "show_fps":1, "volume_sfx":0, "volume_stream":0,
		"volume_voice":0, "autosave":0, "auto_graphics":0, "show_tutorial":0,
		"net_lan":0, "net_upnp":0, "net_directory":0, "pt_mode":0,
		"rtx_upscaling":2, "rtx_frame_generation":1, "fsr_upscaling":0, "fsr_frame_generation":0,
		"display_mode":0, "vsync":0}, true)
	GameData._window_state.clear()
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().grab_focus()
	Engine.max_fps = 30
	var facts := RtxGraphics.facts()
	if not facts.sr or not facts.fg or not facts.reflex:
		_persist(true)
		get_tree().quit(2)
		return
	_check(cycles >= 2, "test includes a reload")
	_check(FileAccess.file_exists(SaveInfo.path(slot)), "copied save exists")
	if not failures.is_empty(): await _finish(); return
	# These node paths match the worker's RPC endpoints.
	session = Session.new(); get_parent().add_child(session)
	game = Game.new(); game.session = session; session.game = game; get_parent().add_child(game)
	for cycle in cycles:
		phase = "load-%d" % cycle
		if not _check(await session.load_game_shown(slot), phase + ": save load completes"): break
		if not _check(session.local_host.frontend, phase + ": real simulation worker"): break
		await _sample("loaded-%d" % cycle, true)
		get_tree().paused = true
		await _sample("paused-%d" % cycle, false)
		get_tree().paused = false
		await _sample("resumed-%d" % cycle, true)
		if not failures.is_empty(): break
	await _finish()
