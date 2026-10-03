class_name NetStatus
extends Node
## Co-op players' status, chat and join / leave messages (child of Session).
##
## From the original:
## - Join / leave lines: textslmp.res "string lmp_player_connected" «Player %s
##   connected to the game», lmp_player_disconnected «Player %s left the
##   game», lmp_player_lost_connection «Player %s lost connection with the
##   server», lmp_player_kicked, lmp_player_banned (formatter
##   cases 0..4; the LMP server sends them as text messages
## ). Losing the server: "string disconnect_msg".
## - Chat: the LMP server relays a player's text to everyone as
##   "^<colour>" + name + "^7: " + text (format; the
##   colour index is the player record's). Here the name is drawn in the
##   player's colour (Quake colour codes 1..4 by player slot, **approx.**: the
##   original's colour assignment is not traced) and ": text" in the text window's
##   default colour; the lines go to the HUD text window. **Approx.**: the
##   original's receiver keeps its own chat list
##   at most 12 lines, wrapped at 0x30c px, ^0..^7 as RGB bits; that overlay is
##   not ported. The input line is (ui/chat_line.gd).
## - Status: the village screen of a network game has a player strip
##   ((464,0)-(800,160)): 56 px cells right to left, the status
##   line «lmp_status_zone / _base / _camp / _connect». Ping
##   is only in the server browser (lmp_connection_6 «Ping:»). The remake
##   shows a small player list (name, ping, status) in every zone of an
##   online game (remake-only, ui/player_list.gd).

signal chat(player_index: int, player_name: String, text: String)
signal status_changed
## Client: the host turned this join down (title, text); the connection closes.
signal refused(title: String, text: String)

const CHAT_MAX := 200   # under 200 characters
const STATUS_EVERY := 1.0
## Quake colour codes (^1 red ^2 green ^3 yellow ^4 blue ^5 cyan ^6 magenta ^7 white).
const COLOURS := [Color(1, 0.3, 0.3), Color(0.35, 1, 0.35), Color(1, 1, 0.35), Color(0.45, 0.6, 1),
	Color(0.35, 1, 1), Color(1, 0.4, 1), Color(1, 1, 1)]

var session: Session
## pid -> {"ping": ms, "state": "connect" | "zone" | "base" | "lag"} (host fills, clients receive).
var status := {}
var _loaded := {}       # host: pid -> zone the peer reported built
var _leaving := {}      # host: pids that said goodbye
var _said := {}         # host: pid -> [times of recent lines] (flood limit)
var _t := 0.0
var _last_sent := {}
var _host_left := false
var _rtt := {}          # host: pid -> smoothed round trip of _rpc_ping (ms)
var _loaded_at := {}    # host: pid -> when it reported its zone built (ticks ms)

static var _lmp: EIResArchive
static var _lmp_tried := false
static var _world_hash := ""
static var _hash_task := -1
var _refused := false


## textslmp.res "string <key>" with %s = `arg`, or `fallback` without that file.
static func lmp_text(key: String, arg := "", fallback := "") -> String:
	if not _lmp_tried:
		_lmp_tried = true
		if GameData.is_open():
			var p := GameData.res_path("textslmp.res")
			if GameFiles.exists(p):
				_lmp = EIResArchive.open_path(p)
	var t := ""
	if _lmp:
		var b := _lmp.read("string " + key)
		if not b.is_empty():
			t = EIText.ansi(b).replace("\r", "").strip_edges()
	if t.is_empty():
		t = fallback
	return t.replace("%s", arg) if t.contains("%s") else t


static func colour(player_index: int) -> Color:
	return COLOURS[clampi(player_index, 0, Session.MAX_PLAYERS - 1)]


# ================================================================ join / leave

func joined_text(player_name: String) -> String:
	return lmp_text("lmp_player_connected", player_name, "Player %s connected to the game")


## Host: the line for a peer that is gone (said goodbye = left, else lost).
func gone_text(pid: int, player_name: String) -> String:
	if _leaving.has(pid):
		_leaving.erase(pid)
		return lmp_text("lmp_player_disconnected", player_name, "Player %s left the game")
	return lmp_text("lmp_player_lost_connection", player_name, "Player %s lost connection with the server")


## "" when the host said it was leaving (its own line came already) or
## turned the join down (its own box came already).
func server_lost_text() -> String:
	if _host_left or _refused:
		return ""
	return lmp_text("disconnect_msg", "", "Game interrupted: either the server is switched off or you are experiencing connection problems")


