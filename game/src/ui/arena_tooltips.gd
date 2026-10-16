class_name ArenaTooltips
extends ArenaHudPanel
## Tooltips share the HUD's logical coordinates and a bounded text measure.
## Native tooltip windows otherwise ignore the scaled canvas and never wrap.

var scope: Control
var world_hint: Callable
var _heading: Label
var _body: Label
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
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.add_theme_color_override("font_color", ArenaCreatureCard.GOLD)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_heading)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 15)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	custom_minimum_size.x = 310
	hide()


func capture(node: Node) -> void:
	if node == self: return
	if node is Control and not node.tooltip_text.is_empty():
		node.set_meta("arena_help", node.tooltip_text)
		node.tooltip_text = ""
	for child in node.get_children(): capture(child)


func _process(_dt: float) -> void:
	if scope == null: return
	var hint := {}
	var control := get_viewport().gui_get_hovered_control()
	var hovered_control := control
	while control and control != scope.get_parent():
		if control.has_meta("arena_help") and control.is_visible_in_tree():
			hint = {"key": control.get_instance_id(), "text": String(control.get_meta("arena_help"))}
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
	_body.text = String(hint.get("text", ""))
	size = Vector2(310, 0)
	var pointer := scope.get_local_mouse_position()
	var at := pointer + Vector2(18, 24)
	if at.y + size.y > scope.size.y - 12: at.y = pointer.y - size.y - 16
	position = at.clamp(Vector2(12, 12), (scope.size - size - Vector2(12, 12)).max(Vector2(12, 12)))
	show()
