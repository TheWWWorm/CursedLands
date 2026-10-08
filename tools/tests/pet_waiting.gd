extends Node
## Base-campaign substitute party, legacy unlabelled animals, wound state
## and disconnected guest ownership. No original story quest is completed.
var checks:=0
var failures:=0
var s: Session
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func pets() -> Array:
	return s.world.units.values().filter(func(u: GameUnit):return CampaignState.is_pet(u))
func enter(id: String) -> void:
	await s.enter_zone(id,1,false)
	s.world.set_physics_process(false);s.world.vm.instances.clear()
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await enter("bz1g")
	var proto:=""
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		if "wolf" in String(row.get("name","")).to_lower():proto=String(row.name);break
	var hero: GameUnit=s.party_units(0)[0]
	var u:=s.world.spawn_unit({"prototype":proto,"name":"waiting_pet","kind":"UNIT","complexion":Vector3.ONE,"position":Vector3(hero.pos.x+2,hero.pos.y,0)})
	for i in 3:check(Spells.tame(s.world,hero,u,100000.0),"actual tame stage "+str(i+1))
	u.hp=u.max_hp*0.5
	var health:=u.hp
	s.state.collect_pets(s.world)
	s.state.pets[0].erase("party") # old saves had no party label
	s.state.create_party("HeroAlone");s.state.add_party_unit("HeroAlone","Hero","Human Hero Hadagan")
	s.state.set_current_party("HeroAlone");s.redeploy_party(0)
	check(pets().is_empty() and s.state.pets.size()==1,"base substitute leaves legacy animal waiting with Zak")
	await enter("bz2g")
	check(pets().is_empty() and s.state.pets.size()==1,"travelling with substitute preserves the waiting animal")
	check(s.save_game("pet_waiting")==OK,"waiting animal saves")
	check(await s.load_game_shown("pet_waiting"),"waiting animal reloads")
	s.world.set_physics_process(false);s.world.vm.instances.clear()
	check(pets().is_empty() and s.state.pets.size()==1,"saved substitute does not deploy or discard the waiting animal")
	s.state.set_current_party("");s.redeploy_party(0)
	check(pets().size()==1 and is_equal_approx(pets()[0].hp,health),"return restores one wounded animal")
	# A saved guest's animal is lent while that player is disconnected.
	if not pets().is_empty():
		u=pets()[0];u.controller=-1;u.set_meta("orphan_of",1)
		s.state.ensure_hero(1,"Human Hero","Pet Guest")
		s.state.collect_pets(s.world)
		check(int(s.state.pets[0].controller)==1,"collection retains the disconnected guest's ownership")
		await enter("bz1g")
		u=pets()[0] if not pets().is_empty() else null
		check(u!=null and u.controller==0 and int(u.get_meta("lent_of",-1))==1,"absent guest's animal is explicitly lent to a present player")
		s.state.collect_pets(s.world)
		check(int(s.state.pets[0].controller)==1,"saving a lent animal does not change its owner")
		if u:u.die(s.party_units(0)[0])
		s.state.collect_pets(s.world)
		check(s.state.pets.is_empty(),"dead animal is removed from the active travel list")
	else:check(false,"restored animal required for ownership checks")
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("PET_WAITING ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
