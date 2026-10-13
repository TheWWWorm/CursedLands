extends "coop_trade.gd"
## The real camp/ENet path, including a paused guest with a private bag.
class ConstructorGame extends Game:
	var inventories: Array = []
	var results: Array = []
	func on_event(e: Dictionary) -> void:
		if e.get("t", "") == "inventory": inventories.append(session.state.items.duplicate())
		if e.get("t", "") == "constr_result":
			var row := e.duplicate(true)
			row.bag = session.state.items.duplicate()
			row.money = session.state.money
			results.append(row)
		super.on_event(e)

func peer(label: String, main: bool) -> Session:
	var n: Node = Node.new() if main else SubViewport.new()
	if n is SubViewport:
		n.size=Vector2i(1280,720); n.own_world_3d=true
	n.name=label; add_child(n); roots.append(n)
	var api:=SceneMultiplayer.new(); api.root_path=n.get_path()
	get_tree().set_multiplayer(api,n.get_path())
	var s:=Session.new(); n.add_child(s)
	var g:=ConstructorGame.new(); g.session=s; s.game=g; n.add_child(g)
	return s

func frames(n:=6)->void:
	for i in n: await get_tree().process_frame

func soon(f:Callable)->bool:
	var end:=Time.get_ticks_msec()+1000
	while Time.get_ticks_msec()<end:
		if f.call():return true
		await get_tree().process_frame
	return bool(f.call())

