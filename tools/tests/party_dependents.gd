extends "coop_story.gd"
## Original Shaina out/return handlers with a guest-owned Kel and a tamed
## animal. Prepared chapter checkpoint, real ENet peers and save roundtrips.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func pets(s: Session) -> Array:
	return s.world.units.values().filter(func(u: GameUnit):return CampaignState.is_pet(u))
func companions(s: Session) -> Array:
	return s.world.units.values().filter(func(u: GameUnit):return u.has_meta("hero") and u.get_meta("hero").has("merc"))
func enter(id: String) -> void:
	await host.enter_zone(id,1,false)
	host.world.set_physics_process(false)
	require(await until(func():return client.zone_id==id and not client.loading_game and not host.loading_game))
	host.world.vm.instances.clear()
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Guest",false);client=c.s;cg=c.g
	var port:=29909
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--label=") and "before" in arg:port=29910
	require(host.host(port,2)==OK)
	GameData.player_name="Dependent Guest"
	require(client.join("127.0.0.1",port)==OK)
	require(await until(func():return host.players.size()==2))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Dependent Guest")
	host.state.create_party("FSusel");host.state.add_party_unit("FSusel","Hero","Human Hero");host.state.set_current_party("FSusel")
	await enter("bz5h")
	# Kel's recruitment happened in the earlier prison camp. Restore that
	# actual actor into the prepared chapter; bz5h does not contain merc2.
	var kel_record: Dictionary={}
	for row: Dictionary in EIMob.load_bytes(GameData.read_file("maps/bz1h.mob")).objects:
		if row.get("name","").to_lower()=="merc2":kel_record=row.duplicate(true);break
	require(not kel_record.is_empty())
	var lead: GameUnit=host.party_units(0)[0]
	kel_record.position=Vector3(lead.pos.x+2,lead.pos.y,0)
	host.world.spawn_unit(kel_record)
	host.state.set_var(0,"apartyn2",1);host.merc_changed(2,true,1)
	check(companions(host).size()==1 and companions(host)[0].controller==1,"Kel is hired by the guest in FSusel")
	var name:=""
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		if "wolf" in String(row.get("name","")).to_lower():name=String(row.name);break
	var guest: GameUnit=host.party_units(1)[0]
	var rec:={"prototype":name,"name":"travel_pet","kind":"UNIT","complexion":Vector3.ONE,"position":Vector3(guest.pos.x+3,guest.pos.y,0)}
	var pet:=host.world.spawn_unit(rec)
	require(pet!=null)
	for i in 3:check(Spells.tame(host.world,guest,pet,100000.0),"original tame stage "+str(i+1))
	pet.hp=pet.max_hp*0.6
	var pet_hp:=pet.hp
	host.announce_unit(pet)
	host.state.collect_pets(host.world)
	check(host.state.pets.size()==1 and int(host.state.pets[0].controller)==1,"pet records its guest owner")
	# Ordinary named LiA chapters keep the same protagonist's animal.
	await enter("gz2h")
	check(pets(host).size()==1 and is_equal_approx(pets(host)[0].hp,pet_hp),"pet follows the named party without healing its body")
	check(not pets(host).is_empty() and await until(func():return client.world.units.values().any(func(u):return u.info.get("name","")=="travel_pet" and u.controller==1)),"guest sees its travelling animal")
	await enter("bz5h")
	var vm:=host.world.vm
	vm.briefings.active="b.merc8.brief_23";vm.briefings.active_player=0;vm.briefings._pending_dialog={}
	host.apply_command({"t":"dialog_done","id":"b.merc8.brief_23"},0)
	for i in 4:vm.tick(GameUnit.TICK)
	check(host.state.current_party=="Shaina","original conversation selects Shaina")
	check(companions(host).is_empty(),"in-place substitute removes guest-owned waiting Kel")
	check(pets(host).is_empty() and host.state.pets.size()==1,"substitute leaves the protagonist's pet waiting intact")
	check(await until(func():return host.zone_id=="gz2h" and client.zone_id=="gz2h" and not host.loading_game and not client.loading_game),"authored Shaina field transfer completes on both peers")
	host.world.set_physics_process(false);host.world.vm.instances.clear()
	check(host.save_game("shaina_waiting")==OK,"temporary chapter with waiting animal saves")
	check(await host.load_game_shown("shaina_waiting"),"temporary chapter with waiting animal reloads")
	host.world.set_physics_process(false)
	require(await until(func():return not client.loading_game and not host.loading_game))
	check(host.state.pets.size()==1 and pets(host).is_empty(),"waiting pet survives a save while absent from the world")
	await enter("bz5h")
	vm=host.world.vm
	host.state.set_var(0,"b.merc8.brief_24",1)
	vm.spawn("VCheck#1#1",[])
	for i in 4:vm.tick(GameUnit.TICK)
	check(host.state.current_party=="FSusel","original return handler restores FSusel in place")
	check(companions(host).size()==1 and companions(host)[0].controller==1,"return restores exactly one guest-owned Kel")
	check(pets(host).size()==1 and pets(host)[0].controller==1 and is_equal_approx(pets(host)[0].hp,pet_hp),"return restores the guest's wounded animal")
	check(companions(host).size()==1 and await until(func():return companions(client).size()==1 and companions(client)[0].controller==1),"returned companion is controlled by the guest on its peer")
	check(host.save_game("party_returned")==OK,"restored party saves")
	check(await host.load_game_shown("party_returned"),"restored party reloads")
	host.world.set_physics_process(false)
	require(await until(func():return not client.loading_game and not host.loading_game))
	check(companions(host).size()==1 and pets(host).size()==1,"save/reload does not duplicate restored dependents")
	await enter("gz2h")
	check(companions(host).size()==1 and companions(host)[0].controller==1 and pets(host).size()==1,"next field deployment keeps both dependents")
	# Death removes only the active animal, never resurrects it next trip.
	if not pets(host).is_empty():pets(host)[0].die(host.party_units(0)[0])
	host.state.collect_pets(host.world)
	check(host.state.pets.is_empty(),"dead active animal is not retained for respawn")
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	for i in 10:await get_tree().process_frame
	print("PARTY_DEPENDENTS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
func _process(_dt: float) -> void:pass
