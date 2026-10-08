extends Node
## Pixel comparison against the former single-item drawing order, plus
## retained-draw, resize, input and pause/notification behavior.
var checks := 0
var failures := 0

class LayoutGame extends Game:
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)

class Reference extends HudDial:
	func _ready() -> void:
		super._ready()
		_hands_layer.hide()
	func _redraw_all() -> void:
		queue_redraw()
	func _draw() -> void:
		super._draw()
		_draw_hands(self)

class LayoutHUD extends GameHUD:
	var calls := 0
	var screen := Vector2(800, 600)
	func _ready() -> void:
		_move_dial = HudDial.new()
		_clock_dial = HudDial.new()
		for d in [_move_dial, _clock_dial]: add_child(d)
		for field in ["_weapons", "_actions", "_slots", "_belt", "_target_label"]:
			# Actual field types retain their normal Control layout properties.
			var control: Control
			match field:
				"_weapons": control = WeaponBar.new()
				"_actions": control = ActionStrip.new()
				"_slots": control = SpellSlots.new()
				"_belt": control = BeltStrip.new()
				_: control = Label.new()
			set(field, control)
		_clock_dial.kind = "clock"
		set_process(false)
	func ui_size() -> Vector2: return screen
	func _selected_gait() -> int: return 2
	func _selected_aggression() -> int: return 1
	func _place_dials() -> void:
		calls += 1
		super._place_dials()
	func clear_controls() -> void:
		for node in [_weapons, _actions, _slots, _belt, _target_label]: node.free()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func draw_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func layout(hud: GameHUD) -> Array:
	var out := []
	for node in [hud._move_dial, hud._clock_dial, hud._weapons, hud._actions, hud._slots, hud._belt, hud._target_label]:
		out.append([node.offset_left, node.offset_right, node.offset_top, node.offset_bottom])
	return out

func _ready() -> void:
	var views: Array[SubViewport] = []
	var dials: Array[HudDial] = []
	var counts := [0, 0]
	for i in 2:
		var view := SubViewport.new()
		view.size = Vector2i(480, 480)
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		var dial: HudDial = HudDial.new() if i == 0 else Reference.new()
		dial.kind = "clock"
		view.add_child(dial)
		dial.position = Vector2(10, 10)
		dial.size = Vector2(200, 200)
		dial.set_process(false)
		views.append(view)
		dials.append(dial)
	dials[0].draw.connect(func(): counts[0] += 1)
	dials[0]._hands_layer.draw.connect(func(): counts[1] += 1)
	for trial in 64:
		for dial in dials:
			dial.kind = "move" if trial >= 48 else "clock"
			dial.size = Vector2.ONE * [80.0, 137.0, 200.0, 319.0][trial % 4]
			dial.selected = trial % (4 if dial.kind == "move" else 3)
			dial.aggression = trial % 3 - 1
			dial.ring_angle = trial * 0.19
			dial.pulse = trial % 2 == 0
			dial._theta = fmod(trial * 0.031, PI / 6.0)
			dial._phase = [0.0, 0.25, 0.5, 0.75][trial % 4]
			dial.set_process(false)
			dial._redraw_all()
		await draw_frame()
		var actual := views[0].get_texture().get_image()
		var expected := views[1].get_texture().get_image()
		check(actual.get_data() == expected.get_data(), "exact dial pixels %d" % trial)
		if trial == 0 or failures:
			actual.save_png("user://dial-retained-%02d.png" % trial)
			expected.save_png("user://dial-reference-%02d.png" % trial)
	var dial := dials[0]
	dial.kind = "clock"
	dial.selected = 1
	dial.pulse = false
	dial.set_process(false)
	await draw_frame()
	var before := counts.duplicate()
	var theta := dial._theta
	dial._last_ms = Time.get_ticks_msec() - 20
	dial._process(0.0)
	await draw_frame()
	check(counts[0] == before[0] and counts[1] > before[1], "hands animate without redrawing the face")
	check(dial._theta > theta, "normal-speed clock advances")
	dial.ring_angle += 0.1
	await draw_frame()
	check(counts[0] > before[0], "world-time ring change redraws the face")
	dial.selected = 0
	dial.set_process(false)
	await draw_frame()
	before = counts.duplicate()
	theta = dial._theta
	dial._last_ms = Time.get_ticks_msec() - 20
	dial._process(0.0)
	await draw_frame()
	check(counts[0] > before[0] and counts[1] > before[1] and dial._theta == theta, "paused blink redraws without moving hands")
	dial.selected = 2
	dial.pulse = true
	dial.set_process(false)
	await draw_frame()
	before = counts.duplicate()
	dial._last_ms = Time.get_ticks_msec() - 20
	dial._process(0.0)
	await draw_frame()
	check(counts[0] > before[0], "quest notification keeps pulsing")
	check(dial._hands_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hands do not intercept input")
	dial.hide()
	check(not dial._hands_layer.is_visible_in_tree(), "hidden dial hides hands")
	dial.show()
	check(dial._hands_layer.is_visible_in_tree(), "shown dial restores hands")
	var touch_before := TouchInput.enabled
	var hud := LayoutHUD.new()
	var g := LayoutGame.new()
	add_child(g)
	g.set_process(false)
	hud.game = g
	add_child(hud)
	for trial in 16:
		TouchInput.enabled = trial % 2 == 0
		hud.screen = Vector2(800, 600) if trial % 4 < 2 else Vector2(600, 1000)
		hud.transform = Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ONE * [1.0, 1.5][trial % 2])
		hud._layout_dials()
		var saved := layout(hud)
		var calls := hud.calls
		for i in 10: hud._layout_dials()
		check(hud.calls == calls, "stable layout reuses offsets %d" % trial)
		hud._place_dials()
		check(layout(hud) == saved, "retained offsets equal full layout %d" % trial)
	var calls := hud.calls
	g.speed = 1
	hud._layout_dials()
	check(hud.calls == calls and hud._clock_dial.selected == 2, "speed updates with retained geometry")
	get_tree().paused = true
	hud._layout_dials()
	check(hud.calls == calls and hud._clock_dial.selected == 0, "pause updates with retained geometry")
	get_tree().paused = false
	hud._layout_dials()
	check(hud.calls == calls and hud._clock_dial.selected == 2, "resume updates with retained geometry")
	TouchInput.enabled = touch_before
	hud.clear_controls()
	hud.free()
	g.free()
	for view in views: view.free()
	await draw_frame()
	print("HUD_RETAINED_CONTROLS checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
