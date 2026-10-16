extends Node
## Real controls and pointer coordinates, with per-language rendered captures.

var checks := 0
var failures: Array[String] = []
var screen: ArenaPveScreen
var rendered := false

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
var errors := Errors.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count := 5) -> void:
	for i in count: await get_tree().process_frame

func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func shot(label: String) -> void:
	if not rendered: return
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pve-ui-" + label + ".png")

func _ready() -> void:
	OS.add_logger(errors)
	rendered = DisplayServer.get_name() != "headless"
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var language := RemakeText.lang
	var native_hash := hash(GameData.db.tables)
	var speed := Engine.time_scale
	for lang in ["en", "ru", "de"]:
		RemakeText.lang = lang
		get_tree().root.size = Vector2i(1280, 800) if lang == "en" else Vector2i(1024, 768)
		await frames()
		screen = ArenaPveScreen.new()
		add_child(screen)
		await frames(8)
		check(screen.landing, lang + " starts on team selection")
		check(screen._landing_models.get_child_count() == 3, lang + " previews all three team members")
		await shot(lang + "-landing")
		screen._seed_input.text = "6519"
		await click(screen._landing_start.get_global_rect().get_center())
		await frames()
		if screen.landing and screen._new_run_dialog.visible:
			screen._new_run_dialog.confirmed.emit()
			screen._new_run_dialog.hide()
			await frames()
		check(not screen.landing and screen.run.stage == "prepare", lang + " start button creates run")
		if screen.landing:
			get_tree().quit(1)
			return
		screen.run.auto_save = false
		check(screen.field.camera.get_camera_transform().origin != Vector3.ZERO, lang + " actual camera projection")
		var uid := int(screen.run.army[0].uid)
		var original := Vector2(screen.run.unit(uid).point[0], screen.run.unit(uid).point[1])
		await click(screen.field.global_position + screen.field.screen_point(original))
		check(screen.selected_uid == uid, lang + " pointer selects the rendered fighter")
		var destination := Vector2(28, 39)
		check(screen.field.ground_point(screen.field.screen_point(destination)).distance_to(destination) < 0.1, lang + " projection round trip")
		await click(screen.field.global_position + screen.field.screen_point(destination))
		check(Vector2(screen.run.unit(uid).point[0], screen.run.unit(uid).point[1]).distance_to(destination) < 0.15, lang + " pointer repositions selected fighter")
		screen._clear_selection()
		var before := screen.run.army.size()
		var offer: ArenaCreatureCard = screen._shop.get_child(0).get_child(0)
		var price: Label = offer.find_children("*", "Label", true, false).filter(func(n): return n.text == str(offer.cost))[0]
		check(price.size.x >= 8 and price.get_global_rect().end.y <= screen._shop_panel.get_global_rect().end.y, lang + " recruitment price remains readable")
		await click(offer.get_global_rect().get_center())
		check(screen.run.army.size() == before + 1 and screen.run.bench_count() == 1, lang + " shop click recruits one creature")
		check(screen.selected_uid == screen.run.next_uid - 1, lang + " recruit becomes placement selection")
		await shot(lang + "-inspect")
		var evolve := screen._inspect_actions.get_child(0) as Button
		check(evolve != null and evolve.get_global_rect().end.y < screen._bench_panel.position.y, lang + " evolution action stays visible outside details scroll")
		screen._clear_selection()
		check(not screen._rail.visible, lang + " details leave the board clear")
		check(screen._start.get_global_rect().end.x <= get_tree().root.size.x + 1, lang + " main action within viewport")
		check(screen._bench_bar.get_global_rect().end.y <= get_tree().root.size.y + 1, lang + " bench within viewport")
		var header: ArenaHudPanel = screen.get_children().filter(func(n): return n is ArenaHudPanel)[0]
		for control in header.find_children("*", "Control", true, false):
			if control is Button or control is Label:
				check(control.get_global_rect().end.x <= get_tree().root.size.x + 1, lang + " header control stays visible: " + control.text)
		await shot(lang + "-prepare")
		await click(screen._start.get_global_rect().get_center())
		check(screen.run.stage == "fight", lang + " start battle control")
		check(not screen._shop_panel.visible and screen._bench_panel.visible, lang + " combat clears shop and keeps reserves")
		await shot(lang + "-combat")
		check(screen.battle.world.time > 0, lang + " real frame clock advances AI battle")
		await click(screen._pause.get_global_rect().get_center())
		check(screen.battle.phase == ArenaMatch.Phase.PAUSED, lang + " pause button is wired")
		var time := screen.battle.world.time
		await frames(8)
		check(screen.battle.world.time == time, lang + " pause freezes native combat")
		screen._speed.select(1)
		screen._speed.item_selected.emit(1)
		check(Engine.time_scale == 2, lang + " battle speed control")
		await click(screen._pause.get_global_rect().get_center())
		# Complete the real encounter under the same native-step simulator.
		screen.battle.set_process(false)
		for tick in 5500:
			if screen.battle.phase != ArenaMatch.Phase.FIGHT: break
			screen.battle.simulate_tick()
		check(screen.run.stage in ["result", "lost"], lang + " result transition")
		await shot(lang + "-result")
		# Deliberate state fixtures exercise layouts and reward controls; these
		# injected outcomes are not counted as combat balance evidence.
		screen.run.wave = 6
		screen.run.last_result.wave = 6
		screen.run.last_result.winner = 0
		screen.run.stage = "result"
		screen.run.advance()
		await frames()
		check(screen._outcome.visible and screen.run.stage == "reward", lang + " boss reward panel")
		check(screen._outcome.get_global_rect().end.x <= get_tree().root.size.x, lang + " reward choices fit viewport")
		await shot(lang + "-reward")
		var reward_button: Button = screen._dock.get_child(1).get_child(0).get_child(2)
		await click(reward_button.get_global_rect().get_center())
		check(screen.run.wave == 7 and screen.run.army.back().prototype == "orcfemalem3", lang + " reward click recruits native companion")
		screen.run._recruit(0, 0, 3)
		screen.run._touch()
		screen._select(uid)
		await frames()
		var merge: Button = screen._inspect_actions.get_child(0)
		check(not merge.disabled, lang + " available native evolution enabled")
		await click(merge.get_global_rect().get_center())
		check(screen.run.unit(uid).prototype == "boarredf3", lang + " evolution button combines original creatures")
		screen._menu.get_popup().id_pressed.emit(4)
		check(screen.run.unit(uid).prototype == "boarredf1", lang + " menu undo restores evolution")
		screen._menu.get_popup().id_pressed.emit(3)
		check(screen.run.deployed_count() == screen.run.capacity(), lang + " menu auto arrange fills available army")
		screen._clear_selection()
		screen.run.boons.assign(["scout", "reserve"])
		screen.run._roll_shop(false)
		while screen.run.bench_count() < screen.run.bench_limit(): screen.run._recruit(3, 0, 3)
		screen.run._touch()
		await frames()
		check(screen._shop.get_child_count() == 6, lang + " six-offer shop")
		check(screen._start.get_global_rect().end.x <= get_tree().root.size.x + 1, lang + " full reserve preserves start action")
		await shot(lang + "-expanded")
		screen.run.stage = "won"
		screen.run.wave = 18
		screen.run.last_result.wave = 18
		screen.run._touch()
		await frames()
		check(screen._outcome.visible and not screen._shop_section.visible, lang + " completed expedition presentation")
		await shot(lang + "-complete")
		screen._guide()
		await frames()
		var guide: AcceptDialog = screen.get_child(screen.get_child_count() - 1)
		if rendered: check(guide.size.x <= get_tree().root.size.x and guide.size.y <= get_tree().root.size.y, lang + " wrapped guide fits window")
		guide.queue_free()
		await frames()
		if lang == "en":
			get_tree().root.size = Vector2i(1280, 720)
			screen.run.stage = "prepare"
			screen.run._touch()
			await frames()
			check(screen.field.screen_point(Vector2(20, 32)).y < screen._bench_panel.position.y - 10, "720p near deployment row stays above reserves")
			check(screen.field.screen_point(Vector2(40.5, 32)).y > screen._shop_panel.get_global_rect().end.y + 60, "720p far row has headroom below shop")
			await shot("en-720-expanded")
		screen.queue_free()
		await frames()
		check(Engine.time_scale == speed, lang + " restores global game speed")
		check(hash(GameData.db.tables) == native_hash, lang + " original stats unchanged")
	RemakeText.lang = language
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no engine or script errors: " + str(errors.messages))
	print("ARENA_PVE_UI ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
