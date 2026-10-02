class_name UpnpPort
extends Node
## Remake-only (the original has no UPnP or any NAT traversal; its LMP servers
## were reached by IP or through the server list): with option "net_upnp"
## (Options → Game, on by default) the host asks the router to forward the
## game's UDP port to this computer, so friends can join over the internet,
## and shows the router's external address to share.
##   1. UPnP IGD (Godot's UPNP class, waits up to 2 s for routers to answer);
##   2. if that fails: PCP (RFC 6887) and then NAT-PMP (RFC 6886) to the
##      default gateway, UDP 5351 (PacketPeerUDP; Apple / many home routers
##      that have UPnP off). The gateway comes from the routing table
##      (Linux /proc/net/route, macOS `route -n get default`, Windows
##      `route print -4 0.0.0.0`), else the LAN address with .1.
## A PCP / NAT-PMP mapping has a lifetime (LIFETIME s) and is renewed at half
## of it. Every mapping is removed when hosting ends (back to the menu,
## quitting). All network waits run on a thread.

signal finished(ok: bool, text: String)

const DESCRIPTION := "Evil Islands remake co-op"
const PMP_PORT := 5351
const LIFETIME := 7200
## Retransmission waits (ms) of one PCP / NAT-PMP request (RFC 6886 3.1
## starts at 250 ms and doubles; cut short here, ~1.75 s per protocol).
const PMP_WAITS := [250, 500, 1000]

var port := 0
var external_ip := ""
var external_port := 0   # the router may give another port than `port` (NAT-PMP / PCP)
var mapped := false
var busy := false
var status := ""
var method := ""         # "UPnP", "PCP" or "NAT-PMP" once mapped
## Tests: the gateway ("ip" or "ip:port") instead of the default route; and
## `skip_upnp` to go straight to PCP / NAT-PMP.
var gateway := ""
var skip_upnp := false
var _thread: Thread
var _upnp: UPNP
var _gw := ""
var _gw_port := PMP_PORT
var _client_ip := ""
var _nonce := PackedByteArray()
var _renew: Timer


## Host started: map `port` (UDP) on the router in the background.
func open(p: int) -> void:
	if not Portability.threads() or OS.has_feature("web"):
		return
	if busy or mapped:
		return
	port = p
	busy = true
	status = RemakeText.t("UPnP: looking for the router…")
	_thread = Thread.new()
	_thread.start(_work)


func _work() -> void:
	var ok := false
	var text := ""
	var upnp_why := ""
	if not skip_upnp:
		var u := UPNP.new()
		var err := u.discover(2000, 2, "InternetGatewayDevice")
		if err != UPNP.UPNP_RESULT_SUCCESS:
			upnp_why = RemakeText.t("no router answered (%s)") % _why(err)
		elif u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
			upnp_why = RemakeText.t("no router with port forwarding")
		else:
			var r := u.add_port_mapping(port, port, DESCRIPTION, "UDP", 0)
			if r != UPNP.UPNP_RESULT_SUCCESS:
				upnp_why = RemakeText.t("the router refused (%s)") % _why(r)
			else:
				ok = true
				var ip := u.query_external_address()
				text = RemakeText.t("UPnP: UDP port %d is open. Your address for friends: %s") % [port, ip if ip else RemakeText.t("(unknown)")]
				_done_map.call_deferred("UPnP", ip, port)
		_upnp = u if ok else null
	else:
		upnp_why = "skipped"
	if not ok:
		var r := _pmp_map(LIFETIME)   # [method or "", external ip, external port, why]
		if r[0] != "":
			ok = true
			var share := _join_text(r[1], r[2]) if r[1] else RemakeText.t("(unknown)")
			text = RemakeText.t("%s: UDP port %d is open. Your address for friends: %s") % [r[0], port, share]
			_done_map.call_deferred(r[0], r[1], r[2])
		else:
			text = RemakeText.t("The router opened no port (UPnP: %s; NAT-PMP/PCP: %s). Forward UDP port %d by hand to play over the internet.") % [upnp_why, r[3], port]
	_done.call_deferred(ok, text)


func _done_map(m: String, ip: String, ext: int) -> void:
	method = m
	external_ip = ip
	external_port = ext


