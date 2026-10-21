extends "coop_trade.gd"
## Real maps, two ENet peers, topic buttons and dialogue close commands.
## Freeze unrelated story/combat ticks after loading; only the authored offer,
## completion bridge, refresh and ordinary dialogue staging advance here.

func run_script(name: String) -> void:
	var vm := host.world.vm
	vm.spawn(name,[null]);vm._run(vm.instances.back())

func stage_dialogue() -> void:
	var world := host.world
	for i in 600:
		world._tick_dialog_movers(GameUnit.TICK)
		world.vm.briefings.staging_tick()
		for u: GameUnit in world.dialog_movers.keys():u.tick(GameUnit.TICK)
		if world.vm.briefings._pending_dialog.is_empty():return
		if i%20==0:await get_tree().process_frame

func cases(zone: String) -> void:
	await host.enter_zone(zone,1,false)
	host.set_physics_process(false);host.world.set_process(false);host.world.set_physics_process(false)
	check(await until(func():return client.world!=null and client.world.zone.get("id","")==zone and not client._remote_loading and not client.loading_game),zone+": both peers loaded")
	var vm := host.world.vm
	var b := vm.briefings
	vm.instances.clear();b._check=INF
	var gipat := zone=="bz11g"
	var npc: GameUnit = vm._by_name("Spletnica" if gipat else "skelet")
	check(npc!=null,zone+": actual fortune-teller exists")
	if npc==null:return
	var source := "b.Spletnica.fq9" if gipat else "b.skelet.skelet_fq2"
	var target := "b.shava.fq9" if gipat else "b.skelet.fq2"
	var price := 500 if gipat else 50
	var original_offer := "Spletnica#1" if gipat else "Skelet#1"
	var guest_purse: Dictionary = host.coop.purse_entry(1).purse
	for player in [0,1]:
		for scenario: Array in [[0,price,price],[price,price-1,price-1],[0,0,price],[price,price,price-1]]:
			vm.instances.clear();host.world.dialog_movers.clear();host.world.dialog_actors.clear()
			for key: String in host.state.gs_keys(0,"b.",true):host.state.set_var(0,key,3)
			for guard: Array in vm.ast.scripts[original_offer].blocks[0].conds.slice(1):
				host.state.set_var(0,guard[2][0][2][1][1],guard[2][1][1])
			host.state.money=scenario[0]
			run_script(original_offer)
			run_script("BuySpletnicaMain#2#1#0" if gipat else "BuySkeletMain#2#1#0")
			if player==0:host.state.money=scenario[1];guest_purse.money=777
			else:guest_purse.money=scenario[1]
			host.sync_state()
			var owner := client if player==1 else host
			var panel: DialogPanel = owner.game.hud._dialog
			host.coop.with_purse(player,b.interact.bind(null,npc,player))
			check(await until(func():return panel.visible and panel._mode==DialogPanel.TOPICS),zone+": current buyer receives topic list")
			var offered := source+("f" if scenario[1]<price else "")
			var options: Array = panel._topics.get("options",[])
			var choice := -1
			for i in options.size():
				if String(options[i].var).to_lower()==offered.to_lower():choice=i
			check(choice>=0,zone+": topic list reflects buyer balance")
			if choice<0:continue
			if player==0:host.state.money=scenario[2]
			else:guest_purse.money=scenario[2]
			var other := host.coop.owner_money(1-player)
			var accepted: bool = scenario[2]>=price
			panel._on_topic(choice)
			check(await until(func():return not b.active.is_empty()),zone+": topic button reaches host authority")
			check(b.active.to_lower()==(source+("" if accepted else "f")).to_lower(),zone+": authority reevaluates stale wallet on selection")
			await stage_dialogue()
			check(b._pending_dialog.is_empty(),zone+": original actors finish staging")
			check(await until(func():return client.game.hud._dialog._mode>=DialogPanel.PLAYING and host.game.hud._dialog._mode>=DialogPanel.PLAYING),zone+": authored response reaches both peers")
			# The other peer may close a shared conversation; its rewards still
			# belong to the initiator. This traverses nested purse ownership.
			var closer: DialogPanel = (host if player==1 else client).game.hud._dialog
			var completed := b.active
			closer._skip();closer._finish()
			check(await until(func():return b.active.is_empty()),zone+": peer closes initiator's conversation")
			run_script("BuyMain#1" if gipat else "BuyNSheriffMain#1")
			check(host.state.get_var(0,target)==(2 if accepted else 0),zone+": unlock survives immediate catalogue refresh")
			check(host.coop.owner_money(player)==scenario[2]-(price if accepted else 0),zone+": actual buyer pays once")
			check(host.coop.owner_money(1-player)==other,zone+": closing peer's purse is untouched")
			host.sync_state()
			check(await until(func():return client.state.get_var(0,target)==(2 if accepted else 0) and client.state.money==int(guest_purse.money)),zone+": private money and shared unlock replicate")
			var before := host.coop.owner_money(player)
			client.game.issue({"t":"dialog_done","id":completed})
			for i in 8:await get_tree().process_frame
			check(host.coop.owner_money(player)==before,zone+": late duplicate close cannot charge again")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"coop_share_loot":0},true)
	host=peer("RumourHost",true);client=peer("RumourGuest",false)
	check(host.host(29984,2)==OK and client.join("127.0.0.1",29984)==OK,"paid-rumour peers connect")
	check(await until(func():return host.players.size()==2),"two paid-rumour participants registered")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Rumour Guest")
	var pid := client.multiplayer.get_unique_id()
	host.coop._pending[pid]={"hero":host.state.heroes[1][0].duplicate(true),"vars":{},"visited":{},"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":0,"items":[]}}
	host.coop.on_hello(pid,1,"Rumour Guest")
	host.set_physics_process(false)
	await cases("bz5h");await cases("bz11g")
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in roots:root.queue_free()
	for i in 10:await get_tree().process_frame
	print("ASTRAL_PAID_TOPICS_COOP ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
