extends "coop_story.gd"
## Real guest purchases, paused-clock delivery, and visible/hidden inventory refresh.
## Headless runs isolate reply latency; rendered runs verify the actual camp rows.
const Refund := preload("res://src/game/training_refund.gd")
var checks := 0
var failures := 0
var measured := {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func hero(s: Session, player: int = 1) -> Dictionary:
	return s.party_units(player)[0].get_meta("hero")
func latency_row(command: Dictionary, predicate: Callable) -> Dictionary:
	host._state_sync_at_ms = Time.get_ticks_msec() + 500
	var at := Time.get_ticks_usec()
	client.submit(command)
	check(await until(func(): return predicate.call(host),3.0),"authority applies "+str(command.t))
	var authority := Time.get_ticks_usec()-at
	check(await until(func(): return predicate.call(client),3.0),"presentation receives "+str(command.t))
	return {"authority_us":authority,"feedback_us":Time.get_ticks_usec()-at}
func capture_camp() -> bool:
	for frame in 8:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture := cg.get_viewport().get_texture().get_image()
		var lit := 0
		for y in range(100,600,100):
			for x in range(200,1000,100):
				var color := picture.get_pixel(x,y)
				if color.r + color.g + color.b > 0.15: lit += 1
		if lit >= 8:
			return picture.save_png("user://training-latency.png") == OK
	return false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
	var a := branch("Host",true); host=a.s; hg=a.g
	var b := branch("Guest",false); client=b.s; cg=b.g
	cg.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	require(host.host(29945,2)==OK)
	GameData.player_name = "Latency Guest"
	require(client.join("127.0.0.1",29945)==OK)
	require(await until(func(): return host.players.size()==2))
	host.state = CampaignState.new()
	host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Latency Guest")
	for i in [0,1]:
		var h: Dictionary = host.state.heroes[i][0]
		h.exp = 10000000.0; h.exp_total = 10000271.0; h.skills = {}; h.perks = []
		Refund.start(h)
	await host.enter_zone("bz2g",1,false)
	host.world.set_physics_process(false); host.world.vm.instances.clear()
	require(await until(func(): return client.zone_id=="bz2g" and not client.loading_game and not client._remote_loading and not client.party_units(1).is_empty(),90))
	var uid: int = client.party_units(1)[0].uid
	var panel := cg.hud._inventory
	panel.open(false); panel._camp.set_mode("spells")
	for i in 12: await get_tree().process_frame
	var samples := []
	for n in 3:
		var target_level := n+1
		samples.append(await latency_row({"t":"train","unit":uid,"stat":"melee"},func(s): return Skills.level(hero(s),"melee")==target_level))
	measured.guest_skill = samples
	if DisplayServer.get_name() != "headless":
		panel._camp.queue_redraw()
		await RenderingServer.frame_post_draw
		check(panel._camp._skill_rows.any(func(row): return row[1].get("stat","")=="melee" and row[1].get("unit")==uid),"rendered training row retains the authoritative character")
		check(await capture_camp(),"visible training screen captured after three point purchases")
	measured.guest_perk = await latency_row({"t":"perk","unit":uid,"perk":"sword1"},func(s): return "sword1" in hero(s).perks)
	measured.guest_refund = await latency_row({"t":"refund_training","unit":uid},func(s): return hero(s).perks.is_empty() and Skills.level(hero(s),"melee")==0)
	var hu: GameUnit = host.party_units(0)[0]
	var at := Time.get_ticks_usec()
	host.submit({"t":"train","unit":hu.uid,"stat":"melee"})
	measured.host_skill_us = Time.get_ticks_usec()-at
	check(Skills.level(hero(host,0),"melee")==1,"host skill applies immediately")
	var big := {"perks":[],"skills":{},"exp":100000000.0}
	for pair: Array in [["sword",1],["axe",2],["dagger",3],["fire",1],["lightning",2],["acid",3],["bs",1],["health",2],["mana",3]]:
		for rank in int(pair[1]): big.perks.append(String(pair[0])+str(rank+1))
	at = Time.get_ticks_usec()
	var possible := Perks.available(big)
	for code: String in possible: Perks.cost(code,big)
	measured.cold_perk_menu_us = Time.get_ticks_usec()-at
	at = Time.get_ticks_usec()
	for draw in 100:
		for code: String in possible: Perks.cost(code,big)
		Refund.amount(big)
	measured.repeat_perk_menu_us = (Time.get_ticks_usec()-at)/100.0
	var before: float = hero(client).exp
	for i in 8: client.submit({"t":"train","unit":uid,"stat":"science"})
	check(await until(func(): return Skills.level(hero(client),"science")==8),"queued point requests applied exactly once")
	check(hero(host).exp==hero(client).exp and hero(client).exp<before,"queued charges agree on both peers")
	get_tree().paused = true
	at = Time.get_ticks_usec()
	client.submit({"t":"train","unit":uid,"stat":"elemental"})
	check(await until(func(): return Skills.level(hero(host),"elemental")==1,1.0),"authority accepts training while the shared clock is paused")
	check(await until(func(): return Skills.level(hero(client),"elemental")==1,0.8),"paused training reply arrives without resuming simulation")
	measured.paused_feedback_us = Time.get_ticks_usec()-at
	check(get_tree().paused,"training reply preserves the shared pause")
	get_tree().paused = false
	var original_items := client.state.items.duplicate()
	var hidden_count := panel._bag.item_count
	var inventory_times := {}
	for count in [20,200,500]:
		client.state.items = []
		for i in count: client.state.items.append(Items.with_wear("stone axe.rock",i*0.001))
		panel.refresh()
		at = Time.get_ticks_usec()
		for i in 20: panel.refresh()
		inventory_times[str(count)] = (Time.get_ticks_usec()-at)/20.0
	measured.inventory_refresh_us = inventory_times
	check(panel._bag.item_count==hidden_count,"camp updates do not rebuild the hidden inventory list")
	panel._set_camp(false)
	panel.refresh()
	check(panel._bag.item_count==500,"fallback inventory still refreshes its visible item list")
	panel._set_camp(true)
	client.state.items = original_items
	panel.refresh()
	var timings: Array = measured.guest_skill + [measured.guest_perk, measured.guest_refund]
	if DisplayServer.get_name() == "headless":
		for row: Dictionary in timings:
			check(int(row.feedback_us)-int(row.authority_us)<200000,"point feedback bypasses half-second campaign batch")
	measured.rendered = DisplayServer.get_name() != "headless"
	measured.fps = Engine.get_frames_per_second()
	measured.checks = checks; measured.failures = failures
	print("TRAINING_LATENCY ",JSON.stringify(measured))
	panel.hide(); host.online=false; client.online=false
	host.multiplayer.multiplayer_peer.close(); client.multiplayer.multiplayer_peer.close()
	for root: Node in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
