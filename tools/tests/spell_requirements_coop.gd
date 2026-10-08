extends "coop_story.gd"
## Real player reset, UI selection, forged client requests and queued casts.
var checks := 0
var failures := 0
const SPELL := "healing{e1;e1}"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func frames(n := 12) -> void:
	for i in n: await get_tree().process_frame
func loaded(id: String) -> bool:
	return client.zone_id==id and not client.loading_game and not client._remote_loading and not host.loading_game \
		and client.state.current_party==host.state.current_party and not client.party_units(1).is_empty()
func freeze() -> void:
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1},true)
	var a:=branch("Host",true);host=a.s;hg=a.g
	var b:=branch("Guest",false);client=b.s;cg=b.g
	require(host.host(29928,2)==OK);GameData.player_name="Spell Guest"
	require(client.join("127.0.0.1",29928)==OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Spell Guest")
	var h: Dictionary=host.state.heroes[1][0]
	h.skills={"astral":100};h.int=25.0;h.exp_total=200271.0;h.spells=[SPELL];h.perks=[]
	check(Spells.complexity(SPELL)>0,"fixture spell requires training")
	var camp := "bz2h" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz2g"
	var field := "gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g"
	await host.enter_zone(camp,1,false);freeze()
	require(await until(func():return loaded(camp)))
	var guest: GameUnit=host.party_units(1)[0]
	check(Spells.known_usable(guest,SPELL),"trained hero meets equipped spell requirements")
	client.submit({"t":"refund_training","unit":guest.uid})
	await frames();host.sync_state()
	check(await until(func():return Skills.level(client.party_units(1)[0].get_meta("hero"),"astral")==0),"co-op reset reaches guest")
	check(SPELL in guest.get_meta("hero").spells,"reset preserves equipped spell without deleting it")
	check(not Spells.known_usable(guest,SPELL),"reset revokes spell eligibility")
	await host.enter_zone(field,1,false);freeze()
	require(await until(func():return loaded(field)))
	guest=host.party_units(1)[0];guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0
	var view: GameUnit=client.party_units(1)[0]
	cg.selected.assign([view]);cg.rig.release();await frames()
	cg.begin_cast(0);check(cg.pending_spell.is_empty(),"mouse/hotkey cannot begin unavailable spell")
	cg.hud._slots.use(0,true);await frames()
	check(guest.orders.is_empty(),"instant self-cast cannot bypass requirements")
	cg.pending_spell=SPELL
	check(cg.pending_target(view).is_empty(),"already selected spell loses valid targeting")
	var pad := cg.get_node("PadField") as PadField
	check(not bool(pad._page_entries("spells")[0].enabled),"radial marks unavailable spell disabled")
	cg.hud._slots._process(0)
	check(not cg.hud._slots._usable[0],"HUD slot greys unavailable spell")
	for command in ["cast","direct_cast"]:
		client.submit({"t":command,"unit":guest.uid,"spell":SPELL,"target":guest.uid});await frames()
		check(guest.orders.is_empty(),"authority rejects unqualified " + command)
	# Restore training without altering the equipped list: the same spell reactivates.
	h=guest.get_meta("hero");h.skills.astral=100;Combat.hero_stats(guest,h);host.sync_state()
	check(await until(func():return Spells.known_usable(view,SPELL)),"training restores spell availability on both peers")
	client.submit({"t":"cast","unit":guest.uid,"spell":SPELL,"target":guest.uid});await frames()
	check(guest.orders.size()==1 and guest.orders[0].get("known_spell",false),"valid network spell queues with execution-time validation")
	if not guest.orders.is_empty():
		guest.order=guest.orders.pop_front()
		h.skills.astral=0
		var mana:=guest.mana
		guest._do_cast(GameUnit.TICK)
		check(guest.order.is_empty() and guest.mana==mana,"queued spell invalidated before execution spends no stamina")
	# Item magic intentionally uses item charges, not learned spell requirements.
	check(not Spells.usable_by(h,0,SPELL),"maximum stamina is also a requirement")
	h.skills.astral=100;Combat.hero_stats(guest,h);guest.mana=guest.max_mana;guest._anim_lock=0
	guest.order={"type":"cast","spell":SPELL,"target":guest,"point":guest.pos,"known_spell":true}
	var mana:=guest.mana
	guest._do_cast(GameUnit.TICK)
	check(guest.action.begins_with("cast") and guest.mana<mana,"eligible spell actually starts and pays stamina")
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for node in branches:node.queue_free()
	await frames()
	print("SPELL_REQUIREMENTS_COOP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