## Leaving to the menu: tell the others it is on purpose (sent at once).
func bye() -> void:
	if session == null or not session.online or not multiplayer.has_multiplayer_peer():
		return
	if session.is_host:
		_rpc_bye_all.rpc()
	else:
		_rpc_bye.rpc_id(1)
	var enet := NetSim.enet_of(multiplayer)
	if multiplayer.multiplayer_peer is NetSim:
		(multiplayer.multiplayer_peer as NetSim).flush_now()
	if enet and enet.host:
		enet.host.flush()


## Client leaving (main menu): a joiner who brought its hero waits (up to
## `secs`) for the host's last progress package, so what it did in the last
## seconds (a purchase…) reaches its merged save; then the goodbye is final.
func leave(secs := 3.0) -> void:
	if session == null or not session.online or session.is_host or not session.coop.brings() \
			or not multiplayer.has_multiplayer_peer():
		bye()
		return
	var n := session.coop.merged_count
	bye()
	var t0 := Time.get_ticks_msec()
	while session.coop.merged_count == n and Time.get_ticks_msec() - t0 < secs * 1000.0 \
			and multiplayer.has_multiplayer_peer() and is_inside_tree():
		await get_tree().process_frame


@rpc("any_peer", "call_remote", "reliable")
func _rpc_bye() -> void:
	if session.is_host:
		var pid := multiplayer.get_remote_sender_id()
		_leaving[pid] = true
		# Its last progress package (the joiner waits for it, leave()), then
		# the connection goes after a moment even if the game just closed.
		session.coop._sent_hash.clear()
		session.coop.send_all()
		get_tree().create_timer(BYE_DROP).timeout.connect(func():
			if not is_inside_tree() or not session.players.has(pid):
				return   # gone already (the joiner closed its side)
			if multiplayer.has_multiplayer_peer() and pid in multiplayer.get_peers():
				(multiplayer as SceneMultiplayer).disconnect_peer(pid)
			# (no peer_disconnected signal for a peer dropped here)
			session.coop._on_peer_gone(pid)
			session._on_peer_disconnected(pid))

const BYE_DROP := 4.0   # seconds the host keeps a leaving joiner's connection


@rpc("authority", "call_remote", "reliable")
func _rpc_bye_all() -> void:
	_host_left = true
	var host_name := "host"
	for p in session.players.values():
		if int(p.index) == 0:
			host_name = String(p.name)
	session.message.emit(lmp_text("lmp_player_disconnected", host_name, "Player %s left the game"))


func forget(pid: int) -> void:
	status.erase(pid)
	_rtt.erase(pid)
	_loaded.erase(pid)
	_said.erase(pid)


# ================================================================ chat

## Local player's line (Enter in the game view).
func say(text: String) -> void:
	text = clean(text)
	if text.is_empty() or session == null or not session.online:
		return
	if session.is_host:
		_relay(1, text)
	else:
		_rpc_say.rpc_id(1, text)


static func clean(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.unicode_at(0) >= 32:
			out += c
	return out.left(CHAT_MAX)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_say(text: String) -> void:
	if session.is_host:
		_relay(multiplayer.get_remote_sender_id(), clean(text))


func _relay(pid: int, text: String) -> void:
	var p: Dictionary = session.players.get(pid, {})
	if p.is_empty() or text.is_empty():
		return
	var now := Time.get_ticks_msec()
	var recent: Array = (_said.get(pid, []) as Array).filter(func(t): return now - int(t) < 4000)
	if recent.size() >= 6:   # flood limit (remake)
		return
	recent.append(now)
	_said[pid] = recent
	_rpc_chat.rpc(int(p.index), String(p.name), text)


@rpc("authority", "call_local", "reliable")
func _rpc_chat(idx: int, player_name: String, text: String) -> void:
	chat.emit(idx, player_name, clean(text))


# ================================================================ join check
# the original refuses a join with «lmp_server_full» (connect reply reason 1
# ) and a server of another protocol version with
# «lmp_wrong_protocol» / «lmp_wrong_protocol_msg» (the server
# list row's flag; the compared value is not traced). Remake: the joiner's
# hello carries PROTOCOL and world_hash(); the host answers a refusal and
# drops the connection.

## Remake co-op protocol; raise it when the messages change incompatibly.
const PROTOCOL := 2
const CoopDb := preload("res://src/game/coop_db.gd")


func _ready() -> void:
	_start_world_hash()
	# Remake (CoopDb): a joiner takes the host's database numbers.
	multiplayer.connected_to_server.connect(send_db_digests)


## Joiner: its table digests to the host (on connecting, and again after it
## switched to the multiplayer database, Session._rpc_lmp). "#lmp" says which
## database they are of; the host answers only digests of the one it plays.
func send_db_digests() -> void:
	if session.is_host or not session.online:
		return
	var d := CoopDb.digests()
	d["#lmp"] = GameData.lmp_db
	_rpc_db_digests.rpc_id(1, d)


func _exit_tree() -> void:
	CoopDb.restore()
	# A hash task still running (or done but never waited for) at quit made
	# the process abort at exit, after the RenderingServer was gone
	# (WorkerThreadPool still held the task's callable): claim it here.
	if _hash_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_hash_task)
		_hash_task = -1


