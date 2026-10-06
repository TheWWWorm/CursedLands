class_name CampaignChoices
extends BoxContainer
## The same two visible choices in the library/import screen and main menu.
signal selected(id: String)
var current := CampaignProfile.ORIGINAL
var buttons: Dictionary = {}


static func title(id: String) -> String:
	return RemakeText.t("Expansion — Lost in Astral") if id == CampaignProfile.ASTRAL else RemakeText.t("Main game — Evil Islands")


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for id: String in [CampaignProfile.ORIGINAL, CampaignProfile.ASTRAL]:
		var button := Button.new()
		button.name = id
		button.text = title(id).replace(" — ", "\n")
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 64
		style_button(button)
		button.pressed.connect(func(): choose(id); selected.emit(id))
		add_child(button)
		buttons[id] = button
	choose(current)
	resized.connect(_layout)
	_layout()


## Reuse the original Options / network plate (saveload UV 122,108–252,127)
## and Interface800's typeface and colours. Nine-slicing keeps its carved
## edges intact around the two-line titles, at any window size.
static func style_button(button: Button) -> void:
	button.add_theme_font_override("font", Interface800.font())
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Interface800.GREY)
	button.add_theme_color_override("font_hover_color", Interface800.TEXT)
	button.add_theme_color_override("font_pressed_color", Interface800.TEXT)
	button.add_theme_color_override("font_hover_pressed_color", Interface800.TEXT)
	button.add_theme_color_override("font_focus_color", Interface800.TEXT)
	button.add_theme_color_override("font_disabled_color", Interface800.GREY.darkened(0.35))
	button.add_theme_color_override("font_shadow_color", Interface800.SHADOW)
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 1)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var light := 0.65 if state == "normal" else (0.4 if state == "disabled" else 1.0)
		var texture := Interface800.tex("saveload")
		var style: StyleBox
		if texture:
			var stone := StyleBoxTexture.new()
			stone.texture = texture
			var k := texture.get_size() / 256.0
			stone.region_rect = Rect2(Vector2(122, 108) * k, Vector2(130, 19) * k)
			stone.texture_margin_left = 6 * k.x
			stone.texture_margin_right = 6 * k.x
			stone.texture_margin_top = 5 * k.y
			stone.texture_margin_bottom = 5 * k.y
			stone.modulate_color = Color(light, light, light)
			style = stone
		else:
			# First run has no original textures until the player imports data.
			var plain := StyleBoxFlat.new()
			plain.bg_color = Color(0.08, 0.09, 0.065)
			plain.border_color = Color(0.38, 0.39, 0.29) * Color(light, light, light)
			plain.set_border_width_all(3)
			style = plain
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Interface800.TEXT
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(-3)
	button.add_theme_stylebox_override("focus", focus)


func _layout() -> void:
	vertical = size.x < 500


func choose(id: String) -> void:
	current = id
	for key: String in buttons:
		buttons[key].set_pressed_no_signal(key == id)
		buttons[key].tooltip_text = RemakeText.t("Installed") if DataSwitch.installed(key) else RemakeText.t("Not installed")


func set_busy(busy: bool) -> void:
	for button: Button in buttons.values():
		button.disabled = busy
