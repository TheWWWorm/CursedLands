class_name UpnpPort
extends Node
## Remake-only (the original has no UPnP; its LMP servers were reached by IP or
## through the server list): with option "net_upnp" (Options → Game, on by
## default) the host asks the router (UPnP IGD, Godot's UPNP class) to
## forward the game's UDP port to this computer, so friends can join over the
## internet, and shows the router's external IP to share. The mapping is
## removed when hosting ends (back to the menu, quitting). Discovery runs on a
## thread (it waits up to 2 s for routers to answer).

signal finished(ok: bool, text: String)

const DESCRIPTION := "Evil Islands remake co-op"

var port := 0
var external_ip := ""
var mapped := false
var busy := false
var status := ""
var _thread: Thread
var _upnp: UPNP


## Host started: map `port` (UDP) on the router in the background.
func open(p: int) -> void:
	if busy or mapped:
		return
	port = p
	busy = true
	status = "UPnP: looking for the router…"
	_thread = Thread.new()
	_thread.start(_work)


func _work() -> void:
	var u := UPNP.new()
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	var ok := false
	var text := ""
	if err != UPNP.UPNP_RESULT_SUCCESS:
		text = "UPnP: no router answered (%s). Forward UDP port %d by hand to play over the internet." % [_why(err), port]
	elif u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		text = "UPnP: no router with port forwarding found. Forward UDP port %d by hand." % port
	else:
		var r := u.add_port_mapping(port, port, DESCRIPTION, "UDP", 0)
		if r != UPNP.UPNP_RESULT_SUCCESS:
			text = "UPnP: the router refused to open UDP port %d (%s). Forward it by hand." % [port, _why(r)]
		else:
			ok = true
			var ip := u.query_external_address()
			text = "UPnP: UDP port %d is open. Your address for friends: %s" % [port, ip if ip else "(unknown)"]
			_done_ip.call_deferred(ip)
	_upnp = u if ok else null
	_done.call_deferred(ok, text)


func _done_ip(ip: String) -> void:
	external_ip = ip


func _done(ok: bool, text: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	mapped = ok
	status = text
	print(text)
	finished.emit(ok, text)


static func _why(err: int) -> String:
	match err:
		UPNP.UPNP_RESULT_NO_GATEWAY: return "no gateway"
		UPNP.UPNP_RESULT_NO_DEVICES: return "no devices"
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING: return "the port is mapped to another computer"
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MECHANISM: return "conflict"
		UPNP.UPNP_RESULT_NOT_AUTHORIZED: return "not authorised"
		UPNP.UPNP_RESULT_ACTION_FAILED: return "action failed"
		UPNP.UPNP_RESULT_SOCKET_ERROR: return "network error"
	return "error %d" % err


## Hosting ends: the router forgets the forwarding (blocking, short).
func close() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
		busy = false
	if mapped and _upnp:
		_upnp.delete_port_mapping(port, "UDP")
		print("UPnP: UDP port %d closed again" % port)
	mapped = false
	_upnp = null
	external_ip = ""
	status = ""


func _exit_tree() -> void:
	close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close()
