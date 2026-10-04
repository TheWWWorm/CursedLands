class_name DifficultyPanel
extends Interface800
## The New Game difficulty box of the original (main menu board 0,:
## a message box ("option_difficulty", "", 3, 1) with
## s: build, click, keys
## ), in 800×600 units stretched to the window:
## - T = height of «string option_difficulty» (font 2, wordbreak, 370 wide),
##   D = height of «tip option_difficulty» (font 1, 370 wide); H = T + D + 108,
##   top = (550 − H) / 2, bottom = top + H, R = top + T + 30;
## - panel (200,top)-(600,bottom) in the 5 px saveload frame
## - title (215,top+15)-(585,..) font 2 centred, COLORREF
## - checkboxes (400−w,R)-(421−w,R+21) easy and (400−w,R+24)-(421−w,R+45) hard,
##   saveload UV 209,55-230,76 (checked: u − 23), labels «string difficulty_easy /
##   _hard» at (430−w, R / R+24) font 2 (the remake centres them on the box), w = ((width easy + width hard) / 2 + 30) / 2;
## - the tip text from (215, top+T+93), font 1, left, wordbreak
## - ✓ (263,bottom+26)-(337,bottom+74) UV 81,2-155,50 tip 50100, ✗ (463,..)-(537,..)
##   UV 160,2-234,50 tip 50101.
## Hard (Normal, 0) is always checked first. A box click picks it (no sound); ✓ /
## Enter stores the choice as the Difficulty Level (messbox\ok.wav, result
## the intro and the new campaign); ✗ / Esc closes (messbox\cancel.wav).

signal accepted(level: int)
signal cancelled

var level := 0      # 1 easy (Novice), 0 hard (Normal)
var _dim: Interface800.Backdrop
var _lay := {}


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_dim = Interface800.dim_layer()
	add_child(_dim)
	resized.connect(queue_redraw)


func open() -> void:
	level = 0
	_dim.capture()   # the frame, frozen and greyed
	visible = true
	queue_redraw()


func _layout() -> Dictionary:
	var title := _t("string option_difficulty", "Difficulty level")
	var desc := GameData.text("tip option_difficulty").strip_edges()
	var t: float = wrap_text(title, 370, 2).size() * line_h(2)
	var d: float = wrap_text(desc, 370, 1).size() * line_h(1) if desc else 0.0
	var h := t + d + 108.0
	var top := floorf((550.0 - h) / 2.0)
	var easy := _t("string difficulty_easy", "Novice")
	var hard := _t("string difficulty_hard", "Normal")
	var w := floorf((floorf((text_width(easy, 2) + text_width(hard, 2)) / 2.0) + 30.0) / 2.0)
	var r := top + t + 30.0
	return {"title": title, "desc": desc, "t": t, "top": top, "bottom": top + h, "r": r, "w": w,
		"easy": easy, "hard": hard,
		"ok": Rect2(263, top + h + 26, 74, 48), "cancel": Rect2(463, top + h + 26, 74, 48),
		"box_easy": Rect2(400 - w, r, 21, 21), "box_hard": Rect2(400 - w, r + 24, 21, 21)}


func _draw() -> void:
	_lay = _layout()
	var L := _lay
	var ui := tex("saveload")
	panel(Rect2(200, L.top, 400, L.bottom - L.top))
	text_block(Rect2(215, L.top + 15, 370, 200), L.title, 2, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	for i in 2:
		var box: Rect2 = L.box_easy if i == 0 else L.box_hard
		var on := (level == 1) == (i == 0)
		var du := -23 if on else 0
		sprite(ui, box, [209 + du, 55, 230 + du, 76])
		# The original draws from the box's top (no DT_VCENTER), which centres the
		# 19 px Times line on the 21 px box only at 4:3; the remake's fonts
		# follow the width and the boxes the height, so the label is centred
		# on the box by its own line box instead.
		text_vc(Rect2(430 - L.w, box.position.y, 200, box.size.y), L.easy if i == 0 else L.hard, 2)
	if L.desc:
		text_block(Rect2(215, L.top + L.t + 93, 370, 300), L.desc, 1)
	sprite(ui, L.ok, [81, 2, 155, 50])
	sprite(ui, L.cancel, [160, 2, 234, 50])


##  order: 0 ✓, 1 ✗, 2 easy box, 3 hard box.
func _hit(p: Vector2) -> String:
	if _lay.is_empty():
		_lay = _layout()
	for k in ["ok", "cancel", "box_easy", "box_hard"]:
		if (_lay[k] as Rect2).has_point(p):
			return k
	return ""


func _get_tooltip(at: Vector2) -> String:
	match _hit(to800(at)):
		"ok": return GameData.text("tip 50100").strip_edges()
		"cancel": return GameData.text("tip 50101").strip_edges()
	return ""


func _accept() -> void:
	sound("messbox\\ok")
	visible = false
	accepted.emit(level)


func _cancel() -> void:
	sound("messbox\\cancel")
	visible = false
	cancelled.emit()


func _gui_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		match _hit(to800(e.position)):
			"ok": _accept()
			"cancel": _cancel()
			"box_easy":
				level = 1
				queue_redraw()
			"box_hard":
				level = 0
				queue_redraw()
	if e is InputEventMouseButton:
		accept_event()


## Enter = ✓, Esc = ✗.
func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER: _accept()
		KEY_ESCAPE: _cancel()
		_: return
	get_viewport().set_input_as_handled()


## A "string <id>" text; missing from texts.res, the original's gives
## the id itself (the German texts.res has no difficulty_easy / _hard /
## option_difficulty). `fallback` only without game data (tools).
static func _t(key: String, fallback: String) -> String:
	if GameData.texts == null:
		return fallback
	var t := GameData.text(key).strip_edges()
	return t if t else key.trim_prefix("string ")
