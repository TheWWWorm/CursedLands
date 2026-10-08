extends Node
## A guest confirms a stacked offer through the real UI/ENet command path.
## Atomic validation also covers stale stock, unaffordable mixed deals,
## worn copies, and a shop whose coefficients differ from the host's UI.
class ObservedGame extends Game:
	var inventories: Array = []
	var results: Array = []
	func on_event(e: Dictionary) -> void:
		if e.get("t","") == "inventory": inventories.append(session.state.items.duplicate())
		if e.get("t","") == "trade_result": results.append(e.duplicate())
		super.on_event(e)
var host: Session
var client: Session
var roots: Array[Node] = []
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func until(f: Callable) -> bool:
	var end := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<end:
		if f.call(): return true
		await get_tree().process_frame
	return bool(f.call())
func peer(label: String, main: bool) -> Session:
	var n: Node = Node.new() if main else SubViewport.new()
	if n is SubViewport:
		n.size = Vector2i(1280,720); n.own_world_3d = true
	n.name=label; add_child(n); roots.append(n)
	var api := SceneMultiplayer.new(); api.root_path=n.get_path()
	get_tree().set_multiplayer(api,n.get_path())
	var s:=Session.new(); n.add_child(s)
	var g:=ObservedGame.new(); g.session=s; s.game=g; n.add_child(g)
	return s
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	host=peer("TradeHost",true); client=peer("TradeGuest",false)
	check(host.host(29975,2)==OK,"host opens isolated ENet port")
	GameData.player_name="Trade Guest"
	check(client.join("127.0.0.1",29975)==OK,"guest joins")
	check(await until(func():return host.players.size()==2),"two peers connected")
	if failures: get_tree().quit(2); return
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero"); host.state.ensure_hero(1,"Human Hero","Trade Guest")
	var potion := "tiny potion 1"
	check(not Items.info(potion).row.is_empty(),"test uses an actual potion")
	var bag := []; bag.resize(20); bag.fill(potion)
	host.state.money=111; host.state.items=["rune:r1"]
	var pid:=client.multiplayer.get_unique_id()
	host.coop._pending[pid]={"hero":host.state.heroes[1][0].duplicate(true),"vars":{},"visited":{},"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":222,"items":bag}}
	host.coop.on_hello(pid,1,"Trade Guest")
	host.set_physics_process(false)
	await host.enter_zone("bz1g",1,false)
	check(await until(func():return client.world!=null and not client.loading_game and not client._remote_loading),"guest enters original Gipath camp")
	host.world.vm.instances.clear()
	host.state.shops[1]={"restock":false,"goods":{potion:40},"sold":{}}
	host.sync_state()
	check(await until(func():return client.state.items.size()==20 and client.state.shops.get(1,{}).get("goods",{}).get(potion,0)==40),"private bag and stock reach the client")
	var panel: InventoryPanel=client.game.hud._inventory
	panel.open(true,1)
	var camp:=panel._camp
	for i in 20: camp._move_now(potion,"bag")
	for i in 4: camp._move_now(potion,"shop")
	camp._process(0)
	check(camp.sell_pile.size()==20 and camp.buy_pile.size()==4,"identical stacks accept more than eight items")
	check(camp._content.sell0[0]==potion and camp._content.sell1[0]=="" and camp._content.buy1[0]=="","one visible cell per identical stack")
	check(camp.bag_count(potion)==0 and camp.shop_left(potion)==36,"staged counts subtract every copy")
	var other:=[]
	for i in 8: other.append("kind%d"%i)
	check(camp._pile_accepts(other,"kind0") and not camp._pile_accepts(other,"kind8"),"a full pile accepts existing types but not a ninth type")
	var g:=client.game as ObservedGame; g.inventories.clear(); g.results.clear()
	camp._on_yes()
	check(camp.trade_wait and not camp.deal_info()[2],"confirmation disables duplicate submission while waiting")
	camp._on_yes(); camp._move_now(potion,"sell")
	check(camp.sell_pile.size()==20,"pending offer cannot be mutated")
	check(await until(func():return not camp.trade_wait and not g.results.is_empty()),"one atomic trade result returns")
	check(g.results.size()==1 and g.results[0].ok,"one confirmed request settles once")
	check(client.state.items==[potion,potion,potion,potion],"all twenty sales and four purchases arrive together")
	check(g.inventories.size()==1 and g.inventories[0]==client.state.items,"client receives one final inventory update")
	check(client.state.money==222+20*Items.sell_price(potion)-4*Items.buy_price(potion),"guest pays the net deal price")
	check(host.state.money==111 and host.state.items==["rune:r1"],"host's purse is untouched")
	check(camp.sell_pile.is_empty() and camp.buy_pile.is_empty() and camp.bag_count(potion)==4,"acknowledged offer clears onto the settled inventory")
	check(host.shop_count(potion,{"shop":1})==56,"shop counts settle with the bag")
	# All-or-nothing on the authority. These failure cases used to be a
	# sequence of sales followed by individually rejected purchases.
	var st:=host.state
	st.items=[potion,potion]; st.money=0
	var before:=st.to_dict().duplicate(true)
	check(not host._trade_apply({"shop":1,"sell":[potion],"buy":[potion,potion,potion]}),"unaffordable mixed deal is rejected")
	check(st.items==before.items and st.money==before.money and st.shops==before.shops,"failed deal leaves bag, money and trader unchanged")
	check(not host._trade_apply({"shop":1,"sell":[potion,potion,potion],"buy":[]}),"oversold stack is rejected as a whole")
	check(st.items==before.items and st.shops==before.shops,"oversold stack consumes nothing")
	check(not host._trade_apply({"shop":1,"sell":[potion],"buy":["tiny potion 2"]}),"stale shop offer is rejected")
	check(st.items==before.items and st.shops==before.shops,"stale shop offer does not sell anything")
	st.items=["dragonamulet"]
	check(not host._trade_apply({"shop":1,"sell":["dragonamulet"],"buy":[]}),"quest items cannot be sold")
	st.items=[]; st.money=0
	st.shops[5]={"restock":false,"goods":{potion:1},"sold":{}}
	Items.coef=Items.COEF
	check(host._trade_apply({"shop":5,"sell":[],"buy":[potion]}) and st.money==0 and st.items==[potion],"authority uses the named free shop's coefficients")
	# Worn copies stay distinct; a failed UI transaction remains editable.
	var weapon := "stone axe.rock"
	var worn := Items.with_wear(weapon,1.0)
	st.items=[weapon,worn];st.money=0
	check(worn!=weapon and host._trade_apply({"shop":1,"sell":[worn],"buy":[]}) and st.items==[weapon],"selling a worn copy preserves its pristine twin")
	camp.sell_pile=[potion];camp.trade_wait=true
	camp.trade_result({"req":camp._trade_req,"ok":false})
	check(not camp.trade_wait and camp.sell_pile==[potion],"rejected offer remains available for correction")
	camp.trade_wait=true
	var old_request:=camp._trade_req
	camp.reset_transactions()
	camp.trade_result({"req":old_request,"ok":true})
	check(not camp.trade_wait and camp.sell_pile.is_empty() and camp._trade_req!=old_request,"zone transfer cancels pending offers and fences late results")
	if DisplayServer.get_name()!="headless":
		st.items=[]
		for i in 20: st.items.append(potion)
		st.money=222
		host.state.shops[1]={"restock":false,"goods":{potion:40},"sold":{}}
		var host_panel: InventoryPanel=host.game.hud._inventory
		host_panel.open(true,1)
		for i in 20: host_panel._camp._move_now(potion,"bag")
		for i in 4: host_panel._camp._move_now(potion,"shop")
		for i in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://trade-stacks.png")
		host_panel.hide()
		# Inspect the actual coloured spell item next to its grey keystone.
		panel.hide()
		var row:=HBoxContainer.new(); add_child(row); row.position=Vector2(200,200)
		for item in ["spell:fireball","keystone:fireball","spell:lightning","keystone:lightning"]:
			var col:=VBoxContainer.new();row.add_child(col)
			var label:=Label.new();label.text=item;col.add_child(label)
			var v:=ItemView.new();v.custom_minimum_size=Vector2(200,200);col.add_child(v);v.show_item(item)
		for i in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://spell-item-colours.png")
		row.queue_free()
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for n in roots: n.queue_free()
	for i in 10:await get_tree().process_frame
	print("COOP_TRADE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
