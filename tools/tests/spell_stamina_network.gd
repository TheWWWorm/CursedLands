extends "coop_loot_network.gd"
class SpellSession extends ObservedSession:
	var spell_events:Array[Dictionary]=[]
	func _on_event(event:Dictionary)->void:
		if event.get("t") in ["ack","castfx"]:spell_events.append(event.duplicate())
		super._on_event(event)
func peer(label:String)->ObservedSession:
	var root:=SubViewport.new();root.name=label;root.size=Vector2i(320,180);root.own_world_3d=true
	add_child(root);roots.append(root)
	var api:=SceneMultiplayer.new();api.root_path=root.get_path();get_tree().set_multiplayer(api,root.get_path())
	var result:=SpellSession.new();root.add_child(result)
	var g:=Game.new();g.session=result;result.game=g;root.add_child(g)
	return result
func finish()->void:
	Engine.time_scale=1
	for p in [host,guest]:
		if p:
			p.online=false;p.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	for root in roots:root.queue_free()
	for i in 10:await get_tree().process_frame
	print("SPELL_STAMINA_NETWORK ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(int(failures>0))
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"confine_mouse":0},true)
	host=peer("SpellHost");guest=peer("SpellGuest")
	check(host.host(29974,2)==OK,"ENet authority starts")
	GameData.player_name="Spell Guest"
	check(guest.join("127.0.0.1",29974)==OK,"guest connects")
	check(await until(func():return host.players.size()==2 and guest.my_index==1),"two distinct peers join")
	if failures:await finish();return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Spell Guest")
	await host.enter_zone("gz1g",1,false)
	check(await until(func():return guest.world!=null and not guest._remote_loading and not guest.party_units(1).is_empty()),"guest receives original field")
	if failures:await finish();return
	host.world.set_process(false);host.world.set_physics_process(false);host.world.vm.instances.clear()
	var caster:GameUnit=host.party_units(1)[0]
	var h:Dictionary=caster.get_meta("hero");h.spells=["healing{}"];h.skills={"astral":100};h.int=25
	Combat.hero_stats(caster,h);caster.race=caster.race.duplicate(true);caster.race.mana_regen=.08
	caster.ai_next=INF;caster._perceive_next=INF
	for direct:bool in [false,true]:
		caster.order={};caster.orders.clear();caster.path.clear();caster._anim_lock=0;caster._pending_hit={};caster.mana=0;caster.stop_steering()
		(guest as SpellSession).spell_events.clear()
		guest.submit({"t":"direct_cast" if direct else "cast","unit":caster.uid,"target":caster.uid,"spell":"healing{}"})
		check(await until(func():return caster.orders.any(func(o):return o.get("stamina_notified",false))),"guest spell waits on authority")
		check(await until(func():return (guest as SpellSession).spell_events.any(func(e):return e.t=="ack" and e.code==EIAcks.OUT_OF_STAMINA and e.to==1)),"stamina voice acknowledgement reaches casting peer")
		for i in 180:
			host.world.time+=GameUnit.TICK;caster.tick(GameUnit.TICK)
			if caster.action.begins_with("cast"):break
		check(caster.action.begins_with("cast"),"authority commits after regeneration without another client command")
		check(await until(func():return (guest as SpellSession).spell_events.any(func(e):return e.t=="castfx" and e.uid==caster.uid)),"committed spell reaches guest")
		check((guest as SpellSession).spell_events.filter(func(e):return e.t=="ack" and e.code==EIAcks.OUT_OF_STAMINA).size()==1,"waiting does not flood co-op acknowledgements")
	await finish()
