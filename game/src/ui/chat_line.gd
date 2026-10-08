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
## character while the line is under 200 characters (NetStatus.CHAT_MAX) and
## 0x30c px wide; the text is font 1 in (0,0)-(0x30f,0x11) of the
## surface, which is shown only while the line is open. Rects are
## stretched per axis and the font follows the width, as Interface800.
## Backspace in the game view (line closed, = 0) clears the chat
## object's own 12-line list (ChatOverlay
## `GameHUD.clear_chat`).

const WRAP := 780.0   # 0x30c

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
	text_changed.connect(_fit)
	focus_exited.connect(func(): visible = false)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var k := Interface800.canvas_size(self) / Vector2(800.0, 600.0)
	position = Vector2(10.0, 573.0) * k   # 800×600 (10,573)-(790,590)
	size = Vector2(780.0, 17.0) * k
	add_theme_font_size_override("font_size", _fs())


func _fs() -> int:
	return maxi(6, int(round(Interface800.canvas_size(self).x * Interface800.FONT_EM[1])))


## a character is taken only while the line stays within 0x30c px.
func _fit(t: String) -> void:
	var f := get_theme_font("font")
	var lim := WRAP * Interface800.canvas_size(self).x / 800.0
	var c := caret_column
	while t.length() > 0 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs()).x > lim:
		t = t.left(t.length() - 1)
	if t != text:
		text = t
		caret_column = mini(c, t.length())


func open() -> void:
	if game == null or not game.session.multiplayer_game:
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
