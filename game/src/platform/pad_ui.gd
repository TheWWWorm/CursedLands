class_name PadUI
extends CanvasLayer
## The gamepad outside the field (PadInput's "ui" route): menus, panels, the
## travel map; and the virtual pointer, which the field's cursor mode shares
## (docs/gamepad_design.md §3.3, §8.6). Two mechanisms, chosen per panel:
## - key bridge: the panels that already take keys get synthetic keys
##   (D-pad → arrows, A → Enter, B → Esc, LB / RB → PgUp / PgDn), so their
##   own key code runs unchanged;
## - snap targets: a mouse-only panel in group "pad_panel" lists
##   `pad_targets()` ([{rect: Rect2 in viewport pixels, id}]); the D-pad moves
##   to the nearest target in its direction, the pointer goes there (hover,
##   tips and highlights work as for a mouse) and A clicks it.
## A panel may also take actions itself with `pad_press(action, phase) -> bool`
## and rename keys with `pad_keys() -> {action: keycode}`.
## The pointer: on a desktop with a mouse the OS pointer is warped (the
## original animated cursor follows it, GameCursor); elsewhere (Web, phones,
## headless tests) synthetic mouse events move it (TouchInput.motion) and it
## is drawn here. Clicks are synthetic mouse buttons (DEVICE_ID_EMULATION).

var pointer := Vector2(-1, -1)
## The pointer is shown and A clicks at it (moved by the stick or a snap).
var pointer_on := false
var _focus_id: Variant = null
var _clicking := false
var _wheel_t := 0.0
var _speed_t := 0.0
var _canvas: Control
var _tex := {}
var _hidden_by_pad := false


func _ready() -> void:
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_pointer)
	add_child(_canvas)
	PadInput.action.connect(_on_action)
	PadInput.mode_changed.connect(_on_mode)


## Warp the OS pointer (a desktop with a mouse) instead of drawing one.
static func os_pointer() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("web") \
		and not Portability.handheld() and DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _on_mode() -> void:
	if PadInput.active != "pad":
		pointer_on = false
		_release_click()
		_canvas.queue_redraw()


# ------------------------------------------------------------------ pointer

## Moves the pointer by a stick value (0..1 per axis) over `dt` real seconds;
## `slow` < 1 near something clickable (magnetism).
func move_pointer(v: Vector2, dt: float, slow := 1.0) -> void:
	if v == Vector2.ZERO:
		_speed_t = 0.0
		return
	if not pointer_on:
		pointer_on = true
		if pointer.x < 0.0:
			pointer = _view_size() * 0.5
	_speed_t = minf(_speed_t + dt, 1.0)
	var k := _view_size().y / 900.0 * pow(2.0, (GameData.option("pad_cursor_speed") - 50.0) / 25.0)
	var speed := (350.0 + 1100.0 * v.length_squared()) * (0.6 + 0.4 * _speed_t) * k * slow
	set_pointer(pointer + v.normalized() * speed * dt * minf(v.length(), 1.0))
	_focus_id = null


func set_pointer(p: Vector2) -> void:
	p = p.clamp(Vector2.ZERO, _view_size() - Vector2.ONE)
	var rel := p - pointer if pointer.x >= 0.0 else Vector2.ZERO
	pointer = p
	if os_pointer():
		PadInput.ignore_mouse_until = Time.get_ticks_msec() + 200
		get_viewport().warp_mouse(p)
	TouchInput.motion(p, rel, MOUSE_BUTTON_MASK_LEFT if _clicking else 0)
	_canvas.queue_redraw()


## A synthetic mouse button at the pointer.
func click(pressed: bool, which := MOUSE_BUTTON_LEFT, double := false) -> void:
	if pointer.x < 0.0:
		pointer = _view_size() * 0.5
	if which == MOUSE_BUTTON_LEFT:
		_clicking = pressed
	TouchInput.button(pointer, pressed, which, double)


func _release_click() -> void:
	if _clicking:
		click(false)


func wheel(up: bool) -> void:
	for pressed in [true, false]:
		click(pressed, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN)


## A synthetic key press and release.
static func key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.device = InputEvent.DEVICE_ID_EMULATION
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)


