extends Node
## Own the touch gesture until its intent is known. Existing UI receives one
## mouse click on release; a hold or camera gesture never first buys an item
## or issues a world order. A physical mouse retains its original behavior.

signal mode_changed
var enabled := false
## Touch mode for good: a phone / tablet, or --touch. Otherwise (a desktop,
## or a browser on a touch-capable PC) a touch turns the touch controls on
## and real mouse movement turns them off again.
var pinned := false
var _last_touch := -100000
var _mouse_run := 0.0
var fingers: Dictionary = {}
var _primary := -1
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _control: Control
var _cancelled := false
var _dragging := false
var _held := false
var _panning := false
var _elapsed := 0.0
var _pair := PackedVector2Array()
var _tap_time := -1000
var _tap_position := Vector2(-1000, -1000)
var _tap_control: Control
var _emitting := false
var _wheel_acc := 0.0
var _scroll_owner: Control
var _hold_owner: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_emulate_mouse_from_touch(false)
	pinned = Portability.handheld() or OS.get_cmdline_user_args().has("--touch")
	enabled = pinned
	if OS.has_feature("web"):
		# The first guess only: a page whose primary pointer is a finger (a
		# phone or tablet). A PC with a touch screen has a fine primary pointer
		# (mouse or touchpad) and starts with the desktop controls; touches and
		# mouse movement switch the mode from then on.
		enabled = bool(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches", true))
	get_tree().auto_accept_quit = not Portability.handheld()
	# SceneTree handles Android Back separately from window close requests.
	# Let our deferred controller/Back guard emit the single Escape action.
	get_tree().quit_on_go_back = false

func game() -> Game:
	var main := get_tree().current_scene
	return main.game as Game if main and "game" in main else null

func target_pixels() -> float:
	if OS.has_feature("web"):
		return 44.0 * float(JavaScriptBridge.eval("window.devicePixelRatio || 1", true)) / get_viewport().get_final_transform().get_scale().x
	var dpi := DisplayServer.screen_get_dpi() if Portability.handheld() else 160
	return 48.0 * maxf(1.0, dpi / 160.0) / get_viewport().get_final_transform().get_scale().x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _emitting and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_moved(event)
	if _emitting or not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_last_touch = Time.get_ticks_msec()
	_mouse_run = 0.0
	if not enabled:
		enabled = true
		mode_changed.emit()
	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position, event.canceled)
	else:
		_drag(event.index, event.position)

## A real mouse (not this node's emulation, not a browser's compatibility
## event right after a touch) moved 40 px: back to the desktop controls.
func _mouse_moved(event: InputEventMouseMotion) -> void:
	if pinned or not enabled or Time.get_ticks_msec() - _last_touch < 1000:
		return
	_mouse_run += event.relative.length()
	if _mouse_run >= 40.0:
		_mouse_run = 0.0
		enabled = false
		mode_changed.emit()

func _press(index: int, point: Vector2) -> void:
	fingers[index] = point
	if fingers.size() == 1:
		_primary = index
		_start = point
		_last = point
		_cancelled = false
		_dragging = false
		_held = false
		_panning = false
		_elapsed = 0.0
		_wheel_acc = 0.0
		_scroll_owner = null
		_hover(point)
		_control = get_viewport().gui_get_hovered_control()
		# A full-screen touch overlay ignores its blank area.
	else:
		_cancelled = true
		_panning = false
		_release_hold()
		_hover(point)
		var next_control := get_viewport().gui_get_hovered_control()
		if is_instance_valid(next_control) and not is_instance_valid(_control):
			_control = next_control
		_tap_time = -1000
		if _dragging:
			button(_last, false)
		_dragging = false
		_pair = PackedVector2Array(fingers.values().slice(0, 2))

