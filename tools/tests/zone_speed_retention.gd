extends "coop_story.gd"
## Actual campaign worlds, route cancellation, safe-zone saves and two ENet peers.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func hold(s: Session) -> void:
	s.set_physics_process(false)
	s.world.set_physics_process(false)
	if s.world.vm:
		s.world.vm.instances.clear()
		s.world.vm.briefings._check = INF
	s.game.hud._tutorial.close()

func travel(s: Session, destination: String, remote: Session = null) -> void:
	s.leave_zone(destination, 1)
	check(await until(func():return s.zone_id == destination and not s.loading_game), "authority arrives in " + destination)
	hold(s)
	if remote:
		check(await until(func():return remote.zone_id == destination and not remote.loading_game), "guest arrives in " + destination)
		hold(remote)
	for i in 6: await get_tree().process_frame

func clock_check(s: Session, rate: int, label: String, remote: Session = null) -> void:
	check(s.game.speed == rate, label + ": active dial")
	check(is_equal_approx(Engine.time_scale, (2.0 if remote else 55.0/27.0) if rate else 1.0), label + ": simulation rate")
	if remote: check(remote.game.speed == rate and remote.clock_speed == rate, label + ": guest clock")

func exercise(s: Session, remote: Session = null) -> void:
	s.game.set_speed(2)
	for i in 6: await get_tree().process_frame
	clock_check(s, 1, "selected 2x", remote)
	s.broadcast({"t":"travel", "options":[]})
	for i in 6: await get_tree().process_frame
	clock_check(s, 0, "route map", remote)
	s.broadcast({"t":"travel_close"})
	for i in 6: await get_tree().process_frame
	clock_check(s, 1, "cancelled route map", remote)
	await travel(s, "gz16h", remote)
	clock_check(s, 1, "field to field", remote)
	await travel(s, "bz14h", remote)
	clock_check(s, 0, "village", remote)
	s.game.set_speed(2)
	check(s.game.speed == 0 and s.field_speed == 1, "village shortcut cannot accelerate or forget field choice")
	var value := s.saved_play_clock()
	check(value == {"paused":false,"speed":0,"field_speed":1}, "village save remembers field speed")
	check(s.save_game("zone-speed-village") == OK, "village save written")
	s.field_speed = 0
	check(s.load_game("zone-speed-village"), "village save restored")
	hold(s)
	if remote:
		check(await until(func():return not remote.loading_game and remote._pool_epoch == s._load_serial), "guest finishes village reload")
		hold(remote)
	for i in 6: await get_tree().process_frame
	clock_check(s, 0, "village reload", remote)
	await travel(s, "gz15h", remote)
	clock_check(s, 1, "return from village", remote)
	s.game.set_speed(1)
	await travel(s, "gz16h", remote)
	clock_check(s, 0, "explicit 1x survives travel", remote)
	s.restore_play_clock({"speed":1,"paused":true})
	check(get_tree().paused and s.field_speed == 1 and s.game.speed == 1, "legacy accelerated paused save")
	s.restore_play_clock({})
	check(not get_tree().paused and s.field_speed == 0 and s.game.speed == 0, "legacy save without a clock defaults to 1x")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_directory":0,"net_lan":0,"auto_graphics":0,"autosave":0,"show_tutorial":0,"coop_clock":1},true)
	var h := branch("Solo", true)
	host = h.s; hg = h.g
	host.state.ensure_hero(0,"Human Hero")
	host._enter_zone("gz15h",1,false)
	hold(host)
	await exercise(host)
	branches[0].queue_free()
	branches.clear()
	for i in 8: await get_tree().process_frame
	h = branch("Host", true); host = h.s; hg = h.g
	var c := branch("Client", false); client = c.s; cg = c.g
	require(host.host(29949,2) == OK)
	require(client.join("127.0.0.1",29949) == OK)
	require(await until(func():return host.players.size() == 2))
	host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero")
	await host.enter_zone("gz15h",1,false)
	require(await until(func():return client.world != null and not client.loading_game))
	hold(host); hold(client)
	await exercise(host, client)
	client.multiplayer.multiplayer_peer.close()
	host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 8: await get_tree().process_frame
	print("ZONE_SPEED_RETENTION ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass
