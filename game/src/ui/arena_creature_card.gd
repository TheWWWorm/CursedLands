class_name ArenaCreatureCard
extends Button
## Compact recruitment tile with a real animated original-game creature.

const PAPER := Color("f0eadc")
const GOLD := Color("d6b66f")
const MUTED := Color("b7c0bd")
const SNOW_INK := Color("141414")
const SNOW_ACCENT := Color("713b0f")
var prototype := ""
var heading := ""
var caption := ""
var footer := ""
var cost := 3
var copies := 0
var copies_needed := 3
var quality := 0
var family := -1
var preview: WikiPreview
var _price: Label
var _copies: Label
var upgrade_ready := false
var _glow: ShaderMaterial


static func style(fill: Color, border := Color("5a624c"), padding := Vector2(10, 8)) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(2)
	result.content_margin_left = padding.x; result.content_margin_right = padding.x
	result.content_margin_top = padding.y; result.content_margin_bottom = padding.y
	return result


func _ready() -> void:
	custom_minimum_size = Vector2(96, 148)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = ArenaRules.title(prototype) + "\n" + caption + "\n" + footer
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", style(Color(0.12, 0.16, 0.17, 0.45), Color(0, 0, 0, 0)))
	add_theme_stylebox_override("pressed", style(Color(0.2, 0.24, 0.22, 0.7), GOLD))
	add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), PAPER))
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	ArenaStars.add_to(self, quality + 1, Vector2(6, 4))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	preview = WikiPreview.new()
	preview.fit_slot = true
	preview.custom_minimum_size.y = 94
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(preview)
	if not prototype.is_empty():
		preview.show_model({"kind": "creature", "value": prototype})
		preview.turn_by(-0.4)
	if disabled: preview.modulate.a = 0.65
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metadata := VBoxContainer.new()
	metadata.name = "OfferInfo"
	metadata.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metadata.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	metadata.add_theme_constant_override("separation", 1)
	box.add_child(metadata)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_theme_constant_override("separation", 4)
	metadata.add_child(price_row)
	var coin := TextureRect.new()
	coin.texture = preload("res://assets/arena/coin.svg")
	coin.custom_minimum_size = Vector2(18, 18)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(coin)
	ink_icon(coin, SNOW_INK)
	_price = _label(price_row, "", 16, SNOW_INK)
	snow_ink(_price)
	_copies = _label(price_row, "", 13, SNOW_INK)
	snow_ink(_copies)
	var traits := HBoxContainer.new()
	traits.alignment = BoxContainer.ALIGNMENT_CENTER
	traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metadata.add_child(traits)
	for key: String in ArenaAlliances.traits(family):
		var emblem := TextureRect.new()
		emblem.texture = load("res://assets/arena/alliance_%s.svg" % key)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.custom_minimum_size = Vector2(18, 18)
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		traits.add_child(emblem)
		ink_icon(emblem, SNOW_INK)
	update_offer()
	var title := _label(self, heading if not heading.is_empty() else ArenaRules.title(prototype), 14, PAPER)
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title.offset_top = 4; title.offset_bottom = 42
	title.offset_left = -14; title.offset_right = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Native German names use long hyphenated compounds. Prefer the existing
	# hyphen as a break, rather than stranding a final letter on its own line.
	title.text = title.text.replace("-", "-\u200b")
	title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	title.max_lines_visible = 2
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.modulate.a = 0
	mouse_entered.connect(func(): title.modulate.a = 1)
	mouse_exited.connect(func(): title.modulate.a = 1 if has_focus() else 0)
	focus_entered.connect(func(): title.modulate.a = 1)
	focus_exited.connect(func(): title.modulate.a = 0)


func update_offer() -> void:
	if not is_instance_valid(_price): return
	_price.text = str(cost)
	_price.add_theme_color_override("font_color", Color("383838") if disabled else SNOW_INK)
	_copies.visible = copies > 0 and copies_needed > 0
	_copies.text = "  %d/%d" % [mini(copies, copies_needed), copies_needed]
	_copies.tooltip_text = RemakeText.t("Copies: %d/%d") % [copies, copies_needed]
	preview.modulate.a = 0.65 if disabled else 1.0
	upgrade_ready = copies_needed > 0 and copies + 1 >= copies_needed
	if upgrade_ready and _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = preload("res://src/ui/arena_upgrade_glow.gdshader")
	if is_instance_valid(preview.creature): preview.creature.material = _glow if upgrade_ready else null
	_copies.text += " ↑" if upgrade_ready else ""
	_copies.add_theme_color_override("font_color", SNOW_ACCENT if upgrade_ready else SNOW_INK)


func _label(parent: Node, value: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	outline(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(label)
	return label


static func ink_icon(icon: TextureRect, color: Color, edge := Color.TRANSPARENT) -> void:
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://src/ui/arena_icon_ink.gdshader")
	ink.set_shader_parameter("ink", color)
	ink.set_shader_parameter("edge_ink", edge)
	icon.material = ink
	icon.modulate = Color.WHITE


static func outline(control: Control) -> void:
	control.add_theme_color_override("font_outline_color", Color("222222"))
	control.add_theme_constant_override("outline_size", 2)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	control.add_theme_constant_override("shadow_offset_y", 1)


static func snow_ink(control: Control, color := SNOW_INK) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		control.add_theme_color_override(state, color)
	control.add_theme_font_override("font", preload("res://fonts/LiberationSans-Regular.ttf"))
	control.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	control.add_theme_constant_override("outline_size", 0)
	control.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	control.add_theme_constant_override("shadow_offset_y", 0)
