class_name GameOverNotice
extends Interface800
## Remake (option "sp_death_notice"): the single-player game over shown at the
## main hero's death as a small notice at the top centre of the field screen,
## below the message log (180..620 × 0..100) and between the unit panel (left)
## and the minimap (right), instead of the original's modal box at the next
## zone change. The game is not paused. In the HUD's 800×600 units scaled by
## the window height and centred horizontally (as MessageLog, PartyFaces):
## - the message box's look: a panel in a 5 px saveload frame
## - texts.res «game_over» (font 2) and «game_over_msg» (font 1)
##   centred, as the original box;
## - three buttons drawn as the Options screen's group buttons (saveload UV
##   122,108-252,127, label font 1; 0.6 at rest, 1.0 under the pointer):
##   Load, Main menu (the original box's ✓ / ✗) and Hide.
## Only the panel takes the mouse; the field around it plays on.
## Remake (gamepad): a "pad_panel" (PadUI): the D-pad snaps to the buttons,
## A presses one, B hides the notice; while it shows, the field does not take
## the pad (GameHUD._panel_open).

signal chosen(what: String)   # "load", "menu" or "hide"

const X := 245.0
const W := 310.0
const TOP := 112.0
const BTN_W := 92.0
const BTN_H := 20.0
const BUTTONS := ["load", "menu", "hide"]
const LABELS := {"load": "Load", "menu": "Main menu", "hide": "Hide"}
const TIPS := {"load": "Load a saved game.", "menu": "End this game and go to the main menu.",
	"hide": "Hide this notice and keep watching. Leaving the area still ends the game."}

var title := ""
var message := ""
## An optional line under the message (GameHUD.show_death_notice).
var hint := ""
## True while the notice still applies (the main hero dead); a load or a
## revival hides it.
var still_dead: Callable
var _hover := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("pad_panel")
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	title = GameData.text("string game_over").strip_edges()
	message = GameData.text("string game_over_msg").strip_edges()
	resized.connect(queue_redraw)


# Height-scaled and centred like the field screen's other widgets.
func _k() -> float:
	return maxf(size.y, 1.0) / 600.0


func kv() -> Vector2:
	return Vector2(_k(), _k())


func _origin() -> Vector2:
	return Vector2((size.x - 800.0 * _k()) * 0.5, 0.0)


func font_px(i: int) -> int:
	return maxi(6, int(round(800.0 * _k() * FONT_EM[i])))


func _layout() -> Dictionary:
	var th := line_h(2)
	var mh := wrap_text(message, W - 20.0, 1).size() * line_h(1)
	var hh := wrap_text(hint, W - 20.0, 1).size() * line_h(1) + 2.0 if hint != "" else 0.0
	mh += hh
	var by := TOP + 6.0 + th + 2.0 + mh + 6.0
	var gap := (W - 20.0 - BTN_W * BUTTONS.size()) / (BUTTONS.size() - 1)
	var btn := {}
	for i in BUTTONS.size():
		btn[BUTTONS[i]] = Rect2(X + 10.0 + i * (BTN_W + gap), by, BTN_W, BTN_H)
	return {"th": th, "hh": hh, "hint_y": by - 6.0 - hh + 2.0, "panel": Rect2(X, TOP, W, by + BTN_H + 7.0 - TOP), "btn": btn}


func _draw() -> void:
	var l := _layout()
	var ui := tex("saveload")
	panel(l.panel)
	text_block(Rect2(X + 10.0, TOP + 6.0, W - 20.0, l.th), title, 2, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	text_block(Rect2(X + 10.0, TOP + 8.0 + l.th, W - 20.0, 200.0), message, 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	if hint != "":
		text_block(Rect2(X + 10.0, l.hint_y, W - 20.0, l.hh), hint, 1, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	for b: String in BUTTONS:
		var r: Rect2 = l.btn[b]
		var on := b == _hover
		if ui:
			sprite(ui, r, [122, 108, 252, 127], Color(1, 1, 1, 1) * (1.0 if on else 0.6))
		else:
			draw_rect(r8(r), BAR if on else PANEL)
		text(Rect2(r.position.x, r.position.y + 2.0, r.size.x, r.size.y), RemakeText.t(LABELS[b]), 1,
			TEXT if on else GREY, HORIZONTAL_ALIGNMENT_CENTER)


func _button_at(at: Vector2) -> String:
	var p := to800(at)
	var l := _layout()
	for b: String in BUTTONS:
		if (l.btn[b] as Rect2).has_point(p):
			return b
	return ""


## Only the panel (with its frame) takes the mouse.
func _has_point(point: Vector2) -> bool:
	return visible and (_layout().panel as Rect2).grow(5.0).has_point(to800(point))


func _get_tooltip(at: Vector2) -> String:
	var b := _button_at(at)
	return RemakeText.t(TIPS[b]) if b != "" else ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var b := _button_at(e.position)
		if b != _hover:
			_hover = b
			queue_redraw()
	elif e is InputEventMouseButton:
		accept_event()
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			var b := _button_at(e.position)
			if b != "":
				sound("messbox\\cancel" if b == "hide" else "messbox\\ok")
				chosen.emit(b)


func pad_targets() -> Array:
	var l := _layout()
	var out: Array = []
	for b: String in BUTTONS:
		out.append({"rect": pad_rect(l.btn[b]), "id": b})
	return out


func pad_press(a: String, phase: String) -> bool:
	if a == "cancel" and phase == "down":
		sound("messbox\\cancel")
		chosen.emit("hide")
		return true
	return false


func _process(_dt: float) -> void:
	if visible and still_dead.is_valid() and not still_dead.call():
		visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		queue_redraw()
