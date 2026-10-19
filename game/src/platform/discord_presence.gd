extends Node
## Optional local Discord Rich Presence. The public application ID is supplied
## by the distributor or EI_DISCORD_APP_ID; no token or account access is used.
const MAX_FRAME := 65528
const UPDATE_SECONDS := 15.0
var application_id := ""
var transport: RefCounted
var rpc_ready := false
var incoming := PackedByteArray()
var outgoing := PackedByteArray()
var desired: Dictionary = {}
var sent: Dictionary = {}
var next_connect := 0.0
var connected_at := 0.0
var last_send := -INF
var sample_at := 0.0
var started := int(Time.get_unix_time_from_system())
var nonce := 0
var active := false
var test_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	application_id = OS.get_environment("EI_DISCORD_APP_ID").strip_edges()
	if application_id.is_empty(): application_id = str(ProjectSettings.get_setting("discord/application_id", "")).strip_edges()
	active = DisplayServer.get_name() != "headless" and OS.get_name() in ["Windows", "Linux"] \
		and not Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--tool=") or arg.contains("-host-config="))
	if ClassDB.class_exists("DiscordIpc"): transport = ClassDB.instantiate("DiscordIpc")

static func valid_id(value: String) -> bool:
	return value.length() >= 17 and value.length() <= 20 and value.is_valid_int() and value.lstrip("0123456789").is_empty()

static func activity_text(value: String) -> String:
	# Discord limits these fields in UTF-8 bytes, including localized names.
	var text := value.left(128)
	while text.to_utf8_buffer().size() > 128:
		text = text.left(text.length() - 1)
	return text

func _process(_dt: float) -> void:
	if not active or transport == null: return
	var now := Time.get_ticks_msec() / 1000.0
	if GameData.option("discord_presence") != 1 or not valid_id(application_id):
		if transport.is_open():
			if rpc_ready: _activity({})
			_flush()
			_disconnect(now)
		return
	if not test_mode and now >= sample_at:
		sample_at = now + 2.0
		desired = current_activity()
	if not transport.is_open():
		if now < next_connect: return
		next_connect = now + 15.0
		for path: String in ipc_paths():
			if transport.open(path):
				connected_at = now; rpc_ready = false; incoming.clear(); outgoing.clear(); sent.clear()
				_send(0, {"v":1,"client_id":application_id}); break
		if not transport.is_open(): return
	_flush()
	var bytes: PackedByteArray = transport.read_bytes()
	if not transport.is_open(): _disconnect(now); return
	incoming.append_array(bytes)
	if incoming.size() > MAX_FRAME + 8: _disconnect(now); return
	while incoming.size() >= 8:
		var opcode := incoming.decode_u32(0)
		var length := incoming.decode_u32(4)
		if length > MAX_FRAME: _disconnect(now); return
		if incoming.size() < length + 8: break
		var payload := incoming.slice(8, length + 8)
		incoming = incoming.slice(length + 8)
		if opcode == 3: _send_bytes(4, payload)
		elif opcode == 2: _disconnect(now); return
		elif opcode == 1:
			var data = JSON.parse_string(payload.get_string_from_utf8())
			if not data is Dictionary: _disconnect(now); return
			if data.get("evt") == "READY": rpc_ready = true
			elif data.get("evt") == "ERROR": _disconnect(now); return
		else: _disconnect(now); return
	if not rpc_ready and now - connected_at > 10.0: _disconnect(now); return
	if rpc_ready and desired != sent and now - last_send >= UPDATE_SECONDS:
		_activity(desired);sent = desired.duplicate(true);last_send = now
	_flush()

func _send(opcode: int, value: Dictionary) -> void:
	_send_bytes(opcode, JSON.stringify(value).to_utf8_buffer())

func _send_bytes(opcode: int, bytes: PackedByteArray) -> void:
	if bytes.size() > MAX_FRAME or outgoing.size() + bytes.size() + 8 > MAX_FRAME + 8:
		_disconnect(Time.get_ticks_msec() / 1000.0); return
	var header := PackedByteArray();header.resize(8);header.encode_u32(0,opcode);header.encode_u32(4,bytes.size())
	outgoing.append_array(header);outgoing.append_array(bytes)

func _activity(value: Dictionary) -> void:
	nonce += 1
	_send(1, {"cmd":"SET_ACTIVITY", "args":{"pid":OS.get_process_id(),"activity":null if value.is_empty() else value},"nonce":str(nonce)})

func _flush() -> void:
	if outgoing.is_empty(): return
	var count: int = transport.write_bytes(outgoing)
	if count > 0: outgoing = outgoing.slice(count)
	elif count < 0: _disconnect(Time.get_ticks_msec() / 1000.0)

func _disconnect(now: float) -> void:
	if transport: transport.close()
	rpc_ready = false;incoming.clear();outgoing.clear();sent.clear();last_send = -INF;next_connect = now + 15.0

func _exit_tree() -> void:
	if transport and transport.is_open():
		if rpc_ready: _activity({});_flush()
		transport.close()

static func ipc_paths() -> Array[String]:
	var paths: Array[String] = []
	if OS.get_name() == "Windows":
		for i in 10: paths.append("\\\\?\\pipe\\discord-ipc-%d" % i)
	else:
		var roots: Array[String] = []
		for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
			var value := OS.get_environment(key)
			if value.is_absolute_path() and value not in roots: roots.append(value)
		if "/tmp" not in roots: roots.append("/tmp")
		for root: String in roots:
			for folder: String in [root, root.path_join("app/com.discordapp.Discord")]:
				for i in 10: paths.append(folder.path_join("discord-ipc-%d" % i))
	return paths

func current_activity() -> Dictionary:
	var details := RemakeText.t("Main menu")
	var state := ""
	var scene := get_tree().current_scene
	if scene:
		for node: Node in scene.get_children():
			if node.is_queued_for_deletion(): continue
			if node is Game and node.session:
				var s: Session = node.session
				details = RemakeText.t("Multiplayer" if not s.lmp.is_empty() else "Co-op campaign" if s.multiplayer_game else "Campaign")
				state = GameData.text("zone " + s.zone_id).get_slice("\n", 0).strip_edges()
				if get_tree().paused: state = (state + " · " if not state.is_empty() else "") + RemakeText.t("Paused")
				break
			if node is ArenaPveScreen:
				details = RemakeText.t("Trials of the Allods")
				var phase := "Battle" if node.run.stage == "fight" else "Preparation"
				if node.run.stage == "won": phase = "Victory"
				elif node.run.stage == "lost": phase = "Defeat"
				state = RemakeText.t("Round %d") % node.run.wave + " · " + RemakeText.t(phase)
				if node.network_play: details += " · " + RemakeText.t("Multiplayer")
				break
	var result := {"details":activity_text(details),"timestamps":{"start":started},"instance":false}
	if not state.is_empty(): result.state = activity_text(state)
	return result
