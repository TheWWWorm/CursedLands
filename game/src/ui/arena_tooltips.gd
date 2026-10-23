class_name ArenaTooltips
extends ArenaHudPanel
## Tooltips share the HUD's logical coordinates and a bounded text measure.
## Native tooltip windows otherwise ignore the scaled canvas and never wrap.

var scope: Control
var input_modal: Control
var world_hint: Callable
var viewport_pointer: Callable
var suspended := false
var _heading: Label
var _body: Label
var _icon: ArenaItemEmblem
var _title_row: HBoxContainer
var _keyboard_navigation := false
var _key: Variant
var _since := 0


func _ready() -> void:
	super._ready()
	surface.a = 0.99
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_title_row = HBoxContainer.new()
	_title_row.add_theme_constant_override("separation", 12)
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title_row)
	_icon = ArenaItemEmblem.new()
	_icon.custom_minimum_size = Vector2(72, 72)
	_title_row.add_child(_icon)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 18)
	_heading.add_theme_color_override("font_color", ArenaCreatureCard.GOLD)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_row.add_child(_heading)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 14)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	hide()


func capture(node: Node) -> void:
	if node == self: return
	if node is Control and not node.tooltip_text.is_empty():
		node.set_meta("arena_help", node.tooltip_text)
		node.tooltip_text = ""
	for child in node.get_children(): capture(child)


func _process(_dt: float) -> void:
	if scope == null: return
	if suspended:
		_key = null
		hide()
		return
	var hint := {}
	var control := get_viewport().gui_get_hovered_control()
	var focus := get_viewport().gui_get_focus_owner()
	if _keyboard_navigation and is_instance_valid(focus) and focus.has_meta("arena_item_kind"): control = focus
	if is_instance_valid(input_modal) and input_modal.visible and (control == null or (control != input_modal and not input_modal.is_ancestor_of(control))):
		_key = null
		hide()
		return
	var hovered_control := control
	while control and control != scope.get_parent():
		if control.has_meta("arena_help") and control.is_visible_in_tree():
			hint = {"key": control.get_instance_id(), "text": String(control.get_meta("arena_help"))}
			if control.has_meta("arena_item_kind"):
				hint.kind = String(control.get_meta("arena_item_kind"))
				hint.title = ArenaItems.title(hint.kind)
			break
		control = control.get_parent() as Control
	if hint.is_empty() and world_hint.is_valid(): hint = world_hint.call(hovered_control)
	var key = hint.get("key")
	if key != _key or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_key = key
		_since = Time.get_ticks_msec()
		hide()
	if hint.is_empty() or Time.get_ticks_msec() - _since < 350:
		hide()
		return
	_heading.text = String(hint.get("title", ""))
	_heading.visible = not _heading.text.is_empty()
	_icon.kind = String(hint.get("kind", ""))
	_icon.visible = not _icon.kind.is_empty()
	_title_row.visible = _heading.visible or _icon.visible
	_body.text = String(hint.get("text", ""))
	var width := 80.0
	for label: Label in [_heading, _body]:
		for line in label.text.split("\n"):
			width = maxf(width, label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x + 24)
	size = Vector2(minf(350 if _icon.visible else 310, width), 0)
	var pointer: Vector2 = scope.get_global_transform_with_canvas().affine_inverse() * viewport_pointer.call() if viewport_pointer.is_valid() else scope.get_local_mouse_position()
	if _keyboard_navigation and is_instance_valid(focus) and focus.has_meta("arena_item_kind"):
		pointer = scope.get_global_transform_with_canvas().affine_inverse() * focus.get_global_rect().end
	var at := pointer + Vector2(18, 24)
	if at.y + size.y > scope.size.y - 12: at.y = pointer.y - size.y - 16
	position = at.clamp(Vector2(12, 12), (scope.size - size - Vector2(12, 12)).max(Vector2(12, 12)))
	show()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed: _keyboard_navigation = true
	elif event is InputEventMouseMotion: _keyboard_navigation = false
