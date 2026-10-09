extends Node
## Real ENet late join, death, revival, save/reload and reconnect against the
## throne-room boundary. Unrelated story/AI is paused in this prepared scene.
var host: Session
var client: Session
var branches: Array[Node] = []
var branch_count := 0
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func until(predicate: Callable, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func branch(guest: bool) -> Session:
	var root: Node = SubViewport.new() if guest else Node.new()
	if root is SubViewport:
		root.size = Vector2i(1280,720); root.own_world_3d = true
		root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	branch_count += 1; root.name = "TrapBranch"+str(branch_count); add_child(root); branches.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path()
	get_tree().set_multiplayer(api,root.get_path())
	var s := Session.new(); s.name = "Session"; root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false); s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz36j" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func ticks(count: int) -> void:
	for i in count:
		host.world.time += ScriptVM.POLL; host.world.vm.tick(ScriptVM.POLL)

func visitor() -> GameUnit:
	for u: GameUnit in host.party_units(1):
		if not u.get_meta("hero",{}).has("merc"): return u
	return null

func sync_visitor(u: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec()+5000; var next := 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next:
			next = Time.get_ticks_msec()+50; host._send_snapshot_records([u.snapshot()],host.world.time)
		await get_tree().process_frame
		var replica: GameUnit = client.world.units.get(u.uid)
		if replica and replica.dead == u.dead and replica.pos.distance_to(u.pos) < .03: return true
	return false

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Boundary Guest"
	check(client.join("127.0.0.1",29933) == OK,"connect guest")
	var ready := await until(loaded)
	check(ready,"guest receives live throne room")
	if ready: freeze(client)
	return ready

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"revive":1,"control_mode":1,"scroll_border":0},true)
	host = branch(false); check(host.host(29933,2) == OK,"open local host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	var kel: Dictionary = host.state.heroes[0][0].duplicate(true)
	kel.merc = 2; kel.unit_name = "merc2"; kel.party = ""; kel.controller = 0; kel.name = "Kel"
	host.state.mercs[2] = kel; host.set_physics_process(false)
	await host.enter_zone("gz36j",1,false); freeze(host)
	host.world.vm.instances.clear()
	host.world.vm.spawn("Trap#0#3",[null]); host.world.vm.spawn("Trap#0#4",[null]); ticks(3)
	check(host.world.vm._party_records().size() == 2,"trap arms with only the two original roles present")
	if not await connect_guest(): await finish(); return
	var u := visitor(); check(u != null,"late joiner is a controllable extra participant")
	if u == null: await finish(); return
	u.pos = Vector2(48,76); u.resync_drawn(); ticks(3)
	check(u.dead,"armed original boundary kills late guest")
	check(host.world.vm._story_records().all(func(x):return not x.dead),"guest trigger leaves safe Kir and Kel alive")
	check(await sync_visitor(u),"client receives guest boundary death")
	Revive.finish(host,u); ticks(5)
	check(not u.dead,"revival does not reset the one-shot trap")
	check(await sync_visitor(u),"client receives revived guest")
	check(host.save_game("individual-trap") == OK,"save spent co-op trap")
	check(await host.load_game_shown("individual-trap"),"reload spent co-op trap")
	freeze(host)
	if not await until(loaded): check(false,"reloaded world delivery"); await finish(); return
	freeze(client); u = visitor(); ticks(5)
	check(u != null and not u.dead and u.pos.y > 75,"reloaded guest remains alive beyond already-spent boundary")
	check(await sync_visitor(u),"client receives loaded spent-trap state")
	client.multiplayer.multiplayer_peer.close()
	var old_root: Node = branches.back(); branches.erase(old_root); old_root.queue_free()
	check(await until(func():return host.players.size() == 1),"host observes real guest disconnect")
	ticks(5)
	if not await connect_guest(): await finish(); return
	u = visitor(); ticks(5)
	check(u != null and not u.dead and u.pos.y > 75,"reconnected character retains its spent trap")
	check(await sync_visitor(u),"reconnected client sees living character")
	host.world.vm.spawn("Trap#0#4",[null]); ticks(3)
	check(u.dead,"new authored activation can kill the same participant again")
	check(await sync_visitor(u),"client receives death from the new activation")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s) and s.multiplayer.multiplayer_peer:
			# A queued branch can still tick before deletion. Match menu teardown:
			# detach the transport before closing it, so status/ack callbacks do
			# not observe an online Session with an already-closed ENet peer.
			var peer := s.multiplayer.multiplayer_peer
			s.online = false
			s.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			peer.close()
	for root: Node in branches:
		if is_instance_valid(root): root.queue_free()
	await frames(8)
	print("STORY_COOP_TRAPS_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