func _process(dt: float) -> void:
	var real := minf(dt / maxf(Engine.time_scale, 0.001), 0.1)
	if os_pointer() and PadInput.active == "pad":
		var want_hidden := not pointer_on
		if want_hidden and Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED]:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_hidden_by_pad = true
		elif not want_hidden and _hidden_by_pad and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = GameData.free_mouse_mode()
			_hidden_by_pad = false
	elif _hidden_by_pad:
		_hidden_by_pad = false
		if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = GameData.free_mouse_mode()
	if not os_pointer():
		_canvas.queue_redraw()
	_track_panel()
	if not PadInput.enabled() or PadInput._route_now() != "ui":
		return
	var ls := PadInput.stick(true)
	if ls != Vector2.ZERO:
		var panel := top_panel()
		if panel and panel.has_method("pad_stick") and panel.call("pad_stick", ls, real):
			pass
		else:
			move_pointer(ls, real)
	else:
		_speed_t = 0.0
	var rs := PadInput.stick(false)
	var panel := top_panel()
	if rs != Vector2.ZERO and panel and panel.has_method("pad_right_stick") and panel.call("pad_right_stick", rs, real):
		return
	if absf(rs.y) > 0.5:
		_wheel_t -= real
		if _wheel_t <= 0.0:
			_wheel_t = 0.12 / absf(rs.y)
			wheel(rs.y < 0.0)
	else:
		_wheel_t = 0.0


## A new top panel starts without the pointer (its keys or snap targets
## lead), unless the field's cursor mode has it.
var _last_panel: Variant = null

func _track_panel() -> void:
	var panel := top_panel()
	if panel == _last_panel:
		return
	_last_panel = panel
	_focus_id = null
	var field: Node = PadInput.field
	if panel != null or not (field != null and is_instance_valid(field) and bool(field.get("cursor_mode"))):
		pointer_on = false
		_canvas.queue_redraw()


func _draw_pointer() -> void:
	if os_pointer() or not pointer_on or PadInput.active != "pad" or pointer.x < 0.0:
		return
	var kind := "cursor_default"
	var g: Game = TouchInput.game()
	if g and g.cursor and g.cursor.kind != "" and not g.hud.blocks_input():
		kind = g.cursor.kind
	if not _tex.has(kind):
		var f := GameCursor.frames(kind)
		_tex[kind] = ImageTexture.create_from_image(f[0]) if not f.is_empty() else null
	var t: Texture2D = _tex[kind]
	var px := _view_size().y / 600.0 * 32.0
	if t:
		var hs: Vector2 = GameCursor.HOTSPOT.get(kind, Vector2.ZERO) * (px / 32.0)
		_canvas.draw_texture_rect(t, Rect2(pointer - hs, Vector2(px, px)), false)
	else:
		_canvas.draw_circle(pointer, 6.0, Color(1, 0.9, 0.6))


# ------------------------------------------------------------------ panels

## The topmost visible panel that takes the pad itself (group "pad_panel").
func top_panel() -> Node:
	var best: Node = null
	for n in get_tree().get_nodes_in_group("pad_panel"):
		if (n is CanvasItem and (n as CanvasItem).is_visible_in_tree()) or (n is Node3D and (n as Node3D).is_visible_in_tree()):
			if n.has_method("pad_active") and not n.call("pad_active"):
				continue
			if best == null or _above(n, best):
				best = n
	return best


static func _above(a: Node, b: Node) -> bool:
	return a.is_greater_than(b)   # later in tree order: drawn over it


func _key_for(panel: Node, a: String, fallback: int) -> int:
	if panel and panel.has_method("pad_keys"):
		var m: Dictionary = panel.call("pad_keys")
		if m.has(a):
			return int(m[a])
	return fallback


