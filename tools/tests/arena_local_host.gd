extends Node
## Real authority processes and both transports. No rendered scene required.
var checks := 0
var failures: Array[String] = []
var startup_result := -999
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func until(predicate: Callable, seconds := 15.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < end: await frames(1)
	return predicate.call()
func connection(name_text: String) -> ArenaOnlineSession:
	var result := ArenaOnlineSession.new(); result.player_name = name_text
	add_child(result); return result
func begin_capture(host: ArenaOnlineSession, port: int) -> void:
	startup_result = await host.local_host.start(port, false)
func _ready() -> void: run.call_deferred()
func run() -> void:
	GameData.options.merge({"net_lan":1,"net_upnp":0,"net_directory":0,"autosave":0,"auto_graphics":0},true)
	Engine.max_fps = 120
	for websocket in [false, true]: await transport(websocket)
	var host := connection("Cancelled host")
	check(await host.local_host.start(0, false) == ERR_INVALID_PARAMETER, "invalid port creates no child")
	begin_capture(host, 29881)
	var child := host.local_host.process_id
	var config := host.local_host._config
	check(child > 0 and host.local_host.starting, "startup is cancellable before readiness")
	await host.close_shown()
	await frames(3)
	check(startup_result == ERR_SKIP, "cancelled startup cannot connect late")
	check(not OS.is_process_running(child) and not FileAccess.file_exists(config), "cancelled child and private config are removed")
	host.queue_free(); await frames(2)
	var blocker := ENetMultiplayerPeer.new()
	check(blocker.create_server(29882) == OK, "reserve occupied port")
	host = connection("Busy port")
	check(await host.local_host.start(29882, false) != OK, "occupied port fails startup")
	check(not host.local_host.frontend and host.local_host.process_id == -1, "failed startup leaves no active authority")
	blocker.close(); host.queue_free(); await frames(2)
	print("ARENA_LOCAL_HOST ", checks, " checks; failures=", JSON.stringify(failures))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
func transport(websocket: bool) -> void:
	var port := 29880 if websocket else 29879
	var host := connection("Worm")
	host.password = "test-password"
	check(await host.local_host.start(port, websocket) == OK, "worker starts %s" % websocket)
	if not host.local_host.owned: host.queue_free(); return
	var child := host.local_host.process_id; var config := host.local_host._config
	check(host.owns_game() and not host.is_host and host.game == null, "owner renders without inline authority")
	check(host.my_seat == 0 and host.members.size() == 1, "owner occupies exactly seat zero")
	check(not FileAccess.file_exists(config) and host.local_host._token.is_empty(), "startup secret is removed after owner handshake")
	var finder := LanDiscovery.new(); finder.discovery_port = ArenaOnlineSession.LAN_PORT
	finder.protocol = ArenaOnlineSession.PROTOCOL; finder.modes = PackedStringArray(["autochess"])
	add_child(finder); finder.scan(true)
	check(await until(func(): return not finder.list().is_empty()), "worker advertises on LAN")
	if not finder.list().is_empty():
		var room: Dictionary = finder.list()[0]
		check(room.name == "Worm" and room.players == 1 and room.pw and room.ws == websocket and room.port == port, "worker LAN details preserve owner and transport")
	var address := ("ws://127.0.0.1:%d" if websocket else "127.0.0.1:%d") % port
	var guest := connection("Guest"); guest.password = host.password
	check(guest.join(address) == OK and await until(func(): return guest.my_seat == 1), "guest occupies seat one")
	check(not guest.owns_game() and host.members.size() == 2, "guest is not an extra owner")
	var rogue := connection("Untrusted"); rogue.password = host.password
	check(rogue.join(address) == OK, "unauthenticated owner probe connects transport")
	rogue._connected = true   # send our own malformed owner hello instead
	check(await until(func(): return rogue.peer != null and rogue.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "owner probe reaches server")
	rogue._send(1, {"t":"hello","protocol":ArenaOnlineSession.PROTOCOL,"version":ProjectSettings.get_setting("application/config/version"),"hash":NetStatus.world_hash(),"name":"Untrusted","password":host.password,"owner":"guessed"})
	check(await until(func(): return rogue.peer == null), "invalid owner token is rejected")
	check(rogue.status == RemakeText.t("Invalid online action.") and host.members.size() == 2, "invalid owner never receives a seat")
	rogue.queue_free()
	guest.request("start", [7319]); await frames(20)
	check(not host.started and not guest.started, "guest cannot start the tournament")
	check(host.start_game(7319) == "Wait for every player to be ready.", "owner waits for guest readiness")
	guest.request("ready")
	check(await until(func(): return host.members.values().all(func(m): return m.ready)), "guest readiness reaches owner")
	var boards := {}; host.board_received.connect(func(data): boards[int(data.seat)] = data)
	check(host.start_game(7319).is_empty(), "owner can start")
	check(await until(func(): return host.started and guest.started), "both replicas receive start")
	if not websocket:
		guest.set_process(false)
		await get_tree().create_timer(6.5).timeout
		guest.set_process(true); await frames(4)
		check(guest.peer != null and host.members.size() == 2, "ENet keeps a guest through a cold scene-build stall")
	check(await until(func(): return boards.has(0)), "seat zero receives its board")
	host.set_process(false)
	await get_tree().create_timer(0.8).timeout
	host._last_frame_at = Time.get_ticks_msec() - 16001
	host.set_process(true); await frames(2)
	check(host.peer != null and host.started, "queued server frames recover a stalled frontend before timeout")
	host.watch(-1)
	check(await until(func(): return boards.size() == 9), "overview receives all nine authoritative boards")
	host.watch(0)
	host.request("buy", [0]); guest.request("buy", [0])
	check(await until(func(): return host.view.army.size() == 1 and guest.view.army.size() == 1), "both players can recruit")
	host.request("speed", [2])
	check(await until(func(): return host.view.battle_speed == 2 and guest.view.battle_speed == 2), "owner sets synchronized 2x")
	guest.request("speed", [1]); await frames(30)
	check(host.view.battle_speed == 2 and guest.view.battle_speed == 2, "guest cannot override speed")
	host.request("ready"); guest.request("ready")
	check(await until(func(): return host.view.global_stage == "fight"), "ready players begin combat")
	check(await until(func(): return float(boards.get(0, {}).get("time", 0.0)) > 0.2), "worker simulation clock advances")
	host.request("speed", [1])
	check(await until(func(): return guest.view.battle_speed == 1), "owner can return to 1x")
	await host.close_shown()
	check(await until(func(): return guest.peer == null), "owner leaving closes the game for connected guests")
	guest.queue_free()
	check(not OS.is_process_running(child), "leaving stops authority")
	check(not FileAccess.file_exists("user://crash/running_%d.cfg" % child), "authority exits cleanly without forced termination")
	check(not FileAccess.get_file_as_string(config + ".log").contains("ERROR:"), "authority log has no runtime errors")
	check(await until(func(): return finder.list().is_empty()), "closed worker disappears from LAN")
	finder.queue_free()
	check(not FileAccess.file_exists(config) and not FileAccess.file_exists(config + ".stop"), "normal shutdown removes private files")
	check(host.peer == null and not host.owns_game(), "closed frontend has no host controls")
	host.queue_free(); await frames(4)
