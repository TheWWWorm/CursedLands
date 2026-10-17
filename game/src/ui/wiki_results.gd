class_name WikiResults
extends ScrollContainer
## Only visible search rows own Controls; the full index remains searchable.
signal item_selected(index: int)
var _canvas: Control
var _rows: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _selected := -1
var _scale := 1.0
var _queued := false
var item_count: int:
	get: return _rows.size()

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_ALL
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_canvas)
	get_v_scroll_bar().value_changed.connect(func(_value): _refresh())
	resized.connect(_queue_refresh)

func set_ui_scale(value: float) -> void:
	_scale = value
	_queue_refresh()

func _row_height() -> float:
	return roundf(65 * _scale)

func clear() -> void:
	_rows.clear()
	_selected = -1
	scroll_vertical = 0
	_queue_refresh()

func add_item(text: String, kind := "book") -> void:
	_rows.append({"text": text, "kind": kind, "key": null, "tip": ""})
	_queue_refresh()

func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	_queued = false
	if not is_instance_valid(_canvas): return
	var stride := _row_height() + 3 * _scale
	_canvas.custom_minimum_size.y = maxf(0, item_count * stride - 3 * _scale)
	var first := maxi(0, int(scroll_vertical / stride))
	var count := mini(maxi(0, item_count - first), ceili(size.y / stride) + 1)
	while _buttons.size() < count:
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.set_meta("wiki_result", true)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("344536") if state in ["pressed", "hover"] else Color("223027")
			style.set_corner_radius_all(4)
			if state == "focus": style.border_color = Color("d8b56b"); style.set_border_width_all(2)
			button.add_theme_stylebox_override(state, style)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		for color: String in ["eee8d8", "b7c4ad"]:
			var label := Label.new()
			label.add_theme_color_override("font_color", Color(color))
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(label)
		button.pressed.connect(func():
			var index: int = button.get_meta("index")
			grab_focus(); select(index); item_selected.emit(index))
		_canvas.add_child(button)
		_buttons.append(button)
	for i in _buttons.size():
		var button := _buttons[i]
		button.visible = i < count
		if i >= count: continue
		var index := first + i
		var row := _rows[index]
		button.set_meta("index", index)
		button.position = Vector2(0, index * stride)
		button.size = Vector2(_canvas.size.x, _row_height())
		button.set_pressed_no_signal(index == _selected)
		button.tooltip_text = row.tip
		button.accessibility_name = row.text.replace("\n", ". ")
		var icon := button.get_child(0) as TextureRect
		var kind: String = row.kind if row.kind in ["character", "allod", "item", "spell", "quest", "creature", "map", "material", "rune"] else "book"
		icon.texture = load("res://icons/wiki/" + kind + ".svg")
		icon.position = Vector2(8, 12) * _scale
		icon.size = Vector2(36, 40) * _scale
		for j in 2:
			var label := button.get_child(j + 1) as Label
			label.text = row.text.get_slice("\n", j)
			label.add_theme_font_size_override("font_size", roundi((16 if j == 0 else 12) * _scale))
			label.position = Vector2(52, 9 if j == 0 else 34) * _scale
			label.size = Vector2(maxf(0, button.size.x - 64 * _scale), 24 * _scale)

func set_item_metadata(index: int, value: Variant) -> void: _rows[index].key = value
func get_item_metadata(index: int) -> Variant: return _rows[index].key
func set_item_tooltip(index: int, value: String) -> void: _rows[index].tip = value
func select(index: int) -> void:
	_selected = index
	_queue_refresh()
func get_item_rect(index: int) -> Rect2:
	return Rect2(0, index * (_row_height() + 3 * _scale), size.x, _row_height())

func visible_indices() -> Array[int]:
	var result: Array[int] = []
	for button in _buttons:
		if button.visible: result.append(int(button.get_meta("index")))
	return result

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or _rows.is_empty(): return
	var index := _selected
	match event.keycode:
		KEY_UP: index -= 1
		KEY_DOWN: index += 1
		KEY_HOME: index = 0
		KEY_END: index = item_count - 1
		_: return
	index = clampi(index, 0, item_count - 1)
	select(index)
	var rect := get_item_rect(index)
	if rect.position.y < scroll_vertical: scroll_vertical = int(rect.position.y)
	elif rect.end.y > scroll_vertical + size.y: scroll_vertical = ceili(rect.end.y - size.y)
	item_selected.emit(index)
	accept_event()