func _on_action(a: String, phase: String) -> void:
	if PadInput.route_of(a) != "ui":
		return
	var panel := top_panel()
	if panel and panel.has_method("pad_press") and panel.call("pad_press", a, phase):
		return
	if phase == "up" and a == "interact":
		_release_click()
		return
	if phase == "repeat" and a in ["up", "down", "left", "right"]:
		_nav(a, panel)
		return
	if phase != "down":
		return
	match a:
		"up", "down", "left", "right":
			_nav(a, panel)
		"interact":
			var targets := _targets(panel)
			if pointer_on or not targets.is_empty():
				if not targets.is_empty() and not pointer_on:
					_snap(targets, "", panel)
				click(true)
			else:
				var k := _key_for(panel, a, KEY_ENTER)
				if k:
					key(k)
		"cancel":
			_release_click()
			PadInput.last_cancel_ms = Time.get_ticks_msec()
			var k := _key_for(panel, a, KEY_ESCAPE)
			if k:
				key(k)
		"context":
			var k := _key_for(panel, a, 0)
			if k:
				key(k)
			elif pointer_on:
				click(true, MOUSE_BUTTON_RIGHT)
				click(false, MOUSE_BUTTON_RIGHT)
		"pause":
			var k := _key_for(panel, a, 0)
			if k:
				key(k)
		"actions", "items":
			var k := _key_for(panel, a, KEY_PAGEUP if a == "actions" else KEY_PAGEDOWN)
			if k:
				key(k)
		"mod", "system":
			wheel(a == "mod")
		"menu":
			var k := _key_for(panel, a, KEY_ESCAPE)
			if k:
				key(k)
		"cursor":
			pointer_on = not pointer_on
			if pointer_on and pointer.x < 0.0:
				set_pointer(_view_size() * 0.5)
			_canvas.queue_redraw()


func _targets(panel: Node) -> Array:
	if panel == null or not panel.has_method("pad_targets"):
		return []
	return panel.call("pad_targets")


const ARROWS := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}
const DIRS := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}


func _nav(dir: String, panel: Node) -> void:
	var targets := _targets(panel)
	if targets.is_empty():
		pointer_on = false
		_canvas.queue_redraw()
		key(_key_for(panel, dir, ARROWS[dir]))
		return
	_snap(targets, dir, panel)


## The next snap target in `dir` from the focused one (spatial navigation:
## within ±60° of the direction, nearest by distance plus twice the sideways
## offset; when nothing lies there, anything ahead within ±89°); "" focuses
## the target nearest the pointer. With nothing focused yet, a panel may name
## where to start (`pad_focus() -> id`, e.g. its selected row): the first
## press lands there.
func _snap(targets: Array, dir: String, panel: Node = null) -> void:
	var cur: Dictionary = {}
	for t: Dictionary in targets:
		if _focus_id != null and t.get("id") == _focus_id:
			cur = t
	if cur.is_empty() and panel != null and panel.has_method("pad_focus"):
		var want: Variant = panel.call("pad_focus")
		for t: Dictionary in targets:
			if want != null and t.get("id") == want:
				_focus_id = want
				pointer_on = true
				set_pointer((t.rect as Rect2).get_center())
				return
	var from := pointer if pointer.x >= 0.0 else _view_size() * 0.5
	var best: Dictionary = {}
	if cur.is_empty() or dir == "":
		var bd := INF
		for t: Dictionary in targets:
			var d := (t.rect as Rect2).get_center().distance_to(from)
			if d < bd:
				bd = d
				best = t
		if not cur.is_empty() and dir == "":
			best = cur
	else:
		from = (cur.rect as Rect2).get_center()
		var dv: Vector2 = DIRS[dir]
		for cone in [60.0, 89.0]:
			var bs := INF
			for t: Dictionary in targets:
				if t == cur:
					continue
				var off := (t.rect as Rect2).get_center() - from
				if off.length() < 1.0:
					continue
				var along := off.dot(dv)
				if along <= 0.0 or absf(off.angle_to(dv)) > deg_to_rad(cone):
					continue
				var score := along + 2.0 * absf(off.cross(dv))
				if score < bs:
					bs = score
					best = t
			if not best.is_empty():
				break
		if best.is_empty():
			best = cur
	if best.is_empty():
		return
	_focus_id = best.get("id")
	pointer_on = true
	set_pointer((best.rect as Rect2).get_center())


## A panel moves the focus itself (a list scrolled by the D-pad): the target
## `id` at `rect` (viewport pixels).
func focus_target(id: Variant, rect: Rect2) -> void:
	_focus_id = id
	pointer_on = true
	set_pointer(rect.get_center())


## The id of the focused snap target (tests, panels).
func focus_id() -> Variant:
	return _focus_id
