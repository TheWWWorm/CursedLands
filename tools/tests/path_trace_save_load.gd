extends Node
## Run in an isolated profile containing a copied save and its enabled mods.
## Exercises the same frontend/worker loading path as the save menu.
const Device = preload("res://src/game/fx/path_trace_device.gd")
var slot := "pt-save-load"
var expected_driver := "d3d12"
var path_mode := 1
var quality := 0
var cycles := 3
var hold_seconds := 6.0
var timeout_seconds := 240.0
var output := "user://path-trace-save-load.json"
var session: Session
var game: Game
var controller: Node
var phase := "startup"
var started := 0
var heartbeat := 0
var active_frames := 0
var history_reused_frames := 0
var require_history := false
var failures: Array[String] = []
var loads: Array[Dictionary] = []
var finishing := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=102
	started=Time.get_ticks_msec()
	run.call_deferred()

func _process(_delta: float) -> void:
	if finishing: return
	var now := Time.get_ticks_msec()
	if is_instance_valid(controller) and controller.stats.get("active",false):
		active_frames+=1
		if controller.stats.get("history_reused",false): history_reused_frames+=1
	if now>=heartbeat:
		heartbeat=now+2000
		print("PT_SAVE_LOAD_STATE ",JSON.stringify({"phase":phase,"elapsed_ms":now-started,"active_frames":active_frames}))
	if now-started>timeout_seconds*1000:
		failures.append("save-load test exceeded its wall-time limit in "+phase)
		_persist()
		finishing=true
		get_tree().quit(1)

func _check(ok: bool,label: String) -> bool:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _persist() -> void:
	var result := {"driver":RenderingServer.get_current_rendering_driver_name(),
		"path_mode":path_mode,"quality":quality,"loads":loads,"active_frames":active_frames,
		"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PT_SAVE_LOAD_RESULT ",JSON.stringify(result))

func _finish() -> void:
	finishing=true
	phase="cleanup"
	if is_instance_valid(session): await session.local_host.stop()
	if is_instance_valid(game): game.queue_free()
	if is_instance_valid(session): session.queue_free()
	for frame in 12: await get_tree().process_frame
	_persist()
	get_tree().quit(0 if failures.is_empty() else 1)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-slot="): slot=arg.trim_prefix("--save-slot=")
		elif arg.begins_with("--expect-driver="): expected_driver=arg.trim_prefix("--expect-driver=")
		elif arg.begins_with("--pt-mode="): path_mode=arg.trim_prefix("--pt-mode=").to_int()
		elif arg.begins_with("--quality="): quality=arg.trim_prefix("--quality=").to_int()
		elif arg.begins_with("--cycles="): cycles=arg.trim_prefix("--cycles=").to_int()
		elif arg.begins_with("--hold-seconds="): hold_seconds=arg.trim_prefix("--hold-seconds=").to_float()
		elif arg.begins_with("--timeout-seconds="): timeout_seconds=arg.trim_prefix("--timeout-seconds=").to_float()
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg=="--require-history": require_history=true
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,
		"volume_voice":0,"autosave":0,"auto_graphics":0,"show_tutorial":0,
		"net_lan":0,"net_upnp":0,"net_directory":0,"pt_mode":path_mode,"q_rt_lighting":quality},true)
	_check(cycles>=2,"test includes a reload")
	_check(RenderingServer.get_current_rendering_driver_name()==expected_driver,"requested rendering driver is active")
	_check(path_mode==0 or Device.supported(),"requested path tracing is supported")
	_check(FileAccess.file_exists(SaveInfo.path(slot)),"copied save exists in the test profile")
	if not failures.is_empty(): await _finish();return
	# Main/Session and Main/Game match the worker's RPC node paths.
	session=Session.new();get_parent().add_child(session)
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game)
	controller=game.get_node("SceneRaytrace")
	var previous_device := 0
	for cycle in cycles:
		phase="load-%d"%cycle
		var before := Time.get_ticks_msec()
		if not _check(await session.load_game_shown(slot),"save load %d completes"%cycle): break
		if not _check(session.local_host.frontend,"load uses the simulation worker"): break
		phase="trace-%d"%cycle
		if path_mode>0:
			# load_game_shown can return before the controller's next tick retires
			# the old world's output. Wait for the replacement, not stale stats.
			while not controller.stats.get("active",false) or not is_instance_valid(controller.device) \
					or controller.device.get_instance_id()==previous_device:
				await get_tree().process_frame
			_check(controller.stats.get("path_tracing",false),"path tracing becomes active")
			var device_id: int = controller.device.get_instance_id()
			_check(device_id!=previous_device,"load creates a fresh ray-tracing device owner")
			previous_device=device_id
		var frames_before := active_frames
		var history_before := history_reused_frames
		await get_tree().create_timer(hold_seconds,true,false,true).timeout
		if path_mode>0:
			_check(active_frames-frames_before>=3,"traced frames continue after load")
			_check(controller.stats.get("active",false) and controller.device.output_ready(),"traced output remains available")
			if require_history:
				_check(history_reused_frames-history_before>(active_frames-frames_before)/2,"responsive history survives ordinary lighting updates")
		loads.append({"cycle":cycle,"load_and_hold_ms":Time.get_ticks_msec()-before,
			"zone":session.zone_id,"active_frames":active_frames-frames_before,"device":previous_device,
			"history_reused_frames":history_reused_frames-history_before,
			"stats":controller.stats.duplicate(true)})
		_persist()
		if not failures.is_empty(): break
	await _finish()
