class_name ChatLine
extends LineEdit
## Co-op chat input (NetStatus.say). As the original's chat object (
## ): the game HUD's key handler (and the camp's
## village and trade screens') opens
## it with Enter in a network game
## (1). The edit line is an 800×600 surface at (10,573)-(790,590)
## ((parent, 10, 0x23d, 0x316, 0x24e)); draws the
## text in white with a caret line, no frame or background. Its keys
## Enter sends a non-empty line and closes, Esc closes
## Backspace / Delete / Home / End / arrows edit; accepts a
## character while the line is under 200 characters and 0x30c px wide.
## **Approx.**: the remake keeps NetStatus.CHAT_MAX (120) as the limit; the
## original's Backspace in the game view (no chat open) clears the chat object's own
## 12-line list; the remake shows chat lines
## the HUD text window instead (see NetStatus), so that key is not ported.

var game: Game


func _ready() -> void:
	visible = false
	max_length = NetStatus.CHAT_MAX
	add_theme_color_override("font_color", Color.WHITE)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "focus", "read_only"]:
		add_theme_stylebox_override(st, empty)
	add_theme_font_override("font", DialogPanel.font())
	text_submitted.connect(_send)
	focus_exited.connect(func(): visible = false)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var k := get_viewport_rect().size.y / 600.0
	var cx := get_viewport_rect().size.x * 0.5
	position = Vector2(cx - 390.0 * k, 573.0 * k)   # 800×600 (10,573)-(790,590), centred
	size = Vector2(780.0 * k, 17.0 * k)
	add_theme_font_size_override("font_size", int(round(13.0 * k)))


func open() -> void:
	if game == null or not game.session.online:
		return
	_place()
	text = ""
	move_to_front()   # over the camp screen too
	visible = true
	grab_focus()


func _send(t: String) -> void:
	game.session.net.say(t)
	text = ""
	release_focus()
	visible = false


func _gui_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		text = ""
		release_focus()
		visible = false
		accept_event()
