extends Node
## Rendered regression for real viewport scaling, body picking and combat feedback.
## Run with an X/Wayland display at least 5113x2856; saves per-state PNGs.

var checks := 0
var failures: Array[String] = []
var screen: ArenaPveScreen
class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
var errors := Errors.new()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(2)

func click(at: Vector2) -> void:
	await move(at)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func shot(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://resolution-" + label + ".png")
	print("CAPTURE ", label, " ", get_viewport().get_visible_rect().size)

func bounded(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(1).encloses(rect), label + " is inside the viewport")

func body(uid: int) -> GameUnit:
	for unit: GameUnit in screen.battle.world.unit_rows():
		if unit.get_meta("arena_placement", {}).get("run_uid", 0) == uid: return unit
	return null

func point(unit: GameUnit) -> Vector2:
	var rects := unit.screen_rects(screen.field.camera)
	return Rect2(rects[0]).get_center() if not rects.is_empty() else Vector2.ZERO

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires rendered native creature bounds.")
		get_tree().quit(1)
		return
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var native := hash(GameData.db.tables)
	var language := RemakeText.lang
	# A fresh process per size also isolates native viewport and GPU caches.
	# Override with --arena-resolution=de,5113,2856.
	var cases := [["en", Vector2i(3840, 2160)]]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--arena-resolution="):
			var requested := argument.get_slice("=", 1).split(",")
			cases = [[requested[0], Vector2i(int(requested[1]), int(requested[2]))]]
	for spec in cases:
		RemakeText.lang = spec[0]
		get_tree().root.size = spec[1]
		get_tree().root.position = Vector2i.ZERO
		await frames(8)
		var tag := "%s-%d" % [spec[0], spec[1].x]
		print("CASE ", tag)
		check(get_tree().root.size == spec[1], tag + " actual physical resolution")
		screen = ArenaPveScreen.new()
		add_child(screen)
		await frames(12)
		var scale := maxf(1, minf(float(spec[1].x) / 1280, float(spec[1].y) / 800))
		check(is_equal_approx(screen._ui_scale, scale), tag + " coherent HUD scale")
		bounded(screen._landing_start, tag + " landing action")
		for button: Button in screen._starter_buttons: bounded(button, tag + " starter choice")
		if spec[1].x >= 3840: await shot(tag + "-landing")
		screen._seed_input.text = "6519"
		screen._begin(1)
		screen.run.auto_save = false
		await frames()
		for control in [screen._menu, screen._round_panel, screen._start, screen._quality, screen._bench_bar]:
			bounded(control, tag + " HUD")
		check(screen._start.get_global_rect().size.y >= 43 * scale, tag + " main target scales")
		check(screen._menu.text == RemakeText.t("Menu"), tag + " labelled menu")
		check(screen.field.numeric_health and not screen.field.show_team_rings, tag + " numeric HP without enemy rings")
		var uid := int(screen.run.army[2].uid)
		var bat := body(uid)
		check(screen.field._pick(point(bat)) == bat, tag + " picks the visible airborne body")
		await move(point(bat))
		await get_tree().create_timer(0.5).timeout
		check(screen._tooltips.visible and screen._tooltips._heading.text == bat.display_name, tag + " native creature hover details")
		bounded(screen._tooltips, tag + " body tooltip")
		if spec[1].x >= 3840: await shot(tag + "-hover")
		await click(point(bat))
		check(screen.selected_uid == uid, tag + " body click selects bat")
		var withdraw := screen._inspect_actions.get_child(0) as Button
		bounded(withdraw, tag + " withdraw action")
		check(not withdraw.disabled and withdraw.text == RemakeText.t("Return to reserves"), tag + " explicit reserve action")
		await click(withdraw.get_global_rect().get_center())
		check(not screen.run.unit(uid).deployed, tag + " reserve action withdraws ally")
		screen.run.undo()
		await frames()
		await click(point(body(uid)))
		await click((screen._army_row.get_child(0) as Button).get_global_rect().get_center())
		check(not screen.run.unit(uid).deployed, tag + " empty reserve slot withdraws ally")
		screen.run.undo()
		screen._clear_selection()
		await frames()
		await move(screen._start.get_global_rect().get_center())
		await get_tree().create_timer(0.5).timeout
		check(screen._tooltips.visible and screen._tooltips.size.x <= 311, tag + " start tooltip has a bounded measure")
		bounded(screen._tooltips, tag + " start tooltip")
		await click(screen._menu.get_global_rect().get_center())
		print("MENU ", tag, " visible=", screen._modal_layer.visible, " rect=", screen._menu.get_global_rect(), " focus=", screen._start.focus_mode)
		bounded(screen._modal_panel, tag + " menu panel")
		check(screen._modal_layer.visible and screen._start.focus_mode == Control.FOCUS_NONE, tag + " modal traps background focus")
		if spec[1].x >= 3840: await shot(tag + "-menu")
		screen._guide()
		await frames()
		bounded(screen._modal_panel, tag + " guide panel")
		check(screen._guide_scroll != null, tag + " guide has bounded scrolling")
		if spec[0] != "en": await shot(tag + "-guide")
		screen._close_modal()
		check(screen._start.focus_mode == Control.FOCUS_ALL, tag + " modal restores focus")
		screen.run.gold = 50
		await click(screen._quality.get_global_rect().get_center())
		bounded(screen._modal_panel, tag + " shop improvement panel")
		var improve: Button = screen._modal_box.find_child("UpgradeRecruitment", true, false)
		await click(improve.get_global_rect().get_center())
		check(screen.run.shop_level == 1 and not screen._modal_layer.visible, tag + " shop improvement button")
		screen._show_recruitment()
		await frames()
		if spec[1].x >= 3840: await shot(tag + "-shop")
		screen._close_modal()
		await click(screen._start.get_global_rect().get_center())
		check(screen.run.stage == "fight", tag + " battle button")
		screen._show_menu()
		check(screen.battle.phase == ArenaMatch.Phase.PAUSED, tag + " menu pauses active battle")
		screen._close_modal()
		check(screen.battle.phase == ArenaMatch.Phase.FIGHT, tag + " closing menu resumes active battle")
		screen.battle.toggle_pause()
		screen._show_menu()
		screen._close_modal()
		check(screen.battle.phase == ArenaMatch.Phase.PAUSED, tag + " menu preserves a manually paused battle")
		screen.battle.toggle_pause()
		screen.battle.set_process(false)
		var saw_hit := false
		for tick in 1000:
			if screen.battle.phase != ArenaMatch.Phase.FIGHT: break
			screen.battle.simulate_tick()
			if not screen._hit_numbers._items.is_empty():
				saw_hit = true
				break
		check(saw_hit and screen._hit_numbers._tex != null, tag + " actual combat emits native damage numbers")
		# Hold a real hit's presentation age while saving the GPU readback.
		# No damage or event value is fabricated for this capture.
		screen._hit_numbers.set_process(false)
		for item in screen._hit_numbers._items: item.t0 = Time.get_ticks_msec() - 400
		screen._hit_numbers.queue_redraw()
		await frames(2)
		if spec[1].x >= 3840: await shot(tag + "-hit")
		var enemy: GameUnit = screen.battle.world.unit_rows().filter(func(unit): return unit.faction == 2)[0]
		screen._select_world(enemy)
		await frames(2)
		check(screen._live_health.text.contains("%d/%d" % [maxi(0, ceili(enemy.hp)), ceili(enemy.max_hp)]), tag + " enemy inspector shows current health")
		screen._clear_selection()
		# The outcome fixture exercises layout; it is not balance evidence.
		screen.run.resolve(0, 32, [103.0, 21.0])
		await frames()
		bounded(screen._outcome, tag + " victory panel")
		check(not screen._message.visible and not screen.field.show_markers, tag + " victory clears placement and health overlays")
		if spec[1].x >= 3840: await shot(tag + "-victory")
		get_tree().root.size = Vector2i(1280, 720)
		await frames(10)
		bounded(screen._outcome, tag + " outcome after live resize")
		check(is_equal_approx(screen._ui_scale, 1), tag + " live resize restores logical scale")
		screen.queue_free()
		await frames()
	check(hash(GameData.db.tables) == native, "original native stats unchanged")
	RemakeText.lang = language
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no engine errors: " + str(errors.messages))
	print("ARENA_RESOLUTION_UI ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
