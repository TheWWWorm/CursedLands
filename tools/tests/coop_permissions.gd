extends "coop_story.gd"
## Two real ENet peers: authenticated commands, separate privileges, snapshots
## and identity across reconnects. No guest-supplied save path reaches disk.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames(n := 12) -> void:
	for i in n: await get_tree().process_frame
func hold(s: Session) -> void:
	s.set_physics_process(false)
	s.world.set_physics_process(false)
	if s.world.vm:
		s.world.vm.instances.clear()
		s.world.vm.briefings._check = INF
	s.game.hud._tutorial.close()
func grant(pid: int, bit: int, yes: bool) -> void:
	host.set_player_permission(pid, bit, yes)
	check(await until(func(): return CoopPermissions.allows(client, client.my_index, bit) == yes), "guest receives permission %d=%s" % [bit, yes])
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_directory":0,"net_lan":0,"auto_graphics":0,
		"autosave":0,"show_tutorial":0,"coop_clock":1,"coop_guest_clock":0,"coop_guest_saves":0}, true)
	GameData.player_name = "Permission Host"
	var h := branch("Host", true); host = h.s; hg = h.g
	var c := branch("Client", false); client = c.s; cg = c.g
	require(host.host(29963, 3) == OK)
	GameData.player_name = "Permission Guest"
	require(client.join("127.0.0.1", 29963) == OK)
	require(await until(func(): return host.players.size() == 2))
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero")
	await host.enter_zone("gz15h", 1, false)
	require(await until(func(): return client.world != null and not client.loading_game))
	hold(host); hold(client); await frames()
	var pid := client.multiplayer.get_unique_id()
	check(host.can_change_clock(0) and not client.can_change_clock(0), "default is host-only")
	client.submit({"t":"clock","sector":2,"player":0})
	await frames()
	check(host.clock_speed == 0, "forged host slot cannot accelerate")
	await grant(pid, CoopPermissions.SPEED, true)
	cg.set_speed(2)
	check(await until(func(): return host.clock_speed == 1 and client.clock_speed == 1), "guest changes shared speed")
	hg.set_speed(0); await frames()
	check(host.clock_paused and client.clock_paused, "host pauses both peers")
	cg.set_speed(1); await frames()
	check(host.clock_paused and client.clock_paused and host.clock_speed == 0, "speed-only guest cannot resume")
	client.submit({"t":"clock","sector":0,"player":0}); await frames()
	check(host.clock_paused, "forged pause request is denied")
	await grant(pid, CoopPermissions.PAUSE, true)
	cg.set_speed(0); await frames(30)
	check(not host.clock_paused and not client.clock_paused, "authorized pause toggle delivered once")
	host.set_player_permission(pid, CoopPermissions.PAUSE, false)
	host.set_player_permission(pid, CoopPermissions.PAUSE, true)
	await frames()
	check(client.save_game("outside-quick") == ERR_UNAUTHORIZED, "guest cannot select another save slot")
	client.submit({"t":"quick_save","slot":"outside-quick"}); await frames()
	check(not FileAccess.file_exists(SaveInfo.path("quick")), "unauthorized save packet cannot write")
	check(not FileAccess.file_exists(SaveInfo.path("outside-quick")), "packet filename is ignored")
	await grant(pid, CoopPermissions.SAVE, true)
	host.state.set_var(0, "permission_test", 123)
	cg.hud._on_esc_board("save")
	check(await until(func(): return FileAccess.file_exists(SaveInfo.path("quick"))), "guest menu saves the host quick slot")
	var saved := CampaignState.load_from(SaveInfo.path("quick"))
	check(saved.get_var(0, "permission_test") == 123, "save contains host state")
	check(int(saved.coop[CoopPermissions.KEY].players["permission guest"]) == 7, "permissions saved by stable name")
	host.state.set_var(0, "permission_test", 999)
	client.submit({"t":"quick_load","player":0}); await frames()
	check(host.state.get_var(0, "permission_test") == 999, "save permission does not grant load")
	await grant(pid, CoopPermissions.LOAD, true)
	check(await client.load_game_shown("outside-quick") == false, "guest cannot load arbitrary host slot")
	check(client.save_game("quick") == OK, "authorized F5 path accepted")
	check(await until(func():
		var data: Variant = CampaignState.read_data(SaveInfo.path("quick"))
		return int(data.get("coop", {}).get(CoopPermissions.KEY, {}).get("players", {}).get("permission guest", 0)) == 15),
		"updated grants reach the checkpoint")
	host.state.set_var(0, "permission_test", 456)
	await grant(pid, CoopPermissions.SPEED, false)
	GameData.set_option("show_fps", 1)
	check(not CoopPermissions.allows(host, 1, CoopPermissions.SPEED), "unrelated settings retain individual grants")
	var epoch := host._load_serial
	cg.hud._on_esc_board("load")
	check(await until(func(): return host._load_serial > epoch and not host.loading_game and not client.loading_game and client._pool_epoch == host._load_serial), "guest menu reload completes on both peers")
	hold(host); hold(client); await frames()
	check(host.state.get_var(0, "permission_test") == 999, "guest quickload restores authoritative saved state")
	check(client.can_change_clock(2) and CoopPermissions.mask(host, 1) == 15, "load restores saved permissions")
	# Rejoin with a new ENet identity; grants belong to the campaign identity.
	client.multiplayer.multiplayer_peer.close()
	check(await until(func(): return host.players.size() == 1), "guest disconnect observed")
	branches[1].queue_free(); branches.remove_at(1); await frames()
	c = branch("Rejoined", false); client = c.s; cg = c.g
	require(client.join("127.0.0.1", 29963) == OK)
	check(await until(func(): return host.players.size() == 2 and client.world != null and not client.loading_game), "guest reconnects")
	check(client.multiplayer.get_unique_id() != pid, "reconnection uses a new transport ID")
	check(await until(func(): return client.can_change_clock(2) and client.can_quick_save_load(false)), "reconnected guest retains named grants")
	# Loading an old save without permissions uses host defaults.
	var old: Dictionary = host.state.coop[CoopPermissions.KEY]
	host.state.coop.erase(CoopPermissions.KEY)
	check(CoopPermissions.mask(host, client.my_index) == 0, "old saves default to host-only")
	host.state.coop[CoopPermissions.KEY] = old
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	await frames(); get_tree().paused = false; Engine.time_scale = 1
	print("COOP_PERMISSIONS ", JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
