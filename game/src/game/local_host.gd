class_name LocalHost
extends Node
## An authoritative process and its local player view have
## independent frame loops. The owner occupies player slot zero, not a second
## co-op slot. All other connections retain the ordinary network protocol.

## Headless animation and placement retain their elapsed-time clocks. The
## visible client renders independently, and world logic keeps 55 ms ticks.
const FRAME_RATE := 30

var session: Session
var frontend := false
var worker := false
## Local transport does not turn an offline campaign into a multiplayer game.
var single_player := false
var _single_clock: Array = []
var _single_pause_observer: Node
var owner_peer := 0
var process_id := -1
var parent_id := -1
var camera := {}
var save_bytes := 0
var awaiting_view := false
var _waiting_zone := ""
var _token := ""
var _config := ""
var _ready_owner := false
var _sequence := 0
var _answers := {}
var _heartbeat := 0.0
var _last_camera := {}
var _last_router := {}
var _stopping := false
var _owner_seen := 0
var _owner_world := 0
var _owner_snapshots := {}
var _owner_refresh := 0
var _shot_serial := 0
var _pending_shots := {}
var _capture_requests := {}
var _shot_generation := 0
var _android_backend: Object


static func available() -> bool:
	return (OS.get_name() in ["Linux", "Windows", "macOS"] or (OS.get_name() == "Android" and Engine.has_singleton("EISimulation"))) \
		and DisplayServer.get_name() != "headless" \
		and not OS.get_cmdline_user_args().has("--ei-inline-host")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options_changed.connect(_options_changed)


func start(port: int, limit: int, solo := false) -> Error:
	if frontend or worker or session.online:
		return ERR_ALREADY_IN_USE
	if OS.get_name() == "Android" and not Engine.has_singleton("EISimulation"):
		return ERR_UNAVAILABLE
	single_player = solo
	_single_clock = []
	_shot_generation += 1
	_pending_shots.clear()
	_token = Crypto.new().generate_random_bytes(32).hex_encode()
	var directory := ProjectSettings.globalize_path("user://local-host")
	DirAccess.make_dir_recursive_absolute(directory)
	_config = directory.path_join("%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()])
	var config := {"token": _token, "parent": OS.get_process_id(), "port": port, "single_player": solo,
		"limit": limit, "password": session.password, "name": GameData.player_name,
		"hero": GameData.hero_class, "options": GameData.options.duplicate(true), "mods": session.mod_config.duplicate(true)}
	var file := FileAccess.open(_config, FileAccess.WRITE)
	if file == null:
		single_player = false
		return FileAccess.get_open_error()
	if OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(_config, 0x180)   # owner read/write
	file.store_var(config)
	file.close()
	var arguments := PackedStringArray(["--headless", "--render-thread", "safe", "--audio-driver", "Dummy", "--max-fps", str(FRAME_RATE),
		"--log-file", _config + ".log"])
	if OS.has_feature("editor"):
		arguments.append_array(["--path", ProjectSettings.globalize_path("res://")])
	arguments.append_array(["--", "--ei-path=" + GameData.root, "--local-host-config=" + _config])
	frontend = true
	session.upnp.remote = true
	session.host_port = port
	session.max_players = clampi(limit, 1, Session.MAX_PLAYERS)
	if OS.get_name() == "Android":
		_android_backend = Engine.get_singleton("EISimulation")
		process_id = _android_backend.start(arguments)
	else:
		process_id = OS.create_process(OS.get_executable_path(), arguments)
	if process_id <= 0:
		_cleanup_files()
		frontend = false
		single_player = false
		session.upnp.remote = false
		return ERR_CANT_FORK
	var deadline := Time.get_ticks_msec() + 30000
	while frontend and not _stopping and process_id > 0 and not FileAccess.file_exists(_config + ".ready") and _process_alive() \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result := ERR_CANT_CREATE
	if frontend and not _stopping and FileAccess.file_exists(_config + ".ready"):
		var ready = JSON.parse_string(FileAccess.get_file_as_string(_config + ".ready"))
		if ready is Dictionary:
			result = int(ready.get("error", ERR_CANT_CREATE))
			port = int(ready.get("port", port))
			session.host_port = port
	if result == OK:
		# The worker uses the host's selected transport. Loopback is the only
		# connection permitted to authenticate as the local owner.
		var address := "ws://127.0.0.1:%d" % port if not single_player and GameData.option("net_websocket") else "127.0.0.1"
		result = session.join(address, port)
		while result == OK and frontend and not _stopping and process_id > 0 and not _ready_owner and _process_alive() \
				and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if result == OK and not _ready_owner:
			result = ERR_TIMEOUT
	# A Back/Cancel action owns cleanup while stop() is running. Startup
	# must not connect late, report success, or delete the child's config
	# while that cancellation is still waiting for the child to exit.
	if _stopping:
		return ERR_SKIP
	if not frontend:
		result = ERR_SKIP
	if result != OK:
		await stop()
	_cleanup_files()
	return result as Error


## Called only by the command-line worker entry point, before it listens.
func configure(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var config: Variant = file.get_var()
	file.close()
	if not config is Dictionary or String(config.get("token", "")).length() != 64:
		return {}
	worker = true
	single_player = bool(config.get("single_player", false))
	_owner_seen = Time.get_ticks_msec()
	_config = path
	_token = config.token
	parent_id = int(config.get("parent", -1))
	GameData.player_name = String(config.get("name", "Player"))
	GameData.hero_class = String(config.get("hero", GameData.hero_class))
	GameData.options.merge(config.get("options", {}), true)
	if ModStore.configuration_error(config.get("mods")) != "": return {}
	session.mod_config = config.mods.duplicate(true)
	GameData.difficulty = GameData.option("difficulty")
	session.password = String(config.get("password", ""))
	return config


func listening(error: Error) -> void:
	# Publish the port and status together; the parent's next frame must
	# never observe a newly created but still empty readiness record.
	var pending := _config + ".ready.tmp"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"error": int(error), "port": session.host_port}))
		file.close()
		DirAccess.rename_absolute(pending, _config + ".ready")
	Engine.max_fps = FRAME_RATE


