extends Node
## Original gz1h positions found by the 20 cm visibility probe. Both a live
## guard and low corpses have exposed body parts despite a blocked eye ray.
## Run with --network to exercise real snapshots and independent renderers.
const CASES: Array = [
	[997056, Vector2(489.253, 75.806), true],
	[997322, Vector2(336.817535, 152.929199), false],
	[1001005, Vector2(455.75, 183.75), true],
	[1002008, Vector2(428.1, 102.1), true],
	[1002008, Vector2(420.1, 94.1), false],
	[1002008, Vector2(420.1, 94.1), true],
	[33318975, Vector2(314.978, 107.6392), true],
]
const DELTAS: Array[Vector2] = [Vector2.ZERO, Vector2(.2, 0), Vector2(-.2, 0), Vector2(0, .2), Vector2(0, -.2)]
var sessions: Array[Session] = []
var games: Array[Game] = []
var branches: Array[Node] = []
var checks := 0
var failures := 0
var blocked_eyes := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func until(predicate: Callable, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func branch(guest: bool) -> Session:
	var root: Node = SubViewport.new() if guest else Node.new()
	if root is SubViewport:
		root.size = Vector2i(1280, 720)
		root.own_world_3d = true
		root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.name = "Guest" if guest else "Host"
	add_child(root); branches.append(root)
	var api := SceneMultiplayer.new()
	api.root_path = root.get_path()
	get_tree().set_multiplayer(api, root.get_path())
	var s := Session.new(); root.add_child(s); sessions.append(s)
	var g := Game.new(); g.session = s; s.game = g
	root.add_child(g); games.append(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	if s.world.vm != null: s.world.vm.instances.clear()
	s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false
	s.game.rig.release(); s.game.rig.set_process(false)
	s.game.get_node("UnitFog").set_process(false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":1,
		"unit_fog":1,"net_upnp":0,"net_lan":0,"net_directory":0,"scroll_border":0}, true)
	var host := branch(false)
	var client: Session
	if "--network" in OS.get_cmdline_user_args():
		client = branch(true)
		check(host.host(29931, 2) == OK, "start local co-op host")
		GameData.player_name = "Visibility Guest"
		check(client.join("127.0.0.1", 29931) == OK, "join local co-op")
		if not await until(func(): return host.players.size() == 2 and client.my_index == 1):
			check(false, "initial connection"); await finish(); return
	host.state = CampaignState.new(); host.state.ensure_hero(0, "Human Hero")
	if client: host.state.ensure_hero(1, "Human Hero", "Visibility Guest")
	await host.enter_zone("gz1h", 1, false)
	freeze(host)
	if client:
		if not await until(func(): return client.world != null and client.zone_id == "gz1h" and not client._remote_loading and client.my_index == 1):
			print("VISIBILITY_LOAD_STATE ", {"host_players":host.players,"client_index":client.my_index,"client_zone":client.zone_id,
				"client_world":client.world != null,"holding":client._zone_holding,"remote_loading":client._remote_loading,"tree_paused":get_tree().paused})
			check(false, "initial world delivery"); await finish(); return
		freeze(client)
	var w := host.world
	var hero: GameUnit = host.party_units(0)[0]
	for entry: Array in CASES:
		var target: GameUnit = w.units[entry[0]]
		var was_dead := target.dead
		target.dead = entry[2]
		for delta: Vector2 in DELTAS:
			for observer: GameUnit in w.party_units():
				observer.pos = entry[1] + delta
				observer.set_meta("perceived", w.time)
				observer.remove_meta("noticed"); observer.remove_meta("seen_corpses")
				observer.resync_drawn()
			target.resync_drawn()
			if w.sight_ray(hero, target) <= .0001: blocked_eyes += 1
			if client:
				var snaps := [target.snapshot()]
				for observer: GameUnit in w.party_units(): snaps.append(observer.snapshot())
				host._send_snap(snaps, w.time)
				if not await until(func(): return client.world.units[hero.uid].pos.distance_to(hero.pos) < .015 and client.world.units[target.uid].dead == target.dead, 5.0):
					check(false, "snapshot delivery"); await finish(); return
			var label := "%d dead=%s offset=%s" % [target.uid, target.dead, delta]
			for g: Game in games:
				var t: GameUnit = g.world.units[target.uid]
				var observer: GameUnit = g.world.units[hero.uid]
				var fog: UnitFog = g.get_node("UnitFog")
				var stable := true
				for facing in 8:
					observer.facing = facing * PI / 4.0
					fog._t = 0.0; fog._process(0.0)
					stable = stable and t.visible and not t.fogged and UnitFog.listed(g, t)
				check(stable, label + " all facings/model/minimap player=" + str(g.session.my_index))
				check(UnitFog.relevant_for(g.session, g.session.my_index).has(t), label + " command relevance player=" + str(g.session.my_index))
		target.dead = was_dead
	check(blocked_eyes >= 20, "fixture exercises blocked eye rays, not only clear ground")
	# Clearing the native retained lists must hide an unrelated distant unit;
	# the wider body check must not expand the native relevance radius.
	var far_target: GameUnit = w.units[997322]
	for observer: GameUnit in w.party_units():
		observer.pos = far_target.pos + Vector2(100, 0)
		observer.set_meta("perceived", w.time)
		observer.remove_meta("noticed"); observer.remove_meta("seen_corpses")
	check(not UnitFog.sees(UnitFog.party_eyes(host.game), far_target), "unnoticed distant target stays outside relevance radius")
	await finish()

func finish() -> void:
	for s: Session in sessions:
		if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches: root.queue_free()
	await frames(8)
	print("UNIT_VISIBILITY ", checks, " checks ", failures, " failures; ", blocked_eyes, " blocked eye samples")
	get_tree().quit(1 if failures else 0)
