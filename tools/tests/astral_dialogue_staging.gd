extends "coop_trade.gd"
func _ready():
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	host=peer("TalkHost",true);client=peer("TalkGuest",false)
	check(host.host(29978,2)==OK and client.join("127.0.0.1",29978)==OK,"dialogue peers connect")
	check(await until(func():return host.players.size()==2),"two participants registered")
	var s:=host
	s.state.ensure_hero(0,"Human Hero");s.state.ensure_hero(1,"Human Hero","Guest")
	s.state.heroes[0][0].unit_name="Hero2"
	await s.enter_zone("bz5h",1,false)
	check(await until(func():return client.world!=null and not client._remote_loading),"both peers loaded")
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	s.world.vm.instances.clear()
	var b:=s.world.vm.briefings;var smith:GameUnit=s.world.vm._by_name("NSheriff")
	var doc:=Briefings.parse(GameData.text("briefing buy_sw_01"))
	var protagonist:GameUnit=s.party_units(0)[0]
	for alias:String in ["Hero2","Hero3","Hero4","Jun","Shaina"]:
		protagonist.info.name=alias
		for player in [0,1]:
			var actors=[alias.to_lower(),"nsheriff"]
			var c:=b.cast(actors,smith,player)
			check(c.a==s.party_units(player)[0].uid,"buyer is protagonist: "+alias)
			check(c.b==smith.uid and not c.has("c"),"merchant stays second actor: "+alias)
			check(c.names[alias.to_lower()]==c.a,"speech role follows initiating player")
			var before:=smith.pos
			b._face(c,false,true)
			check(not s.world.dialog_movers.has(smith),"merchant does not approach buyer")
			check(smith.pos==before,"merchant display position retained")
			s.world.dialog_movers.clear()
			for u:GameUnit in s.world.units.values():u.orders.clear()
	var ordinary:=b.cast(["hero","nsheriff"],smith,1)
	check(ordinary.a==s.party_units(1)[0].uid and ordinary.b==smith.uid,"generic protagonist remains guest")
	var extra:=GameUnit.new();extra.uid=1999001;extra.world=s.world;extra.info={"name":"companion"};extra.pos=smith.pos+Vector2(3,3)
	s.world.set_unit(extra.uid,extra)
	var trio:=b.cast(["shaina","nsheriff","companion"],smith,1)
	check(trio.c==extra.uid and trio.b==smith.uid,"real third companion retains authored role")
	b._face(trio,false,true)
	check(s.world.dialog_movers.has(extra) and not s.world.dialog_movers.has(smith),"only real third companion moves to third mark")
	s.world.dialog_movers.clear();s.world.zone.cage=true
	b._face(ordinary,false,true)
	check(s.world.dialog_movers.has(smith),"cage scene still deliberately brings NPC to protagonist")
	s.world.zone.cage=false
	s.world.dialog_movers.clear();s.world.erase_unit(extra.uid);extra.free()
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in roots:root.queue_free()
	for i in 5:await get_tree().process_frame
	print("ASTRAL_DIALOGUE_STAGING ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
