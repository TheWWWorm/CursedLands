class_name ArenaShopAction
extends Button
## A compact shop action: level or reroll, price, and optional XP progress.

var emblem: Texture2D
var value: Label
var price: Label
var progress: Label


func _ready() -> void:
	custom_minimum_size = Vector2(80, 60)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var fill := Color("202726")
		var border := Color("777257")
		if state in ["hover", "hover_pressed"]: fill = Color("344248"); border = ArenaCreatureCard.GOLD
		elif state == "pressed": fill = Color("504a35"); border = ArenaCreatureCard.GOLD
		elif state == "disabled": fill = Color("1a201f"); border = Color("4b5143")
		elif state == "focus": fill = Color.TRANSPARENT; border = ArenaCreatureCard.PAPER
		add_theme_stylebox_override(state, ArenaCreatureCard.style(fill, border, Vector2(4, 4)))
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 5; center.offset_right = -5
	center.offset_top = 4; center.offset_bottom = -4
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	center.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	box.add_child(row)
	if emblem:
		var icon := TextureRect.new()
		icon.texture = emblem
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(25, 28)
		row.add_child(icon)
	value = Label.new()
	value.add_theme_font_size_override("font_size", 25)
	value.add_theme_color_override("font_color", ArenaCreatureCard.PAPER)
	value.visible = emblem == null
	row.add_child(value)
	var cost := HBoxContainer.new()
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_theme_constant_override("separation", 2)
	row.add_child(cost)
	var coin := TextureRect.new()
	coin.texture = preload("res://assets/arena/coin.svg")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(13, 15)
	cost.add_child(coin)
	price = Label.new()
	price.add_theme_font_size_override("font_size", 14)
	price.add_theme_color_override("font_color", ArenaCreatureCard.GOLD)
	cost.add_child(price)
	progress = Label.new()
	progress.add_theme_font_size_override("font_size", 11)
	progress.add_theme_color_override("font_color", ArenaCreatureCard.MUTED)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.visible = emblem == null
	box.add_child(progress)
	for child: Control in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_state(level: int, cost: int, xp := 0, needed := 0) -> void:
	value.text = str(level)
	price.text = str(cost)
	price.get_parent().visible = emblem != null or needed > 0
	progress.text = RemakeText.t("XP %d/%d") % [xp, needed] if needed > 0 else RemakeText.t("Max")
	for child: Control in [value, price, progress]: child.modulate.a = 0.55 if disabled else 1.0