func hello() -> void:
	_rpc_owner.rpc_id(1, _token)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_owner(token: String) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not worker or not session.is_host or owner_peer != 0 or token != _token \
			or not CoopProgress.peer_alive(multiplayer, pid):
		return
	# A remote player knowing a process argument still cannot become owner.
	var address := session.net._address(pid)
	if not NetStatus._local_address(address):
		return
	owner_peer = pid
	_owner_seen = Time.get_ticks_msec()
	var host: Dictionary = session.players[1]
	session.players.erase(1)
	session.players[pid] = host
	session._rpc_mod_config.rpc_id(pid, session.mod_config)
	session._rpc_welcome.rpc_id(pid, 0)
	session._rpc_players.rpc(session.players)
	_rpc_owned.rpc_id(pid)
	session._send_clock(pid)
	session.players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_owned() -> void:
	if not frontend:
		return
	_ready_owner = true
	_token = ""
	if single_player and _single_pause_observer == null:
		var observer := SinglePauseObserver.new()
		observer.owner_host = self
		observer.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(observer)
		_single_pause_observer = observer
	_sync_single_clock()


## The observer has no frame callbacks. Pause notifications deliver the
## change immediately, including menus and controller-wheel pauses.
class SinglePauseObserver extends Node:
	var owner_host: LocalHost
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
			owner_host._sync_single_clock()


func _sync_single_clock() -> void:
	if not frontend or not single_player or not _ready_owner or not CoopProgress.peer_alive(multiplayer, 1):
		return
	var value := [get_tree().paused, Engine.time_scale]
	if value != _single_clock:
		_single_clock = value
		_rpc_single_clock.rpc_id(1, bool(value[0]), float(value[1]))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_single_clock(paused: bool, rate: float) -> void:
	if not single_player or not authorized(multiplayer.get_remote_sender_id()) \
			or not is_finite(rate) or rate <= 0.0 or rate > 8.0:
		return
	Engine.time_scale = rate
	get_tree().paused = paused
	if session.game:
		session.game.speed = int(rate > 1.0)


func authorized(pid: int) -> bool:
	return worker and session.is_host and owner_peer > 1 and pid == owner_peer


func request(command: String, data := {}) -> Dictionary:
	if not frontend or not _ready_owner or not CoopProgress.peer_alive(multiplayer, 1):
		return {"ok": false}
	_sequence += 1
	var serial := _sequence
	_rpc_request.rpc_id(1, serial, command, data)
	var deadline := Time.get_ticks_msec() + 180000
	while not _answers.has(serial) and process_id > 0 and _process_alive() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result: Dictionary = _answers.get(serial, {"ok": false})
	_answers.erase(serial)
	return result


