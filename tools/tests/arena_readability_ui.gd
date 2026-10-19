extends "arena_expansion_ui.gd"
var language := "en"
func wait_models() -> void:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		if screen.battle._queued_formation.is_empty() and screen.battle.formation_motion.movers.is_empty() and screen._shop.get_children().all(func(box): return box.get_child(0) is Label or not box.get_child(0)._preview_pending): break
	await frames(24)
func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen += 1; GameData.arena_mode = 1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): language=arg.trim_prefix("--lang=")
	RemakeText.lang=language
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800)
	get_window().position=Vector2i.ZERO
	get_window().grab_focus(); await frames(6)
	screen=ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text="7191"; screen._begin(); screen.run.auto_save=false
	screen.run.gold=100; screen.run.training=36
	screen.run.army.clear()
	for pair in [[0,0],[0,1],[11,0],[13,0],[23,2],[8,1]]: screen.run._recruit(pair[0],pair[1],9)
	screen.run.arrange()
	var benched := screen.run._recruit(23,0,3)
	screen.run.reserve_slots(); screen.run.shop.clear()
	for family in [0,0,11,13,21,24]: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	for plan: Dictionary in screen.run.bot_plans: plan.done=true
	screen.run._touch(); await wait_models()
	check(screen._shop.get_child(0).get_child(0).upgrade_ready and screen._shop.get_child(1).get_child(0).upgrade_ready, "both displayed offers complete owned boar")
	var first: ArenaCreatureCard = screen._shop.get_child(0).get_child(0)
	var rare: ArenaCreatureCard = screen._shop.get_child(4).get_child(0)
	check(not first._upgrade_marker.get_global_rect().intersects(screen._shop.get_child(0).get_child(1).get_global_rect()), "upgrade arrow does not overlap lock")
	check(first._upgrade_marker.visible and not rare._upgrade_marker.visible, "upgrade arrow is distinct from rarity")
	check(first._glow.get_shader_parameter("upgrade_pulse") and not rare._glow.get_shader_parameter("upgrade_pulse"), "upgrade pulses, rarity remains steady")
	check(first._ownership.text=="★ ×1  ★★ ×1", "shop marks each owned rank in one line")
	var duplicates: Array[Dictionary]=screen.run.army.duplicate(true)
	duplicates.append(screen.run.army[0].duplicate(true)); first.owned_army=duplicates; first.update_offer()
	check(first._ownership.text=="★ ×2  ★★ ×1", "duplicate ownership uses one compact count")
	first.owned_army=screen.run.army; first.update_offer()
	for box: Control in screen._shop.get_children():
		var card: ArenaCreatureCard = box.get_child(0)
		bounded(card,"six-offer shop card")
		check(card.get_global_rect().grow(1).encloses(card._ownership.get_global_rect()),"owned-rank line stays within its offer")
	check(screen.battle.world.unit_rows().any(func(u):return u.info.prototype=="driadgreena7" and u.info.get("texture")=="driad00"), "deployed woodsfolk receives native green palette")
	screen._round_banner._age=10
	await shot("readability-"+language+"-shop")
	# Actual UI target binding, both selection orders, and retained reserve slot.
	var field_uid := int(screen.run.army[0].uid)
	screen._select(field_uid); screen._army_row.get_child(5).pressed.emit(); await frames(8)
	check(not screen.run.unit(field_uid).deployed and screen.run.reserve_slots()[5].uid==field_uid, "clicked empty reserve receives selected unit in slot five")
	check(int(screen._army_row.get_child(5).get_meta("arena_creature").uid)==field_uid, "reserve widget retains chosen location")
	var outgoing := int(screen.run.army.filter(func(e):return e.deployed)[0].uid)
	screen._select(outgoing); screen._army_row.get_child(5).pressed.emit(); await wait_models()
	check(screen.run.unit(field_uid).deployed and screen.run.reserve_slots()[5].uid==outgoing, "field then occupied bench swaps units")
	screen._army_row.get_child(5).pressed.emit(); screen._select_world(body(field_uid)); await wait_models()
	check(screen.run.unit(outgoing).deployed and screen.run.reserve_slots()[5].uid==field_uid, "bench then field also swaps units")
	# A fresh solo purchase through the screen merges the matching native archer.
	var archer: Dictionary = screen.run.army.filter(func(e):return e.family==11)[0]
	for i in 2:
		screen.run.shop[2]={"family":11,"rank":0,"locked":false}; screen.run._touch()
		screen._shop.get_child(2).get_child(0).pressed.emit(); await frames(6)
	check(screen.run.unit(archer.uid).rank==1 and screen.run.copies(screen.run.unit(archer.uid)).size()==1, "fresh solo UI merges three matching archers immediately")
	check(screen._evolution_notice.current.get("to","")==ArenaRules.prototype(11,1), "merge feedback appears on triggering purchase")
	screen._evolution_notice.clear(); screen._clear_selection(); await wait_models()
	var viewed: ArenaRun = screen.run.company(1)
	viewed.army.clear(); viewed._recruit(21,1,12); viewed._recruit(18,0,5); viewed.arrange()
	screen._show_player(1); await frames(45)
	for box: Control in screen._shop.get_children():
		var card := box.get_child(0) as ArenaCreatureCard
		if card:
			check(not screen._scout_bar.get_global_rect().intersects(card.get_global_rect()), "scout heading stays below shop evolution strip")
			check(not screen._scout_bar.get_global_rect().intersects(card._title.get_global_rect()), "scout heading leaves room for hovered recruit name")
	check(not screen._scout_bar.get_global_rect().intersects(screen._damage_panel.get_global_rect()), "scout identity and damage share non-overlapping rows")
	check(first._ownership.visible, "scouting keeps local ownership on the local shop")
	screen._toggle_shop(); await frames(8)
	bounded(screen._scout_bar, "scout heading with shop hidden")
	screen._toggle_shop(); await frames(8)
	check(screen._damage_panel.rows.size()==viewed.deployed_count(), "scouting shows watched preparation roster")
	var titles := screen._damage_panel.rows.values().map(func(row):return row.title.text)
	check(titles.has(ArenaRules.title(ArenaRules.prototype(21,1))) and not titles.has(ArenaRules.title("boarredf1")), "scouted damage names are theirs, not local player's")
	var watched := screen._viewed_battle()
	watched.round_army.assign(viewed.army.duplicate(true)); watched.friendly_damage[int(viewed.army[0].uid)]=123.0
	screen.run.stage="fight"; screen._damage_wait=0; screen._process(0)
	check(screen._damage_panel.rows[int(viewed.army[0].uid)].value.text=="123", "scouted damage values use watched battle ledger")
	screen.run.stage="prepare"; await shot("readability-"+language+"-spectator")
	screen._show_player(0); screen._hide_inspector()
	# Fit all board corners and figure/health-bar height at normal and tall ratios.
	for resolution in [Vector2i(1280,720),Vector2i(1280,960),Vector2i(1600,900)]:
		get_window().size=resolution; await frames(6); screen.field.reset_camera()
		var safe := screen.field.battle_screen_rect().grow(2)
		var board := screen.battle.bounds()
		for x: float in [board.position.x,board.end.x]:
			for y: float in [board.position.y,board.end.y]:
				for z: float in [0.0,4.5]:
					var at := screen.field.camera.unproject_position(Vector3(x,z,-y))
					check(safe.has_point(at), "entire battle and tall figures fit safe viewport at "+str(resolution))
		screen._show_player(1); await frames(8)
		check(not screen._scout_bar.get_global_rect().intersects(screen._shop_panel.get_global_rect()), "scout and shop remain separate after resize "+str(resolution))
		bounded(screen._battle_sidebar, "scout sidebar after resize "+str(resolution))
		screen._show_player(0)
	get_window().size=Vector2i(1280,800); await frames(6)
	bounded(screen._start,"start button after viewport resize")
	check(not screen._standings.get_global_rect().intersects(screen._round_panel.get_global_rect()), "player standings sit below the round status")
	screen.field.reset_camera()
	screen.set_process(false)
	var detail_entry: Dictionary = screen.run.army.filter(func(e): return e.family==8)[0]
	screen._inspect(detail_entry.prototype,detail_entry); await frames(8)
	check(screen._rail.accented and screen._rail.edge==ArenaStars.for_family(8), "inspector border follows unit price tier")
	check(not screen._standings.visible, "inspector text is not overlapped by player standings")
	var evolution: ArenaEvolutionPath = screen._inspect_box.get_node("EvolutionPath")
	check(evolution.get_child_count()==5 and evolution.size.y<80, "inspector evolution fits one compact strip")
	check(evolution._steps[2].get_meta("arena_help").contains(ArenaRules.title(ArenaRules.prototype(8,2))), "compact evolution retains full form names on hover")
	for stars: ArenaStars in screen._rail.find_children("*","ArenaStars",true,false): check(stars.color==ArenaStars.for_family(8),"inspector star tint follows price tier")
	bounded(screen._rail,"localized inspector")
	await shot("readability-"+language+"-inspector")
	screen._hide_inspector(); screen._round_banner._key=""; screen._round_banner._pending.clear()
	screen.run.wave=2; screen.run.last_result={"wave":1,"winner":0,"income":{"base":5,"interest":2,"victory":1,"streak":0,"total":8}}
	screen._round_banner.update_round(screen.run,0,4,false); await frames(4)
	await shot("readability-"+language+"-income")
	check(screen._round_banner.position.y < screen._hud.size.y*0.4, "round notice stays in upper HUD")
	bounded(screen._round_banner,"localized unframed round notice")
	screen._round_banner.update_round(screen.run,3,4,false)
	var old_level := screen.run.capacity(); screen.run.training=55; screen._refresh(); await frames(2)
	check(screen.run.capacity()>old_level and is_instance_valid(screen._level_sound) and screen._level_sound.playing, "company level plays independent UI cue")
	# Run actual native combat through the private worker at 2x; the camera stays.
	if language=="en":
		screen.run.wave=1; screen.run.last_result.clear()
		screen.run._touch()
		screen.set_process(true); screen._hide_inspector(); screen.field.reset_camera()
		var pose := [screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset]
		GameData.arena_speed=2; screen._fight()
		var deadline := Time.get_ticks_msec()+45000
		while screen.battle.phase != ArenaMatch.Phase.FIGHT and Time.get_ticks_msec()<deadline: await frames(1)
		check(screen.battle.phase==ArenaMatch.Phase.FIGHT,"fresh solo starts real private-worker combat")
		check(pose==[screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset],"round start preserves camera")
		await frames(90)
		await shot("readability-"+language+"-combat")
		check(screen.battle.external_combat,"combat receives authoritative worker snapshots")
		await frames(120)
	check(errors.messages.is_empty(), "no engine errors: "+str(errors.messages))
	print("ARENA_READABILITY_UI ",language," checks=",checks," failures=",JSON.stringify(failures))
	screen.queue_free(); screen=null; await frames(6)
	get_tree().quit(0 if failures.is_empty() else 1)
