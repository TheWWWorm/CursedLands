extends Node
## Targeted integration check, not a full-game performance benchmark. Exercise
## real menu callbacks, worker teardown and diagnostic export after a battle
## and a loaded campaign. Use an isolated user directory with retention-end.
var main
var sampler: PerformanceLog
var checks := 0
var failures := []
var observations := []
var snapshot_usec := []


func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame


func until(condition: Callable, seconds := 60.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	return condition.call()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
	return ok


func record(label: String) -> void:
	var start := Time.get_ticks_usec()
	var data := sampler.snapshot(label)
	snapshot_usec.append(Time.get_ticks_usec() - start)
	observations.append(data)
	print("MENU_PERFORMANCE ", JSON.stringify(data))


func current_menu():
	for node in main.get_children():
		if node.get_script() == preload("res://src/ui/main_menu.gd"): return node
	return null


func current_trials() -> ArenaPveScreen:
	for node in main.get_children():
		if node is ArenaPveScreen: return node
	return null


func world_refs() -> Array:
	return get_tree().get_nodes_in_group(GameWorld.DIAGNOSTIC_GROUP).map(func(w): return weakref(w))


func all_freed(refs: Array) -> bool:
	return refs.all(func(w: WeakRef): return w.get_ref() == null)


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		get_tree().quit(); return
	# The test controller must survive Main._clear and Main.start_game.
	main = get_parent()
	main.remove_child(self)
	main.get_tree().root.add_child(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	sampler = CrashReport.instance._performance
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA), true)
	GameData.options.merge({"autosave":0, "show_tutorial":0, "auto_graphics":0,
		"net_lan":0, "net_upnp":0, "net_directory":0, "display_mode":0,
		"confine_mouse":0, "vsync":0, "fps_limit":0, "scroll_border":0,
		"pad_enabled":0, "camera_style":1, "coop_clock":1}, true)
	await frames(15)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameData.arena_mode = 1
	GameData.arena_speed = 2
	await main.open_menu()
	await frames(15)
	record("initial-menu")
	var menu = current_menu()
	if not check(menu != null, "main menu opens"): finish(); return
	menu._arena_pve_button.pressed.emit()
	if not check(await until(func(): return current_trials() != null), "Trials menu button opens Trials"):
		finish(); return
	var screen := current_trials()
	await frames(15)
	screen._seed_input.text = "7319"
	screen._landing_start.pressed.emit()
	screen.run.auto_save = false
	# One late-round fixture, not a claim to complete a whole tournament.
	screen.run.wave = 12
	screen.run.stage = "prepare"
	screen.run.lives = 100
	for player in 9:
		var company := (screen.run as ArenaTournamentRun).company(player)
		company.army.clear()
		company.wave = 12
		company.training = 110
		company.gold = 50
		company.auto_save = false
		company.lives = company.life_limit()
		for family in [7,9,10,11,17,18,22]: company._recruit(family, 1, 10)
		company.arrange()
	(screen.run as ArenaTournamentRun)._prepare_round()
	for plan: Dictionary in screen.run.bot_plans: plan.done = true
	screen._refresh()
	screen._tournament_battles.synchronize()
	await frames(40)
	screen._tournament_battles.request_start()
	if not check(await until(func(): return screen.run.stage != "prepare"), "populated battle starts"):
		finish(); return
	var worker := -1
	if screen._tournament_battles is ArenaSoloBattles:
		worker = screen._tournament_battles.connection.local_host.process_id
	check(worker > 0 and OS.is_process_running(worker), "Trials uses its actual private worker")
	record("Trials-combat")
	check(await until(func(): return screen.run.stage != "fight", 65.0), "battle settles")
	var old_worlds := world_refs()
	var old_screen: WeakRef = weakref(screen)
	screen._menu.pressed.emit()
	var exit_button: Button
	for button in screen._modal_box.find_children("*", "Button", true, false):
		if button.text == RemakeText.t("Main menu"): exit_button = button
	if not check(exit_button != null, "Trials main-menu button exists"): finish(); return
	exit_button.pressed.emit()
	check(await until(func(): return current_menu() != null and not main._leaving), "Trials menu exit completes")
	await frames(15)
	check(old_screen.get_ref() == null and all_freed(old_worlds), "Trials screen and all old worlds are freed")
	check(await until(func(): return worker <= 0 or not OS.is_process_running(worker), 10.0), "Trials worker terminates")
	record("after-Trials-menu")
	menu = current_menu()
	menu._load_slot("retention-end")
	var loaded := func() -> bool:
		return main.game != null and main.session != null and main.session.world != null \
			and not main.session.loading_game and not main.session._remote_loading
	if not check(await until(loaded, 90.0),
		"campaign loads through the ordinary save handler"):
		finish(); return
	await frames(60)
	var game: Game = main.game
	var session: Session = main.session
	var party := session.party_units(session.my_index)
	if not check(not party.is_empty(), "loaded campaign has a controllable hero"): finish(); return
	var hero: GameUnit = party[0]
	game.selected.assign([hero])
	game.rig.focus(hero.position)
	game.rig.follow(hero)
	game.hud.text_window.open = false
	game.set_speed(2)
	# Standalone campaign retains the original 55 ms / 27 ms clock. Co-op
	# uses exactly 2.0; both are the accelerated position of the game dial.
	var accelerated := 2.0 if session.multiplayer_game else 55.0 / 27.0
	check(await until(func(): return game.speed == 1 and is_equal_approx(Engine.time_scale, accelerated), 10.0),
		"campaign uses its accelerated clock setting")
	check(get_viewport().msaa_3d == Viewport.MSAA_4X
		and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA
		and is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "actual viewport realizes Ultra anti-aliasing and native scale")
	record("deep-save-loaded")
	var began := Time.get_ticks_msec()
	var next_order := 0.0
	var next_spell := 0.0
	var cast_slot := 0
	var start := hero.pos
	var last := start
	var distance := 0.0
	var initial_dead := session.world.unit_rows().filter(func(u): return u.dead).size()
	# Let the normal 30-second sampler fire repeatedly in a rendered world.
	while Time.get_ticks_msec() - began < 95000 and not hero.dead:
		await get_tree().process_frame
		distance += hero.pos.distance_to(last)
		last = hero.pos
		var elapsed := (Time.get_ticks_msec() - began) / 1000.0
		if elapsed < next_order: continue
		next_order = elapsed + 0.5
		if hero.action.begins_with("cast"): continue
		if hero.hp < hero.max_hp * 0.6 and elapsed >= next_spell and hero.mana > 40:
			game.begin_cast(3)
			game.cast_on(hero)
			game.cancel_touch_target()
			next_spell = elapsed + 3.0
			continue
		var foes := session.world.unit_rows().filter(func(u): return not u.dead and not u.hidden \
			and u.visible and u.controller < 0 and session.world.is_enemy(hero, u) \
			and hero.pos.distance_to(u.pos) < 18 and session.world.sight_ray(hero, u) > 0.1)
		foes.sort_custom(func(a,b): return hero.pos.distance_squared_to(a.pos) < hero.pos.distance_squared_to(b.pos))
		if not foes.is_empty():
			var target: GameUnit = foes[0]
			if elapsed >= next_spell and hero.mana > 100:
				game.begin_cast(cast_slot % 3)
				game.cast_on(target, null, target.pos)
				game.cancel_touch_target()
				cast_slot += 1
				next_spell = elapsed + 5.0
			elif hero.action in ["idle", "walk", "run"]:
				game.forced_on("attack", target, null)
		elif hero.action == "idle":
			game.issue({"t":"move", "units":[hero.uid], "x":230, "y":210, "run":true})
	var play := {"wall_seconds":(Time.get_ticks_msec()-began)/1000.0, "travel_m":distance,
		"start":[start.x,start.y], "end":[hero.pos.x,hero.pos.y], "hp":hero.hp,
		"new_dead":session.world.unit_rows().filter(func(u): return u.dead).size()-initial_dead,
		"cast_attempts":cast_slot}
	observations.append({"campaign":play})
	check(not hero.dead, "equipped hero survives integration run")
	record("deep-save-played")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://menu-performance-campaign.png")
	old_worlds = world_refs()
	var old_game: WeakRef = weakref(game)
	var old_session: WeakRef = weakref(session)
	worker = session.local_host.process_id
	game.hud.toggle_menu()
	game.hud._on_signpost("exit")
	check(game.hud._quit_box != null, "campaign exit uses its confirmation dialog")
	game.hud._quit_box._answer(true)
	check(await until(func(): return current_menu() != null and not main._leaving), "campaign confirmed exit returns to menu")
	await frames(15)
	check(old_game.get_ref() == null and old_session.get_ref() == null and all_freed(old_worlds),
		"campaign session, game and all old worlds are freed")
	check(await until(func(): return worker <= 0 or not OS.is_process_running(worker), 10.0), "campaign worker terminates")
	record("final-menu")
	CrashReport.save_dir_override = "user://performance-reports"
	var exported := CrashReport.instance.save_report({})
	var report := FileAccess.get_file_as_string(exported)
	var captured := []
	for line: String in report.split("\n"):
		if not line.begins_with("PERFORMANCE "): continue
		var parsed: Variant = JSON.parse_string(line.trim_prefix("PERFORMANCE "))
		if parsed is Dictionary: captured.append(parsed)
	var campaign_intervals := captured.filter(func(row): return row.reason == "interval" \
		and row.pid == OS.get_process_id() and is_equal_approx(row.time_scale, accelerated) \
		and not row.worlds.is_empty() and row.worlds[0].get("zone", "") == "gz17h")
	check(campaign_intervals.size() >= 2, "existing export includes multiple accelerated campaign intervals")
	check(captured.any(func(row): return row.reason == "report" and row.world_count == 0),
		"existing export includes current state after both menu exits")
	observations.append({"export":exported})
	finish()


func finish() -> void:
	var result := {"checks":checks, "failures":failures, "observations":observations,
		"snapshot_usec":snapshot_usec}
	FileAccess.open("user://menu-performance-log.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MENU_PERFORMANCE_DONE ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