@rpc("authority", "call_remote", "reliable")
func _rpc_answer(serial: int, result: Dictionary) -> void:
	if frontend:
		_answers[serial] = result


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(serial: int, command: String, data: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not authorized(pid):
		return
	var result := {"ok": true}
	match command:
		"campaign":
			await session.new_campaign(bool(data.get("intro", true)))
		"lmp":
			result.ok = session.new_lmp_game(String(data.get("base", "")), String(data.get("quest", "")), int(data.get("pk", 0)))
		"load":
			result.ok = await session.load_game_shown(String(data.get("slot", "")))
		"save":
			camera = data.get("camera", {})
			var frame: Image
			var png: PackedByteArray = data.get("image", PackedByteArray())
			if not png.is_empty():
				frame = Image.new()
				if frame.load_png_from_buffer(png) != OK:
					frame = null
			var error := session.save_game(String(data.get("slot", "")), String(data.get("name", "")), frame)
			result.ok = error in [OK, ERR_BUSY]
			result.queued = error == ERR_BUSY
			result.error = int(error)
			result.notified = error not in [OK, ERR_BUSY, ERR_UNAUTHORIZED, ERR_UNAVAILABLE]
		"measure_save":
			result.bytes = session.save_bytes_needed()
		"clock":
			session.set_coop_clock(int(data.get("sector", -1)))
		"sandbox":
			result.error = session.sandbox_action(str(data.get("action", "")))
			result.ok = result.error == ""
		"lobby":
			session.set_lobby_mode(data)
		"kick":
			result.ok = session.net.kick(int(data.get("pid", 0)), bool(data.get("ban", false)))
		_:
			result.ok = false
	if CoopProgress.peer_alive(multiplayer, pid):
		_rpc_answer.rpc_id(pid, serial, result)


func save(slot: String, save_name: String, frame: Image) -> void:
	var png := PackedByteArray()
	if frame == null and DisplayServer.get_name() != "headless":
		frame = get_viewport().get_texture().get_image()
	if frame and not frame.is_empty():
		frame = frame.duplicate()
		frame.resize(SaveInfo.SHOT_SIZE.x, SaveInfo.SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
		png = frame.save_png_to_buffer()
	var answer := await request("save", {"slot": slot, "name": save_name, "camera": view(), "image": png})
	if not bool(answer.get("ok", false)) and not bool(answer.get("notified", false)):
		session.message.emit(RemakeText.t("Could not save the game."))


func measure_save() -> void:
	var answer := await request("measure_save")
	save_bytes = int(answer.get("bytes", 0))


## Worker-initiated autosaves have no rendered viewport. Capture the owner's
## completed zone after loading, with a per-slot ticket so a newer manual save
## or autosave always wins over a delayed capture.
func saved(slot: String, has_image: bool) -> void:
	if worker and owner_peer > 1 and CoopProgress.peer_alive(multiplayer, owner_peer):
		_shot_serial += 1
		if has_image:
			_capture_requests.erase(slot)
		else:
			_capture_requests[slot] = {"serial": _shot_serial, "zone": session.zone_id}
		_rpc_save_shot.rpc_id(owner_peer, slot, session.zone_id, _shot_serial, not has_image)


@rpc("authority", "call_remote", "reliable")
func _rpc_save_shot(slot: String, zone: String, serial: int, needed: bool) -> void:
	if not frontend:
		return
	_pending_shots[slot] = serial
	if not needed or DisplayServer.get_name() == "headless":
		return
	var generation := _shot_generation
	var deadline := Time.get_ticks_msec() + 120000
	while frontend and not _stopping and _shot_generation == generation \
			and _pending_shots.get(slot) == serial and Time.get_ticks_msec() < deadline:
		if session.world and session.zone_id == zone and not session.loading_game \
				and not session._remote_loading and not session._zone_holding and LoadingScreen._current == null:
			break
		await get_tree().process_frame
	if not _shot_current(slot, zone, serial, generation):
		return
	# LoadingScreen can disappear after this frame's picture was submitted.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _shot_current(slot, zone, serial, generation):
		var frame := get_viewport().get_texture().get_image()
		if frame and not frame.is_empty():
			frame.resize(SaveInfo.SHOT_SIZE.x, SaveInfo.SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
			_rpc_save_shot_image.rpc_id(1, slot, zone, serial, frame.save_png_to_buffer())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_save_shot_image(slot: String, zone: String, serial: int, png: PackedByteArray) -> void:
	if not authorized(multiplayer.get_remote_sender_id()):
		return
	var ticket: Dictionary = _capture_requests.get(slot, {})
	if ticket.get("serial", -1) != serial or ticket.get("zone", "") != zone \
			or session.zone_id != zone or png.size() > 1024 * 1024:
		return
	var frame := Image.new()
	if frame.load_png_from_buffer(png) != OK or frame.get_size() != SaveInfo.SHOT_SIZE:
		return
	# Only the authority writes the image. A newer manual save can invalidate
	# this ticket before its cancellation message reaches the visible process.
	SaveInfo.write_shot_image(slot, frame)
	_capture_requests.erase(slot)


func _shot_current(slot: String, zone: String, serial: int, generation: int) -> bool:
	return frontend and not _stopping and _shot_generation == generation \
		and _pending_shots.get(slot) == serial and session.world != null \
		and session.zone_id == zone and not session.loading_game and not session._remote_loading \
		and not session._zone_holding and LoadingScreen._current == null


func restore_view(pose: Dictionary) -> void:
	if not frontend or session.game == null:
		return
	camera = pose
	_last_camera = pose
	if session.game.rig:
		session.game.rig.set_pose(pose)
	if session.game.hud and session.game.hud.minimap:
		session.game.hud.minimap.zoom = float(pose.get("minimap_zoom", 1.0))


## Loading must not advance an unseen host's party. The owner's reliable
## loaded acknowledgement also covers ordinary travel, not just save loads.
func publishing_zone() -> void:
	if not worker or not session.lmp.is_empty() or owner_peer <= 1 or session.world == null:
		return
	awaiting_view = true
	_waiting_zone = session.zone_id
	session.world.process_mode = Node.PROCESS_MODE_DISABLED


func zone_loaded(pid: int, zone: String) -> void:
	if authorized(pid) and awaiting_view and zone == _waiting_zone and session.world:
		awaiting_view = false
		_waiting_zone = ""
		session.world._frame_ms = -1
		session.world.process_mode = Node.PROCESS_MODE_PAUSABLE


func view() -> Dictionary:
	if session.game == null or session.game.rig == null:
		return {}
	var out := session.game.rig.pose()
	if session.game.hud and session.game.hud.minimap:
		out.minimap_zoom = session.game.hud.minimap.zoom
	return out


func _options_changed() -> void:
	if frontend and _ready_owner:
		_rpc_options.rpc_id(1, GameData.options)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_options(options: Dictionary) -> void:
	if authorized(multiplayer.get_remote_sender_id()):
		for key in options:
			if not ModSchema.RULES.has(key): GameData.options[key] = options[key]
		GameData.difficulty = GameData.option("difficulty")
		GameData.options_changed.emit()
		Engine.max_fps = FRAME_RATE


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_camera(pose: Dictionary) -> void:
	if authorized(multiplayer.get_remote_sender_id()) and not session.loading_game:
		camera = pose


func _process(dt: float) -> void:
	_sync_single_clock()
	if worker:
		_send_owner_snapshots()
	_heartbeat += dt
	if _heartbeat < 0.25:
		return
	_heartbeat = 0.0
	if worker:
		if _owner_gone():
			GameData.trace("local simulation owner exited")
			get_tree().quit()
		_send_router()
	elif frontend and _ready_owner and CoopProgress.peer_alive(multiplayer, 1):
		_rpc_alive.rpc_id(1)
		if session.world and not session.loading_game:
			var pose := view()
			if pose != _last_camera:
				_last_camera = pose
				_rpc_camera.rpc_id(1, pose)


func _owner_gone() -> bool:
	# Cold zone/shader builds pump ENet but cannot run the owner's frame
	# heartbeat. A live local process must not lose its authority merely
	# because that build takes longer than two minutes on a slower device.
	if parent_id > 0 and (OS.has_feature("linuxbsd") or
			(OS.has_feature("android") and Engine.has_singleton("EISimulation"))):
		return not CrashReport.alive(parent_id)
	return Time.get_ticks_msec() - _owner_seen > 120000


## The local view receives its controlled units after each worker frame,
## including commands while paused. The ordinary world snapshot RPC carries
## both streams, with per-actor sequence checks rejecting older arrivals.
## Periodic resends recover loss.
func _send_owner_snapshots() -> void:
	if not worker or owner_peer <= 1 or not session.online or not session.is_host \
			or session.world == null or session.loading_game or awaiting_view \
			or session.movie_active() or not session.lmp.is_empty() \
			or not CoopProgress.peer_alive(multiplayer, owner_peer):
		return
	var w := session.world
	if _owner_world != w.get_instance_id():
		_owner_world = w.get_instance_id()
		_owner_snapshots.clear()
		_owner_refresh = 0
	var now := Time.get_ticks_msec()
	var refresh := now >= _owner_refresh
	if refresh:
		_owner_refresh = now + 250
	var current := {}
	var snaps := []
	for u: GameUnit in w.party_units():
		if u.controller != 0:
			continue
		var sn := u.snapshot()
		current[u.uid] = sn
		if refresh or _owner_snapshots.get(u.uid) != sn:
			snaps.append(sn)
	_owner_snapshots = current
	if not snaps.is_empty():
		session._send_snapshot_records(snaps, w.time, owner_peer)


func _send_router() -> void:
	if owner_peer <= 1 or not CoopProgress.peer_alive(multiplayer, owner_peer):
		return
	var state := {}
	for key in ["port", "external_ip", "external_port", "mapped", "busy", "status", "method"]:
		state[key] = session.upnp.get(key)
	if state != _last_router:
		_last_router = state
		_rpc_router.rpc_id(owner_peer, state)


@rpc("authority", "call_remote", "reliable")
func _rpc_router(state: Dictionary) -> void:
	if not frontend:
		return
	var old_status := session.upnp.status
	for key in ["port", "external_ip", "external_port", "mapped", "busy", "status", "method"]:
		if state.has(key): session.upnp.set(key, state[key])
	if not session.upnp.busy and session.upnp.status != "" and session.upnp.status != old_status:
		session.upnp.finished.emit(session.upnp.mapped, session.upnp.status)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_alive() -> void:
	if authorized(multiplayer.get_remote_sender_id()):
		_owner_seen = Time.get_ticks_msec()


func stop() -> void:
	if not frontend or _stopping:
		return
	_stopping = true
	_shot_generation += 1
	_pending_shots.clear()
	if _ready_owner and CoopProgress.peer_alive(multiplayer, 1):
		_rpc_shutdown.rpc_id(1)
		session._flush_load_notice()
	var deadline := Time.get_ticks_msec() + 5000
	while process_id > 0 and _process_alive() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if process_id > 0 and _process_alive():
		if _android_backend: _android_backend.stop(process_id)
		else: OS.kill(process_id)
	process_id = -1
	frontend = false
	_ready_owner = false
	session.upnp.close()
	session.upnp.remote = false
	session.online = false
	single_player = false
	_single_clock = []
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_stopping = false
	_cleanup_files()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_shutdown() -> void:
	if authorized(multiplayer.get_remote_sender_id()):
		session.coop.flush()
		session.net.bye()
		get_tree().quit()


func _cleanup_files() -> void:
	if _config.is_empty():
		return
	for path in [_config, _config + ".ready", _config + ".ready.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _exit_tree() -> void:
	# A normal exit awaits stop(). On a process/window exit the parent
	# watchdog also covers a frontend that cannot run another frame.
	if frontend and _ready_owner and CoopProgress.peer_alive(multiplayer, 1):
		_rpc_shutdown.rpc_id(1)
		session._flush_load_notice()
	_cleanup_files()


func _process_alive() -> bool:
	if process_id <= 0:
		return false
	return bool(_android_backend.is_running(process_id)) if _android_backend else OS.is_process_running(process_id)


func _notification(what: int) -> void:
	if worker and what == NOTIFICATION_APPLICATION_RESUMED:
		_owner_seen = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_PAUSED and OS.get_name() == "Android" \
			and worker and single_player and session and session.world and not session.loading_game:
		# Android suspends this service with its owner. The owner's focus-out
		# save RPC can still be queued, so persist authority before suspension
		# instead of depending on the app surviving until the next resume.
		# The service stops its frame loop itself. Do not also pause the tree:
		# the owner's unchanged clock would not be resent after resuming, so
		# a different focus/lifecycle ordering could leave simulation frozen.
		session.save_game("autosave")
