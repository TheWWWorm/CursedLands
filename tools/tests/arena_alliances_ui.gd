extends "arena_expansion_ui.gd"
## Rendered continuity, physical preview pixels, side feedback and timed rounds.
func preview_ids() -> Dictionary:
	var ids := {}
	for preview: WikiPreview in screen._hud.find_children("*", "WikiPreview", true, false):
		if preview.creature:
			ids[preview.get_instance_id()] = preview.creature._vp.get_instance_id()
	return ids
func retained(ids: Dictionary, label: String) -> void:
	var current := preview_ids()
	for key in ids:
		check(current.get(key) == ids[key], label)
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.options.merge({"gfx_soft_ground":1,"footprints":1,"marks":1,"auto_graphics":0,"confine_mouse":0},true)
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"
	var dimensions := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size = dimensions;get_tree().root.position = Vector2i.ZERO
	RemakeText.lang = lang
	await frames(8)
	screen = ArenaPveScreen.new();add_child(screen);await frames(18)
	var tag := "alliances-%s-%d" % [lang,dimensions.x]
	screen._seed_input.text="1941";screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,1)
	screen.run._recruit(1,1,6);screen.run._recruit(3,1,7)
	screen._refresh();await frames(20)
	for i in 100:
		if screen.battle.formation_motion.movers.is_empty(): break
		await get_tree().create_timer(0.05).timeout
	var identities := {}
	for unit in screen.battle.world.unit_rows(): identities[unit.get_instance_id()] = unit.model.get_instance_id()
	var portraits := preview_ids()
	var resized: Array[int] = []
	for preview: WikiPreview in screen._hud.find_children("*", "WikiPreview", true, false):
		if preview.creature:
			preview.creature._vp.size_changed.connect(func(): resized.append(1))
	var reserve := screen.run.army.filter(func(entry):return not entry.deployed)[0] as Dictionary
	var reserve_button := screen._army_row.get_child(0) as Button
	await click(reserve_button.get_global_rect().get_center())
	retained(portraits,"selecting reserves retains all portrait viewports")
	check(screen.selected_uid == int(reserve.uid),"reserve selected")
	await click(screen._army_row.get_child(1).get_global_rect().get_center())
	retained(portraits,"changing selected reserve retains all portrait viewports")
	check(resized.is_empty(), "reserve selection never reallocates another portrait image")
	# Move an existing field creature, preserving its clip and every other actor.
	screen._clear_selection()
	var uid := int(screen.run.army[0].uid)
	await click(point(body(uid)))
	var animation := body(uid).model.player
	var length := animation.current_animation_length
	animation.seek(length * 0.45, true)
	await click(screen.field.screen_point(Vector2(29,39)))
	check(Vector2(screen.run.unit(uid).point[0], screen.run.unit(uid).point[1]).distance_to(Vector2(29,39)) < 0.1 and screen.selected_uid == 0,"move releases selection")
	for unit in screen.battle.world.unit_rows():
		check(identities.get(unit.get_instance_id()) == unit.model.get_instance_id(),"moving retains every actor and figure")
	check(body(uid).order.get("type", "") == "move" or body(uid).action in ["run", "walk"],"moved creature receives a native movement command")
	retained(portraits,"field placement retains shop and remaining reserve portraits")
	check(resized.is_empty(), "field selection and placement never resize other portrait targets")
	# Locking and an unrelated purchase update controls without recreating offers.
	var lock := screen._shop.get_child(0).get_child(1) as Button
	var lock_rect := lock.get_global_rect()
	await click(lock_rect.get_center())
	retained(portraits,"locking retains portrait render targets")
	check(screen._shop.get_child(0).get_child(1).get_global_rect() == lock_rect,"lock position is stable")
	for preview: WikiPreview in screen._hud.find_children("*","WikiPreview",true,false):
		if not preview.creature or not preview.is_visible_in_tree():continue
		var physical := preview.get_global_rect().size
		var pixels := Vector2(preview.creature._vp.size)
		check(pixels.x >= floorf(physical.x) and pixels.y >= floorf(physical.y),"preview renders at physical display resolution")
		preview_fits(preview,"physical preview")
	await move(Vector2(620,420)*screen._ui_scale);await frames(20)
	await shot(tag+"-prepare")
	# Side evolution has no input surface over the battlefield.
	screen._evolution_notice.present([{"uid":uid,"from":"boarredf1","to":"boarredf3","old_rank":0,"rank":1}])
	await get_tree().create_timer(0.35).timeout
	bounded(screen._evolution_notice,"side evolution")
	check(screen._evolution_notice.position.x > screen._hud.size.x * 0.65,"evolution stays at the right edge")
	check(screen._evolution_notice.mouse_filter==Control.MOUSE_FILTER_IGNORE,"evolution never captures battlefield clicks")
	await shot(tag+"-evolution")
	screen._evolution_notice.clear()
	# Actual real-time countdown, paused menus, then automatic start at expiry.
	hold_preparation = false
	screen.run.preparation_left = 12
	await get_tree().create_timer(0.3).timeout
	check(screen.run.preparation_left < 11.85 and screen.run.preparation_left > 10.5,"visible preparation clock advances in real time")
	screen._show_menu();await frames()
	var paused := screen.run.preparation_left
	await get_tree().create_timer(0.3).timeout
	check(is_equal_approx(screen.run.preparation_left,paused),"menu pauses the preparation timer")
	screen._close_modal()
	screen.run.preparation_left = 0.15
	await get_tree().create_timer(0.35).timeout
	check(screen.run.stage=="fight" and screen.battle.phase==ArenaMatch.Phase.FIGHT,"timer automatically starts both AI teams")
	check(screen.selected_uid==0,"automatic start releases selected creature")
	screen.battle.set_process(false);screen.battle.world.set_process(false);screen.battle.world.set_physics_process(false)
	for tick in 1800:
		if screen.battle.phase != ArenaMatch.Phase.FIGHT: break
		screen.battle.simulate_tick()
	check(screen.battle.phase==ArenaMatch.Phase.FINISHED,"timed-start native fight resolves")
	check(not screen._outcome.visible,"result waits for final animation")
	screen.battle._process(1.6);await frames()
	bounded(screen._outcome,"side result")
	check(screen._outcome.visible and not screen._outcome_shade.visible,"result has no modal shade")
	check(screen._outcome.position.x > screen._hud.size.x * 0.65,"victory stays at the right edge")
	await shot(tag+"-victory")

	# Side result advances without any continue/confirm button.
	check(screen._dock.find_children("*", "Button", true, false).is_empty(), "ordinary result has no confirmation button")
	var wave_before := screen.run.wave
	screen._show_menu(); var remaining := screen._result_remaining
	await get_tree().create_timer(0.3).timeout
	check(is_equal_approx(screen._result_remaining, remaining), "menu pauses result transition")
	screen._close_modal(); screen._result_remaining = 0.1
	await get_tree().create_timer(0.25).timeout
	check(screen.run.wave == wave_before + 1 and screen.run.stage == "prepare", "result advances into the next preparation automatically")
	screen.battle.set_process(true)
	hold_preparation = true
	# Training is a direct, visible HUD purchase. Level changes odds and capacity.
	screen.run.gold = 20; screen.run.training = 5; screen._refresh(); await frames()
	bounded(screen._train_button, "visible training button")
	var old_gold := screen.run.gold
	var shelf := screen.run.shop.duplicate(true)
	await click(screen._train_button.get_global_rect().get_center())
	check(screen.run.gold == old_gold - 5 and screen.run.training == 10, "HUD training click buys XP directly")
	check(not screen._modal_layer.visible and screen.run.capacity() == 4, "training needs no menu or confirmation")
	check(screen.run.shop == shelf, "training preserves existing offers")
	check(screen._level_label.text.contains(str(screen.run.capacity())), "HUD displays the company level")
	# Alliance hover explains automatic contributions and bonuses.
	var beast := screen._alliance_list.get_node("beast") as Control
	check(beast.is_visible_in_tree(), "alliance progress is permanently visible beside the field")
	await move(beast.get_global_rect().get_center()); await get_tree().create_timer(0.45).timeout
	check(screen._rail.visible and not screen._modal_layer.visible, "alliance details open on hover")
	bounded(screen._rail, "alliance detail panel")
	await shot(tag + "-alliance")
	await move(Vector2(600,420)*screen._ui_scale);await get_tree().create_timer(0.3).timeout
	check(not screen._rail.visible,"alliance details close after leaving")
	await shot(tag + "-hud")
	# Menus expose neither training nor sandbox; main menu has no Arena button.
	screen._show_menu();await frames()
	var labels: Array[String] = []
	for button: Button in screen._modal_box.find_children("*","Button",true,false): labels.append(button.text)
	check(not labels.has(RemakeText.t("Sandbox")) and not labels.has(RemakeText.t("Train your company")),"menu contains neither arena nor training")
	check(screen._menu_items.keys().all(func(k):return k != 1 and k != 5),"removed actions have no focus targets")
	screen._close_modal()
	# Camps contain actual upgrades, never a pact selection or extra confirm.
	screen.run.wave = 5;screen.run.stage = "fight";screen.run.resolve(0,20,[40,10]);screen.run.advance()
	await frames(12)
	check(screen.run.stage == "reward" and screen.run.rewards.all(func(r):return r.kind not in ["pact","pact_upgrade"]),"camp cannot show retired pact UI")
	bounded(screen._outcome,"localized camp")
	await shot(tag + "-camp")
	var first := screen._dock.get_child(2).get_child(0) as Button
	await click(first.get_global_rect().get_center())
	check(screen.run.stage == "prepare" and screen.run.wave == 6,"upgrade choice immediately returns to preparation")
	check(errors.messages.is_empty(), "no script or shader errors")
	print("ARENA_ALLIANCES_UI ",checks," checks; failures=",JSON.stringify(failures)," errors=",JSON.stringify(errors.messages))
	get_tree().quit(0 if failures.is_empty() else 1)
