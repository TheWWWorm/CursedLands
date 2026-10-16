class_name WikiResults
extends ScrollContainer
signal item_selected(index: int)
var _box: VBoxContainer
var _buttons: Array[Button] = []
var item_count: int:
	get: return _buttons.size()

func _ready() -> void:
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus=true
	_box=VBoxContainer.new();_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation",3);add_child(_box)

func clear() -> void:
	for child in _box.get_children(): _box.remove_child(child);child.queue_free()
	_buttons.clear()

func add_item(text: String, kind := "book") -> void:
	var index := _buttons.size()
	var button := Button.new();button.toggle_mode=true;button.custom_minimum_size.y=65;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.set_meta("wiki_result",true)
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new();style.bg_color=Color("344536") if state in ["pressed","hover"] else Color("223027")
		style.set_corner_radius_all(4);style.set_content_margin_all(10)
		if state=="focus":style.border_color=Color("d8b56b");style.set_border_width_all(2)
		button.add_theme_stylebox_override(state,style)
	var icon := TextureRect.new();icon.texture=load("res://icons/wiki/"+(kind if kind in ["character","allod","item","spell","quest","creature","map","material","rune"] else "book")+".svg");icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.position=Vector2(8,12);icon.size=Vector2(36,40);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(icon)
	var box := VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);box.offset_left=52;box.offset_top=9;box.offset_right=-12;box.offset_bottom=-8
	var title := Label.new();title.text=text.get_slice("\n",0);title.add_theme_color_override("font_color",Color("eee8d8"));title.add_theme_font_size_override("font_size",16)
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(title)
	var detail := Label.new();detail.text=text.get_slice("\n",1);detail.add_theme_color_override("font_color",Color("b7c4ad"));detail.add_theme_font_size_override("font_size",12)
	detail.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;detail.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(detail)
	button.pressed.connect(func(): select(index);item_selected.emit(index))
	_box.add_child(button);_buttons.append(button)

func set_item_metadata(index: int, value: Variant) -> void: _buttons[index].set_meta("key",value)
func get_item_metadata(index: int) -> Variant: return _buttons[index].get_meta("key")
func set_item_tooltip(index: int, value: String) -> void: _buttons[index].tooltip_text=value
func select(index: int) -> void:
	for i in _buttons.size():_buttons[i].set_pressed_no_signal(i==index)
func get_item_rect(index: int) -> Rect2: return _buttons[index].get_rect()
