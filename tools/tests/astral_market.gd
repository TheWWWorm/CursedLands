extends "dialogue_feedback.gd"
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"coop_share_loot":0},true)
	var s:=CaptureSession.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");s.state.ensure_hero(1,"Human Hero","Guest")
	await s.enter_zone("bz5h",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	var vm:=s.world.vm;vm.instances.clear()
	var b:=vm.briefings;b.active="";b._pending_dialog={};b._check=INF
	var smith:GameUnit=vm._by_name("NSheriff");smith._talk_command=0;smith._talk_posted=9
	s.coop.joiners["market_guest"]={"idx":1,"purse":{"money":0,"items":[]}}
	var row:=GameData.db.find("briefings","buy_sw_01")
	var price:=-int(row.money)
	check(price==170,"price comes from original Astral briefing reward")
	# Authored scripts selected a success/failure topic before the purse
	# changed. Opening the catalogue must use its current buyer's balance.
	for scenario:Array in [[0,0,1000,0,true],[0,1000,0,0,false],[1,0,0,1000,true],[1,1000,1000,0,false],[1,0,1000,170,true],[0,0,170,0,true],[0,0,169,1000,false]]:
		var player:int=scenario[0]
		for key:String in s.state.gs_keys(0,"b.",true):s.state.set_var(0,key,3)
		s.state.set_var(0,"b.NSheriff.buy_1",2)
		s.state.money=scenario[1];s.state.items=[]
		s.coop.joiners.market_guest.purse={"money":0,"items":[]}
		vm.spawn("BuyNSheriff#1",[null]);vm.tick(.1);vm.tick(.1);vm.instances.clear()
		s.state.money=scenario[2];s.coop.joiners.market_guest.purse.money=scenario[3]
		s.coop.with_purse(player,b.interact.bind(null,smith,player,false,true))
		var options:Array=s.events.back().options
		var choices:=options.filter(func(e):return String(e.var).to_lower().begins_with("b.nsheriff.buy_sw_01"))
		check(choices.size()==1,"one offer for current buyer")
		if choices.size()!=1:continue
		var key:String=choices[0].var
		check(key.to_lower().ends_with("buy_sw_01") == scenario[4],"first opening uses current buyer balance "+str(scenario))
		s.coop.with_purse(player,b.topic.bind(player,key,smith.uid))
		var complete:=b.active
		s.coop.with_purse(player,b.complete.bind(player,complete,true))
		check(s.state.money==int(scenario[2])-(price if player==0 and scenario[4] else 0),"host charged only for host purchase")
		check(s.coop.joiners.market_guest.purse.money==int(scenario[3])-(price if player==1 and scenario[4] else 0),"guest charged only for guest purchase")
		check((not s.state.items.is_empty())==(player==0 and scenario[4]),"host receives only host purchase")
		check((not s.coop.joiners.market_guest.purse.items.is_empty())==(player==1 and scenario[4]),"guest receives item on first successful selection")
		vm.instances.clear()
	g.queue_free();s.queue_free()
	await get_tree().process_frame
	print("ASTRAL_MARKET ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
