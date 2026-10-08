extends "coop_story.gd"
## Ordinary Shelter exit, using its original map graph and real guest UI.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func travel_map(g: Game) -> TravelMap:
	for child in g.hud._travel.get_children():
		if child is TravelMap: return child
	return null

func destination(map: TravelMap, id: String) -> Button:
	for child in map._extra.get_children():
		if child is Button and child.text == host.zone_title(id): return child
	return null

func rebuild_extra(map: TravelMap) -> void:
	map._extra.free()
	map._build_extra()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0,
		"net_lan":0, "net_directory":0, "auto_exit":0}, true)
	var h := branch("Host", true); host = h.s; hg = h.g
	var c := branch("Guest", false); client = c.s; cg = c.g
	(cg.get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	require(host.host(29916, 2) == OK)
	GameData.player_name = "Shelter Guest"
	require(client.join("127.0.0.1", 29916) == OK)
	require(await until(func(): return host.players.size() == 2))
	host.set_physics_process(false); client.set_physics_process(false)
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero", "Shelter Guest")
	host.state.create_party("FSusel")
	host.state.add_party_unit("FSusel", "Hero2", "Hero2")
	host.state.set_current_party("FSusel")
	host.state.visited["gz3h"] = true
	# zone3's arrival handler opens the camp and edge, but leaves z.gz3h = 0.
	host.state.set_var(0, "z.bz3h", 2)
	host.state.set_var(0, "z.gz3h_bz3h", 2)
	await host.enter_zone("bz3h", 1, false)
	host.world.set_physics_process(false)
	require(await until(func(): return client.zone_id == "bz3h" and not client.loading_game and not host.loading_game))
	for i in 5: host.world.vm.tick(GameUnit.TICK)
	host.world.vm.instances.clear()
	var ex: Dictionary = host.world.zone.exits[1]
	var center: Vector2 = ex.remove.get_center()
	var hero: GameUnit = host.party_units(0)[0]
	hero.pos = center
	hg.issue({"t":"move", "units":[hero.uid], "x":center.x, "y":center.y, "exit":1})
	host._check_exits()
	require(await until(func(): return host.map_open and client.map_open))
	var map := travel_map(hg)
	var guest_map := travel_map(cg)
	require(map != null and guest_map != null)
	check(host.state.get_var(0, "z.gz3h") == 0, "ordinary departure does not change original story visibility")
	check(map._offer("gz3h").get("entrance") == 2, "native route returns to the desert's Shelter entrance")
	check(map._offer("gz4h").is_empty(), "unopened later area has no route")
	check(destination(map, "gz3h") != null, "visited reachable desert has a destination button")
	check(destination(guest_map, "gz3h") != null and destination(guest_map, "gz3h").disabled,
		"guest sees the same destination but only the host can select it")
	check(destination(map, "bz3h") == null, "Stay here does not gain a duplicate camp destination")
	# Even a route offer must not reveal an unvisited same-island story area.
	map.options.append({"zone":"gz4h", "entrance":1, "title":host.zone_title("gz4h")})
	rebuild_extra(map)
	check(destination(map, "gz4h") == null, "unvisited hidden area stays hidden")
	map.options.pop_back()
	for piece: Dictionary in map._pieces:
		if piece.id == "gz3h": piece.state = 1
	rebuild_extra(map)
	check(destination(map, "gz3h") == null, "selectable island piece does not gain a duplicate destination")
	for piece: Dictionary in map._pieces:
		if piece.id == "gz3h": piece.state = 0
	rebuild_extra(map)
	for i in 10: await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shelter-exit-host.png")
		cg.get_viewport().get_texture().get_image().save_png("user://shelter-exit-guest.png")
	var button := destination(map, "gz3h")
	if button:
		button.pressed.emit()
		check(await until(func(): return host.zone_id == "gz3h" and client.zone_id == "gz3h" and not host.loading_game and not client.loading_game),
			"ordinary exit button transfers both peers")
		host.world.set_physics_process(false)
		check(not host.map_open and not client.map_open, "travel UI closes on both peers")
		check(host.party_units(0).size() == 1 and host.party_units(1).size() == 1, "both players arrive with usable characters")
		check(host.save_game("shelter_exit") == OK, "ordinary departure saves")
		check(await host.load_game_shown("shelter_exit"), "ordinary departure reloads")
		require(await until(func(): return not host.loading_game and not client.loading_game and client.zone_id == "gz3h"))
		check(host.state.current_party == "FSusel", "departure retains the current chapter")
	host.online = false; client.online = false
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	print("SHELTER_EXIT ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass
