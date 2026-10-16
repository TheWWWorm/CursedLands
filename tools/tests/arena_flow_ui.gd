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
	var tag := "flow-%s-%d" % [lang,dimensions.x]
	screen._seed_input.text="1941";screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,1)
	screen.run._recruit(1,1,6);screen.run._recruit(3,1,7)
	screen._refresh();await frames(20)
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
	check(animation.current_animation_position > length * 0.35,"moved creature keeps its animation phase")
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
	# Pact cards show progress for all choices before committing.
	hold_preparation=true
	screen.run.wave=3;screen.run.stage="fight";screen.run.resolve(0,20,[40,10]);screen.run.advance()
	await frames(16)
	bounded(screen._outcome,"pact camp")
	for label: Label in screen._dock.find_children("*","Label",true,false):
		check(screen._outcome.get_global_rect().grow(1).encloses(label.get_global_rect()),"pact text stays inside frame")
	await shot(tag+"-pact-choices")
	var chosen := screen.run.choose_reward(0)
	check(chosen.is_empty(),"pact can be chosen")
	screen._refresh();await frames(12)
	await move(screen._pact_hint.get_global_rect().get_center());await get_tree().create_timer(0.4).timeout
	check(screen._rail.visible and screen._showing_company,"pact count exposes requirements on hover")
	check(screen._pact_hint.text==RemakeText.t("Pact %d/%d") % [3,3],"pact counter uses distinct deployed families")
	await shot(tag+"-pact-active")
	await move(Vector2(610,420)*screen._ui_scale);await frames()
	# Empty-field expiry deploys purchased reserves, empty-company expiry forfeits.
	screen.run.begin(1942);screen.run.auto_save=false
	Fixture.buy_company(screen.run,0)
	for entry in screen.run.army:entry.deployed=false
	screen._refresh();await frames(10)
	hold_preparation=false;screen.run.preparation_left=0.01
	await get_tree().create_timer(0.1).timeout
	check(screen.run.stage=="fight" and screen.run.deployed_count()==3,"empty-field timeout deploys reserves")
	screen.run.begin(1943);screen.run.auto_save=false;screen._refresh()
	screen.run.preparation_left=0.01
	await get_tree().create_timer(0.15).timeout
	check(screen.run.stage=="result" and screen.run.lives==2,"empty company forfeits at expiry")
	screen.battle._process(1.6);await frames()
	bounded(screen._outcome,"empty-company side result")
	await shot(tag+"-forfeit")
	screen.queue_free();await frames(8)
	check(errors.messages.is_empty(),"no scene, shader or script errors: "+JSON.stringify(errors.messages))
	print("ARENA_FLOW_UI ",checks," checks; failures=",JSON.stringify(failures))
	OS.remove_logger(errors)
	get_tree().quit(0 if failures.is_empty() else 1)