func _drag(index: int, point: Vector2) -> void:
	if not fingers.has(index):
		return
	fingers[index] = point
	if fingers.size() >= 2:
		var now := PackedVector2Array(fingers.values().slice(0, 2))
		var g := game()
		if not is_instance_valid(_control) and g and _pair.size() == 2 and not g.hud.blocks_camera():
			g.rig.touch_gesture(_pair, now)
		elif is_instance_valid(_control) and _pair.size() == 2:
			var owner := _control
			while owner and not owner.has_method("touch_transform"):
				owner = owner.get_parent() as Control
			if owner:
				owner.call("touch_transform", _pair, now)
		_pair = now
		return
	if index == _primary and is_instance_valid(_scroll_owner):
		var delta := point - _last
		_last = point
		_scroll(point, delta)
		return
	if index == _primary and _panning and not _cancelled:
		_pan_world(_last, point)
		_last = point
		return
	if index != _primary or _cancelled or _held:
		return
	var relative := point - _last
	_last = point
	if point.distance_to(_start) < target_pixels() * 0.22 and not _dragging:
		return
	if not is_instance_valid(_control):
		# A one-finger world drag is not a move order: it moves the map under
		# the finger (the PC's WASD); two fingers turn and zoom.
		_panning = true
		_pan_world(_start, point)   # from the touch-down: the ground stays under the finger
		return
	var owner := _control
	while owner and not owner.has_method("touch_scroll") and not owner is ScrollContainer:
		owner = owner.get_parent() as Control
	if owner and owner.has_method("touch_draggable") and owner.call("touch_draggable", _start):
		owner = null
	if owner:
		_cancelled = false
		_held = true  # scroll completion must never click the row under it
		_scroll_owner = owner
		_scroll(point, point - _start)
		return
	if not _dragging:
		_dragging = true
		button(_start, true)
	motion(point, relative, MOUSE_BUTTON_MASK_LEFT)

func _pan_world(from: Vector2, to: Vector2) -> void:
	var g := game()
	if g and not g.hud.blocks_camera():
		g.rig.touch_drag(from, to)

func _scroll(point: Vector2, delta: Vector2) -> void:
	if _scroll_owner is ScrollContainer:
		(_scroll_owner as ScrollContainer).scroll_vertical -= int(delta.y)
		return
	_wheel_acc += delta.length()
	if _wheel_acc >= target_pixels() * 0.5:
		_scroll_owner.call("touch_scroll", point, delta)
		_wheel_acc = 0.0

func _release(index: int, point: Vector2, cancelled: bool) -> void:
	if not fingers.has(index):
		return
	fingers.erase(index)
	if index == _primary:
		_release_hold()
		if _dragging:
			button(point, false)
		elif not _cancelled and not _held and not _panning and not cancelled:
			var now := Time.get_ticks_msec()
			var double := now - _tap_time < 330 and point.distance_to(_tap_position) < target_pixels() * 0.4 and _control == _tap_control
			_tap_time = -1000 if double else now
			_tap_position = point
			_tap_control = _control
			button(point, true, MOUSE_BUTTON_LEFT, double)
			button(point, false, MOUSE_BUTTON_LEFT, double)
		_primary = -1
		_dragging = false
		_panning = false
	if fingers.is_empty():
		_pair.clear()
		_control = null

func _process(dt: float) -> void:
	if _primary < 0 or _cancelled or _dragging or _held or _panning or fingers.size() != 1:
		return
	_elapsed += dt
	if _elapsed < 0.5:
		return
	_held = true
	_tap_time = -1000
	var control := _control
	while is_instance_valid(control):
		if control.has_method("touch_hold"):
			_hold_owner = control
			control.call("touch_hold", control.get_global_transform_with_canvas().affine_inverse() * _start)
			return
		control = control.get_parent() as Control
	# Hover remains on the point after release for the original help display.

func _hover(point: Vector2) -> void:
	# Input.parse_input_event queues events until the next flush. Resolve the
	# GUI owner synchronously, before deciding whether this is a world gesture.
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func motion(point: Vector2, relative: Vector2, mask := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	var transform := get_viewport().get_final_transform()
	event.position = transform * point
	event.global_position = event.position
	event.relative = transform.basis_xform(relative)
	event.button_mask = mask
	_emitting = true
	Input.parse_input_event(event)
	_emitting = false

func button(point: Vector2, pressed: bool, which := MOUSE_BUTTON_LEFT, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = get_viewport().get_final_transform() * point
	event.global_position = event.position
	event.button_index = which
	event.pressed = pressed
	event.double_click = double
	_emitting = true
	Input.parse_input_event(event)
	_emitting = false

func cancel_gesture() -> void:
	_release_hold()
	_panning = false
	if _dragging:
		button(_last, false)
	fingers.clear()
	_primary = -1
	_dragging = false
	_cancelled = true
	_tap_time = -1000

func _release_hold() -> void:
	if is_instance_valid(_hold_owner) and _hold_owner.has_method("touch_release"):
		_hold_owner.call("touch_release")
	_hold_owner = null

func holding(control: Control) -> bool:
	return _held and is_instance_valid(_hold_owner) and _hold_owner == control

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture()
		var g := game()
		var testing := Array(OS.get_cmdline_user_args()).any(func(arg): return String(arg).begins_with("--tool="))
		if not testing and enabled and g and g.session.is_host and not g.session.online and not g.hud._esc_open:
			g.session.save_game("autosave")
			g.hud.toggle_menu()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		PadInput.android_back_request()
