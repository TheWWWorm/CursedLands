extends Node
## Real ENet peers leave in one server poll while a third guest stays online.
## Record attempted sends before forwarding them to the actual transport.
class ObservedSession extends ArenaOnlineSession:
	var stale_sends := 0
	func _send(id: int, data: Dictionary, reliable := true) -> void:
		if is_host and peer is ENetMultiplayerPeer:
			var remote := (peer as ENetMultiplayerPeer).get_peer(id)
			if remote != null and remote.get_state() != ENetPacketPeer.STATE_CONNECTED:
				stale_sends += 1
		super._send(id, data, reliable)

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await frames(1)
	return predicate.call()

func connection(name_text: String) -> ObservedSession:
	var session := ObservedSession.new()
	session.player_name = name_text
	add_child(session)
	return session

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	GameData.options.merge({"net_lan":0, "net_upnp":0, "net_directory":0, "auto_graphics":0}, true)
	Engine.max_fps = 120
	for iteration in 3:
		var host := connection("Host")
		var port := 29883 + iteration
		check(host.host(port) == OK, "Server starts")
		var first := connection("First")
		var second := connection("Second")
		var survivor := connection("Survivor")
		for guest in [first, second, survivor]:
			check(guest.join("127.0.0.1:%d" % port) == OK, "Guest connects")
		check(await until(func(): return survivor.my_seat >= 0 and survivor.members.size() == 4), "All guests receive the full roster")
		# Queue both disconnect datagrams before the next server poll.
		host.set_process(false)
		first.close()
		second.close()
		await frames(6)
		host.set_process(true)
		check(await until(func(): return host.members.size() == 2 and survivor.members.size() == 2), "Survivor receives the final roster")
		check(host.stale_sends == 0, "No lobby packet targets a peer already disconnected in the same poll")
		check(survivor.peer != null and survivor.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Survivor stays connected")
		survivor.request("ready")
		check(await until(func(): return host.members.values().all(func(member): return member.ready)), "Survivor can still change readiness")
		survivor.close()
		await until(func(): return host.members.size() == 1)
		host.close()
		for session in [host, first, second, survivor]: session.queue_free()
		await frames(3)
	print("ARENA_ONLINE_DISCONNECT ", checks, " checks; failures=", JSON.stringify(failures))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
