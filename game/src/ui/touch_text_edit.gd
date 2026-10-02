class_name TouchTextEdit
extends RefCounted
## A real text field provides IME, selection, paste and the soft keyboard.
## The original screen keeps its custom-drawn label once editing finishes.
static func open(owner: Control, value: String, limit: int, changed: Callable, title := "") -> void:
	if owner.has_node("TouchTextEdit"):
		return
	var panel := PanelContainer.new()
	panel.name = "TouchTextEdit"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 12
	panel.offset_left = -minf(owner.size.x * 0.45, 320)
	panel.offset_right = minf(owner.size.x * 0.45, 320)
	panel.z_index = 100
	var column := VBoxContainer.new()
	panel.add_child(column)
	if title:
		var label := Label.new()
		label.text = RemakeText.t(title)
		column.add_child(label)
	var row := HBoxContainer.new()
	column.add_child(row)
	var field := LineEdit.new()
	field.text = value
	field.max_length = limit
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(180, TouchInput.target_pixels())
	field.add_theme_font_size_override("font_size", maxi(18, int(TouchInput.target_pixels() * 0.35)))
	row.add_child(field)
	field.text_changed.connect(changed)
	var done := Button.new()
	done.text = "✓"
	done.custom_minimum_size = Vector2.ONE * TouchInput.target_pixels()
	row.add_child(done)
	var close := func():
		DisplayServer.virtual_keyboard_hide()
		panel.queue_free()
	done.pressed.connect(close)
	field.text_submitted.connect(func(_text): close.call())
	owner.visibility_changed.connect(func():
		if not owner.is_visible_in_tree() and is_instance_valid(panel): close.call())
	owner.add_child(panel)
	field.grab_focus()
	field.caret_column = field.text.length()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(field.text, field.get_global_rect(), DisplayServer.KEYBOARD_TYPE_DEFAULT, limit, field.caret_column, field.caret_column)
