extends "arena_expansion_ui.gd"
## Actual reward, inventory and equipment controls at localized desktop sizes.

func move(at: Vector2) -> void:
	# UI input uses viewport events; no OS warp event can arrive late and
	# overwrite the intended hover on a different desktop/window offset.
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(3)

func click_control(control: Control) -> void:
	await frames(6)
	await get_tree().create_timer(0.05).timeout
	await click(control.get_global_rect().get_center())

func click(at: Vector2) -> void:
	await move(at)
	# Let deferred container sizes settle before the press/release pair.
	await get_tree().create_timer(0.08).timeout
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().create_timer(0.035).timeout
		await frames(2)

func key(code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.shift_pressed = shift
		Input.parse_input_event(event)
		await frames(2)

func pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)

func texts(node: Node) -> String:
	var result := String(node.text) if node is Label or node is Button else ""
	for child in node.get_children(): result += "\n" + texts(child)
	return result

func start_drag(source: Control) -> void:
	source.grab_focus()
	await frames(8)
	var start := source.get_global_rect().get_center()
	await move(start)
	var press := InputEventMouseButton.new()
	press.position = start; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	Input.parse_input_event(press)
	await frames(4)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(85, 12); motion.relative = Vector2(85, 12); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await frames(8)
	check(get_viewport().gui_is_dragging(), "physical press/move starts a native drag")

func release_drag(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at; motion.relative = Vector2(40, 10); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await frames(5)
	var release := InputEventMouseButton.new()
	release.position = at; release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	Input.parse_input_event(release)
	await frames(10)

func reserve_button(uid: int) -> Button:
	for button: Button in screen._army_row.get_children():
		if int(button.get_meta("arena_creature", {}).get("uid", 0)) == uid: return button
	return null

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 0
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"
	var dimensions := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=", 1).split(",")
			lang = spec[0]; dimensions = Vector2i(int(spec[1]), int(spec[2]))
	get_tree().root.size = dimensions
	get_tree().root.position = Vector2i.ZERO
	RemakeText.lang = lang
	await frames(8)
	screen = ArenaPveScreen.new()
	add_child(screen)
	await frames(15)
	screen._seed_input.text = "6519"
	screen._begin()
	screen.run.auto_save = false
	Fixture.buy_company(screen.run, 1)
	var first_uid := int(screen.run.army[0].uid)
	var second_uid := int(screen.run.army[1].uid)
	var bench_uid := int(screen.run.army[2].uid)
	screen.run.bench(bench_uid)
	await frames(12)
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(20,15); orbit.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	screen.field._orbit = true
	screen.field._gui_input(orbit)
	check(screen.field.yaw != ArenaPveField.DEFAULT_YAW and screen.field.pitch_offset != 0, "middle drag rotates and tilts the Autochess camera")
	screen.field.reset_camera()
	check(screen.battle.state.world_time == ArenaMatch.DAYTIME and screen.battle.world.daylight() > 0.9, "Autochess starts in daytime")
	check(screen._item_tray.visible and screen._item_tray._empty.visible, "empty tray stays on the board")
	bounded(screen._item_tray, "empty item tray")
	screen.run.offer_items_after(3)
	screen.run._touch()
	await frames(12)
	check(screen._modal_layer.visible, "new reward opens exactly three cards")
	check(screen._equipment_panel._offer_row.get_child_count() == 3, "three reward choices")
	check(get_viewport().gui_get_focus_owner() == null, "mouse reward opens without a preselected item")
	for card: Button in screen._equipment_panel._offer_row.get_children():
		await move(card.get_global_rect().get_center())
		check(card.is_hovered() and not card.has_focus(), "every reward card responds to mouse hover")
	await key(KEY_TAB)
	check(screen._equipment_panel._offer_row.get_child(0).has_focus(), "first navigation input focuses the first reward")
	await key(KEY_RIGHT)
	check(screen._equipment_panel._offer_row.get_child(1).has_focus(), "keyboard moves between rewards")
	await move(screen._equipment_panel._offer_row.get_child(0).get_global_rect().get_center())
	check(get_viewport().gui_get_focus_owner() == null, "mouse motion clears keyboard reward selection")
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(screen._equipment_panel._offer_row.get_child(0).has_focus(), "first controller input focuses the first reward")
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(screen._equipment_panel._offer_row.get_child(1).has_focus(), "controller moves between rewards")
	check(PadInput.active == "pad", "controller navigation retains controller input mode")
	await move(screen._equipment_panel._offer_row.get_child(0).get_global_rect().get_center())
	check(get_viewport().gui_get_focus_owner() == null, "mouse motion clears controller reward selection")
	bounded(screen._modal_panel, "reward cards")
	var kind := String(screen.run.item_offers[0])
	await shot("tray-%s-%d-reward" % [lang, dimensions.x])
	await click_control(screen._equipment_panel._offer_row.get_child(0))
	await frames(10)
	var item_uid := int(screen.run.items[0].uid)
	check(not screen._modal_layer.visible and screen._item_uid == item_uid, "reward closes and selects its new owned item")
	check(screen.run.item_for(first_uid).is_empty(), "reward does not equip itself")
	check(screen._item_targets[first_uid].visible and screen._item_targets[second_uid].visible, "all deployed allies expose circular targets")
	check(reserve_button(bench_uid).get_node("CreatureItemTarget").visible, "reserve exposes circular target")
	check(not screen._tooltips.visible, "carrying suppresses background tooltip")
	await click_control(screen._item_targets[first_uid])
	check(screen.run.item_for(first_uid) == kind and screen._item_uid == 0, "click target equips and leaves carry mode")
	await frames(8)
	check(screen._item_targets[first_uid].visible and screen._item_targets[first_uid].kind == kind, "equipped field badge persists after assignment")
	check(screen._item_tray.buttons[item_uid].equipped, "tray marks equipped ownership")
	screen.run.offer_items_after(5)
	screen.run._touch()
	await frames(10)
	var replacement_kind := String(screen.run.item_offers[1])
	await pad(JOY_BUTTON_DPAD_RIGHT)
	await pad(JOY_BUTTON_DPAD_RIGHT)
	await pad(JOY_BUTTON_A)
	check(screen.run.items.size() == 2 and screen.run.items.back().kind == replacement_kind, "controller accepts exactly the highlighted reward")
	var replacement_uid := int(screen.run.items.back().uid)
	await click_control(screen._item_targets[first_uid])
	check(screen.run.item_for(first_uid) == replacement_kind and screen._owned_item(item_uid).unit_uid == 0, "replacement returns former relic to stash")
	# A physical native drag goes from the tray to a reserve portrait.
	await start_drag(screen._item_tray.buttons[item_uid])
	await shot("tray-%s-%d-drag" % [lang, dimensions.x])
	await release_drag(reserve_button(bench_uid).get_global_rect().get_center())
	check(screen.run.item_for(bench_uid) == kind and screen._item_uid == 0, "drag assigns reserve without selecting it for deployment")
	check(screen.selected_uid == 0 and screen.field.ghost_id.is_empty(), "item drag never leaves a creature placement ghost")
	check(not get_viewport().gui_is_dragging(), "drop ends native drag")
	# Dragging an equipped badge transfers that same owned item.
	await start_drag(reserve_button(bench_uid).get_node("CreatureItemTarget"))
	await release_drag(screen._item_targets[second_uid].get_global_rect().get_center())
	check(screen.run.item_for(bench_uid).is_empty() and screen.run.item_for(second_uid) == kind, "equipped reserve badge transfers to field")
	check(screen._item_uid == 0, "source release cannot re-enter carry mode")
	await start_drag(screen._item_tray.buttons[item_uid])
	await release_drag(screen._item_tray.stash.get_global_rect().get_center())
	check(screen._owned_item(item_uid).unit_uid == 0 and screen.run.items.size() == 2, "explicit stash drop preserves item ownership")
	# A bad drop does not change ownership or creature placement.
	var placements: Array = screen.run.army.map(func(u): return u.point.duplicate())
	var enemies := screen.battle.world.unit_rows().filter(func(u): return int(u.get_meta("arena_placement", {}).get("team", -1)) == 1)
	await start_drag(screen._item_tray.buttons[replacement_uid])
	await release_drag(point(enemies[0]))
	check(screen._owned_item(replacement_uid).unit_uid == first_uid and screen._item_uid == 0, "enemy drop rejects assignment and snaps back")
	await start_drag(screen._item_tray.buttons[item_uid])
	await key(KEY_ESCAPE)
	check(screen._item_uid == 0 and not get_viewport().gui_is_dragging(), "Escape cancels logical state and native drag preview")
	await release_drag(Vector2(700, 520))
	await start_drag(screen._item_tray.buttons[item_uid])
	var cancel_event := InputEventMouseButton.new()
	cancel_event.position = Vector2(700, 520); cancel_event.button_index = MOUSE_BUTTON_RIGHT; cancel_event.pressed = true
	Input.parse_input_event(cancel_event)
	await frames(4)
	check(screen._item_uid == 0 and not get_viewport().gui_is_dragging(), "right click cancels item before camera orbit")
	cancel_event.pressed = false; Input.parse_input_event(cancel_event)
	await release_drag(Vector2(700, 520))
	check(screen.run.army.map(func(u): return u.point.duplicate()) == placements, "equip, invalid drops and cancellation preserve deployment")
	# Keyboard uses real visible field targets, then restores normal navigation.
	screen._item_tray.focus_item(item_uid)
	await key(KEY_ENTER)
	await key(KEY_TAB)
	var target := get_viewport().gui_get_focus_owner()
	check(target != null and target.has_meta("item_target_uid") and target.is_visible_in_tree(), "Tab reaches a visible creature target")
	var keyboard_uid := int(target.get_meta("item_target_uid", 0))
	await key(KEY_ENTER)
	check(screen._owned_item(item_uid).unit_uid == keyboard_uid, "Enter equips the focused creature")
	screen._item_tray.focus_item(item_uid)
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	check(screen._item_tray.buttons[item_uid].focus_next.is_empty(), "cancel clears temporary target focus links")
	screen._item_tray.focus_item(item_uid)
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == screen._item_tray.buttons[replacement_uid], "normal Tab reaches the next owned item after cancellation")
	# Read-only scouting rejects the same owned UID on a different match.
	screen._pick_item(item_uid)
	var scout := ArenaPveMatch.new()
	scout.world = screen.battle.world
	scout.run = screen.run
	screen.field.match_state = scout
	await frames(3)
	check(screen._item_uid == 0 and not screen._can_edit_equipment(), "switching match cancels carry and makes inventory read-only")
	screen.field.match_state = screen.battle
	scout.world = null; scout.free()
	screen._sync_item_tray()
	# Modal isolation also cancels the gesture without changing its carrier.
	screen._pick_item(item_uid)
	screen._guide()
	await frames(4)
	check(screen._item_uid == 0 and screen._modal_layer.visible, "opening another modal cancels assignment")
	screen._close_modal()
	check(screen._item_tray.editable, "closing modal restores tray editing")
	screen._pick_item(item_uid)
	screen.run.sell(bench_uid)
	await frames(8)
	check(screen._item_uid == item_uid and reserve_button(bench_uid) == null, "roster changes safely remove a carry target")
	screen._item_tray.focus_item(item_uid)
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() != null and get_viewport().gui_get_focus_owner().is_visible_in_tree(), "target focus rebuilds after a reserve is removed")
	screen._cancel_item()
	# Inventory scrolling retains control identities and focus visibility.
	var retained: Control = screen._item_tray.buttons[item_uid]
	for extra_kind: String in ArenaItems.RULES:
		screen.run.items.append({"uid":screen.run.next_item_uid, "kind":extra_kind, "unit_uid":0})
		screen.run.next_item_uid += 1
	screen.run._touch()
	await frames(12)
	check(screen._item_tray.buttons[item_uid] == retained, "state refresh retains item controls")
	var last_uid := int(screen.run.items.back().uid)
	screen._item_tray.focus_item(last_uid)
	await frames(12)
	check(screen._item_tray.scroll.get_v_scroll_bar().value > 0, "tray scroll follows keyboard focus")
	bounded(screen._item_tray, "full item tray")
	check(screen._battle_sidebar.get_global_rect().end.y <= screen._bench_panel.get_global_rect().position.y, "sidebar stays above reserves")
	# A real start locks all mutations, but focus still exposes item detail.
	screen._pick_item(item_uid)
	screen._fight()
	await frames(12)
	check(screen._item_uid == 0 and not screen._can_edit_equipment(), "starting combat cancels assignment and locks equipment")
	var carrier := int(screen._owned_item(item_uid).unit_uid)
	var snapshot_kind := String(body(carrier).get_meta("arena_placement").item)
	var actual_kind := String(screen._owned_item(item_uid).kind)
	screen._owned_item(item_uid).kind = "storm" if actual_kind != "storm" else "ward"
	screen.run._touch()
	await frames(4)
	check(screen._item_targets[carrier].kind == snapshot_kind, "combat badge reads frozen placement equipment")
	screen._owned_item(item_uid).kind = actual_kind
	screen.run._touch()
	screen._item_tray.focus_item(item_uid)
	await key(KEY_TAB)
	await get_tree().create_timer(0.5).timeout
	check(screen._tooltips.visible, "keyboard item inspection remains available during combat")
	await shot("tray-%s-%d-combat-tooltip" % [lang, dimensions.x])
	var owned := screen.run.items.duplicate(true)
	await key(KEY_ENTER)
	check(screen._item_uid == 0 and screen.run.items == owned, "combat activation cannot change equipment")
	# Existing alliance help retains bounded localized wrapping.
	for alliance: String in ArenaAlliances.RULES:
		screen._show_alliance(alliance)
		await frames(5)
		bounded(screen._rail, "localized alliance help " + alliance)
		check(texts(screen._inspect_box).contains(RemakeText.t(ArenaAlliances.RULES[alliance].help)), "full translated alliance explanation " + alliance)
	screen.queue_free()
	await frames(8)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("ARENA_EQUIPMENT_UI ", lang, " ", dimensions, " ", checks, " checks; failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
