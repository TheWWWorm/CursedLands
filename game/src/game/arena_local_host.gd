class_name ArenaLocalHost
extends Node
## Desktop autochess authority owns its frame loop; the owner is a normal
## rendered replica authenticated into seat zero on the loopback connection.
const FRAME_RATE := 60
var session: ArenaOnlineSession
var frontend := false
var worker := false
var solo_combat := false
var starting := false
var owned := false
var owner_peer := 0
var process_id := -1
var parent_id := -1
var _config := ""
var _token := ""
var _generation := 0
var _heartbeat := 0.0
var _owner_seen := 0
var _stopping := false

static func available() -> bool:
	return OS.get_name() in ["Linux", "Windows", "macOS"] \
		and DisplayServer.get_name() != "headless" \
		and not OS.get_cmdline_user_args().has("--ei-inline-host")

func _ready() -> void:
	process_priority = 100   # change animation speed after this frame's world callbacks

func start(port: int, use_websocket: bool, solo := false) -> Error:
	if frontend or worker or starting or session.peer != null: return ERR_ALREADY_IN_USE
	if port < (0 if solo else 1) or port > 65535: return ERR_INVALID_PARAMETER
	solo_combat = solo
	_generation += 1
	var generation := _generation
	_token = Crypto.new().generate_random_bytes(32).hex_encode()
	var directory := ProjectSettings.globalize_path("user://autochess-host")
	DirAccess.make_dir_recursive_absolute(directory)
	_config = directory.path_join("%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()])
	var config := {"token":_token, "parent":OS.get_process_id(), "port":port, "websocket":use_websocket,
		"solo_combat":solo, "password":session.password, "name":session.player_name, "language":RemakeText.lang,
		"options":GameData.options.duplicate(true)}
	# The visible process owns router mapping and its existing status UI.
	config.options.net_upnp = 0
	if solo: config.options.net_lan = 0
	var file := FileAccess.open(_config, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	if OS.get_name() != "Windows": FileAccess.set_unix_permissions(_config, 0x180)
	file.store_var(config); file.close()
	frontend = true; starting = true; owned = false
	session.host_port = port
	process_id = OS.create_process(OS.get_executable_path(), _arguments())
	if process_id <= 0:
		frontend = false; starting = false; cleanup(_config)
		return ERR_CANT_FORK
	var deadline := Time.get_ticks_msec() + 30000
	while generation == _generation and not FileAccess.file_exists(_config + ".ready") \
			and alive() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if generation != _generation: return ERR_SKIP
	var result := ERR_CANT_CREATE
	if FileAccess.file_exists(_config + ".ready"):
		var ready = JSON.parse_string(FileAccess.get_file_as_string(_config + ".ready"))
		if ready is Dictionary:
			result = int(ready.get("error", ERR_CANT_CREATE))
			port = int(ready.get("port", port))
	if result == OK:
		result = session.join(("ws://127.0.0.1:%d" if use_websocket else "127.0.0.1:%d") % port)
		while generation == _generation and result == OK and not owned and alive() and session.peer != null \
				and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if generation != _generation: return ERR_SKIP
		if result == OK and not owned: result = ERR_TIMEOUT
	starting = false
	if result != OK:
		var reaper := stop()
		if reaper: await reaper.tree_exited
		return result as Error
	_token = ""
	# Configuration includes credentials; remove it after the child's read.
	cleanup(_config)
	return OK

func _arguments() -> PackedStringArray:
	var args := PackedStringArray(["--headless", "--render-thread", "safe", "--audio-driver", "Dummy",
		"--max-fps", str(FRAME_RATE), "--log-file", _config + ".log"])
	if OS.has_feature("editor"): args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--ei-path=" + GameData.root, "--autochess-host-config=" + _config])
	return args

func configure(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var config = file.get_var(); file.close()
	if not config is Dictionary or not config.get("token") is String or config.token.length() != 64 \
			or not ArenaRun._integer(config.get("port"), 0 if config.get("solo_combat", false) else 1, 65535) or not config.get("options") is Dictionary:
		return {}
	solo_combat = bool(config.get("solo_combat", false))
	worker = true; _config = path; _token = config.token
	parent_id = int(config.get("parent", -1)); _owner_seen = Time.get_ticks_msec()
	session.player_name = String(config.get("name", "")); session.password = String(config.get("password", ""))
	GameData.options.merge(config.options, true)
	RemakeText.lang = String(config.get("language", "en"))
	Engine.max_fps = FRAME_RATE
	return config

func listening(error: Error) -> void:
	var file := FileAccess.open(_config + ".ready.tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"error":int(error),"port":session.host_port})); file.close()
		DirAccess.rename_absolute(_config + ".ready.tmp", _config + ".ready")

func hello(data: Dictionary) -> void:
	if frontend and starting: data.owner = _token

func may_own(id: int, token: Variant) -> bool:
	if not worker or owner_peer != 0 or not token is String or token != _token: return false
	var address := ""
	if session.peer is ENetMultiplayerPeer:
		var remote := (session.peer as ENetMultiplayerPeer).get_peer(id)
		if remote: address = remote.get_remote_address()
	elif session.peer is WebSocketMultiplayerPeer:
		address = (session.peer as WebSocketMultiplayerPeer).get_peer_address(id)
	return NetStatus._local_address(address)

func claim(id: int) -> void:
	owner_peer = id; _token = ""; _owner_seen = Time.get_ticks_msec()

func welcomed(data: Dictionary) -> void:
	if frontend and starting and data.get("owner", false) == true and session.my_seat == 0:
		owned = true

func packet(id: int, data: Dictionary) -> bool:
	if not worker or id != owner_peer or owner_peer <= 1: return false
	if solo_combat and session.solo_packet(id, data): return true
	if data.t == "owner_alive":
		_owner_seen = Time.get_ticks_msec()
		return true
	return false

func _process(dt: float) -> void:
	if _stopping: return
	_heartbeat += dt / maxf(Engine.time_scale, 0.001)
	if worker and session.game:
		Engine.time_scale = float(session.game.battle_speed) if session.game.run.stage == "fight" else 1.0
	if _heartbeat < 0.25: return
	_heartbeat = 0.0
	if worker:
		var gone := not CrashReport.alive(parent_id) if OS.has_feature("linuxbsd") else Time.get_ticks_msec() - _owner_seen > 120000
		if gone or FileAccess.file_exists(_config + ".stop"):
			shutdown()
	elif frontend and owned:
		if not alive(): session.fail("Connection to the host was lost.")
		else: session._send(1, {"t":"owner_alive"}, false)

func shutdown() -> void:
	if _stopping: return
	_stopping = true
	session.close()
	if session.game:
		session.game.queue_free(); session.game = null
	# Release battles and their native resources before shutting global services.
	for i in 4: await get_tree().process_frame
	get_tree().quit()

func alive() -> bool:
	return process_id > 0 and OS.is_process_running(process_id)

## A root-owned reaper survives removal of this lobby, including cancellation
## during startup. It retains the config until the child exits or is killed.
func stop() -> Node:
	if not frontend: return null
	_generation += 1; frontend = false; starting = false; owned = false; _token = ""
	var reaper := Reaper.new(); reaper.pid = process_id; reaper.config = _config
	process_id = -1
	get_tree().root.add_child(reaper)
	return reaper

static func cleanup(path: String) -> void:
	if path.is_empty(): return
	for suffix in ["", ".ready", ".ready.tmp", ".stop"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _exit_tree() -> void:
	if frontend: stop()
	elif worker: cleanup(_config)

class Reaper extends Node:
	var pid := -1
	var config := ""
	var deadline := 0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		deadline = Time.get_ticks_msec() + 5000
		var file := FileAccess.open(config + ".stop", FileAccess.WRITE)
		if file: file.store_string("stop"); file.close()
	func _process(_dt: float) -> void:
		if pid > 0 and OS.is_process_running(pid):
			if Time.get_ticks_msec() < deadline: return
			OS.kill(pid)
		ArenaLocalHost.cleanup(config); queue_free()