@rpc("any_peer", "call_remote", "reliable")
func _rpc_db_digests(theirs: Dictionary) -> void:
	if not session.is_host or bool(theirs.get("#lmp", false)) != GameData.lmp_db:
		return   # of the other database: it sends them again once it switched
	theirs.erase("#lmp")
	var rows: Dictionary = CoopDb.rows_for(theirs)
	if not rows.is_empty():
		print("NetStatus: host database tables sent to %d: %s" % [multiplayer.get_remote_sender_id(), rows.keys()])
		_rpc_db_rows.rpc_id(multiplayer.get_remote_sender_id(), rows)


@rpc("authority", "call_remote", "reliable")
func _rpc_db_rows(rows: Dictionary) -> void:
	print("NetStatus: host database values in %s: %d fields" % [rows.keys(), CoopDb.apply(rows)])


## Remake: MD5 over the maps' .mpr / .mob files (sorted by lower-case name).
## The joiner builds every zone's ground and objects from its own files, so
## they must be the host's: the German edition's differ (other monster stats,
## object positions, ground sectors) and would show another world; the
## Russian and English ones are the same. Texts, speech, faces and the
## database stay each player's own (the host's numbers rule the game).
static func world_hash() -> String:
	_start_world_hash()
	if _hash_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_hash_task)
		_hash_task = -1
	return _world_hash


static func _start_world_hash() -> void:
	if _world_hash != "" or _hash_task >= 0 or not GameData.is_open():
		return
	var dir := GameData.root.path_join("maps")
	if Portability.threads():
		_hash_task = WorkerThreadPool.add_task(_hash_job.bind(dir), false, "world hash")
	else:
		_world_hash = _hash_maps(dir)


static func _hash_job(dir: String) -> void:
	_world_hash = _hash_maps(dir)


static func _hash_maps(dir: String) -> String:
	var files := Array(GameFiles.files(dir)).filter(func(f: String):
		return f.get_extension().to_lower() in ["mpr", "mob"])
	files.sort_custom(func(a: String, b: String): return a.to_lower() < b.to_lower())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for f: String in files:
		ctx.update(f.to_lower().to_utf8_buffer())
		ctx.update(GameFiles.read(dir.path_join(f)))
	return ctx.finish().hex_encode()


## Host: true when the joiner `pid` is turned down (its box is sent, the
## connection dropped a moment later).
func refuse(pid: int, protocol: int, world: String) -> bool:
	var why: Array = []
	if session.players.size() >= session.max_players:
		why = [lmp_text("lmp_server_full", "", "Server is full"), lmp_text("lmp_server_full_msg", "", "There is no room for another player in this game.")]
	elif protocol != PROTOCOL:
		why = [lmp_text("lmp_wrong_protocol", "", "Wrong communication protocol version"),
			lmp_text("lmp_wrong_protocol_msg", "", "Wrong communication protocol version")]
	elif world != world_hash():
		why = [lmp_text("lmp_wrong_protocol", "", "Wrong communication protocol version"),
			RemakeText.t("The host's Evil Islands maps differ from yours: another edition of the game. Both players need an edition with the same maps (the English and Russian ones have them; the German one does not).")]
	if why.is_empty():
		return false
	print("NetStatus: join refused (%s)" % why[0])
	_rpc_refused.rpc_id(pid, why[0], why[1])
	get_tree().create_timer(1.0).timeout.connect(func():
		var enet := NetSim.enet_of(multiplayer)
		if enet and enet.get_peer(pid):
			enet.get_peer(pid).peer_disconnect_later()
		elif multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(pid))
	return true


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(title: String, text: String) -> void:
	_refused = true
	refused.emit(title, text)


