extends "arena_expansion_ui.gd"
## Underlords-inspired reward/tray presentation using real Control drag events.

func move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(3)

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	Engine.max_fps = 30
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
	var reserve_uid := int(screen.run.army[2].uid)
	screen.run.bench(reserve_uid)
	for kind: String in ArenaItems.RULES:
		screen.run.items.append({"uid":screen.run.next_item_uid, "kind":kind, "unit_uid":0})
		screen.run.next_item_uid += 1
	screen.run.equip_item(1, int(screen.run.army[0].uid))
	var dragged_kind := screen.run.item_for(int(screen.run.army[0].uid))
	screen.run._touch()
	await frames(20)
	var tag := "equipment-tray-%s-%d" % [lang, dimensions.x]
	bounded(screen._item_tray, "persistent tray")
	check(screen._battle_sidebar.get_global_rect().end.y <= screen._bench_panel.get_global_rect().position.y, "sidebar stays above reserves")
	await shot(tag + "-tray")
	screen.run.item_offers.assign(["ward", "guardian", "storm"])
	screen.run.item_reward_round = 3
	screen.run._touch()
	await frames(15)
	check(screen._modal_layer.visible and screen._equipment_panel._offer_row.get_child_count() == 3, "three reward-only cards")
	bounded(screen._modal_panel, "reward modal")
	for card in screen._equipment_panel._offer_row.get_children():
		bounded(card, "reward card " + card.kind)
		check(screen._equipment_scroll.get_global_rect().grow(1).encloses(card.get_global_rect()), "whole reward and choose action visible without scrolling " + card.kind)
		check(card.description.get_content_height() <= card.description.size.y + 1, "complete effect visible " + card.kind)
		check(card.description.get_parsed_text() == ArenaItems.description(card.kind, false), "emphasis preserves translated effect " + card.kind)
		check(ArenaItemEmblem.ART[card.kind].resource_path.ends_with(".png") and not card.art.framed, "native item picture without icon medallion " + card.kind)
	await shot(tag + "-rewards")
	screen._choose_item(1)
	await frames(15)
	check(not screen._modal_layer.visible and screen._item_uid > 0, "choice closes reward and selects owned item")
	check(screen._item_targets.size() >= 2, "deployed creature targets exist")
	await shot(tag + "-targets")
	screen._cancel_item()
	var source: Control = screen._item_tray.buttons[1]
	screen._item_tray.focus_item(1)
	await frames(12)
	var start := source.get_global_rect().get_center()
	await move(start)
	var press := InputEventMouseButton.new()
	press.position = start; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	Input.parse_input_event(press)
	await frames(4)
	var drag := InputEventMouseMotion.new()
	drag.position = start + Vector2(90, 15); drag.relative = Vector2(90, 15); drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(drag)
	await frames(10)
	check(get_viewport().gui_is_dragging(), "real press and movement starts native drag")
	await shot(tag + "-drag")
	var target: Control = screen._item_targets[int(screen.run.army[1].uid)]
	var end := target.get_global_rect().get_center()
	drag = InputEventMouseMotion.new()
	drag.position = end; drag.relative = end - start; drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(drag)
	await frames(4)
	var release := InputEventMouseButton.new()
	release.position = end; release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	Input.parse_input_event(release)
	await frames(12)
	check(screen.run.item_for(int(screen.run.army[1].uid)) == dragged_kind and screen._item_uid == 0, "drop transfers equipped relic once")
	for slot: Control in screen._item_targets.values():
		if not slot.visible: continue
		for unit: GameUnit in screen.battle.world.unit_rows():
			if unit.dead or not unit.visible: continue
			var health := Rect2(screen.field.health_anchor(unit) + Vector2(-48, -40) * screen._ui_scale, Vector2(96, 46) * screen._ui_scale)
			check(not slot.get_global_rect().intersects(health), "equipped badge clears every HP and star marker")
	await shot(tag + "-equipped")
	await move(screen._item_tray.buttons[1].get_global_rect().get_center())
	await get_tree().create_timer(0.5).timeout
	check(screen._tooltips.visible, "tray shows illustrated item tooltip")
	await shot(tag + "-tooltip")
	screen.queue_free()
	await frames(8)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("ARENA_EQUIPMENT_PRESENTATION ", tag, " ", checks, " checks; failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
