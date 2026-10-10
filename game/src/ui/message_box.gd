class_name MessageBox
extends Interface800
## the original's message box ((parent, title key, message key, result
## base, flags,...); build, click, keys)
## with ✓ and ✗ (flags 3), in 800×600 units:
## - T = height of the title (font 2, wordbreak, 370 wide), M = height of the
##   message (font 2); H = T + M + 60, top = (550 − H) / 2, bottom = top + H;
## - panel (200,top)-(600,bottom), saveload frame (195,top−5)-(605,bottom+5)
## - title (215,top+15) centred, COLORREF; message (215,top+T+30)
## DrawText format = the constructor's last argument (1 =
##   DT_CENTER for the Load screen's boxes) | DT_WORDBREAK;
## - ✓ (263,bottom+26)-(337,bottom+74) UV 81,2-155,50 tip 50100, ✗ (463,..)-(537,..)
##   UV 160,2-234,50 tip 50101; ✓ buttons\messbox\ok.wav, ✗ cancel.wav;
##   Enter / Esc the same;
## - flags 1 (✓ only, e.g. «no_disc_space»): ✓ at (363,bottom+26)-(437,..);
##   Esc still answers ✗ (base | 2)
## - a message key may be a printf format, e.g.
##   «key_already_mapped_msg» with the key and the action it has.
## The screen it opens over is not drawn while it is up: (box, 1, 1)
## over a screen that is not the game alone takes no new capture, and
##  draws only the frozen frame and the top screen — the parent
## hides itself while `MessageBox.is_up(box)`.

signal answered(yes: bool)
## Remake: with `esc_closes`, Esc closes the box without an answer.
signal dismissed

var title := ""
var message := ""
var ok_only := false   # flags 1
var esc_closes := false   # remake: Esc dismisses instead of answering ✗


static func ask(parent: Node, title_key: String, message_key: String, args: Array = [], ok_alone := false) -> MessageBox:
	var b := MessageBox.new()
	b.title = GameData.text("string " + title_key).strip_edges()
	b.message = GameData.text("string " + message_key).strip_edges()
	if not args.is_empty():
		b.message = b.message % args
	b.ok_only = ok_alone
	parent.add_child(b)
	return b


## `b` is untyped: a typed MessageBox parameter rejects a freed box before
## is_instance_valid can test it.
static func is_up(b) -> bool:
	return is_instance_valid(b) and b is MessageBox and not (b as MessageBox).is_queued_for_deletion()


func _ready() -> void:
	add_to_group("pad_panel")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	resized.connect(queue_redraw)


func _rects() -> Dictionary:
	var t: float = wrap_text(title, 370, 2).size() * line_h(2)
	var m: float = wrap_text(message, 370, 2).size() * line_h(2)
	var h := t + m + 60.0
	var top := floorf((550.0 - h) / 2.0)
	return {"t": t, "top": top, "bottom": top + h,
		"ok": Rect2(363 if ok_only else 263, top + h + 26, 74, 48), "cancel": Rect2(463, top + h + 26, 74, 48)}


func _draw() -> void:
	var r := _rects()
	var ui := tex("saveload")
	panel(Rect2(200, r.top, 400, r.bottom - r.top))
	text_block(Rect2(215, r.top + 15, 370, 200), title, 2, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	text_block(Rect2(215, r.top + r.t + 30, 370, 400), message, 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_action(ui, r.ok, true)
	if not ok_only:
		_action(ui, r.cancel, false)


## Keep decisions visible even when original UI artwork is unavailable.
## The same rectangles serve artwork, fallback drawing and touch input.
func _action(ui: Texture2D, r: Rect2, yes: bool) -> void:
	if ui:
		sprite(ui, r, [81, 2, 155, 50] if yes else [160, 2, 234, 50])
		return
	panel(r)
	var c := r.get_center()
	var points := [c + Vector2(-16, 0), c + Vector2(-4, 12), c + Vector2(18, -14)] if yes else \
		[c + Vector2(-13, -13), c + Vector2(13, 13), c + Vector2(-13, 13), c + Vector2(13, -13)]
	var col := Color(0.65, 0.85, 0.5) if yes else Color(0.95, 0.55, 0.45)
	var width := maxf(2.0, kv().y * 3.0)
	draw_line(p8(points[0]), p8(points[1]), col, width, true)
	draw_line(p8(points[1 if yes else 2]), p8(points[2 if yes else 3]), col, width, true)


func pad_targets() -> Array:
	var r := _rects()
	var targets := [{"id": "ok", "rect": pad_rect(r.ok)}]
	if not ok_only:
		targets.append({"id": "cancel", "rect": pad_rect(r.cancel)})
	return targets


func _get_tooltip(at: Vector2) -> String:
	var r := _rects()
	var p := to800(at)
	if (r.ok as Rect2).has_point(p):
		return GameData.text("tip 50100").strip_edges()
	if not ok_only and (r.cancel as Rect2).has_point(p):
		return GameData.text("tip 50101").strip_edges()
	return ""


func _answer(yes: bool) -> void:
	sound("messbox\\ok" if yes else "messbox\\cancel")
	answered.emit(yes)
	queue_free()


func _dismiss() -> void:
	sound("messbox\\cancel")
	dismissed.emit()
	queue_free()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var r := _rects()
		var p := to800(e.position)
		if (r.ok as Rect2).has_point(p):
			_answer(true)
		elif not ok_only and (r.cancel as Rect2).has_point(p):
			_answer(false)
	if e is InputEventMouseButton:
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER: _answer(true)
		KEY_ESCAPE:
			if esc_closes:
				_dismiss()
			else:
				_answer(false)
		_: return
	get_viewport().set_input_as_handled()