# ================================================================ status

## Remake (the original loads zones on a thread, only plays the
## progress movie): the remake builds a zone on the main thread, which stops
## the network for as long as the build takes - over a minute on a first run
## while shaders and caches are made. The other side's ENet then times the
## connection out (Session.PEER_TIMEOUT_MS) and a joiner waiting for the first
## zone never gets it. The build calls this between its steps (next to
## LoadingScreen.tick) so ENet keeps acknowledging and sending; what arrives
## only queues up and is handled after the build as usual (the RPCs are run
## by SceneMultiplayer's own poll). A peer dropping meanwhile is handled once
## the build is over (Session._on_peer_disconnected).
const KEEP_ALIVE_MS := 100
static var _alive_ms := 0

static func keep_alive() -> void:
	var now := Time.get_ticks_msec()
	if now - _alive_ms < KEEP_ALIVE_MS:
		return
	_alive_ms = now
	var tree := Engine.get_main_loop() as SceneTree
	var mp := tree.get_multiplayer() if tree else null
	# ENet (or NetSim around it) only: WebSocket peers have no such timeout.
	if NetSim.enet_of(mp) == null \
			or mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	mp.multiplayer_peer.poll()


## Client, after building a zone the host sent.
func zone_loaded() -> void:
	if session.online and not session.is_host:
		_rpc_loaded.rpc_id(1, session.zone_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_loaded(zone: String) -> void:
	if session.is_host:
		_loaded[multiplayer.get_remote_sender_id()] = zone.left(32)
		_loaded_at[multiplayer.get_remote_sender_id()] = Time.get_ticks_msec()


func _physics_process(dt: float) -> void:
	if session == null or not session.online or not session.is_host:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = STATUS_EVERY
	var enet := NetSim.enet_of(multiplayer)
	var brief := session.zone_id != "" and session.campaign != null \
		and String(session.campaign.zone(session.zone_id).get("type", "")) == "brief"
	var here := "base" if brief else "zone"
	var out := {}
	for pid in session.players:
		var ping := 0
		var state := here
		if int(pid) != 1:
			var p := enet.get_peer(int(pid)) if enet else null
			if p == null and enet != null:
				continue
			# The round trip of our own ping (what the game's messages see,
			# queues included); ENet's own estimate until the first answer.
			ping = int(_rtt.get(pid, p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if p else 0))
			_rpc_ping.rpc_id(int(pid), Time.get_ticks_msec())
			if String(_loaded.get(pid, "")) != session.zone_id or session.world == null:
				state = "connect"
			elif ping > 1000:
				state = "lag"
		elif session.world == null:
			state = "connect"
		out[pid] = {"ping": ping, "state": state}
	status = out
	status_changed.emit()
	if out != _last_sent:
		_last_sent = out.duplicate(true)
		_rpc_status.rpc(out)


@rpc("authority", "call_remote", "reliable")
func _rpc_ping(t: int) -> void:
	_rpc_pong.rpc_id(1, t)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pong(t: int) -> void:
	if not session.is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	var ms := float(Time.get_ticks_msec() - t)
	if ms < 0.0 or ms > 60000.0:
		return
	# A ping that waited out the peer's zone build measures the build, not
	# the connection: only pings sent after it reported the current zone count.
	if String(_loaded.get(pid, "")) != session.zone_id or t < int(_loaded_at.get(pid, 0)):
		return
	_rtt[pid] = ms if not _rtt.has(pid) else lerpf(float(_rtt[pid]), ms, 0.3)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_status(s: Dictionary) -> void:
	status = s
	status_changed.emit()


## The status line's text (textslmp lmp_status_*; "lag" is remake-only).
static func state_text(state: String) -> String:
	match state:
		"zone": return lmp_text("lmp_status_zone", "", "In zone")
		"base": return lmp_text("lmp_status_base", "", "In base")
		"connect": return lmp_text("lmp_status_connect", "", "Enters")
		"lag": return RemakeText.t("Connection problems")
	return state
