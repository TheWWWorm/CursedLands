class_name ArenaItemSlot
extends Button
## A focusable circular relic or empty creature slot. Drag release is not a click.

signal activated
const TRAY_SIZE := 40.0
const TARGET_SIZE := 34.0
const BADGE_SIZE := 28.0
const DRAG_SIZE := 44.0
var kind := "":
	set(value):
		kind = value
		if is_instance_valid(_art): _art.kind = value
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var equipped := false:
	set(value):
		equipped = value
		queue_redraw()
var target_hover := false:
	set(value):
		target_hover = value
		queue_redraw()
var make_drag: Callable
var accept_drop: Callable
var receive_drop: Callable
var _art: ArenaItemEmblem
var _drag_started := false

func _init() -> void:
	custom_minimum_size = Vector2.ONE * TRAY_SIZE

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_art = ArenaItemEmblem.new()
	_art.kind = kind
	_art.custom_minimum_size = Vector2.ONE
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.offset_left = 4; _art.offset_top = 4
	_art.offset_right = -4; _art.offset_bottom = -4
	_art.visible = not kind.is_empty()
	pressed.connect(func():
		if not _drag_started: activated.emit())
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]: sig.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 2
	var active := selected or target_hover or has_focus() or is_hovered()
	draw_circle(size * 0.5, radius, Color("111b20"), true, -1, true)
	draw_circle(size * 0.5, radius, ArenaCreatureCard.GOLD if active else Color("687b80"), false, 2.5 if active else 1.5, true)
	if is_instance_valid(_art): _art.visible = not kind.is_empty()
	if kind.is_empty():
		var center := size * 0.5
		draw_line(center - Vector2(7, 0), center + Vector2(7, 0), Color("a0b5b7"), 2, true)
		draw_line(center - Vector2(0, 7), center + Vector2(0, 7), Color("a0b5b7"), 2, true)
	if equipped:
		var mark := Vector2(size.x - 8, size.y - 8)
		draw_circle(mark, 6, Color("182c23"))
		draw_polyline(PackedVector2Array([mark + Vector2(-3, 0), mark + Vector2(-1, 2), mark + Vector2(4, -3)]), Color("a5e5b4"), 2, true)

func _get_drag_data(at: Vector2) -> Variant:
	if not make_drag.is_valid(): return null
	var data: Variant = make_drag.call(at)
	if not data is Dictionary or data.is_empty(): return null
	_drag_started = true
	var preview := ArenaItemEmblem.new()
	preview.kind = String(data.kind)
	preview.custom_minimum_size = Vector2.ONE * DRAG_SIZE
	# Keep the pointer and drop target visible while carrying the item.
	preview.position = Vector2(12, 12)
	set_drag_preview(preview)
	return data

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return accept_drop.is_valid() and bool(accept_drop.call(at, data))

func _drop_data(at: Vector2, data: Variant) -> void:
	if receive_drop.is_valid(): receive_drop.call(at, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: _finish_drag.call_deferred()

func _finish_drag() -> void:
	_drag_started = false
