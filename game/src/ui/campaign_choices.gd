class_name CampaignChoices
extends BoxContainer
## The same two visible choices in the library/import screen and main menu.
signal selected(id: String)
var current := CampaignProfile.ORIGINAL
var layout_unit_scale := 1.0
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


## Reuse the original Options / network rim and camp stone surface, with
## Interface800's typeface and colours. The large stone tile keeps its grain
## at any button width; the carved rim is drawn once around the whole face.
class StonePlate extends StyleBox:
	# Options makes scaled style duplicates; retain both layers when copied.
	@export_storage var face: StyleBoxTexture
	@export_storage var rim: StyleBoxTexture
	func _draw(canvas_item: RID, rect: Rect2) -> void:
		# Source margins are texels; destination margins are UI units. An HD
		# atlas must not turn a 7-unit border into a 28-unit border and consume
		# the whole button. Draw the full-resolution sources at logical size.
		var k := rim.texture.get_size() / 256.0
		var l := rim.texture_margin_left / k.x
		var r := rim.texture_margin_right / k.x
		var t := rim.texture_margin_top / k.y
		var b := rim.texture_margin_bottom / k.y
		var inner := rect.grow_individual(-l, -t, -r, -b)
		_tile(canvas_item, face.texture, inner, face.region_rect, face.modulate_color)
		var dx := [rect.position.x, inner.position.x, inner.end.x, rect.end.x]
		var dy := [rect.position.y, inner.position.y, inner.end.y, rect.end.y]
		var uv := rim.region_rect
		var sx := [uv.position.x, uv.position.x + rim.texture_margin_left, uv.end.x - rim.texture_margin_right, uv.end.x]
		var sy := [uv.position.y, uv.position.y + rim.texture_margin_top, uv.end.y - rim.texture_margin_bottom, uv.end.y]
		for y in 3:
			for x in 3:
				if x == 1 and y == 1: continue
				# The source's side strip is only six logical pixels high.
				# Repeat it at native density instead of stretching it over the button.
				_tile(canvas_item, rim.texture, Rect2(dx[x], dy[y], dx[x+1]-dx[x], dy[y+1]-dy[y]),
					Rect2(sx[x], sy[y], sx[x+1]-sx[x], sy[y+1]-sy[y]), rim.modulate_color)

	func _tile(canvas_item: RID, texture: Texture2D, dest: Rect2, source: Rect2, tint: Color) -> void:
		var tile := source.size * 256.0 / texture.get_size()
		if tile.x <= 0 or tile.y <= 0: return
		for y in maxi(0, ceili(dest.size.y / tile.y)):
			for x in maxi(0, ceili(dest.size.x / tile.x)):
				var offset := Vector2(x, y) * tile
				var size := tile.min(dest.size - offset)
				texture.draw_rect_region(canvas_item, Rect2(dest.position + offset, size),
					Rect2(source.position, source.size * size / tile), tint)

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
			stone.texture_margin_left = 12 * k.x
			stone.texture_margin_right = 11 * k.x
			stone.texture_margin_top = 7 * k.y
			stone.texture_margin_bottom = 6 * k.y
			# Repeat the stone at its source scale. Stretching the tiny centre
			# of this original plate blurs it across wide settings buttons.
			stone.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			stone.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			stone.modulate_color = Color(light, light, light)
			style = stone
			var surface := Interface800.tex("campinfo")
			if surface:
				stone.draw_center = false
				var face := StyleBoxTexture.new()
				face.texture = surface
				face.region_rect = Rect2(Vector2(14, 14) * surface.get_size() / 256.0, Vector2(100, 100) * surface.get_size() / 256.0)
				face.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
				face.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
				face.modulate_color = stone.modulate_color
				var plate := StonePlate.new()
				plate.face = face
				plate.rim = stone
				style = plate
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
	vertical = size.x < 500 * layout_unit_scale


func choose(id: String) -> void:
	current = id
	for key: String in buttons:
		buttons[key].set_pressed_no_signal(key == id)
		buttons[key].tooltip_text = RemakeText.t("Installed") if DataSwitch.installed(key) else RemakeText.t("Not installed")


func set_busy(busy: bool) -> void:
	for button: Button in buttons.values():
		button.disabled = busy
