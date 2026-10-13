extends "coop_trade.gd"
## Real UI/ENet repair batches and player-swap stacks, with private purses.
## Authority controls exercise stale copies, total cost and equipment ownership.
class TxSession extends Session:
	var repairs: Array = []
	func submit(cmd: Dictionary) -> void:
		if cmd.get("t", "") == "repair": repairs.append(cmd.duplicate(true))
		super.submit(cmd)

class TxGame extends Game:
	var inventories: Array = []
	var results: Array = []
	var equipment: Array = []
	func on_event(e: Dictionary) -> void:
		if e.get("t", "") == "inventory": inventories.append(session.state.items.duplicate())
		if e.get("t", "") == "equip": equipment.append(e.duplicate(true))
		if e.get("t", "") == "repair_result":
			var row := e.duplicate(true)
			row.bag = session.state.items.duplicate()
			row.money = session.state.money
			results.append(row)
		super.on_event(e)

func peer(label: String, main: bool) -> Session:
	var n: Node = Node.new() if main else SubViewport.new()
	if n is SubViewport:
		n.size = Vector2i(1280,720); n.own_world_3d = true
		n.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	n.name=label; add_child(n); roots.append(n)
	var api := SceneMultiplayer.new(); api.root_path=n.get_path()
	get_tree().set_multiplayer(api,n.get_path())
	var s := TxSession.new(); n.add_child(s)
	var g := TxGame.new(); g.session=s; s.game=g; n.add_child(g)
	return s

