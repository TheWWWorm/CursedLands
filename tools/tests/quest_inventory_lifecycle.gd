extends Node
## Original quest carriers, real save/reload and zone revisit. Commands are
## direct to isolate inventory lifetime from combat/pathfinding and dialogue UI.
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz3g",1,false)
	var w:=s.world;var vm:=w.vm
	vm.instances.clear()
	if not w.units.has(3323):vm._add_mob("zone3obr.mob")
	var hero: GameUnit=s.party_units(0)[0]
	hero.stats.dex=999.0
	for nid in [3323,3470]:
		var carrier: GameUnit=w.units.get(nid)
		check(carrier!=null,"original stolen-pair carrier %d is present"%nid)
		if carrier:s.steal(hero,carrier)
	check(s.state.quest_items.has("awl") and s.state.quest_items.has("knife"),"both quest items are stolen from their actual carriers")
	vm.briefings._rewards("m4")
	check(not s.state.quest_items.has("awl") and not s.state.quest_items.has("knife"),"authored M4 turn-in consumes both items")
	check(s.save_game("quest_inventory")==OK,"stolen-carrier checkpoint saves")
	check(await s.load_game_shown("quest_inventory"),"stolen-carrier checkpoint reloads")
	await s.enter_zone("bz1g",1,false)
	await s.enter_zone("gz3g",1,false)
	w=s.world;vm=w.vm;vm.instances.clear()
	hero=s.party_units(0)[0]
	for nid in [3323,3470]:
		var carrier: GameUnit=w.units.get(nid)
		check(carrier!=null and carrier.has_meta("pockets"),"revisited carrier retains its mutable inventory %d"%nid)
		if carrier:
			carrier.die(hero)
			check(not carrier.get_meta("loot",[]).any(func(it):return String(it) in ["awl","knife"]),"corpse does not regenerate its stolen quest item %d"%nid)
			s.take_loot(hero,carrier)
	check(not s.state.quest_items.has("awl") and not s.state.quest_items.has("knife"),"loot after turn-in/save/reload/revisit cannot duplicate the pair")
	# The amulet has a DB turn-in, not an EraseQuestItem in zone6.
	s.state.add_item("dragonamulet");s.state.add_item("dcbook")
	vm.briefings._rewards("z15")
	check(not s.state.quest_items.has("dragonamulet") and not s.state.quest_items.has("dcbook"),"authored Z15 dialogue consumes the Dragon Amulet and book")
	await s.enter_zone("gz7g",1,false)
	vm=s.world.vm
	for i in 5:vm.tick(GameUnit.TICK)
	vm.instances.clear()
	s.state.add_item("cagekey00")
	vm.world.lever_sys.set_state(4955,1)
	vm.spawn("VCheck#0#170",[null])
	for i in 4:vm.tick(GameUnit.TICK)
	check(not s.state.quest_items.has("cagekey00"),"actual Dead City cage-open handler consumes the Cage Key")
	# An object argument means the named unit's carried bag, not player 0.
	await s.enter_zone("gz11k",1,false)
	vm=s.world.vm
	for i in 5:vm.tick(GameUnit.TICK)
	vm.instances.clear()
	var guardian: GameUnit=vm.globals.get("DGuardian")
	check(guardian!=null,"original DGuardian role resolves")
	if guardian:
		guardian.info.quest_items=["driadidol00","driadidol00"]
		guardian.set_meta("pockets",["driadidol00","driadidol00","tiny potion 1"])
		s.state.add_item("driadidol00")
		vm.spawn("VTriger#0#227",[null])
		vm.tick(GameUnit.TICK)
		check(guardian.get_meta("pockets").count("driadidol00")==1,"RemoveQuestItem removes one copy from its named unit")
		check(s.state.quest_items.has("driadidol00"),"unit removal leaves the player's separate copy intact")
		check(guardian.get_meta("pockets").has("tiny potion 1"),"unit removal preserves unrelated carried loot")
	await s.enter_zone("gz6g",1,false)
	vm=s.world.vm
	for i in 5:vm.tick(GameUnit.TICK)
	vm.instances.clear()
	var dragon: GameUnit=vm.globals.get("YDragon")
	check(dragon!=null,"authored young dragon resolves")
	if dragon:
		dragon.pos.y=294
		hero=s.party_units(0)[0];hero.pos=dragon.pos+Vector2(40,0)
		s.state.set_var(0,"GFol",1)
		vm.spawn("VCheck#0#362",[null])
		for i in 3:vm.tick(GameUnit.TICK)
		check(dragon.mode=="guard" and dragon.mode_data.get("point")==Vector2(78,336),"crossing the original boundary sends the dragon home")
		for i in 155:vm.tick(GameUnit.TICK)
		check(s.state.get_var(0,"GFol")==0,"original 150-tick delay clears the dragon-follow flag")
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	print("QUEST_INVENTORY_LIFECYCLE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
