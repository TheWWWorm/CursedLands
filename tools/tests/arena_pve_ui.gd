extends Node
const Fixture = preload("arena_fixture.gd")
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
	Input.warp_mouse(at)
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

func hover(at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	Input.parse_input_event(event)
	await get_tree().create_timer(0.4).timeout

func shot(label: String) -> void:
	if not rendered: return
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pve-ui-" + label + ".png")


func reward_buttons() -> Array[Node]:
	return screen._dock.find_children("ChooseReward", "Button", true, false)


func reward_bounds(lang: String) -> void:
	check(screen._army_title.tooltip_text.is_empty() and screen._army_title.mouse_filter == Control.MOUSE_FILTER_IGNORE, lang + " camp hides inactive army tooltips")
	check(screen._outcome.get_global_rect().end.x <= get_tree().root.size.x, lang + " camp fits viewport width")
	for button: Button in reward_buttons():
		check(button.get_global_rect().end.y <= screen._outcome.get_global_rect().end.y - 8, lang + " camp choice stays within its panel")
	for label: Label in screen._dock.find_children("*", "Label", true, false):
		check(label.get_global_rect().end.x <= screen._outcome.get_global_rect().end.x - 8, lang + " camp text stays inside frame")

func body_point(uid: int) -> Vector2:
	for unit: GameUnit in screen.battle.world.unit_rows():
		if int(unit.get_meta("arena_placement", {}).get("run_uid", 0)) == uid:
			var rects := unit.screen_rects(screen.field.camera)
			if not rects.is_empty(): return Rect2(rects[0]).get_center()
			return screen.field.screen_point(unit.pos)
	return Vector2.ZERO

func _ready() -> void:
	OS.add_logger(errors)
	rendered = DisplayServer.get_name() != "headless"
	# Let startup's deferred saved-window application finish before test sizes.
	await frames(24)
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
		check(is_instance_valid(screen._landing_panel), lang + " explains an empty purchased company")
		await shot(lang + "-landing")
		screen._seed_input.text = "6519"
		await click(screen._landing_start.get_global_rect().get_center())
		await frames()
		if screen.landing and screen._modal_layer.visible:
			screen._close_modal()
			screen._begin()
			await frames()
		check(not screen.landing and screen.run.stage == "prepare", lang + " start button creates run")
		if screen.landing:
			get_tree().quit(1)
			return
		Fixture.buy_company(screen.run)
		screen.run.auto_save = false
		check(screen.field.camera.get_camera_transform().origin != Vector3.ZERO, lang + " actual camera projection")
		var uid := int(screen.run.army[0].uid)
		var original := Vector2(screen.run.unit(uid).point[0], screen.run.unit(uid).point[1])
		await click(body_point(uid))
		check(screen.selected_uid == uid, lang + " pointer selects the rendered fighter")
		var destination := Vector2(28, 39)
		check(screen.field.ground_point(screen.field.screen_point(destination)).distance_to(destination) < 0.1, lang + " projection round trip")
		await click(screen.field.global_position + screen.field.screen_point(destination))
		check(Vector2(screen.run.unit(uid).point[0], screen.run.unit(uid).point[1]).distance_to(destination) < 0.15, lang + " pointer repositions selected fighter")
		screen._clear_selection()
		# This purchase becomes the second boar for the later evolution check;
		# its identity must not depend on changes to the seeded opening shuffle.
		screen.run.shop[0] = {"family": 0, "rank": 0, "locked": false}
		screen.run._touch()
		await frames()
		var before := screen.run.army.size()
		var offer: ArenaCreatureCard = screen._shop.get_child(0).get_child(0)
		var price: Label = offer.find_children("*", "Label", true, false).filter(func(n): return n.text == str(offer.cost))[0]
		check(price.size.x >= 8 and price.get_global_rect().end.y <= screen._shop_panel.get_global_rect().end.y, lang + " recruitment price remains readable")
		await click(offer.get_global_rect().get_center())
		check(screen.run.army.size() == before + 1 and screen.run.bench_count() == 1, lang + " shop click recruits one creature")
		check(screen.selected_uid == screen.run.next_uid - 1, lang + " recruit becomes placement selection")
		await shot(lang + "-inspect")
		check(screen._sell_target.visible and screen._sell_target.get_global_rect().end.y < screen._bench_panel.get_global_rect().position.y, lang + " selected recruit exposes sell destination")
		var reserve_id := screen.selected_uid
		await click(body_point(uid))
		check(screen.run.unit(reserve_id).deployed and not screen.run.unit(uid).deployed, lang + " pointer swaps reserve directly into full army")
		screen._menu_action(4)
		check(not screen.run.unit(reserve_id).deployed and screen.run.unit(uid).deployed, lang + " swap undo restores full formation")
		screen._clear_selection()
		check(not screen._rail.visible, lang + " details leave the board clear")
		check(screen._army_row.find_children("*", "Control", true, false).all(func(control): return control.tooltip_text.is_empty()), lang + " rebuilt reserves keep scaled help")
		screen._show_menu()
		await frames()
		check(screen._menu_items[3].has_meta("arena_help") and screen._menu_items[4].has_meta("arena_help"), lang + " menu actions retain bounded explanatory help")
		screen._close_modal()
		check(screen._start.get_global_rect().end.x <= get_tree().root.size.x + 1, lang + " main action within viewport")
		check(screen._bench_bar.get_global_rect().end.y <= get_tree().root.size.y + 1, lang + " bench within viewport")
		var header: ArenaHudPanel = screen._hud.get_children().filter(func(n): return n is ArenaHudPanel)[0]
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
		check(screen._pause.tooltip_text.is_empty() and screen._pause.has_meta("arena_help"), lang + " pause state keeps scaled help")
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
		screen.battle.set_process(true)
		await get_tree().create_timer(1.7).timeout
		await shot(lang + "-result")
		# Deliberate state fixtures exercise layouts and reward controls; these
		# injected outcomes are not counted as combat balance evidence.
		screen.run.wave = 3
		screen.run.last_result.wave = 3
		screen.run.last_result.winner = 0
		screen.run.stage = "result"
		screen.run.advance()
		await frames()
		check(reward_buttons().size() == 3, lang + " first camp offers three distinct pacts")
		reward_bounds(lang)
		await shot(lang + "-pacts")
		await click((reward_buttons()[2] as Button).get_global_rect().get_center())
		check(screen.run.wave == 4 and screen.run.pact == "vanguard", lang + " pact choice commits and resumes preparation")
		screen.run._recruit(2, 0, 3)
		screen.run.arrange()
		await frames()
		check(screen.run.pact_active() and screen.battle.team_count(0) == screen.run.deployed_count() + 1, lang + " eligible formation shows native guest on battlefield")
		await hover(screen._army_title.get_global_rect().get_center())
		check(screen._showing_company and screen._rail.visible, lang + " army counter opens pact details")
		var counter := screen._army_title
		var text_width := counter.get_theme_font("font").get_string_size(counter.text, HORIZONTAL_ALIGNMENT_LEFT, -1, counter.get_theme_font_size("font_size")).x
		check(counter.size.x >= text_width + counter.get_theme_stylebox("hover").get_minimum_size().x + 22, lang + " hovered army counter keeps capacity readable")
		await shot(lang + "-company")
		screen._clear_selection()
		screen.run.wave = 6
		screen.run.last_result.wave = 6
		screen.run.last_result.winner = 0
		screen.run.stage = "result"
		screen.run.advance()
		await frames()
		check(screen._outcome.visible and screen.run.stage == "reward", lang + " boss reward panel")
		reward_bounds(lang)
		await shot(lang + "-reward")
		var reward_button: Button = reward_buttons()[0]
		await click(reward_button.get_global_rect().get_center())
		check(screen.run.wave == 7 and screen.run.army.back().prototype == "orcfemalem3", lang + " reward click recruits native companion")
		screen.run.gold += 12
		screen.run.shop[0] = {"family": 0, "rank": 0, "locked": false}
		screen._recruit_offer(0)
		await frames()
		check(screen.run.unit(uid).prototype == "boarredf3", lang + " purchase automatically evolves original creatures")
		screen._menu_action(4)
		check(screen.run.unit(uid).prototype == "boarredf1", lang + " menu undo restores purchase and evolution")
		screen._menu_action(3)
		check(screen.run.deployed_count() == screen.run.capacity(), lang + " menu auto arrange fills available army")

		screen._clear_selection()
		screen.run.wave = 9
		screen.run.last_result.wave = 9
		screen.run.stage = "result"
		screen.run.advance()
		await frames()
		reward_bounds(lang)
		await shot(lang + "-pact-upgrade")
		await click((reward_buttons()[0] as Button).get_global_rect().get_center())
		check(screen.run.pact_rank == 1 and screen.run.pact_prototype() == "batlightm9", lang + " Ingos camp upgrades to native regional support")
		screen.run.boons.assign(["scout", "reserve"])
		screen.run._roll_shop(false)
		while screen.run.bench_count() < screen.run.bench_limit(): screen.run._recruit(3, 0, 3)
		screen.run._touch()
		await frames()
		check(screen._shop.get_child_count() == 6, lang + " six-offer shop")
		check(screen._start.get_global_rect().end.x <= get_tree().root.size.x + 1, lang + " full reserve preserves start action")
		await shot(lang + "-expanded")
		screen.run.boons.assign(["merchant", "scout", "reserve"])
		screen.run.wave = 15; screen.run.stage = "result"; screen.run.last_result.wave = 15
		screen.run.advance()
		await frames()
		check(reward_buttons().size() == 3, lang + " exhausted boon pool offers a companion beside pact and gold")
		reward_bounds(lang)
		await shot(lang + "-full-boon-camp")
		var field_unit: GameUnit = screen.battle.world.unit_rows()[0]
		screen.field.creature_clicked.emit(field_unit)
		check(not screen._rail.visible, lang + " camp does not open creature details behind its choices")
		await click((reward_buttons()[0] as Button).get_global_rect().get_center())
		check(screen.run.pact_rank == 2 and screen.run.pact_prototype() == "batlightm10", lang + " final pact upgrade works with full reserves")
		await hover(screen._army_title.get_global_rect().get_center())
		await shot(lang + "-company-final")
		screen._clear_selection()
		screen.run.wave = 24; screen.run.stage = "result"; screen.run.last_result.wave = 24
		screen.run.advance()
		await frames()
		check(reward_buttons().size() == 2, lang + " completed pact and boons leave two useful camp choices")
		check(screen.run.rewards[0].prototype == "octopushadaganm15", lang + " late camp offers native Suslanger companion")
		reward_bounds(lang)
		await shot(lang + "-late-camp")
		await click((reward_buttons()[0] as Button).get_global_rect().get_center())
		check(screen.run.wave == 25 and screen.run.army.back().prototype == "octopushadaganm15", lang + " late companion reaches a full reserve through overflow")
		screen._clear_selection()
		screen.run.stage = "won"
		screen.run.wave = ArenaRules.WAVE_COUNT
		screen.run.last_result.wave = ArenaRules.WAVE_COUNT
		screen.run._touch()
		await frames()
		check(screen._outcome.visible and not screen._shop_section.visible, lang + " completed expedition presentation")
		await shot(lang + "-complete")
		screen._guide()
		await frames()
		var guide := screen._modal_panel
		if rendered: check(guide.get_global_rect().end.x <= get_tree().root.size.x and guide.get_global_rect().end.y <= get_tree().root.size.y, lang + " wrapped guide fits window")
		screen._close_modal()
		await frames()
		if lang == "en":
			get_tree().root.size = Vector2i(1280, 720)
			screen.run.stage = "prepare"
			screen.run._touch()
			await frames()
			check(screen.field.screen_point(Vector2(20, 32)).y < screen._bench_panel.get_global_rect().position.y - 10, "720p near deployment row stays above reserves")
			check(screen.field.screen_point(Vector2(40.5, 32)).y > screen._shop_panel.get_global_rect().end.y + 60, "720p far row has headroom below shop")
			await shot("en-720-expanded")
			screen.run.wave = 15; screen.run.pact_rank = 1; screen.run.stage = "result"; screen.run.last_result.wave = 15
			screen.run.advance()
			await frames()
			reward_bounds("en 720p")
			await shot("en-720-camp")
		screen.queue_free()
		await frames()
		check(Engine.time_scale == speed, lang + " restores global game speed")
		check(hash(GameData.db.tables) == native_hash, lang + " original stats unchanged")
	RemakeText.lang = language
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no engine or script errors: " + str(errors.messages))
	print("ARENA_PVE_UI ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
