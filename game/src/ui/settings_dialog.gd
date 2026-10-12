class_name SettingsDialog
extends Control
## Bounded settings surface, scaled for the display. The body scrolls while
## navigation and actions stay visible; small windows keep 44 px targets.
const INK := Interface800.TEXT
const MUTED := Interface800.GREY
const GOLD := Interface800.TEXT
var _surface: PanelContainer
var _frame: CarvedFrame
var _backdrop: Interface800.Backdrop
var dialog_body: VBoxContainer
var _preferred := Vector2(960, 720)
var _ui_scale := 1.0

func build_shell(title: String, preferred: Vector2) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_panel")
	_preferred = preferred
	theme = Theme.new()
	# Controls are scaled with the dialog. Rasterize a private font at the
	# display scale instead of magnifying the small 22 px glyph cache.
	theme.default_font = Interface800.font().duplicate()
	theme.default_font_size = 22
	for type in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit", "SpinBox", "PopupMenu"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_disabled_color", type, MUTED)
	var sample := Button.new()
	CampaignChoices.style_button(sample)
	for type in ["Button", "OptionButton", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, sample.get_theme_stylebox(state))
	sample.free()
	theme.set_stylebox("normal", "LineEdit", plate(Color(0,0,0,0.6), Color("716248"), 12))
	theme.set_stylebox("panel", "PopupMenu", plate(Color("171710"), Color("8b7953"), 10))
	theme.set_constant("v_separation", "PopupMenu", 10)
	for enabled in [false, true]:
		var icon := Image.new()
		icon.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="26"><rect x="1" y="1" width="46" height="24" rx="12" fill="%s" stroke="#a89b76" stroke-width="2"/><circle cx="%d" cy="13" r="8" fill="%s"/></svg>' % ["#756031" if enabled else "#25251f", 35 if enabled else 13, "#f4e6b4" if enabled else "#aaa99f"])
		var texture := ImageTexture.create_from_image(icon)
		for suffix in ["", "_disabled"]:
			theme.set_icon(("checked" if enabled else "unchecked") + suffix, "CheckButton", texture)
	theme.set_stylebox("hover", "PopupMenu", plate(Interface800.BAR, Color.TRANSPARENT, 4))
	theme.set_color("font_hover_color", "PopupMenu", INK)
	_backdrop = Interface800.dim_layer()
	add_child(_backdrop)
	_frame = CarvedFrame.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_surface = PanelContainer.new()
	var padding := StyleBoxEmpty.new()
	padding.set_content_margin_all(24)
	_surface.add_theme_stylebox_override("panel", padding)
	add_child(_surface)
	dialog_body = VBoxContainer.new()
	dialog_body.add_theme_constant_override("separation", 16)
	_surface.add_child(dialog_body)
	var heading := make_label(title, dialog_body)
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", GOLD)
	_surface.resized.connect(_center_surface)
	_surface.minimum_size_changed.connect(layout_shell.call_deferred)
	resized.connect(layout_shell)
	layout_shell()
	visible = false

static func plate(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(padding)
	return style

func layout_shell() -> void:
	if _surface == null: return
	var safe := Portability.safe_rect(size).grow(-16)
	_ui_scale = clampf(minf(safe.size.x / 1248.0, safe.size.y / 768.0), 1.0, 3.0)
	if theme.default_font is FontFile or theme.default_font is SystemFont:
		theme.default_font.oversampling = _ui_scale
	_surface.scale = Vector2.ONE * _ui_scale
	_surface.size = _preferred.min(safe.size / _ui_scale)
	_center_surface()
	_scale_popups(_surface)

func _center_surface() -> void:
	if _surface == null: return
	_surface.position = Portability.safe_rect(size).get_center() - _surface.size * _ui_scale * 0.5
	_frame.position = _surface.position
	_frame.scale = _surface.scale
	_frame.size = _surface.size
	_frame.queue_redraw()

func capture_background() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is SettingsDialog:
			_backdrop.texture = ancestor._backdrop.texture
			return
		if ancestor is OptionsPanel:
			_backdrop.texture = ancestor._dim.texture
			return
		ancestor = ancestor.get_parent()
	if not visible: _backdrop.capture()

func _scale_popups(node: Node) -> void:
	if node is OptionButton:
		# OptionButton already propagates its canvas scale to the popup.
		# Multiplying the font here again makes 4K choices three times too big.
		node.get_popup().add_theme_font_size_override("font_size", 20)
		node.get_popup().add_theme_constant_override("v_separation", 10)
	for child in node.get_children(): _scale_popups(child)

func make_label(value: String, parent: Node, muted := false) -> Label:
	var label := Label.new()
	label.text = RemakeText.t(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if muted: label.add_theme_color_override("font_color", MUTED)
	parent.add_child(label)
	return label

func make_button(value: String, parent: Node, action: Callable) -> Button:
	var button := Button.new()
	button.text = RemakeText.t(value)
	button.custom_minimum_size.y = 46
	CampaignChoices.style_button(button)
	button.add_theme_font_override("font", theme.default_font)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", plate(Color(0,0,0,0.25), Color(0.38,0.34,0.25,0.6), 16))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


class CarvedFrame extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Interface800.PANEL)
		var texture := Interface800.tex("saveload")
		if texture == null:
			draw_rect(Rect2(Vector2.ZERO,size), Color("8b7953"), false, 5)
			return
		var corners := [Vector2.ZERO, Vector2(size.x,0), size, Vector2(0,size.y)]
		var inner := [Vector2(5,5), Vector2(size.x-5,5), size-Vector2(5,5), Vector2(5,size.y-5)]
		for side in 4:
			var next := (side+1)%4
			draw_polygon(PackedVector2Array([corners[side],corners[next],inner[next],inner[side]]),
				PackedColorArray([Color.WHITE]), PackedVector2Array([Vector2(2,254)/256.0,
				Vector2(180,254)/256.0,Vector2(180,249)/256.0,Vector2(2,249)/256.0]),texture)
