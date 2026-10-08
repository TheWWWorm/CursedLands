extends Node
## Actual Gipath guard perception/commands with a real late-joining peer.
## Unrelated AI/story is paused; no performance conclusion comes from this.
var host: Session
var client: Session
var branches: Array[Node] = []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame

func until(predicate: Callable, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func branch(guest: bool) -> Session:
	var root: Node = SubViewport.new() if guest else Node.new()
	if root is SubViewport:
		root.size = Vector2i(1280,720); root.own_world_3d = true; root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.name = "GuardGuest" if guest else "GuardHost"; add_child(root); branches.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path(); get_tree().set_multiplayer(api,root.get_path())
	var s := Session.new(); s.name = "Session"; root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false); s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz10g" and client.my_index == 1 \
		and not client.loading_game and not client._remote_loading and not client._zone_holding and client._pool_epoch == host._load_serial

func ticks(n: int) -> void:
	for i in n: host.world.time += ScriptVM.POLL; host.world.vm.tick(ScriptVM.POLL)

func attack_target(u: GameUnit) -> GameUnit:
	if u.order.get("type","") == "attack": return u._order_target()
	for order: Dictionary in u.orders:
		if order.get("type","") == "attack": return order.get("target")
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host = branch(false)
	var opened := host.host(29934,2) == OK; check(opened,"start local guard host")
	if not opened: await finish(); return
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	var kel: Dictionary = host.state.heroes[0][0].duplicate(true)
	kel.merc = 2; kel.unit_name = "merc2"; kel.party = ""; kel.controller = 0; kel.name = "Kel"; host.state.mercs[2] = kel
	host.set_physics_process(false); await host.enter_zone("gz10g",1,false); freeze(host)
	# Let the original startup finish its Sleep(2) and define CityGuard;
	# discard the unrelated scripts it arms before they execute.
	for i in 4:
		host.world.vm.instances = host.world.vm.instances.filter(func(x):return x.sname == "WorldScript")
		ticks(1)
	host.world.vm.instances.clear()
	client = branch(true); GameData.player_name = "Guard Guest"
	check(client.join("127.0.0.1",29934) == OK,"connect late guest")
	if not await until(loaded): check(false,"guest map delivery"); await finish(); return
	check(true,"late guest receives actual Gipath map"); freeze(client)
	var w := host.world; var vm := w.vm
	var u: GameUnit = host.party_units(1)[0]
	var guards: Array = vm.globals.get("CityGuard",[]).filter(func(g):return g != null and not g.dead)
	check(guards.size() >= 2,"original WorldScript created living city guards")
	if guards.size() < 2: await finish(); return
	var guard: GameUnit = guards[0]; var guard_id := guard.uid
	var authored_facing := guard.facing
	vm.globals.CityGuard = [guard]; guard.order.clear(); guard.orders.clear(); guard.remove_meta("ai_target")
	var far := Vector2(10,10)
	for corner: Vector2 in [Vector2(270,10),Vector2(10,300),Vector2(270,300)]:
		if corner.distance_to(guard.pos) > far.distance_to(guard.pos): far = corner
	far = w.nav.nearest_walkable(far,20)
	for native: GameUnit in vm._story_records(): native.pos = far; native.resync_drawn()
	var found := false
	for radius in [5.0,3.0,2.0]:
		for angle in 16:
			var point: Vector2 = guard.pos+Vector2.from_angle(angle*TAU/16)*radius
			if not w.nav.is_walkable(point): continue
			u.pos = point; guard.facing = (u.pos-guard.pos).angle()
			if vm._sees_has([guard],u): found = true; break
		if found: break
	check(found,"real guard can notice guest on a walkable map position")
	if not found: await finish(); return
	check(vm._story_records().all(func(n):return not vm._sees_has([guard],n)),"both native roles remain outside guard perception")
	print("GUARD_PROBE ",{"guard":guard.uid,"position":guard.pos,"guest":u.pos,"native":far,"sight_ray":w.sight_ray(guard,u)})
	u.hidden = true; vm.spawn("VCityGuard#0#2",[null]); ticks(3)
	check(guard.order.is_empty() and guard.orders.is_empty(),"hidden extra guest does not activate guard")
	u.hidden = false; u.resync_drawn(); guard.resync_drawn(); ticks(3)
	check(attack_target(guard) == u and guard.get_meta("ai_target",null) == u,"original alarm orders real guard to attack visible extra guest")
	check(guard.gait_run,"original guard Run action remains")
	var deadline := Time.get_ticks_msec()+5000; var next := 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next:
			next = Time.get_ticks_msec()+50; host._send_snapshot_records([u.snapshot(),guard.snapshot()],w.time)
		await get_tree().process_frame
		var replica: GameUnit = client.world.units.get(guard_id)
		if replica and replica.gait_run == guard.gait_run and client.world.units[u.uid].pos.distance_to(u.pos) < .03: break
	check(client.world.units[guard_id].gait_run and client.world.units[u.uid].pos.distance_to(u.pos) < .03,"client receives actual running guard and guest positions")
	var saved_facing := guard.facing
	var corpse: GameUnit = guards[1]
	var corpse_id := corpse.uid
	var corpse_point: Vector2 = w.nav.nearest_walkable_for(corpse,corpse.pos+Vector2(3,2),5)
	corpse.pos = corpse_point; corpse.facing = .85; corpse.die()
	# Ordinary combat orders are re-evaluated after load. Save an untriggered
	# alarm instead, and prove its live guest query resumes against new units.
	u.hidden = true; guard.order.clear(); guard.orders.clear(); guard.remove_meta("ai_target")
	vm.instances.clear(); vm.spawn("VCityGuard#0#2",[null]); ticks(3)
	check(host.save_game("guard-guest") == OK,"save pending guest guard alarm")
	check(await host.load_game_shown("guard-guest"),"reload pending guest guard alarm"); freeze(host)
	check(await until(loaded),"client receives reloaded guard world")
	guard = host.world.units[guard_id]; u = host.party_units(1)[0]
	check(is_equal_approx(guard.facing,saved_facing),"living guard retains saved facing and vision cone")
	corpse = host.world.units[corpse_id]
	if not (corpse.dead and is_zero_approx(corpse.hp) and corpse.pos.distance_to(corpse_point) < .001 and is_equal_approx(corpse.facing,.85)):
		print("CORPSE_RELOAD_DIAGNOSTIC ",{"uid":corpse_id,"dead":corpse.dead,"hp":corpse.hp,"position":corpse.pos,"expected":corpse_point,"facing":corpse.facing,
			"saved":host.state.zones.gz10g.units.get(corpse_id)})
	check(corpse.dead and is_zero_approx(corpse.hp) and corpse.pos.distance_to(corpse_point) < .001 and is_equal_approx(corpse.facing,.85),"moved corpse retains death, position and facing")
	check(host.world.vm.instances.any(func(x):return x.sname == "VCityGuard#0#2" and not x.killed),"pending original alarm retains saved state")
	u.hidden = false; ticks(3)
	if attack_target(guard) != u:
		print("GUARD_RELOAD_DIAGNOSTIC ",{"guard":guard.pos,"facing":guard.facing,"guest":u.pos,"hidden":u.hidden,
			"noticed":host.world.vm._sees_has([guard],u),"group":host.world.vm.globals.get("CityGuard",[]),
			"orders":guard.orders,"time":host.world.vm.time,"threads":host.world.vm.instances.map(func(x):return [x.sname,x.poll,x.killed,x.frames.size()])})
	check(attack_target(guard) == u,"resumed alarm targets the re-created guest")
	var legacy := CampaignState.load_from(SaveInfo.path("guard-guest"))
	# Old saves have six-field living NPC rows and no corpse pose row.
	legacy.zones.gz10g.units[guard_id].resize(6)
	legacy.zones.gz10g.units.erase(corpse_id)
	check(legacy.save(SaveInfo.path("guard-guest-legacy")) == OK,"write isolated old-format NPC fixture")
	check(await host.load_game_shown("guard-guest-legacy"),"load old-format NPC state"); freeze(host)
	check(await until(loaded),"client receives old-format world")
	check(is_equal_approx(host.world.units[guard_id].facing,authored_facing) and host.world.units[corpse_id].dead,
		"old NPC rows retain authored facing fallback and death state")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s) and s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches: root.queue_free()
	await frames(8)
	print("STORY_COOP_PREDICATES_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
