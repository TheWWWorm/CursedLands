extends "coop_story.gd"
## Real ENet peers receive equipment charge and effects from one authority.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	if s.world.vm: s.world.vm.instances.clear()

func finish() -> void:
	for s: Session in [host,client]:
		if s:
			s.online = false
			var peer := s.multiplayer.multiplayer_peer
			s.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			if peer: peer.close()
	for root in branches: root.queue_free()
	for i in 5: await get_tree().process_frame
	print("ENCHANTED_EQUIPMENT_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"show_tutorial":0},true)
	var h := branch("Host",true); host = h.s; hg = h.g
	var c := branch("Guest",false); client = c.s; cg = c.g
	check(host.host(29947,2) == OK,"ENet authority opens")
	CoopProgress.bring_slot = ""
	GameData.player_name = "Equipment Guest"
	check(client.join("127.0.0.1",29947) == OK,"guest connects")
	check(await until(func():return host.players.size()==2 and client.my_index==1),"guest handshake completes")
	if failures: await finish(); return
	host.state = CampaignState.new()
	host.state.ensure_hero(0,"Human Hero"); host.state.ensure_hero(1,"Human Hero")
	var sword := "unique sword.steel|weak{it}"
	var sight := "uniquegipathadagan helm.iron|eagle_sight{ic}"
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		sight = "jun high pants.diamond|eagle_sight{ic;d1;m2}"
	for idx in [0,1]:
		var rec: Dictionary = host.state.heroes[idx][0]
		rec.armors = [sight]; rec.weapons = [Items.with_charge(sword,0)]; rec.quick = []
	var zone := "gz1h" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz1g"
	await host.enter_zone(zone,1,false)
	freeze(host)
	check(await until(func():return client.world != null and client.zone_id==zone and not client._remote_loading and not client._zone_holding,90),"guest receives equipment and map")
	if failures: await finish(); return
	freeze(client)
	var owner: GameUnit = host.party_units(0)[0]
	var visitor: GameUnit = host.party_units(1)[0]
	var owner_rec: Dictionary = owner.get_meta("hero")
	var guest_rec: Dictionary = visitor.get_meta("hero")
	# Reset to a known depleted state after the ordinary zone/loading ticks.
	for u: GameUnit in [owner,visitor]:
		var rec: Dictionary = u.get_meta("hero")
		rec.weapons = [Items.with_charge(sword,0)]; rec.armors = [sight]
		u.buffs = {}; u.remove_meta("ic_cd")
	for i in 10: host.world._advance(GameUnit.TICK)
	check(owner.sense_bonus(0)>0 and visitor.sense_bonus(0)>0,"both owners activate their sensing equipment")
	check(absf(Items.charge(owner_rec.weapons[0])-Items.energy(sword)*0.01)<0.002,"authority recharges each sword once per tick")
	host.sync_state()
	host._send_snapshot_records([owner.snapshot(),visitor.snapshot()],host.world.time)
	check(await until(func():return client.world.units[visitor.uid].sense_bonus(0)>0 \
		and absf(Items.charge(client.world.units[visitor.uid].get_meta("hero").weapons[0])-Items.charge(guest_rec.weapons[0]))<0.002),"guest receives sight effect and exact authoritative charge")
	var frozen: String = client.world.units[visitor.uid].get_meta("hero").weapons[0]
	for i in 20: client.world._deliver(GameUnit.TICK)
	check(client.world.units[visitor.uid].get_meta("hero").weapons[0]==frozen,"guest cannot recharge its own replica")
	# A real host pause excludes wall time from equipment and effect clocks.
	host._rpc_clock(true,true,0)
	var charge := String(owner_rec.weapons[0])
	await get_tree().create_timer(0.2,true,false,true).timeout
	check(owner_rec.weapons[0]==charge,"shared pause keeps equipment charge frozen")
	host._rpc_clock(true,false,0)
	for i in 1000: host.world._advance(GameUnit.TICK)
	check(Items.charge(owner_rec.weapons[0])==Items.energy(sword),"owner's depleted sword recharges fully")
	check(Items.charge(guest_rec.weapons[0])==Items.energy(sword),"guest's depleted sword recharges fully")
	host.world.combat.weapon_spell(owner,visitor)
	check(visitor.buffs.has("weak"),"recharged ancient sword applies Weaken")
	host.sync_state(); host._send_snapshot_records([owner.snapshot(),visitor.snapshot()],host.world.time)
	check(await until(func():return client.world.units[visitor.uid].buffs.has("weak") \
		and absf(Items.charge(client.world.units[owner.uid].get_meta("hero").weapons[0])-Items.charge(owner_rec.weapons[0]))<0.002),"guest receives the renewed sword effect and spent charge")
	await finish()