func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"switch_filters":1},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
	host=peer("ConstructorHost",true);client=peer("ConstructorGuest",false)
	check(host.host(29978,2)==OK,"isolated constructor host")
	GameData.player_name="Constructor Guest"
	check(client.join("127.0.0.1",29978)==OK,"guest connects")
	check(await until(func():return host.players.size()==2),"peers connected")
	if failures:get_tree().quit(2);return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Constructor Guest")
	var h:Dictionary=host.state.heroes[1][0]
	h.skills={"elemental":100};h.int=100.0;h.spells=[];h.perks=[]
	host.state.money=111;host.state.items=["rune:r1"]
	var pid:=client.multiplayer.get_unique_id()
	host.coop._pending[pid]={"hero":h.duplicate(true),"vars":{},"visited":{},"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":1000000,"items":[]}}
	host.coop.on_hello(pid,1,"Constructor Guest")
	host.set_physics_process(false)
	await host.enter_zone("bz1g",1,false)
	check(await until(func():return client.world!=null and not client.loading_game and not client._remote_loading),"guest loads camp")
	host.world.set_physics_process(false);host.world.vm.instances.clear()
	host.world.vm.briefings.active="";host.world.vm.briefings._pending_dialog={}
	host.game.hud._dialog.hide();client.game.hud._dialog.hide()
	var actor:GameUnit=host.party_units(1)[0]
	h=actor.get_meta("hero");h.skills={"elemental":72};h.int=25.0
	Combat.hero_stats(actor,h)
	actor.max_mana=135
	client.party_units(1)[0].max_mana=135
	var purse:Dictionary=host.coop.purse_entry(1).purse
	var g:=client.game as ConstructorGame
	var panel:InventoryPanel=g.hud._inventory
	var camp:=panel._camp
	var key:="keystone:litnwall"
	var mods:=["e2","e1","d1","m1","m1","m1","m1","m1"]
	var pieces:=[key]
	var built:="litnwall"
	for code:String in mods:
		pieces.append("rune:"+code);built=Spells.with_mod(built,code)
	var result_item:="spell:"+built
	check(Spells.complexity(built)==72 and int(Spells.parse(built).mana)==35,"eight-rune lightning wall fixture")
	# Cover all-shop, mixed, and already-purchased runes independently.
	for source in ["shop","mixed","bag"]:
		panel.hide();camp.reset_transactions()
		var bag:=[];var goods:={};var froms:=[]
		for i in pieces.size():
			var from:String="bag" if source=="bag" or source=="mixed" and i<=3 else "shop"
			froms.append(from)
			if from=="bag":bag.append(pieces[i])
			else:goods[pieces[i]]=int(goods.get(pieces[i],0))+1
		purse.items=bag.duplicate();purse.money=1000000
		host.state.shops[3]={"restock":false,"goods":goods.duplicate(),"sold":{}}
		host.sync_state()
		check(await soon(func():return client.state.items==bag and client.state.shops.get(3,{}).get("goods",{})==goods),source+" fixture synchronized")
		panel.open(true,3);camp.set_mode("spellconstr");camp.refresh(client.party_units(1)[0])
		for i in pieces.size():camp._move_now(pieces[i],froms[i])
		check(camp.s_spell=="litnwall" and camp.s_runes.size()==8,source+" accepts eight purchased runes")
		check(camp.spell_preview()==built and camp.deal_info()[2],source+" valid preview can assemble")
		var cost:int=camp.deal_info()[1]
		if source=="mixed":check(cost==4975,"five shop mana runes give the displayed 4975 total")
		await frames();g.inventories.clear();g.results.clear();camp.press_sounds.clear()
		host._state_waiting[pid]=host._state_serial+10000;host._state_pending[pid]=true
		get_tree().paused=true
		camp._on_yes();camp._on_yes()
		var retry:Dictionary=client._input_out.pending.get(client._input_out.serial,{})
		if not retry.is_empty():client._rpc_cmd_fast.rpc_id(1,var_to_bytes([retry,retry]))
		check(await soon(func():return not g.results.is_empty()),source+" receives acknowledgement while paused")
		check(g.results.size()==1 and g.results[0].ok and g.results[0].bag==[result_item],source+" settled inventory precedes success")
		check(client.state.items==[result_item] and client.state.money==1000000-cost,source+" settles all ingredients and fee once")
		check(g.inventories.size()==1 and host.state.items==["rune:r1"] and host.state.money==111,source+" one refresh and private purse preserved")
		check(camp.press_sounds.size()==1,source+" confirms successful assembly once")
		check(camp.s_ready() and camp._s_item()==result_item and not camp.s_wait,source+" completed spell remains visible in constructor")
		camp._move(result_item,"sready");camp._process(0)
		check(camp.bag_items().has(result_item) and camp.bag_count(result_item)==1,source+" completed spell returns visibly to bag")
		check(client.state.shops[3].goods.is_empty(),source+" shop loses only purchased ingredients")
		get_tree().paused=false
		if not retry.is_empty():client._rpc_cmd_fast.rpc_id(1,var_to_bytes([retry]))
		await frames()
		check(g.results.size()==1 and client.state.items==[result_item],source+" duplicate delivery cannot construct twice")
		# The reverse operation has the same state-before-result contract.
		camp._move_now(result_item,"bag");g.results.clear();g.inventories.clear()
		get_tree().paused=true;camp._on_yes()
		check(await soon(func():return not g.results.is_empty()),source+" disassembly replies while paused")
		check(g.results.size()==1 and g.results[0].ok and g.results[0].bag==pieces,source+" disassembly returns all eight rune copies before acknowledgement")
		get_tree().paused=false;await frames()
	# A stale shop selection is rejected atomically and can still be edited.
	camp.reset_transactions();purse.items=[key];purse.money=1000000
	host.state.shops[3].goods={"rune:m1":1};host.sync_state()
	check(await soon(func():return client.state.items==[key]),"stale fixture synced")
	camp._move_now(key,"bag");camp._move_now("rune:m1","shop")
	host.state.shops[3].goods.clear();g.results.clear()
	camp._on_yes();check(await soon(func():return not g.results.is_empty()),"stale selection acknowledged")
	check(not g.results[0].ok and purse.items==[key] and purse.money==1000000,"missing shop rune consumes nothing")
	check(not camp.s_wait and camp.s_runes==["rune:m1"],"refused constructor stays editable")
	for s:Session in [host,client]:
		s.online=false;var transport=s.multiplayer.multiplayer_peer
		s.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();transport.close()
	for n in roots:n.queue_free()
	await frames(8)
	print("SPELL_CONSTRUCTOR_TRANSACTIONS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
