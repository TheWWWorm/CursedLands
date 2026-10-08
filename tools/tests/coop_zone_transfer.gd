extends "coop_story.gd"
## Original maps, two ENet peers, and delayed packets from an earlier world.
## Simulation is stopped after deployment so story triggers do not choose the
## next destination for this transport/lifecycle regression.

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	await get_tree().create_timer(0.45).timeout

func freeze() -> void:
	for s: Session in [host, client]:
		s.set_physics_process(false)
		s.world.set_process(false)
		s.world.set_physics_process(false)
		for u: GameUnit in s.world.party_units():
			u.blocked = false
			u.command({"type":"stop"})
		s.game.hud._tutorial.close()

func reject_old_order(old_zone: String, old_generation: int, label: String) -> void:
	var u := host.party_units(1)[0] as GameUnit
	var before := u.orders.duplicate(true)
	var packet := {"t":"move", "units":[u.uid], "x":17.0, "y":19.0,
		"_zone":old_zone, "_generation":old_generation}
	client._rpc_cmd.rpc_id(1, packet)
	await settle()
	check(u.orders == before, label + ": delayed old order rejected")
	client.submit({"t":"move", "units":[u.uid], "x":u.pos.x + 2.0, "y":u.pos.y})
	await settle()
	check(u.orders.size() == 1 and u.orders[0].get("type", "") == "move" and u.orders[0].to.distance_to(u.pos + Vector2(2,0)) < 0.01,
		label + ": current-world client order accepted")
	if NetStatus.PROTOCOL >= 7:
		var remote := client.world.units[u.uid] as GameUnit
		var old_pos := remote.pos
		var stale := u.snapshot()
		stale[1] = 17.0; stale[2] = 19.0
		host._rpc_snap.rpc_id(client.multiplayer.get_unique_id(), [stale], 12345.0, old_generation)
		await settle()
		check(remote.pos == old_pos and client.world.time != 12345.0, label + ": old snapshot rejected")
		host._send_snap([u.snapshot()], host.world.time)
		await settle()
		check(remote.pos.distance_to(u.pos) < 0.03, label + ": current snapshot accepted")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"auto_graphics":0,
		"autosave":0,"scroll_border":0,"show_tutorial":0}, true)
	await get_tree().process_frame
	var h := branch("Host", true); host = h.s; hg = h.g
	var c := branch("Client", false); client = c.s; cg = c.g
	require(host.host(29898, 2) == OK)
	GameData.player_name = "Transfer Guest"
	require(client.join("127.0.0.1", 29898) == OK)
	require(await until(func(): return host.players.size() == 2))
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero", "Transfer Guest")
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var first := "bz1r" if astral else "bz1g"
	var second := "cz1h" if astral else "gz1g"
	await host.enter_zone(first, 1, false)
	require(await until(func(): return client.world != null and client.zone_id == first))
	freeze()
	var generation := host._load_serial
	var old_world: WeakRef = weakref(host.world)
	var old_client_world: WeakRef = weakref(client.world)
	var old_time := host.world.time
	host.travel_options = [{"zone":second,"entrance":1}]
	host.broadcast({"t":"travel", "options":host.travel_options})
	await settle()
	host._travel(second, 1)
	check(host.loading_game and host.zone_id == first, "travel freezes before deferred rebuild")
	check(host.world.process_mode == Node.PROCESS_MODE_DISABLED, "old authority world stopped")
	if DisplayServer.get_name() != "headless":
		check(LoadingScreen._current != null, "loading image exists when travel map closes")
	# Client is remote and may still be issuing commands until prepare arrives.
	var remote_hero := client.party_units(1)[0] as GameUnit
	client.submit({"t":"move","units":[remote_hero.uid],"x":17.0,"y":19.0})
	require(await until(func(): return client.loading_game or client.zone_id == second))
	check(client.loading_game and host.zone_id == first, "client loading starts before authority rebuild")
	check(host.world.time == old_time, "old world cannot advance while awaiting client")
	require(await until(func(): return client.zone_id == second and not client.loading_game and not host.loading_game))
	freeze()
	await settle()
	check(old_world.get_ref() == null and old_client_world.get_ref() == null, "both old worlds freed after transfer")
	check(host._load_serial > generation and client._pool_epoch == host._load_serial, "peers agree on new world generation")
	await reject_old_order(first, generation, "different map")
	# Same map: a zone-name check alone must not accept pre-reload commands.
	host.save_game("transfer_reload")
	host.script_game_over()
	await settle()
	check(not is_instance_valid(cg.hud._game_over_box), "scripted client failure has no misleading reload question")
	check(cg.hud._death_notice != null and cg.hud._death_notice.visible and not cg.hud._death_notice.allow_load,
		"scripted client failure waits for host even when other heroes live")
	check(hg.hud._death_notice != null and hg.hud._death_notice.allow_load, "scripted host failure retains reload action")
	generation = host._load_serial
	require(await host.load_game_shown("transfer_reload"))
	require(await until(func(): return not client.loading_game and client._pool_epoch == host._load_serial))
	freeze()
	check(not cg.hud._death_notice.visible and not hg.hud._death_notice.visible, "host reload dismisses both failure notices")
	await reject_old_order(second, generation, "same-map reload")
	# A named destination bypasses the global route map, even when it has no
	# selectable island piece (LiA's brief/small scenes use this path).
	generation = host._load_serial
	host.leave_zone(first, 1)
	check(host.loading_game and not host.map_open, "authored named destination starts direct loading")
	require(await until(func(): return client.zone_id == first and not client.loading_game and not host.loading_game))
	freeze()
	check(host._load_serial > generation and host.travel_options.is_empty(), "direct transfer completes without a route choice")
	client.multiplayer.multiplayer_peer.close()
	host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	await settle()
	print("ZONE_TRANSFER ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass
