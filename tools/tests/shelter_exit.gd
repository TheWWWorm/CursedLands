extends "coop_story.gd"
## Ordinary LiA camp departure: original region reveal, hover, objectives,
## host authority and save/reload over real ENet. --portal matches the report.
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

func hit_point(map: TravelMap, id: String) -> Vector2:
	var i := map._piece_of(id)
	if i < 0: return Vector2.INF
	# Pick an actual rendered triangle, through the normal ray-based input.
	for pair: Array in map._pieces[i].faces:
		var mesh: MeshInstance3D = pair[0]
		var faces: PackedVector3Array = pair[1]
		for t in range(0, faces.size(), 3):
			var at := mesh.global_transform * ((faces[t] + faces[t+1] + faces[t+2]) / 3.0)
			var point := map._cam.unproject_position(at) * map.size / Vector2(map._vp.size)
			if map._piece_at(point) == i and map._button_at(point) < 0: return point
	return Vector2.INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var portal := OS.get_cmdline_user_args().has("--portal")
	var camp_id := "bz2h" if portal else "bz3h"
	var region := "gz1h" if portal else "gz3h"
	var edge := region + "_" + camp_id
	var entrance := 5 if portal else 2
	var quest := "q2h" if portal else "q8h"
	var label := "portal" if portal else "shelter"
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0,
		"net_lan":0, "net_directory":0, "auto_exit":0, "scroll_border":0}, true)
	var h := branch("Host", true); host = h.s; hg = h.g
	var c := branch("Guest", false); client = c.s; cg = c.g
	(cg.get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	require(host.host(29916, 2) == OK)
	GameData.player_name = "Map Guest"
	require(client.join("127.0.0.1", 29916) == OK)
	require(await until(func(): return host.players.size() == 2))
	host.set_physics_process(false); client.set_physics_process(false)
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero", "Map Guest")
	host.state.create_party("FSusel")
	host.state.add_party_unit("FSusel", "Hero2", "Hero2")
	host.state.set_current_party("FSusel")
	host.state.visited[region] = true
	# Existing remake saves have a visited region but its z.<id> is still 0.
	host.state.set_var(0, "z." + camp_id, 2)
	host.state.set_var(0, "z." + edge, 2)
	host.state.set_var(0, "q.%s.%s" % [region, quest], 1)
	await host.enter_zone(camp_id, 1, false)
	host.world.set_physics_process(false)
	require(await until(func(): return client.zone_id == camp_id and not client.loading_game and not host.loading_game))
	host.world.vm.instances.clear()
	check(host.state.get_var(0, "z." + region) == 0, "fixture starts with the missing reveal from an old save")
	check(host.save_game(label + "_before") == OK, "old hidden-region state saves")
	check(await host.load_game_shown(label + "_before"), "old hidden-region state reloads")
	require(await until(func(): return not host.loading_game and not client.loading_game))
	host.world.set_physics_process(false)
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
	check(host.state.get_var(0, "z." + region) == 1, "ordinary edge departure reveals the region as the original does")
	check(client.state.get_var(0, "z." + region) == 1, "guest receives the reveal before building its map")
	check(map._offer(region).get("entrance") == entrance, "native return entrance remains selected")
	check(map._offer("gz4h").is_empty(), "unopened later area has no route")
	check(map._pieces[map._piece_of("gz4h")].state == 0, "unrelated hidden region stays hidden")
	check(destination(map, region) == null and destination(guest_map, region) == null,
		"both peers use the original island region without a fallback destination button")
	for i in 10: await get_tree().process_frame
	var host_point := hit_point(map, region)
	var guest_point := hit_point(guest_map, region)
	check(host_point != Vector2.INF and guest_point != Vector2.INF, "region triangles are reachable by the actual input picker")
	for panel: TravelMap in [map, guest_map]:
		var index := panel._piece_of(region)
		panel._on_move(host_point if panel == map else guest_point)
		check(panel._hover == index and not panel._hover_brief, "region hover shows its location and quest panel")
		check(panel._pieces[index].quests.has(GameData.text("quest " + quest).get_slice("\n", 0).strip_edges()),
			"hover panel includes the active original quest")
		var material: StandardMaterial3D = panel._pieces[index].mats[0]
		check(material.albedo_texture == panel._tex_map and material.albedo_color == panel._highlight,
			"hover uses the original outlined region texture and Suslanger tint")
	if portal:
		check(GameData.text("quest q2h").begins_with("Списки рабов"), "fixture matches the user's original quest screenshot")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://" + label + "-map-host.png")
		cg.get_viewport().get_texture().get_image().save_png("user://" + label + "-map-guest.png")
	map._on_press(host_point)
	guest_map._on_press(guest_point)
	check(map.objectives != null and guest_map.objectives != null, "both peers can browse objectives by clicking the region")
	if map.objectives and guest_map.objectives:
		check(map.objectives.zone == region and map.objectives.quests.has(quest), "region opens its matching objectives")
		check(map.objectives.leader and not guest_map.objectives.leader, "only the host gets travel confirmation")
		guest_map.objectives.travel()
		client.submit({"t":"travel", "zone":region, "entrance":entrance})
		for i in 10: await get_tree().process_frame
		check(host.map_open and client.map_open and host.zone_id == camp_id, "guest confirmation and travel RPC cannot transfer the party")
		map.objectives.travel()
		check(await until(func(): return host.zone_id == region and client.zone_id == region and not host.loading_game and not client.loading_game),
			"host confirms the region and both peers arrive")
		host.world.set_physics_process(false)
		host.world.vm.instances.clear()
		check(not host.map_open and not client.map_open, "travel UI closes on both peers")
		check(host.party_units(0).size() == 1 and host.party_units(1).size() == 1, "both players arrive with usable characters")
		check(host.save_game(label + "_after") == OK, "revealed region saves")
		check(await host.load_game_shown(label + "_after"), "revealed region reloads")
		require(await until(func(): return not host.loading_game and not client.loading_game and client.zone_id == region))
		check(host.state.get_var(0, "z." + region) == 1 and client.state.get_var(0, "z." + region) == 1,
			"reveal survives save/reload on both peers")
		check(host.state.current_party == "FSusel", "departure retains the current chapter")
	host.online = false; client.online = false
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	print("MAP_REGION ", label, " ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass
