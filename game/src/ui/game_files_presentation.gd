class_name GameFilesPresentation
extends Control
## Shared presentation for the desktop and portable game-file setup screens.
## Text remains native, so it is rasterized at its displayed size. The approved
## logo and flat controls do not depend on the player's original archives.

const LOGO: Texture2D = preload("res://icon.png")
const TEXT := Color("eee5c9")
const MUTED := Color("c1b999")
const SANS: Font = preload("res://fonts/LiberationSans-Regular.ttf")
const SERIF: Font = preload("res://fonts/LiberationSerif-Regular.ttf")

var scroll: ScrollContainer
var body: VBoxContainer
var _logo: TextureRect
var _title: Label
var _choices: CampaignChoices
var _ui_scale := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("141310")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	scroll = ScrollContainer.new()
	scroll.name = "SetupScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	body = VBoxContainer.new()
	body.name = "SetupContent"
	center.add_child(body)
	theme = Theme.new()
	theme.default_font = SANS
	resized.connect(_layout)
	_layout()


func add_title(text: String) -> void:
	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_logo)
	_title = Label.new()
	_title.text = text
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_override("font", SERIF)
	_title.add_theme_color_override("font_color", TEXT)
	body.add_child(_title)


func set_choices(choices: CampaignChoices) -> void:
	_choices = choices


## Called after the host has added its controls and whenever the viewport changes.
func refresh() -> void:
	_ui_scale = -1.0
	_layout()


func _flat(fill: Color, border: Color, unit: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(1, roundi(unit)))
	style.set_corner_radius_all(maxi(1, roundi(2 * unit)))
	style.content_margin_left = 12.0 * unit
	style.content_margin_right = 12.0 * unit
	style.content_margin_top = 8.0 * unit
	style.content_margin_bottom = 8.0 * unit
	return style


func _button_style(state: String, unit: float) -> StyleBoxFlat:
	match state:
		"hover": return _flat(Color("393529"), Color("b49b65"), unit)
		"pressed", "hover_pressed": return _flat(Color("514329"), Color("dbc17e"), unit)
		"disabled": return _flat(Color("1b1b18"), Color("454235"), unit)
		_: return _flat(Color("28271f"), Color("756a4b"), unit)


func _layout() -> void:
	if scroll == null or size.x <= 0 or size.y <= 0:
		return
	var safe := Portability.safe_rect(size)
	# Match the game's 1280x720 reference while drawing fonts at their actual
	# pixel size. Small and portrait screens scroll instead of shrinking text.
	var unit := clampf(minf(safe.size.x / 1280.0, safe.size.y / 720.0), 1.0, 3.0)
	var margin := 16.0 * unit
	scroll.offset_left = safe.position.x + margin
	scroll.offset_right = -(size.x - safe.end.x + margin)
	scroll.offset_top = safe.position.y + margin
	scroll.offset_bottom = -(size.y - safe.end.y + margin)
	body.custom_minimum_size.x = minf(700.0 * unit, maxf(1.0, safe.size.x - 2.0 * margin - 14.0 * unit))
	if is_equal_approx(unit, _ui_scale):
		return
	_ui_scale = unit
	body.add_theme_constant_override("separation", roundi(9 * unit))
	theme.default_font_size = roundi(17 * unit)
	theme.set_font("font", "Button", SERIF)
	theme.set_font_size("font_size", "Button", roundi(18 * unit))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color("fff3c8"))
	theme.set_color("font_pressed_color", "Button", Color("fff3c8"))
	theme.set_color("font_hover_pressed_color", "Button", Color("fff3c8"))
	theme.set_color("font_focus_color", "Button", Color("fff3c8"))
	theme.set_color("font_disabled_color", "Button", Color("979485"))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", Color("f0d797"))
	theme.set_color("selection_color", "LineEdit", Color("77643c"))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		theme.set_stylebox(state, "Button", _button_style(state, unit))
	var focus := _flat(Color.TRANSPARENT, Color("f5d994"), unit)
	focus.set_border_width_all(maxi(2, roundi(2 * unit)))
	focus.set_expand_margin_all(-3 * unit)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "LineEdit", _flat(Color("151713"), Color("817556"), unit))
	theme.set_stylebox("focus", "LineEdit", _flat(Color("1a1c16"), Color("eed18c"), unit))
	theme.set_stylebox("read_only", "LineEdit", _flat(Color("151713"), Color("5a5546"), unit))
	theme.set_stylebox("background", "ProgressBar", _flat(Color("151713"), Color("817556"), unit))
	theme.set_stylebox("fill", "ProgressBar", _flat(Color("9a793e"), Color("d4b475"), unit))
	if _logo:
		_logo.custom_minimum_size = Vector2.ONE * 112 * unit
	if _title:
		_title.add_theme_font_size_override("font_size", roundi(31 * unit))
	if _choices:
		_choices.layout_unit_scale = unit
		_choices.add_theme_constant_override("separation", roundi(10 * unit))
		_choices._layout()
		for button: Button in _choices.buttons.values():
			button.add_theme_font_override("font", SERIF)
			button.add_theme_font_size_override("font_size", roundi(18 * unit))
			for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				button.add_theme_stylebox_override(state, _button_style(state, unit))
			button.add_theme_stylebox_override("focus", focus)
			button.add_theme_color_override("font_color", MUTED)
			button.add_theme_color_override("font_pressed_color", TEXT)
			button.add_theme_color_override("font_hover_pressed_color", TEXT)
			button.custom_minimum_size.y = 64 * unit
	_apply_control_sizes(body, unit)


func _apply_control_sizes(node: Node, unit: float) -> void:
	if node is Button:
		var button := node as Button
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Browse buttons share a row with an expanding path field. Reserve their
		# translated label width so the field cannot squeeze them into a tall,
		# one-character-wide column.
		if button.get_parent() is HBoxContainer:
			button.autowrap_mode = TextServer.AUTOWRAP_OFF
			var font := button.get_theme_font("font")
			var px := button.get_theme_font_size("font_size")
			button.custom_minimum_size.x = ceilf(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 32 * unit)
		var base := 64.0 if _choices and button in _choices.buttons.values() else 42.0
		button.custom_minimum_size.y = maxf(base * unit, TouchInput.target_pixels() if Portability.constrained() else 0.0)
	elif node is LineEdit:
		(node as LineEdit).custom_minimum_size.y = 42 * unit
	for child in node.get_children():
		_apply_control_sizes(child, unit)
