extends "story_coop_traps_net.gd"
## Original Shelter dismissal, disguise hand-in, transformation, Kel dialogue
## and elder's exit unlock. --single covers solo; default uses a real guest.
var single := false
var named := false
var guest_prototype := ""

func loaded() -> bool:
	return single or (client.world != null and client.zone_id == host.zone_id and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial and client.state.current_party == host.state.current_party \
		and not client.party_units(1).is_empty())

func kel(s: Session) -> GameUnit:
	for u: GameUnit in s.world.units.values():
		if String(u.info.get("name","")).to_lower()=="merc2":return u
	return null

func complete(id: String, player := 0) -> void:
	var vm := host.world.vm
	vm.briefings.active=id;vm.briefings.active_player=player
	if player>0:
		client.submit({"t":"dialog_done","id":id})
		check(await until(func():return host.state.get_pvar(player,id)==2.0),"guest completes original dialogue "+id)
	else:
		vm.briefings.complete(0,id)
		ticks(1)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	single=OS.get_cmdline_user_args().has("--single")
	named=OS.get_cmdline_user_args().has("--named-roster")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host=branch(false)
	if not single:check(host.host(29943,2)==OK,"open Shelter host")
	host.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
	host.state.create_party("FPrison");host.state.add_party_unit("FPrison","Hero","Hero1")
	host.state.set_current_party("FPrison")
	if named:
		host.state.add_party_unit("FPrison","merc2","merc2")
	else:
		host.state.make_merc(2,{"prototype":"merc2","name":"merc2","kind":"UNIT","type":50})
	await host.enter_zone("bz2h",1,false);freeze(host);ticks(6)
	check(kel(host)!=null and kel(host).has_meta("hero"),"Kir and Kel arrive in the original FPrison party")
	if not single:
		client=branch(true);GameData.player_name="Shelter Guest"
		check(client.join("127.0.0.1",29943)==OK,"connect real guest before dismissal")
		check(await until(loaded),"guest receives first Shelter visit")
		if not loaded():await finish();return
		freeze(client)
		guest_prototype=String(client.party_units(1)[0].proto.name)
		check(not guest_prototype.is_empty(),"initial guest has received its usable character and roster")
	await complete("b.bz2h.brief_6",0 if single else 1)
	check(host.state.party_member("FPrison::merc2").is_empty(),"initial briefing removes Kel's party membership")
	check(kel(host)!=null and not kel(host).has_meta("hero") and kel(host).hidden,"initial briefing keeps Kel hidden as a camp NPC")
	check(host.save_game("kel_hidden")==OK,"save before the disguise quest")
	var hidden:=CampaignState.load_from(SaveInfo.path("kel_hidden"))
	check(hidden.zones.bz2h.get("detached",[]).size()==1,"save stores Kel independently of the travelling party")
	check(await host.load_game_shown("kel_hidden"),"reload hidden Kel")
	freeze(host);check(await until(loaded),"party receives hidden-NPC reload")
	if not single:freeze(client)
	check(kel(host)!=null and kel(host).hidden,"Kel remains hidden until the authored hand-in")
	# Prepared completed quest: the tested operation is its actual Shaina
	# hand-in and both unmodified VCheck#1#2 threads, not the quest objectives.
	host.state.set_var(0,"q.gz1h.q3h",2)
	host.state.set_var(0,"b.merc8.brief_15",1)
	await complete("b.merc8.brief_15",0 if single else 1)
	ticks(3)
	check(host.state.get_var(0,"Trans")==1.0 and kel(host)!=null and not kel(host).hidden,"native hand-in reveals Kel before transformation")
	ticks(25);await frames(4)
	check(await until(func():return not host.loading_game and host.state.current_party=="FSusel" and loaded()),"authored same-zone transfer completes disguise for the party")
	freeze(host);if not single:freeze(client)
	check(kel(host)!=null and not kel(host).hidden and kel(host).pos.distance_to(Vector2(83.5,233))<0.1,"Kel survives redeployment and remains at his original camp position")
	check(kel(host)!=null and Briefings.pending_for(host.state,kel(host),0).has(["merc2","n3_2"]),"Kel offers the progression conversation")
	if not single:
		check(kel(client)!=null and not kel(client).hidden and kel(client).controller<0,"guest receives visible NPC Kel after transformation")
		print("KEL_GUEST_HANDOFF ",{"initial":guest_prototype,"party":client.state.current_party,
			"host":host.party_units(1).map(func(u):return [u.uid,u.proto.name,u.info.get("name"),u.controller]),
			"client":client.party_units(1).map(func(u):return [u.uid,u.proto.name,u.info.get("name"),u.controller])})
		check(client.state.current_party=="FSusel" and client.party_units(1)[0].proto.name==guest_prototype \
			and host.party_units(1)[0].proto.name==guest_prototype,"guest keeps its chosen character and control through the host's disguise change")
	# Make the legacy save precisely as old builds left it: no detached NPC
	# record, no living Kel. Keep the original flags and waiting VM intact.
	check(host.save_game("kel_ready")==OK,"save after the disguise hand-in")
	var legacy:=CampaignState.load_from(SaveInfo.path("kel_ready"))
	var k:=kel(host)
	if k:
		for key: String in ["units","carried"]:legacy.zones.bz2h.get(key,{}).erase(k.uid)
	legacy.zones.bz2h.erase("detached")
	check(legacy.save(SaveInfo.path("kel_legacy"))==OK,"write disposable older-format soft-lock checkpoint")
	check(await host.load_game_shown("kel_legacy"),"load older-format missing-Kel save")
	freeze(host);check(await until(loaded),"party receives recovered older save")
	if not single:freeze(client)
	check(kel(host)!=null and not kel(host).hidden,"old save recovers the missing quest NPC without replaying rewards")
	check(host.state.money==legacy.money and host.state.items==legacy.items,"recovery preserves current money and inventory")
	await complete("b.merc2.n3_2",0 if single else 1)
	check(host.state.get_var(0,"b.Elder.brief_17")==1.0,"Kel's actual completion unlocks the elder")
	await complete("b.Elder.brief_17");await complete("b.Elder.brief_18")
	check(host.state.get_var(0,"z.gz1h_gz2h")==2.0,"elder's original dialogue opens the next route")
	check(host.save_game("kel_recovered")==OK,"save the recovered quest progression")
	check(await host.load_game_shown("kel_recovered"),"reload the recovered progression")
	freeze(host);check(await until(loaded),"party receives final reload")
	check(kel(host)!=null and host.world.units.values().filter(func(u):return String(u.info.get("name","")).to_lower()=="merc2").size()==1,"recovery is idempotent and never duplicates Kel")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer:s.multiplayer.multiplayer_peer.close()
	for root: Node in branches:
		if is_instance_valid(root):root.queue_free()
	await frames(8)
	print("SHELTER_KEL ",checks," checks ",failures," failures single=",single," named=",named)
	get_tree().quit(1 if failures else 0)
