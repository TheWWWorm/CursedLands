extends "coop_story.gd"
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
	else:print("PASS ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func freeze(s:Session) -> void:
	s.set_physics_process(false);s.world.set_physics_process(false);s.world.set_process(false)
	if s.world.vm:s.world.vm.instances.clear()
	s.game.rig.set_process(false)
func sync_effects(on:bool) -> bool:
	for attempt in 60:
		host._send_snapshot_records(host.world.party_units().map(func(u:GameUnit):return u.snapshot()),host.world.time)
		await frames(2)
		var ok:=true
		for actor:GameUnit in host.world.party_units():
			var remote:GameUnit=client.world.units.get(actor.uid)
			ok=ok and remote!=null and remote.buffs.has("invisible")==on and remote.buffs.has("silence")==on and remote.model.get("_invisible")==on
		if ok:return true
	return false
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Guest",false);client=c.s;cg=c.g
	check(host.host(29971,2)==OK,"open stealth host");GameData.player_name="Stealth Guest"
	check(client.join("127.0.0.1",29971)==OK,"connect stealth guest")
	check(await until(func():return host.players.size()==2),"stealth peers register")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Stealth Guest")
	host.state.create_party("Pretty");host.state.add_party_unit("Pretty","Nalo","Human Hadagan Pretty");host.state.set_current_party("Pretty")
	await host.enter_zone("gz15h",1,false)
	check(await until(func():return client.world!=null and client.zone_id=="gz15h" and not client._remote_loading),"both peers load native Nalo role")
	freeze(host);freeze(client)
	check(host.party_units(0).size()==1 and host.party_units(1).size()==1,"both owners have a distinct Nalo actor")
	for u:GameUnit in host.world.party_units():
		print("NET_STEALTH_CAST ",u.uid)
		Spells.apply(host.world,u,"invisibility{d2;d2}",u,u.pos);Spells.apply(host.world,u,"silence{d2;d2}",u,u.pos)
	check(await sync_effects(true),"replicated effects and fading reach the guest for both actors")
	for u:GameUnit in host.world.party_units():
		var remote:GameUnit=client.world.units[u.uid]
		check(u.detect(0)==.5 and remote.detect(0)==.5 and u.detect(3)==0 and remote.detect(3)==0,"host and guest agree on sight and hearing detectability")
		var saved:=CampaignState.body_state(u)
		u.buffs.clear();u.refresh_max_hp();CampaignState.apply_body(u,saved)
		check(u.model.get("_invisible")==true and u.detect(0)==.5 and u.detect(3)==0,"loaded body restores gameplay and figure fade")
		u.set_equipment(u.info.armors,u.info.weapons)
		check(u.model.get("_invisible")==true,"outfit rebuild retains invisibility")
		check(remote.get_meta("fx_magic",{}).has("silence"),"guest receives original Silent Step emitter")
	for u:GameUnit in host.world.party_units():
		u.buffs.invisible[GameUnit.EFFECT_TICKS]=1;u.buffs.silence[GameUnit.EFFECT_TICKS]=1;u._tick_effects()
	check(await sync_effects(false),"expiry removes both buffs and restores opaque figures on both peers")
	for root:Node in branches:root.queue_free()
	await frames(8);TexUpscale.shutdown()
	print("STEALTH_EFFECTS_NET ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
func _process(_dt:float) -> void:pass
