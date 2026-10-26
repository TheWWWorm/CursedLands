extends "arena_equipment_ui.gd"
## Equipment must remain reachable on every creature in a compact formation.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "expanded roster mounted")
	var lang := "en"
	var dimensions := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=", 1).split(",")
			lang = spec[0]; dimensions = Vector2i(int(spec[1]), int(spec[2]))
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = dimensions
	get_tree().root.position = Vector2i.ZERO
	RemakeText.lang = lang
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(15)
	screen._seed_input.text = "6519"; screen._begin(); screen.run.auto_save = false
	check(screen.run is ArenaTournamentRun and screen.run.expansion, "expanded Autochess uses the production tournament screen")
	screen.run.army.clear(); screen.run.training = ArenaRules.MAX_TRAINING
	for index in 9:
		var entry := screen.run._recruit([0, 9, 14, 11, 11, 11, 13, 7, 28][index], index % 3, 1)
		entry.deployed = true
		entry.point = [25.0 - (index / 3) * 3.0, 29.0 + (index % 3) * 3.0]
	screen.run.items.assign([{"uid":1,"kind":"haste","unit_uid":0}]); screen.run.next_item_uid = 2
	screen.run._touch(); await frames(20)
	for entry: Dictionary in screen.run.army:
		await click_control(screen._item_tray.buttons[1])
		var target: Control = screen._item_targets.get(int(entry.uid))
		check(is_instance_valid(target) and target.is_visible_in_tree(), "reachable target family %s rank %s" % [entry.family, entry.rank])
		if target and target.visible:
			if entry.family == 11:
				var center := target.get_global_rect().get_center()
				var stable := true
				for frame in 60:
					await frames(1)
					stable = stable and target.get_global_rect().has_point(center)
				check(stable, "idle animation keeps the Woodsfolk equipment target under the pointer")
			await move(target.get_global_rect().get_center())
			await click_control(target)
			check(screen.run.item_for(entry.uid) == "haste", "Swift Boots click equips family %s rank %s" % [entry.family, entry.rank])
		else: screen._cancel_item()
	await click_control(screen._item_tray.buttons[1])
	# Native drags use the same reachable targets for all Woodsfolk stars.
	for entry: Dictionary in screen.run.army:
		if entry.family != 11: continue
		screen._cancel_item()
		await start_drag(screen._item_tray.buttons[1])
		await release_drag(screen._item_targets[int(entry.uid)].get_global_rect().get_center())
		check(screen.run.item_for(entry.uid)=="haste", "native drag equips Woodsfolk star " + str(entry.rank + 1))
		var actor := body(entry.uid)
		check(is_equal_approx(actor.actions(),18.0), "equipped Woodsfolk receives Swift Boots speed")
		var marker: Control = screen.field._unit_markers[actor.get_instance_id()]
		check(str(maxi(0,ceili(actor.hp))) in str(marker.state) and not str(marker.state).contains("%d/%d" % [ceili(actor.hp),ceili(actor.max_hp)]), "health marker omits redundant maximum")
	await click_control(screen._item_tray.buttons[1])
	await shot("equipment-crowded-%s-%d" % [lang, dimensions.x])
	screen._cancel_item()
	var badge: Control = screen._alliance_list.get_node("beast")
	# A synthetic motion alone leaves the virtual display's physical pointer
	# elsewhere. Align it first so a later native event cannot undo the hover.
	Input.warp_mouse(badge.get_global_rect().get_center())
	await frames(4)
	await move(badge.get_global_rect().get_center()); await frames(15)
	check(get_viewport().gui_get_hovered_control() == badge, "pointer stays over the Beast badge")
	check(screen._rail.visible, "Beasts hover opens roster")
	await click_control(badge)
	var start := badge.get_global_rect().get_center()
	var finish := screen._inspect_scroll.get_global_rect().get_center()
	for step in 12:
		await move(start.lerp(finish, float(step + 1) / 12.0))
	check(screen._rail.visible and screen._showing_company, "Beasts roster stays reachable while moving from badge")
	if screen._rail.visible:
		for step in 20:
			var wheel := InputEventMouseButton.new(); wheel.position = finish; wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
			Input.parse_input_event(wheel); await frames(1)
		var bar := screen._inspect_scroll.get_v_scroll_bar()
		check(screen._inspect_scroll.scroll_vertical > 0 or bar.max_value <= bar.page, "Beasts roster scrolls when its full list exceeds the panel")
		var last := screen._inspect_box.get_child(screen._inspect_box.get_child_count() - 1).get_child(31) as Control
		check(screen._inspect_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "last Beast is reachable")
	await shot("beasts-scroll-%s-%d" % [lang, dimensions.x])
	await key(KEY_ESCAPE)
	check(not screen._rail.visible, "Escape dismisses the pinned alliance")
	for family in [11, 32, 19, 38]:
		var entry := {"family":family,"rank":1,"prototype":ArenaRules.prototype(family,1)}
		screen._inspect(entry.prototype, entry)
		screen._pinned_alliance = "fixture-stats"
		await frames(12)
		bounded(screen._rail, "rank stats inspector")
		check(screen._live_health is RichTextLabel and screen._live_health.bbcode_enabled, "inspector renders bold star values")
		check(screen._live_health.text.count("[b]") >= 7, "each primary stat includes current star emphasis")
		check(not screen._live_health.get_parsed_text().contains("[b]"), "markup never reaches the player")
		await shot("rank-stats-%d-%s-%d" % [family,lang,dimensions.x])
		screen._hide_inspector()
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	screen.queue_free(); await frames(3)
	print("ARENA_EQUIPMENT_ROSTER_UI ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
