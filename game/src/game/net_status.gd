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

const CHAT_MAX := 120
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

static var _lmp: EIResArchive
static var _lmp_tried := false


## textslmp.res "string <key>" with %s = `arg`, or `fallback` without that file.
static func lmp_text(key: String, arg := "", fallback := "") -> String:
	if not _lmp_tried:
		_lmp_tried = true
		if GameData.is_open():
			var p := GameData.res_path("textslmp.res")
			if FileAccess.file_exists(p):
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
	return COLOURS[clampi(player_index, 0, 3)]


# ================================================================ join / leave

func joined_text(player_name: String) -> String:
	return lmp_text("lmp_player_connected", player_name, "Player %s connected to the game")


## Host: the line for a peer that is gone (said goodbye = left, else lost).
func gone_text(pid: int, player_name: String) -> String:
	if _leaving.has(pid):
		_leaving.erase(pid)
		return lmp_text("lmp_player_disconnected", player_name, "Player %s left the game")
	return lmp_text("lmp_player_lost_connection", player_name, "Player %s lost connection with the server")


## "" when the host said it was leaving (its own line came already).
func server_lost_text() -> String:
	if _host_left:
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


@rpc("any_peer", "call_remote", "reliable")
func _rpc_bye() -> void:
	if session.is_host:
		var pid := multiplayer.get_remote_sender_id()
		_leaving[pid] = true
		# Its connection may just vanish (the game closed): let it go now.
		(func():
			if multiplayer.has_multiplayer_peer() and pid in multiplayer.get_peers():
				(multiplayer as SceneMultiplayer).disconnect_peer(pid)
			# (no peer_disconnected signal for a peer dropped here)
			session.coop._on_peer_gone(pid)
			session._on_peer_disconnected(pid)
			).call_deferred()


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


# ================================================================ status

## Client, after building a zone the host sent.
func zone_loaded() -> void:
	if session.online and not session.is_host:
		_rpc_loaded.rpc_id(1, session.zone_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_loaded(zone: String) -> void:
	if session.is_host:
		_loaded[multiplayer.get_remote_sender_id()] = zone.left(32)


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
			if p == null:
				continue
			# The round trip of our own ping (what the game's messages see,
			# queues included); ENet's own estimate until the first answer.
			ping = int(_rtt.get(pid, p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))
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
		"lag": return "Connection problems"
	return state