func _done(ok: bool, text: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	mapped = ok
	status = text
	print(text)
	if ok and method != "UPnP":
		_start_renew()
	finished.emit(ok, text)


static func _why(err: int) -> String:
	match err:
		UPNP.UPNP_RESULT_NO_GATEWAY: return RemakeText.t("no gateway")
		UPNP.UPNP_RESULT_NO_DEVICES: return RemakeText.t("no devices")
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING: return RemakeText.t("the port is mapped to another computer")
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MECHANISM: return RemakeText.t("conflict")
		UPNP.UPNP_RESULT_NOT_AUTHORIZED: return RemakeText.t("not authorised")
		UPNP.UPNP_RESULT_ACTION_FAILED: return RemakeText.t("action failed")
		UPNP.UPNP_RESULT_SOCKET_ERROR: return RemakeText.t("network error")
	return RemakeText.t("error %d") % err


## "ip:port", or "[ip]:port" for an IPv6 address.
static func _join_text(ip: String, p: int) -> String:
	return ("[%s]:%d" if ip.contains(":") else "%s:%d") % [ip, p]


# ------------------------------------------------------------------ PCP / NAT-PMP

## Maps (lifetime > 0) or removes (0) the port: PCP first, NAT-PMP when the
## router answers PCP with version 0 / not at all. Blocking: thread or exit.
## Returns [method or "", external ip, external port, why it failed].
func _pmp_map(lifetime: int) -> Array:
	if _gw == "":
		var g := gateway if gateway else default_gateway()
		if g == "":
			return ["", "", 0, RemakeText.t("no gateway")]
		if g.count(":") == 1:
			_gw_port = g.get_slice(":", 1).to_int()
			g = g.get_slice(":", 0)
		_gw = g
		_client_ip = _local_ip_for(_gw)
	var udp := PacketPeerUDP.new()
	if udp.bind(0) != OK:
		return ["", "", 0, RemakeText.t("network error")]
	udp.set_dest_address(_gw, _gw_port)
	var why := RemakeText.t("no answer from %s") % _gw
	if method != "NAT-PMP":   # a router that answered NAT-PMP before keeps it
		var r := _pcp(udp, lifetime)
		if r[0] != "" or (lifetime == 0 and method == "PCP"):
			udp.close()
			return r
		if r[3] != "":
			why = r[3]
	var r2 := _natpmp(udp, lifetime)
	udp.close()
	if r2[0] == "" and r2[3] == "":
		r2[3] = why
	return r2


## One request, retransmitted per PMP_WAITS; the first answer from the
## gateway with the expected opcode, or empty.
func _ask(udp: PacketPeerUDP, req: PackedByteArray, op_byte: int, op: int) -> PackedByteArray:
	for wait: int in PMP_WAITS:
		udp.put_packet(req)
		var until := Time.get_ticks_msec() + wait
		while Time.get_ticks_msec() < until:
			while udp.get_available_packet_count() > 0:
				var pkt := udp.get_packet()
				if udp.get_packet_ip() != _gw:
					continue
				if pkt.size() >= 2 and pkt[1] == op:
					return pkt
				if pkt.size() >= 2 and pkt[0] == 0 and op_byte == 2:
					return pkt   # PCP sent to a NAT-PMP-only router: "unsupported version"
			OS.delay_msec(10)
	return PackedByteArray()


## RFC 6887 MAP request (60 bytes), UDP, suggested external port = port.
func _pcp(udp: PacketPeerUDP, lifetime: int) -> Array:
	if _nonce.is_empty():
		var c := Crypto.new()
		_nonce = c.generate_random_bytes(12)
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_u8(2)          # version
	b.put_u8(1)          # R=0, opcode MAP
	b.put_u16(0)
	b.put_u32(lifetime)
	b.put_data(_v4_mapped(_client_ip))
	b.put_data(_nonce)
	b.put_u8(17)         # UDP
	b.put_u8(0); b.put_u16(0)
	b.put_u16(port)
	b.put_u16(port if lifetime > 0 else 0)
	b.put_data(_v4_mapped("0.0.0.0"))
	var pkt := _ask(udp, b.data_array, 2, 0x81)
	if pkt.is_empty():
		return ["", "", 0, ""]
	if pkt[0] != 2:
		return ["", "", 0, ""]   # NAT-PMP-only router: try that
	if pkt.size() < 60 or pkt[3] != 0:
		return ["", "", 0, RemakeText.t("PCP error %d") % (pkt[3] if pkt.size() > 3 else -1)]
	var ext := (pkt[42] << 8) | pkt[43]
	var ip := _ip_from16(pkt.slice(44, 60))
	return ["PCP", ip, ext, ""]


## RFC 6886: external address (opcode 0) then the UDP mapping (opcode 1).
func _natpmp(udp: PacketPeerUDP, lifetime: int) -> Array:
	var ip := ""
	if lifetime > 0:
		var a := _ask(udp, PackedByteArray([0, 0]), 0, 128)
		if a.is_empty():
			return ["", "", 0, ""]
		if a.size() >= 12 and a[2] == 0 and a[3] == 0:
			ip = "%d.%d.%d.%d" % [a[8], a[9], a[10], a[11]]
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_u8(0)
	b.put_u8(1)          # map UDP
	b.put_u16(0)
	b.put_u16(port)
	b.put_u16(port if lifetime > 0 else 0)
	b.put_u32(lifetime)
	var pkt := _ask(udp, b.data_array, 0, 129)
	if pkt.is_empty():
		return ["", "", 0, ""]
	var code := (pkt[2] << 8) | pkt[3] if pkt.size() >= 4 else -1
	if pkt.size() < 16 or code != 0:
		return ["", "", 0, RemakeText.t("NAT-PMP error %d") % code]
	return ["NAT-PMP", ip, (pkt[10] << 8) | pkt[11], ""]


static func _v4_mapped(ip: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16)
	out[10] = 0xff
	out[11] = 0xff
	var parts := ip.split(".")
	if parts.size() == 4:
		for i in 4:
			out[12 + i] = int(parts[i])
	return out


static func _ip_from16(a: PackedByteArray) -> String:
	var mapped4 := true
	for i in 10:
		mapped4 = mapped4 and a[i] == 0
	if mapped4 and a[10] == 0xff and a[11] == 0xff:
		return "%d.%d.%d.%d" % [a[12], a[13], a[14], a[15]]
	var groups := PackedStringArray()
	for i in 8:
		groups.append("%x" % ((a[2 * i] << 8) | a[2 * i + 1]))
	return ":".join(groups)


## Renew a PCP / NAT-PMP mapping at half its lifetime (RFC 6886 3.3).
func _start_renew() -> void:
	if _renew == null:
		_renew = Timer.new()
		_renew.wait_time = LIFETIME / 2.0
		_renew.timeout.connect(func():
			if mapped and not busy and _thread == null:
				busy = true
				_thread = Thread.new()
				_thread.start(func():
					var r := _pmp_map(LIFETIME)
					_renewed.call_deferred(r[0] != "")))
		add_child(_renew)
	_renew.start()


func _renewed(ok: bool) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	if not ok:
		print("%s: renewing UDP port %d failed" % [method, port])


# ------------------------------------------------------------------ addresses

## The IPv4 default gateway (routing table), else the LAN address with .1.
static func default_gateway() -> String:
	match OS.get_name():
		"Linux", "Android":
			var f := FileAccess.open("/proc/net/route", FileAccess.READ)
			if f:
				var best := ""
				var metric := 1 << 30
				f.get_line()
				while not f.eof_reached():
					var c := f.get_line().split("\t", false)
					if c.size() > 6 and c[1] == "00000000" and c[2] != "00000000" and (c[3].hex_to_int() & 2) and c[6].to_int() < metric:
						var h := c[2].hex_to_int()   # little-endian
						best = "%d.%d.%d.%d" % [h & 255, (h >> 8) & 255, (h >> 16) & 255, (h >> 24) & 255]
						metric = c[6].to_int()
				if best:
					return best
		"macOS", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var out := []
			if OS.execute("route", ["-n", "get", "default"], out) == 0 and out.size() > 0:
				for line: String in String(out[0]).split("\n"):
					line = line.strip_edges()
					if line.begins_with("gateway:"):
						var g := line.trim_prefix("gateway:").strip_edges()
						if g.is_valid_ip_address():
							return g
		"Windows":
			var out := []
			if OS.execute("route", ["print", "-4", "0.0.0.0"], out) == 0 and out.size() > 0:
				for line: String in String(out[0]).split("\n"):
					var c := line.strip_edges().split(" ", false)
					if c.size() >= 3 and c[0] == "0.0.0.0" and c[1] == "0.0.0.0" and c[2].is_valid_ip_address():
						return c[2]
	var lan := lan_ipv4()
	return lan.substr(0, lan.rfind(".")) + ".1" if lan else ""


## The first private IPv4 LAN address: 192.168 first (172.16/12 is often a
## container bridge), then 10/8, then 172.16/12.
static func lan_ipv4() -> String:
	var lan := ""
	var rank := 9
	for a: String in IP.get_local_addresses():
		var r := 0 if a.begins_with("192.168.") else 1 if a.begins_with("10.") \
			else 2 if a.begins_with("172.") and int(a.get_slice(".", 1)) >= 16 and int(a.get_slice(".", 1)) <= 31 else 9
		if a.count(".") == 3 and r < rank:
			rank = r
			lan = a
	return lan


## A global unicast IPv6 address of this computer (2000::/3), or "".
## Temporary (privacy) addresses are as good for a game session.
static func global_ipv6() -> String:
	for a: String in IP.get_local_addresses():
		var l := a.to_lower()
		if l.contains(":") and not l.contains("%") and (l.begins_with("2") or l.begins_with("3")):
			return a
	return ""


## The local IPv4 address in the gateway's /24, else the LAN one.
static func _local_ip_for(gw: String) -> String:
	var net := gw.substr(0, gw.rfind(".") + 1)
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and a.begins_with(net):
			return a
	var lan := lan_ipv4()
	return lan if lan else "127.0.0.1"


## Hosting ends: the router forgets the forwarding (blocking, short).
func close() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
		busy = false
	if _renew:
		_renew.stop()
	if mapped and method == "UPnP" and _upnp:
		_upnp.delete_port_mapping(port, "UDP")
		print("UPnP: UDP port %d closed again" % port)
	elif mapped and (method == "PCP" or method == "NAT-PMP"):
		_pmp_map(0)
		print("%s: UDP port %d closed again" % [method, port])
	mapped = false
	method = ""
	_upnp = null
	_gw = ""
	external_ip = ""
	external_port = 0
	status = ""


func _exit_tree() -> void:
	close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close()
