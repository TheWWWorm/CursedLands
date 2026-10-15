extends "coop_trade.gd"
## Real camp actions on the host and an ENet guest, including paused menus.
## Load must arrive in the same state update as the changed belt inventory.
var measurements := []

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func soon(f: Callable) -> bool:
	var end := Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<end:
		if f.call(): return true
		await get_tree().process_frame
	return bool(f.call())

func load_check(u: GameUnit, camp: CampView, expected: float, label: String) -> void:
	check(is_equal_approx(float(u.stats.load),expected),label+" effective weight")
	var text := "%d/%d" % [int(expected),int(u.stats.max_load)]
	check(camp._hero_rows().any(func(row):return row[1]==text),label+" visible camp weight")
	measurements.append({"case":label,"expected":expected,"actual":u.stats.load,"display":text})

func exercise(s: Session, player: int, wand: String, spent: String) -> void:
	var authority: GameUnit=host.party_units(player)[0]
	var h: Dictionary=authority.get_meta("hero")
	h.quick=[]
	Combat.hero_stats(authority,h)
	# A belt-only change must not rebuild models, heal, or erase live modifiers.
	authority.stats.to_hit=173.25
	host.sync_state()
	await frames(8)
	var u: GameUnit=s.party_units(player)[0]
	s.game.selected=[u]
	var panel: InventoryPanel=s.game.hud._inventory
	panel.open(false)
	var camp:=panel._camp
	camp.refresh(u);camp.set_mode("weapons")
	await frames()
	var base:float=authority.stats.load
	var hp:=authority.hp;var mana:=authority.mana
	var model:=authority.model
	var label:="host" if player==0 else "guest"
	load_check(u,camp,base,label+" before")
	get_tree().paused=true
	camp._press(wand,"bag")
	check(await soon(func():return u.get_meta("hero").quick.size()==1),label+" paused equip command arrives")
	load_check(u,camp,base+Items.weight(wand),label+" one wand")
	camp._press(spent,"bag")
	check(await soon(func():return u.get_meta("hero").quick.size()==2),label+" second charged copy arrives")
	load_check(u,camp,base+Items.weight(wand)+Items.weight(spent),label+" two wands")
	camp._press(wand,"belt")
	check(await soon(func():return u.get_meta("hero").quick.size()==1),label+" first wand removed")
	load_check(u,camp,base+Items.weight(spent),label+" after removal")
	check(u.get_meta("hero").quick==[spent],label+" remaining charge state preserved")
	camp._press(spent,"belt")
	check(await soon(func():return u.get_meta("hero").quick.is_empty()),label+" last wand removed")
	load_check(u,camp,base,label+" empty belt")
	check(authority.hp==hp and authority.mana==mana and authority.model==model and authority.stats.to_hit==173.25,label+" transfer preserves pools model and effective modifiers")
	var records:=host._hero_stat_records()
	check(is_equal_approx(float(records[authority.uid].load),base),label+" next authoritative snapshot contains current weight")
	get_tree().paused=false
	panel.hide()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
	var wand:="wand 1.rock|healing"
	var spent:=Items.with_charge(wand,Items.energy(wand)*0.5)
	check(Items.is_wand(wand) and Items.weight(wand)>0 and spent!=wand,"real positive-weight wand and charged-copy fixtures")
	host=peer("WeightHost",true);client=peer("WeightGuest",false)
	check(host.host(29983,2)==OK,"isolated weight test host")
	GameData.player_name="Weight Guest"
	check(client.join("127.0.0.1",29983)==OK,"weight guest connects")
	check(await until(func():return host.players.size()==2),"two peers connected")
	if failures:get_tree().quit(2);return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Weight Guest")
	host.state.items=[wand,spent]
	var pid:=client.multiplayer.get_unique_id()
	host.coop._pending[pid]={"hero":host.state.heroes[1][0].duplicate(true),"vars":{},"visited":{},"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":222,"items":[wand,spent]}}
	host.coop.on_hello(pid,1,"Weight Guest")
	host.set_physics_process(false)
	await host.enter_zone("bz1g" if GameData.campaign_id==CampaignProfile.ORIGINAL else "bz1h",1,false)
	check(await until(func():return client.world!=null and not client.loading_game and not client._remote_loading),"guest enters safe zone")
	if failures:get_tree().quit(2);return
	host.world.set_physics_process(false);host.world.vm.instances.clear()
	host.world.vm.briefings.active="";host.world.vm.briefings._pending_dialog={}
	host.game.hud._dialog.hide();client.game.hud._dialog.hide()
	# Freeze before capturing exact item charge strings for the transaction.
	host.state.items=[wand,spent];host.coop.purse_entry(1).purse.items=[wand,spent]
	host.sync_state();await frames(8)
	check(host.camp_available() and host.shop_available(),"authored map is a safe zone")
	await exercise(host,0,wand,spent)
	await exercise(client,1,wand,spent)
	# The same path in offline single player must update without a peer round trip.
	host.online=false
	await exercise(host,0,wand,spent)
	# Consumables also stop contributing when their cast consumes the belt item.
	var u:GameUnit=host.party_units(0)[0]
	var h:Dictionary=u.get_meta("hero")
	var base:float=u.stats.load
	host.state.items.append("tiny potion 1")
	host._item_command({"t":"give_quick","unit":u.uid,"item":"tiny potion 1"},0)
	check(is_equal_approx(float(u.stats.load),base+Items.weight("tiny potion 1")),"potion addition updates load")
	check(host.consume_quick(u,"tiny potion 1") and is_equal_approx(float(u.stats.load),base),"consumed potion removes its weight")
	check(not host.consume_quick(u,"tiny potion 1") and is_equal_approx(float(u.stats.load),base),"duplicate consumption cannot change load")
	FileAccess.open("user://belt-weight.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"campaign":GameData.campaign_id,"measurements":measurements},"\t"))
	client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for n in roots:n.queue_free()
	await frames(10)
	print("BELT_WEIGHT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
