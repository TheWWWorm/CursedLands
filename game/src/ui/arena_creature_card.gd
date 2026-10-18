class_name ArenaCreatureCard
extends Button
## Compact recruitment tile with a real animated original-game creature.

const PAPER := Color("f0eadc")
const GOLD := Color("d6b66f")
const MUTED := Color("b7c0bd")
const SNOW_INK := GOLD
const SNOW_ACCENT := Color("f2d58f")
const TRIBE_COLORS := {
	"beast": Color("e2bc75"), "horde": Color("ed998b"),
	"warrior": Color("9dc8e7"), "hunter": Color("a5d99a"),
	"mage": Color("c9a7ec"),
}
var prototype := ""
var heading := ""
var caption := ""
var footer := ""
var cost := 3
var copies := 0
var copies_needed := 3
var quality := 0
var family := -1
var represented_traits := {}
var preview: WikiPreview
var _price: Label
var _copies: Label
var _info: ArenaInfoPanel
var _offer_icons: Array[TextureRect] = []
var upgrade_ready := false
var _glow: ShaderMaterial
var _title: Label
var _traits: HBoxContainer
var _stars: ArenaStars
var _shown_prototype := ""
var _shown_family := -2
var _preview_pending := false


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
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), PAPER))
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	_stars = ArenaStars.add_to(self, quality + 1, Vector2(6, 4))
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
	preview.custom_minimum_size.y = 84
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(preview)
	if disabled: preview.modulate.a = 0.65
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info = ArenaInfoPanel.new()
	_info.name = "OfferInfo"
	_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_info.custom_minimum_size.x = 76
	box.add_child(_info)
	var metadata := VBoxContainer.new()
	metadata.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metadata.add_theme_constant_override("separation", 2)
	_info.add_child(metadata)
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
	_offer_icons.append(coin)
	ink_icon(coin, cost_accent(cost))
	_price = _label(price_row, "", 17, PAPER)
	snow_ink(_price, PAPER)
	_price.add_theme_font_override("font", preload("res://fonts/LiberationSans-Bold.ttf"))
	_copies = _label(price_row, "", 13, PAPER)
	snow_ink(_copies, PAPER)
	_traits = HBoxContainer.new()
	_traits.alignment = BoxContainer.ALIGNMENT_CENTER
	_traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metadata.add_child(_traits)
	var title := _label(self, heading if not heading.is_empty() else ArenaRules.title(prototype), 14, PAPER)
	_title = title
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
	mouse_entered.connect(func(): title.modulate.a = 1; _info.highlighted = not disabled)
	mouse_exited.connect(func(): title.modulate.a = 1 if has_focus() or _preview_pending else 0; _info.highlighted = has_focus())
	focus_entered.connect(func(): title.modulate.a = 1; _info.highlighted = true)
	focus_exited.connect(func(): title.modulate.a = 1 if _preview_pending else 0; _info.highlighted = is_hovered() and not disabled)
	update_offer()


func _process(_delta: float) -> void:
	# A reroll swaps six figures. Retain their render targets and admit one
	# model per frame, so first-use meshes cannot stall the whole shop update.
	if _shown_prototype != prototype:
		if not ArenaAnimationWarmup.ready_for(prototype): return
		if not ArenaAnimationWarmup.claim_model_frame(): return
		_shown_prototype = prototype
		preview.show_model({"kind": "creature", "value": prototype}, true)
		preview.turn_by(-0.4)
		for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_instance_valid(preview.creature): preview.creature.material = _glow if upgrade_ready or cost >= 4 else null
	if is_instance_valid(preview.creature) and (preview.creature._framed < 3 or is_instance_valid(preview.creature._old_pivot)): return
	_preview_pending = false
	preview.modulate.a = 0.65 if disabled else 1.0
	_title.modulate.a = 1 if is_hovered() or has_focus() else 0
	set_process(false)


func update_offer() -> void:
	if not is_instance_valid(_price): return
	if _shown_family != family:
		_shown_family = family
		for icon: TextureRect in _traits.get_children():
			_offer_icons.erase(icon); _traits.remove_child(icon); icon.queue_free()
		for key: String in ArenaAlliances.traits(family):
			var emblem := TextureRect.new()
			emblem.set_meta("tribe", key)
			emblem.texture = load("res://assets/arena/alliance_%s.svg" % key)
			emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			emblem.custom_minimum_size = Vector2(18, 18)
			emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_traits.add_child(emblem); _offer_icons.append(emblem)
	if _shown_prototype != prototype:
		_preview_pending = true
		_title.text = (heading if not heading.is_empty() else ArenaRules.title(prototype)).replace("-", "-\u200b")
		_title.modulate.a = 1
		set_process(true)
	_stars.count = clampi(quality + 1, 1, 3)
	_stars.custom_minimum_size = Vector2(_stars.count * 14 - 2, 12)
	_stars.queue_redraw()
	_price.text = str(cost)
	_price.add_theme_color_override("font_color", MUTED if disabled else PAPER)
	var accent := cost_accent(cost)
	_info.accent = accent.lerp(MUTED, 0.55) if disabled else accent
	_info.highlighted = not disabled and (is_hovered() or has_focus())
	for icon in _offer_icons:
		if icon.has_meta("tribe"):
			var key := String(icon.get_meta("tribe"))
			tribe_icon(icon, key, int(represented_traits.get(key, 0)) > 0)
		else:
			(icon.material as ShaderMaterial).set_shader_parameter("ink", _info.accent)
	_copies.visible = copies > 0 and copies_needed > 0
	_copies.text = "%d/%d" % [mini(copies, copies_needed), copies_needed]
	_copies.tooltip_text = RemakeText.t("Copies: %d/%d") % [copies, copies_needed]
	preview.modulate.a = 0.0 if _preview_pending else 0.65 if disabled else 1.0
	upgrade_ready = copies_needed > 0 and copies + 1 >= copies_needed
	if (upgrade_ready or cost >= 4) and _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = preload("res://src/ui/arena_upgrade_glow.gdshader")
	if _glow:
		_glow.set_shader_parameter("glow_color",GOLD if upgrade_ready else cost_accent(cost))
		_glow.set_shader_parameter("glow_strength",0.65 if upgrade_ready else 0.4)
	if is_instance_valid(preview.creature): preview.creature.material = _glow if upgrade_ready or cost >= 4 else null
	_copies.text += " ↑" if upgrade_ready else ""
	_copies.add_theme_color_override("font_color", SNOW_ACCENT if upgrade_ready else PAPER)


static func cost_accent(price: int) -> Color:
	# The price stays explicit. Color only helps scan the available price bands.
	if price <= 1: return PAPER
	if price == 2: return Color("8fc8ee")
	if price == 3: return Color("a6d5b0")
	if price == 4: return Color("c9afe6")
	return GOLD


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


static func ink_icon(icon: TextureRect, color: Color, edge := Color("222222")) -> void:
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://src/ui/arena_icon_ink.gdshader")
	ink.set_shader_parameter("ink", color)
	ink.set_shader_parameter("edge_ink", edge)
	icon.material = ink
	icon.modulate = Color.WHITE


static func tribe_icon(icon: TextureRect, key: String, represented: bool) -> void:
	var color: Color = TRIBE_COLORS.get(key, PAPER)
	if icon.material == null: ink_icon(icon, PAPER)
	var ink := icon.material as ShaderMaterial
	ink.set_shader_parameter("ink", color if represented else MUTED)
	ink.set_shader_parameter("glow", 0.9 if represented else 0.0)
	ink.set_shader_parameter("glow_ink", color)


static func outline(control: Control) -> void:
	control.add_theme_color_override("font_outline_color", Color("222222"))
	control.add_theme_constant_override("outline_size", 2)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	control.add_theme_constant_override("shadow_offset_y", 1)


static func snow_ink(control: Control, color := SNOW_INK) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		control.add_theme_color_override(state, color)
	control.add_theme_font_override("font", preload("res://fonts/LiberationSans-Regular.ttf"))
	control.add_theme_color_override("font_outline_color", Color("222222"))
	control.add_theme_constant_override("outline_size", 2)
	control.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	control.add_theme_constant_override("shadow_offset_y", 0)


static func tribe_names(parent: Node, family: int, pixels := 13) -> HFlowContainer:
	var flow:=HFlowContainer.new();flow.add_theme_constant_override("h_separation",8)
	flow.add_theme_constant_override("v_separation",3);parent.add_child(flow)
	for key: String in ArenaAlliances.traits(family):
		var pair:=HBoxContainer.new();pair.add_theme_constant_override("separation",4);flow.add_child(pair)
		var icon:=TextureRect.new();icon.texture=load("res://assets/arena/alliance_"+key+".svg")
		icon.custom_minimum_size=Vector2(pixels+3,pixels+3)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pair.add_child(icon);tribe_icon(icon,key,true)
		var label:=Label.new();label.text=RemakeText.t(ArenaAlliances.RULES[key].name)
		label.add_theme_font_size_override("font_size",pixels);label.add_theme_color_override("font_color",GOLD)
		pair.add_child(label)
	return flow