func soon(f: Callable, seconds := 3.0) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if f.call(): return true
		await get_tree().process_frame
	return bool(f.call())

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
	host=peer("TxHost",true); client=peer("TxGuest",false)
	check(host.host(29977,2)==OK,"host opens transaction test port")
	GameData.player_name="Transaction Guest"
	check(client.join("127.0.0.1",29977)==OK,"guest joins")
	check(await until(func():return host.players.size()==2),"peers connected")
	if failures: get_tree().quit(2); return
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero"); host.state.ensure_hero(1,"Human Hero","Transaction Guest")
	var weapon := "stone axe.rock"
	var worn := Items.with_wear(weapon,1.0)
	var charged := Items.with_charge(Items.with_wear(weapon,2.0),0.4)
	var h: Dictionary = host.state.heroes[1][0]
	h.weapons=[worn,charged]
	var bag := [worn,worn,charged,weapon]
	host.state.money=111; host.state.items=["rune:r1"]
	var pid := client.multiplayer.get_unique_id()
	host.coop._pending[pid]={"hero":h.duplicate(true),"vars":{},"visited":{},"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":50000,"items":bag}}
	host.coop.on_hello(pid,1,"Transaction Guest")
	host.set_physics_process(false)
	await host.enter_zone("bz1g",1,false)
	check(await until(func():return client.world!=null and not client.loading_game and not client._remote_loading),"guest loads original camp")
	host.world.set_physics_process(false); host.world.vm.instances.clear()
	host.world.vm.briefings.active=""; host.world.vm.briefings._pending_dialog={}
	host.game.hud._dialog.hide(); client.game.hud._dialog.hide()
	host.state.shops[1]={"restock":false,"goods":{},"sold":{}}
	# Loading can allow a few normal charge-regeneration ticks. Establish
	# the exact charged-copy fixture after the world is frozen, then sync it.
	bag=[worn,worn,charged,weapon]
	host.coop.purse_entry(1).purse.items=bag.duplicate()
	host.sync_state()
	check(await soon(func():return client.state.items==bag),"private worn bag reaches guest")
	var panel: InventoryPanel=client.game.hud._inventory
	panel.open(true,1)
	var camp := panel._camp
	camp.set_mode("repair")
	for it in [worn,worn,charged]: camp._move_now(it,"bag")
	if camp.repair_pile.size()!=3:
		print("REPAIR_STAGE_DIAGNOSTIC ",{"mode":camp.mode,"bag":client.state.items,"pile":camp.repair_pile,"worn":worn,"charged":charged,"worn_count":camp.bag_count(worn),"charged_count":camp.bag_count(charged),"noconstr":camp._noconstr()})
	check(camp.repair_pile.size()==3,"three damaged copies staged")
	var cost: int = camp.deal_info()[1]
	var cg := client.game as TxGame
	await frames(8)   # drain initial campaign delivery before counting action replies
	cg.inventories.clear(); cg.results.clear(); cg.equipment.clear()
	(client as TxSession).repairs.clear(); camp.press_sounds.clear()
	# An outstanding periodic state must not hold an explicit action reply.
	host._state_waiting[pid]=host._state_serial+10000
	host._state_pending[pid]=true
	get_tree().paused=true
	var start := Time.get_ticks_msec()
	camp._on_yes(); camp._on_yes(); camp._move_now(worn,"rep")
	var retry: Dictionary=client._input_out.pending.get(client._input_out.serial,{})
	if not retry.is_empty():
		client._rpc_cmd_fast.rpc_id(1,var_to_bytes([retry,retry]))
		client._rpc_cmd.rpc_id(1,retry)
	check((client as TxSession).repairs.size()==1,"one confirmation submits one repair batch; double submit is ignored")
	check(camp.repair_pile.size()==3 and not camp.deal_info()[2],"pending repair retains and locks its selection")
	check(await soon(func():return not cg.results.is_empty(),0.8),"repair reply arrives while simulation is paused")
	var elapsed := Time.get_ticks_msec()-start
	check(get_tree().paused,"repair preserves shared pause")
	get_tree().paused=false
	# Let the old implementation finish too, to expose its missing result
	# independently from the bag's repaired contents in the baseline run.
	if cg.results.is_empty(): host.sync_state()
	var fixed_bag := [weapon,weapon,Items.with_wear(charged,0.0),weapon]
	check(await soon(func():return client.state.items==fixed_bag),"all selected bag copies repair together, preserving charge")
	check(client.state.money==50000-cost,"guest pays the complete quoted repair cost once")
	check(host.state.money==111 and host.state.items==["rune:r1"],"repair leaves the host purse untouched")
	check(cg.results.size()==1 and cg.results[0].ok and cg.results[0].bag==fixed_bag,"one result follows the final inventory")
	check(cg.inventories.size()==1,"batch publishes one inventory refresh")
	check(camp.repair_pile.is_empty() and camp.press_sounds.size()==1,"successful repair clears the selection and confirms once")
	if not retry.is_empty(): client._rpc_cmd_fast.rpc_id(1,var_to_bytes([retry]))
	await frames()
	check(cg.results.size()==1 and client.state.money==50000-cost,"late duplicate packet cannot repair or charge twice")
	print("REPAIR_BATCH_FEEDBACK_MS ",elapsed)
	# Repair all equipped copies in one transaction and one equipment refresh.
	panel.open(true,1); camp.set_mode("weapons")
	var u: GameUnit = client.party_units(1)[0]
	camp.refresh(u)
	var before_money := client.state.money
	cost=camp.deal_info()[1]
	cg.inventories.clear(); cg.results.clear(); cg.equipment.clear(); (client as TxSession).repairs.clear()
	camp._on_yes()
	check((client as TxSession).repairs.size()==1,"repair-all submits equipment as one batch")
	check(await soon(func():return not cg.results.is_empty(),0.8),"equipment batch is acknowledged promptly")
	if cg.results.is_empty(): host.sync_state()
	check(await soon(func():return (u.get_meta("hero").weapons as Array).all(func(it):return Items.wear(it)==0)),"all equipped weapons restore durability")
	check(cg.equipment.size()==1 and cg.inventories.size()==1,"equipment refresh and state publish happen once")
	check(client.state.items==fixed_bag and client.state.money==before_money-cost,"equipment batch preserves matching bag copies")
	# A stale co-op selection is refused as a whole, without losing the pile.
	var purse: Dictionary = host.coop.purse_entry(1).purse
	purse.items=[worn,worn]; host.sync_state()
	check(await soon(func():return client.state.items==[worn,worn]),"stale-selection fixture synced")
	camp.set_mode("repair"); camp._move_now(worn,"bag"); camp._move_now(worn,"bag")
	purse.items.pop_back(); before_money=purse.money; cg.results.clear()
	camp._on_yes()
	check(await soon(func():return not cg.results.is_empty(),0.8),"stale repair receives a refusal")
	check(purse.items==[worn] and purse.money==before_money,"missing copy causes no partial repair or charge")
	check(cg.results.size()==1 and not cg.results[0].ok and camp.repair_pile==[worn,worn] and camp.deal_info()[3],"rejected repair remains editable")
	camp.reset_transactions(); panel.hide()
	if host.has_method("_repair_apply"):
		host.state.items=[worn,worn]; host.state.money=0
		check(not host.call("_repair_apply",{"shop":1,"items":[worn,worn]},0),"unaffordable batch rejected")
		check(host.state.items==[worn,worn] and host.state.money==0,"unaffordable batch preserves all originals")
		check(not host.call("_repair_apply",{"shop":1,"items":[worn],"unit":u.uid},0),"another player's equipment cannot be repaired by the request")
		check(not host.call("_repair_apply",{"shop":1,"items":[worn,42]},0),"malformed repair rejected")
		Items.coef=Shops.coef(1)
		check(host.call("_repair_apply",{"shop":5,"items":[worn,worn]},0) and host.state.money==0,"named free shop rates override the host's open-shop rates")
		check(host.state.items==[weapon,weapon],"free repair restores both copies")
	# Both sides of a player exchange use the same exact-item stacks as a shop.
	var potion := "tiny potion 1"
	var kinds := ["tiny potion 2","tiny potion 3","rune:e1","rune:e2","rune:r1",weapon,worn]
	var all_items := []; all_items.resize(20); all_items.fill(potion)
	all_items.append_array(kinds); all_items.append(charged)
	purse.items=all_items.duplicate(); purse.money=500
	host.state.items=["rune:r2","rune:r2","rune:r2"]; host.state.money=111
	host.sync_state()
	check(await soon(func():return client.state.items==all_items),"swap fixture has separate bags")
	host.swap.send({"t":"request","to":1}); client.swap.send({"t":"request","to":0})
	check(await soon(func():return host.swap.partner()==1 and client.swap.partner()==0),"player offers pair over ENet")
	panel.open_swap(); var hc := host.game.hud._inventory._camp
	host.game.hud._inventory.open_swap()
	for i in 12: camp._move_now(potion,"bag")
	check(camp.sell_pile.size()==12 and camp.bag_count(potion)==8,"rapid clicks stage twelve copies and subtract pending copies")
	check(await soon(func():return host.swap.offers.get(1,{}).get("items",[]).size()==12),"authority retains every copy beyond eight")
	for it in kinds: camp._move_now(it,"bag")
	check(await soon(func():return host.swap.offers.get(1,{}).get("items",[]).size()==19),"eight distinct stacks fit the offer")
	camp._move_now(potion,"bag"); camp._move_now(charged,"bag")
	check(camp.sell_pile.size()==20 and not charged in camp.sell_pile,"full grid accepts an existing stack but rejects a ninth variant")
	check(await soon(func():return host.swap.offers.get(1,{}).get("items",[]).size()==20),"stack increment reaches authority")
	camp._process(0); hc._process(0)
	check(camp._content.sell0[0]==potion and camp._content.sell1[0]==kinds[0],"own grid gives duplicate copies one cell")
	check(hc._content.buy0[0]==potion and hc._content.buy1[0]==kinds[0],"partner grid uses matching stack cells")
	check(hc.buy_pile.count(potion)==13,"partner stack quantity is complete")
	var old_offer: Dictionary=host.swap.offers[1].duplicate(true)
	var old_bag: Array=host.swap._bag(1).duplicate()
	host.swap.command({"t":"set","items":old_offer.items+[charged],"money":0},1)
	check(host.swap.offers[1]==old_offer and host.swap._bag(1)==old_bag,"authority rejects ninth stack without silently truncating or returning escrow")
	host.swap.command({"t":"set","items":[potion,42],"money":0},1)
	check(host.swap.offers[1]==old_offer,"malformed offer cannot replace an agreed item set")
	var oversized := []; oversized.resize(Session.MAX_TRADE_ITEMS+1); oversized.fill(potion)
	host.swap.command({"t":"set","items":oversized,"money":0},1)
	check(host.swap.offers[1]==old_offer and host.swap._bag(1)==old_bag,"oversized payload leaves the whole offer unchanged")
	if DisplayServer.get_name()!="headless":
		await frames(8); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://player-swap-stacks.png")
	client.swap.send({"t":"withdraw"})
	check(await soon(func():return client.swap.partner()<0 and host.swap.partner()<0),"withdrawing closes both offers")
	check(await soon(func():return client.state.items.size()==all_items.size() and client.state.items.count(potion)==20),"withdrawal returns every stacked copy")
	host.swap.send({"t":"request","to":1}); client.swap.send({"t":"request","to":0})
	check(await soon(func():return client.swap.partner()==0),"offers pair again")
	panel.open_swap(); host.game.hud._inventory.open_swap()
	for i in 12: camp._move_now(potion,"bag")
	for i in 3: hc._move_now("rune:r2","bag")
	check(await soon(func():return client.swap.partner_offer().get("items",[]).size()==3 and host.swap.partner_offer().get("items",[]).size()==12),"both final stacked offers are visible")
	camp._swap_side("accept"); hc._swap_side("accept")
	check(await soon(func():return host.swap.offers.is_empty() and client.swap.offers.is_empty()),"both agreements commit the exchange")
	check(host.state.items.count(potion)==12 and host.state.items.count("rune:r2")==0,"host receives all twelve offered copies")
	check(client.state.items.count(potion)==8 and client.state.items.count("rune:r2")==3,"guest receives all three copies and retains its remainder")
	check(host.state.money==111 and client.state.money==500,"item-only exchange preserves both purses")
	for s: Session in [host,client]:
		s.online=false; var transport=s.multiplayer.multiplayer_peer
		s.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new(); transport.close()
	for n in roots: n.queue_free()
	await frames(8)
	print("CAMP_TRANSACTIONS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
