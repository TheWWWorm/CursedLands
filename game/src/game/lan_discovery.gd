class_name LanDiscovery
extends Node
## The game list of the local network.
##
## the original (traced 2026-10-04): no
## DirectPlay; its own UDP protocol on port 8888. At start
##  takes the computer's first IPv4 address (gethostname
## gethostbyname) and keeps its classful broadcast address (/8, /16 or /24 by
## the first byte); every socket is opened with SO_BROADCAST.
## While the server screen is open its update
## every 0.5 s: message 3 {the client's clock} to that broadcast address, then
## to the selected row and to one address-book entry in turn. Every server
## answers with its record (: name, base, quest, players, max
## players, password flag) and a protocol word; the
## client keeps it with the round trip as its ping and flags a
## record of another protocol ("wrong protocol" on ✓). Internet
## servers came from Nival's master server (a3master.nival.com, TCP 28004 on
## Refresh), which is gone; a "private" server (the default) is not registered
## there and is found only by the broadcast or its address.
##
## Remake: the same scheme on a port of its own (PORT, the game itself runs on
## Session.PORT through ENet, whose socket cannot answer other packets): a
## host answers queries while it hosts; a joiner's Multiplayer screen
## broadcasts a query every 0.5 s (255.255.255.255, the classful broadcast of
## each private IPv4 address of this device, and the loopback for a host on
## this computer) and asks the address-book entries directly. Not in the
## browser build (no UDP sockets there): `available()`.

const PORT := 27016
const EVERY := 0.5          # every 0.5 s
const FORGET_MS := 3000     # a game that stopped answering leaves the list
const QUERY := "EIq1"
const ANSWER := "EIa1"
## the original: an unanswered row shows ping 9999.
const NO_PING := 9999

## Host side: the session whose game is described.
var session: Session
var _sock: PacketPeerUDP
var _token := ""

## Joiner side: games heard, "ip:port" -> {name, mode, base, quest, players,
## max, ping, pw, ws, protocol, ip, port, address, seen, local}.
var games := {}
## Joiner side: more hosts asked directly (the address book's IPs).
var direct: PackedStringArray = []
var _scan := false
var _t := 0.0
var _sent := {}             # query number -> msec sent


## LAN games need UDP sockets: not in the browser build.
static func available() -> bool:
	return not OS.has_feature("web")


## The discovery port: PORT, or --lan-port=N (tests: a port of their own).
static func port() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lan-port=") and a.trim_prefix("--lan-port=").is_valid_int():
			return a.trim_prefix("--lan-port=").to_int()
	return PORT


# ================================================================ host

## Host: start answering queries (false when the port is taken, e.g. by
## another host on this computer: that game is then joined by address only).
func listen() -> bool:
	stop()
	if not available():
		return false
	_sock = PacketPeerUDP.new()
	if _sock.bind(port(), "0.0.0.0") != OK:
		push_warning("LanDiscovery: port %d is in use; this game is not listed on the local network." % port())
		_sock = null
		return false
	_token = "%08x" % (randi() & 0x7fffffff)
	return true


func stop() -> void:
	if _sock:
		_sock.close()
	_sock = null


func listening() -> bool:
	return _sock != null


func _answer() -> void:
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		var from := _sock.get_packet_port()
		if pkt.size() < 8 or pkt.size() > 512 or pkt.slice(0, 4).get_string_from_ascii() != QUERY:
			continue
		var q: Variant = bytes_to_var(pkt.slice(4))
		if not q is Dictionary or session == null or not session.online or not session.is_host:
			continue
		var info := session.lan_info()
		info["t"] = int((q as Dictionary).get("t", 0))
		info["n"] = int((q as Dictionary).get("n", 0))
		info["id"] = _token
		info["v"] = NetStatus.PROTOCOL
		var out := ANSWER.to_ascii_buffer()
		out.append_array(var_to_bytes(info))
		_sock.set_dest_address(ip, from)
		_sock.put_packet(out)


# ================================================================ joiner

