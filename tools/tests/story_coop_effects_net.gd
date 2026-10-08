extends Node
## Actual throne-room shrines, spell effects, ENet snapshots and saved VM.
## Prepared scene: unrelated boss/cutscene threads and actor AI are paused.
var host: Session
var client: Session
var branches: Array[Node] = []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(n := 3) -> void:
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
		root.size = Vector2i(1280,720); root.own_world_3d = true
		root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.name = "Guest" if guest else "Host"
	add_child(root); branches.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path()
	get_tree().set_multiplayer(api, root.get_path())
	var s := Session.new(); root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false)
	s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz36j" and not client._remote_loading and not client._zone_holding and not client.loading_game and client.my_index == 1

func buffs(u: GameUnit) -> bool:
	return u.buffs.has("strength") and u.buffs.has("speed") and u.buffs.has("antimagic")

func sync_party(party: Array) -> bool:
	# Production sends unreliable snapshots repeatedly. A single datagram
	# during initial world publication is not a delivery acknowledgement.
	var deadline := Time.get_ticks_msec()+5000
	var next := 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next:
			next = Time.get_ticks_msec()+50
			var snaps := []
			for u: GameUnit in party: snaps.append(u.snapshot())
			host._send_snapshot_records(snaps, host.world.time)
		await get_tree().process_frame
		if party.all(func(u: GameUnit):
			var replica: GameUnit = client.world.units.get(u.uid)
			# HP is derived from byte-quantized body parts after receipt. Check
			# those wire values and max HP, not exact unquantized authority HP.
			return replica != null and replica.snapshot()[8] == u.snapshot()[8] \
				and is_equal_approx(replica.max_hp, snappedf(u.max_hp,1.0/16.0)) \
				and replica.buffs.keys() == u.buffs.keys()): return true
	print("SHRINE_DELIVERY_FAILED ",JSON.stringify({"serial":host._load_serial,"epoch":client._pool_epoch,
		"holding":client._zone_holding,"loading":client._remote_loading,"players":host.players}))
	for u: GameUnit in party:
		var replica: GameUnit = client.world.units.get(u.uid)
		print("SHRINE_UNIT ", {"id":u.uid,"hp":u.hp,"buffs":u.buffs.keys(),
			"replica_hp":replica.hp if replica else -1,"replica_buffs":replica.buffs.keys() if replica else []})
	return false

func trigger(lever: int, label: String) -> void:
	var vm := host.world.vm
	var party := vm._party_records()
	check(party.size() == 3 and vm._story_records()[1].controller == 1, label+": real guest-owned Kel plus extra guest")
	for u: GameUnit in party:
		u.buffs.clear(); u.refresh_max_hp(); u.hp = 1
	check(await sync_party(party), label+": client first receives injured, unbuffed party")
	# Use the normal authoritative lever path; the original handler then runs.
	host.world.levers[lever].enabled = true
	vm._use_lever(host.party_units(1)[0], lever)
	vm.tick(GameUnit.TICK)
	for u: GameUnit in party:
		check(buffs(u) and u.hp > 1, label+": authored buffs/healing reach "+u.display_name)
	check(await sync_party(party), label+": snapshots arrive through ENet")
	for u: GameUnit in party:
		var replica: GameUnit = client.world.units.get(u.uid)
		check(replica != null and buffs(replica) and replica.hp > 1, label+": independent client displays buffs/healing for "+u.display_name)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host = branch(false); client = branch(true)
	check(host.host(29932,2) == OK, "open local host")
	GameData.player_name = "Shrine Guest"
	check(client.join("127.0.0.1",29932) == OK, "connect local guest")
	if not await until(func(): return host.players.size() == 2 and client.my_index == 1):
		check(false, "initial connection"); await finish(); return
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Shrine Guest")
	var kel: Dictionary = host.state.heroes[0][0].duplicate(true)
	kel.merc = 2; kel.unit_name = "merc2"; kel.party = ""; kel.controller = 1; kel.name = "Kel"
	host.state.mercs[2] = kel
	host.set_physics_process(false)
	await host.enter_zone("gz36j",1,false); freeze(host)
	host.world.vm.instances.clear(); host.world.vm.spawn("Healing#0#1", [host.party_units(0)[0]])
	if not await until(loaded):
		check(false, "initial throne-room delivery"); await finish(); return
	freeze(client)
	await trigger(1022201,"First shrine")
	check(host.save_game("coop-shrine") == OK,"save actual co-op shrine state")
	check(await host.load_game_shown("coop-shrine"),"reload actual co-op shrine save")
	freeze(host)
	if not await until(loaded):
		check(false,"reloaded world delivery"); await finish(); return
	freeze(client)
	check(host.world.vm.instances.any(func(i): return i.sname == "Healing#1#1" and not i.killed),"saved original chain resumes at opposite shrine")
	for u: GameUnit in host.world.vm._party_records():
		check(buffs(u),"saved buffs survive for "+u.display_name)
	await trigger(1022202,"Opposite shrine after reload")
	if DisplayServer.get_name() != "headless":
		# Inspect the party in the open hall, clear of the entrance lintel.
		var party := host.world.vm._party_records()
		for i in party.size():
			party[i].pos = Vector2(45+i*2,50); party[i].resync_drawn()
		await sync_party(party)
		var u: GameUnit = host.party_units(1).filter(func(x): return not x.get_meta("hero",{}).has("merc"))[0]
		host.game.rig.set_pose({"at":[u.pos.x, host.world.ground_at(u.pos.x,u.pos.y)+3, -u.pos.y],
			"yaw":0.5,"distance":16,"tilt":.75,"free":true})
		await frames(20)
		check(get_viewport().get_texture().get_image().save_png("user://coop-shrine.png") == OK,"rendered shrine effect capture")
		print("SHRINE_IMAGE ",ProjectSettings.globalize_path("user://coop-shrine.png"))
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if s and s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches: root.queue_free()
	await frames(8)
	print("STORY_COOP_EFFECTS_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