## Joiner: start / stop asking (the Multiplayer screen's join pages).
func scan(on: bool) -> void:
	if on == _scan:
		return
	_scan = on
	if not on:
		if _sock:
			_sock.close()
		_sock = null
		return
	if not available():
		_scan = false
		return
	_sock = PacketPeerUDP.new()
	_sock.set_broadcast_enabled(true)
	if _sock.bind(0, "0.0.0.0") != OK:
		_sock = null
		_scan = false
		return
	_t = 0.0


func scanning() -> bool:
	return _scan


## Where a query goes: the limited broadcast, each private IPv4 address's
## classful broadcast (rule), the loopback, the direct hosts.
static func targets(extra: PackedStringArray = []) -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for a: String in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var b := a.split(".")
		var first := int(b[0])
		var bc := ""
		if first < 128:
			bc = "%s.255.255.255" % b[0]
		elif first < 192:
			bc = "%s.%s.255.255" % [b[0], b[1]]
		elif first < 224:
			bc = "%s.%s.%s.255" % [b[0], b[1], b[2]]
		if bc and not bc in out:
			out.append(bc)
	for h in extra:
		if h.is_valid_ip_address() and not h in out:
			out.append(h)
	return out


func _query() -> void:
	var n := randi() & 0xffff
	_sent[n] = Time.get_ticks_msec()
	if _sent.size() > 64:
		_sent.erase(_sent.keys()[0])
	var pkt := QUERY.to_ascii_buffer()
	pkt.append_array(var_to_bytes({"t": Time.get_ticks_msec(), "n": n}))
	for ip in targets(direct):
		_sock.set_dest_address(ip, port())
		_sock.put_packet(pkt)


func _hear() -> void:
	var now := Time.get_ticks_msec()
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		if pkt.size() < 8 or pkt.size() > 2048 or pkt.slice(0, 4).get_string_from_ascii() != ANSWER:
			continue
		var a: Variant = bytes_to_var(pkt.slice(4))
		if not a is Dictionary or not _sent.has(int(a.get("n", -1))):
			continue
		var gport := int(a.get("port", Session.PORT))
		var g := {
			"name": NetStatus.clean(String(a.get("name", ""))).left(24),
			"mode": "lmp" if String(a.get("mode", "")) == "lmp" else "coop",
			"base": String(a.get("base", "")).left(16),
			"quest": String(a.get("quest", "")).left(32),
			"players": clampi(int(a.get("players", 0)), 0, 99),
			"max": clampi(int(a.get("max", 0)), 0, 99),
			"ping": clampi(now - int(a.get("t", now)), 0, NO_PING),
			"pw": bool(a.get("pw", false)),
			"ws": bool(a.get("ws", false)),
			"protocol": int(a.get("v", 0)),
			"in_game": bool(a.get("in_game", false)),
			"id": String(a.get("id", "")).left(16),
			"ip": ip, "port": gport, "seen": now,
			"local": ip.begins_with("127."),
		}
		g["address"] = ("ws://%s:%d" if g.ws else "%s:%d") % [ip, gport]
		# One line per game: the same host heard on the loopback and its
		# LAN address keeps the address that answered first (and its ping).
		var key := String(g.id) if g.id else "%s:%d" % [ip, gport]
		if games.has(key) and String(games[key].ip) != ip and now - int(games[key].seen) < FORGET_MS:
			games[key].seen = now
			continue
		games[key] = g
	for k in games.keys():
		if now - int(games[k].seen) > FORGET_MS:
			games.erase(k)


## The games heard, sorted by name (the original sorts by a clicked column).
func list() -> Array:
	var out := games.values()
	out.sort_custom(func(x, y): return String(x.name).naturalnocasecmp_to(String(y.name)) < 0 \
		if String(x.name) != String(y.name) else String(x.address) < String(y.address))
	return out


## The game answering from `ip` (an address-book entry), {} when none.
func game_at(ip: String, gport := 0) -> Dictionary:
	for g: Dictionary in games.values():
		if String(g.ip) == ip and (gport <= 0 or int(g.port) == gport):
			return g
	return {}


func _process(dt: float) -> void:
	if _scan and _sock:
		_t -= dt
		if _t <= 0.0:
			_t = EVERY
			_query()
		_hear()
	elif _sock and not _scan:
		_answer()


func _exit_tree() -> void:
	if _sock:
		_sock.close()
	_sock = null
