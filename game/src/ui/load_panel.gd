class_name LoadPanel
extends Interface800
## the original's Load / Save screen (one class, s, mode
## 0 Load, 1 Save; build, text, preview
## click, double click, keys
## characters, ✓, load
## save, delete, list
## box results, update), in 800×600 units stretched
## to the window:
## - the escMenu signpost (unmoco1) with its "load" + "loadlabel" boards
##   ("save" + "savelabel" in Save mode), turned π/2, depth 4.8; opened from
##   the Esc menu it slides in over 0.5 s, y = 700 − 150e (Load) or
##   700 − 80e (Save); the main menu opens Load without it, at y 550;
## - panels in 5 px saveload frames: list (100,100)-(390,500)
##   preview (410,100)-(700,320), info (410,340)-(700,500);
## - 16 rows (108,108+24k)-(370,132+24k): name (112,111+24k)-(290,132+24k) left,
##   date «%d/%m, %H:%M» (290,..)-(365,..) right, font 1; the selected
##   row's bar; scroll bar (108,108)-(384,492), speed 1, range
##   n − 16, moving the view only;
## - preview: the save's 256×192 shot stretched over (410,100)-(700,320);
## - info: allod, zone, «Day  N,  h:mm» from (440,360) every 24; the save's file
##   name (440,460)-(680,485) right;
## - ✓ (163,526)-(237,574) UV 81,2-155,50 tip 60101 (Save mode 60100), Delete
##   (363,526)-(437,574) UV 2,2-76,50 tip 60102, ✗ (563,526)-(637,574) UV
##   160,2-234,50 tip 60103.
## Save mode: the first row is the save about to be made (directory "save<n+1>",
## the game's time, allod and zone, its default name, no date; its preview the
## frame taken when the game switched to its menus) and is selected; it cannot
## be deleted. The selected row's name is an edit field: the caret is a 1 px
## line 0xff b3 31 (COLORREF) from the row's top to 3 px above its
## bottom, after the first `caret` characters, drawn while that text is
## narrower than 178. The first Backspace / Delete / character on a row clears
## its name; Left / Right / Home / End first take the row's name; a character
## is inserted at the caret while the name is under 60 characters and stays
## under 178 wide (font 1). Quick / auto saves keep their names. ✓ / Enter /
## double click on the first row saves at once, on another row asks
## «overwrite» / «overwrite_msg» first; the name saved is the edited text, else
## the row's name (the first row: empty = the default name).
## Input: row click selects (buttons\save\select.wav), double click / Enter /
## ✓ loads or saves (messbox\ok.wav), Up / Down ±1, PgUp / PgDn ±16
## (select.wav), Esc / ✗ closes (messbox\cancel.wav); Delete (buttons\save\
## delete.wav) asks «delete» / «delete_msg» first. The Delete key only edits.
## Scroll bar: the
## thumb drags (keeping where it was grabbed), held arrows scroll dt · 16 rows
## per second, the wheel scrolls one row per notch (delta / 120) over the list
## area (108,108)-(374,492); clicks on the track do nothing.
## While the board slides , the text widget (over
## (100,100)-(700,500), the screen's first widget [0]) is hidden
## (0) in the draw: names, dates, info and caret
## appear when the slide ends; panels, frames, bar, preview and buttons slide
## in with the board. While a message box is up the screen is not drawn (only
## the frozen frame and the box, see MessageBox).
##  first checks the free disk space: GetDiskFreeSpaceExA's bytes
## available to the caller on the game folder's drive (0 = the
## call failed, no check) against 1 000 000 + the sizes of the files in
## saves\current\ (the running game's working copy); short
## «no_disc_space» / «no_disc_space_msg» (base, ✓ only), and ✓ / Enter
##  closes the screen without saving; Esc only closes
## the box. Remake: the drive of user://saves and the size of the campaign
## state the save would write (CampaignState.to_dict serialised) stand in.
## Remake: saves are SaveInfo slots (user://saves/<slot>.sav + .info.sav +
## .shot.png).

signal load_requested(slot: String)
signal save_requested(slot: String, name: String, frame: Image)
signal closed
## Set when the screen closes because a save is being loaded (
## sends no result then; ✗ / Esc close it).
var loading := false

const ROWS := 16
const OK_RECT := Rect2(163, 526, 74, 48)
const DELETE_RECT := Rect2(363, 526, 74, 48)
const CANCEL_RECT := Rect2(563, 526, 74, 48)
const BAR_RECT := Rect2(108, 108, 276, 384)
const PREVIEW := Rect2(410, 100, 290, 220)
const NAME_X := 112.0
const NAME_W := 178.0          # 0xb2: the name column (12..190 of the text widget)
const NAME_MAX := 60           # 0x3c characters
const CARET := Color8(0xff, 0xb3, 0x31)   # CPen(PS_SOLID, 1)
const SPEED := 1.0             # the scroll bar's speed (argument)

var save_mode := false
var saves: Array = []     # SaveInfo, newest first (Save mode: the new entry first)
var sel := -1
var top := 0
var _shot: Texture2D
var _boards := {}         # false (Load) / true (Save) -> InterfaceBoard
var _dim: Interface800.Backdrop
var _box: MessageBox
var _frame: Image         # the frame the game was captured in (Save mode preview)
var _drag := false
var _grab := 0.0
var _hold := 0
var _acc := 0.0           # scroll bar: fractional rows (arrows, wheel)
var _slide := 1.0         # slide-in time, 0..1
var _edit := ""           #  of the screen: the edit field's text
var _edited := false
var _caret := 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_dim = Interface800.dim_layer()
	add_child(_dim)
	for save: bool in [false, true]:
		var parts := PackedStringArray(["save", "savelabel"] if save else ["load", "loadlabel"])
		var b := InterfaceBoard.create("unmoco1", "escmenu00", "escmenu00labels", parts,
			PI * 0.5, Vector3(400, 550, 4.8))
		b.show_behind_parent = true
		b.visible = false
		add_child(b)
		_boards[save] = b
	resized.connect(queue_redraw)


## Load (`save` false) or Save. `frame`: the frame captured when the game
## switched to its menus (the backdrop and the new save's shot); without it
## the screen captures the current one. `fresh`: the Save mode's new entry
## (SaveInfo.make_fresh). `slide`: opened from the Esc menu.
func open(save := false, frame: Image = null, slide := false, fresh: SaveInfo = null) -> void:
	save_mode = save and fresh != null
	loading = false
	_frame = frame
	_refresh_list(fresh)
	top = 0
	if frame:
		_dim.use(frame)
	else:
		_dim.capture()   # the frame, frozen and greyed
	for k: bool in _boards:
		_boards[k].visible = k == save_mode
	_slide = 0.0 if slide else 1.0
	hide_text = slide
	_place_board()
	visible = true
	# Load selects the newest save (none: −1), Save the new entry.
	_select(0 if not saves.is_empty() else -1)


## the saves newest first, the new entry ahead of them in Save mode.
func _refresh_list(fresh: SaveInfo = null) -> void:
	if fresh == null and save_mode and not saves.is_empty() and saves[0].fresh:
		fresh = saves[0]
	saves = SaveInfo.list()
	if save_mode and fresh:
		saves.insert(0, fresh)


func _close() -> void:
	visible = false
	_drag = false
	_hold = 0
	_acc = 0.0
	closed.emit()


func _max_top() -> int:
	return maxi(0, saves.size() - ROWS)


## clamp, keep the row in view, take its name into the edit
## field, reload the preview.
func _select(i: int) -> void:
	sel = clampi(i, 0, saves.size() - 1) if not saves.is_empty() else -1
	if sel >= 0:
		if sel >= top + ROWS:
			top = sel - ROWS + 1
		if sel < top:
			top = sel
		_edited = false
		_edit = (saves[sel] as SaveInfo).display_name()
		_caret = _edit.length()
	_shot = (saves[sel] as SaveInfo).shot() if sel >= 0 and not saves[sel].error else null
	queue_redraw()


##  the board placement: y = 700 − (150 | 80) · e, e the
## ease-in-out of t (2t² below ½, else 1 − 2(1 − t)²).
func _place_board() -> void:
	var t := clampf(_slide, 0.0, 1.0)
	var e := 2.0 * t * t if t < 0.5 else 1.0 - 2.0 * (1.0 - t) * (1.0 - t)
	var b: InterfaceBoard = _boards[save_mode]
	b.place(Vector3(400, 700.0 - (80.0 if save_mode else 150.0) * e, 4.8))


func _editable() -> bool:
	return save_mode and sel >= 0 and not (saves[sel] as SaveInfo).is_protected()


func _draw() -> void:
	_boards[save_mode].visible = visible and not MessageBox.is_up(_box)
	if MessageBox.is_up(_box):
		return   # the frozen frame and the box only
	var ui := tex("saveload")
	panel(Rect2(100, 100, 290, 400))
	panel(Rect2(410, 100, 290, 220))
	panel(Rect2(410, 340, 290, 160))
	if sel >= top and sel < top + ROWS:
		draw_rect(r8(Rect2(108, 108 + 24 * (sel - top), 262, 24)), BAR)
	for k in ROWS:
		var i := top + k
		if i >= saves.size():
			break
		var s: SaveInfo = saves[i]
		var row_y := 111.0 + 24 * k
		var name := _edit if i == sel and save_mode and _edited else s.display_name()
		text(Rect2(NAME_X, row_y, NAME_W, 21), name, 1)
		if i == sel and _editable() and not hide_text:
			_draw_caret(row_y)
		if not s.fresh:
			text(Rect2(290, row_y, 75, 21), s.date_text(), 1, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	vbar(BAR_RECT, top, _max_top())
	if _shot:
		draw_texture_rect(_shot, r8(PREVIEW), false)
	if sel >= 0 and not saves[sel].error:
		var s: SaveInfo = saves[sel]
		if s.zone:
			text(Rect2(440, 360, 250, 24), s.allod_text(), 1)
			text(Rect2(440, 384, 250, 24), s.zone_text(), 1)
			text(Rect2(440, 408, 250, 24), s.day_text(), 1)
		text(Rect2(440, 460, 240, 25), s.slot, 1, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	sprite(ui, OK_RECT, [81, 2, 155, 50])
	sprite(ui, DELETE_RECT, [2, 2, 76, 50])
	sprite(ui, CANCEL_RECT, [160, 2, 234, 50])


## the caret after the first `caret` characters of the edit text
## (row rect (12,11)-(190,32) of the text widget), only while that is narrower
## than the name column; LineTo from the row's top to its bottom − 3.
func _draw_caret(row_y: float) -> void:
	_caret = clampi(_caret, 0, _edit.length())
	var w := text_width(_edit.substr(0, _caret), 1)
	if w >= NAME_W:
		return
	var x := NAME_X + w
	draw_line(p8(Vector2(x, row_y)), p8(Vector2(x, row_y + 21 - 3)), CARET, 1.0)


# ------------------------------------------------------------------ input

func _hit(p: Vector2) -> Array:
	if OK_RECT.has_point(p):
		return ["ok"]
	if CANCEL_RECT.has_point(p):
		return ["cancel"]
	if DELETE_RECT.has_point(p):
		return ["delete"]
	var b := vbar_hit(BAR_RECT, top, _max_top(), p)
	if b:
		return ["bar", b]
	for k in ROWS:
		if Rect2(108, 108 + 24 * k, 262, 24).has_point(p) and top + k < saves.size():
			return ["row", top + k]
	return []


func _get_tooltip(at: Vector2) -> String:
	var h := _hit(to800(at))
	if h.is_empty():
		return ""
	match h[0]:
		"ok": return GameData.text("tip %d" % (60100 if save_mode else 60101)).strip_edges()
		"delete": return GameData.text("tip 60102").strip_edges()
		"cancel": return GameData.text("tip 60103").strip_edges()
	return ""


## Load loads; Save saves the new entry at once and asks before
## overwriting another one (message box base).
func _accept() -> void:
	if sel < 0:
		return
	if not save_mode:
		_load()
		return
	sound("messbox\\ok")
	if sel == 0:
		_save()
		return
	_box = MessageBox.ask(self, "overwrite", "overwrite_msg")
	_box.answered.connect(func(yes: bool):
		_box = null
		queue_redraw()
		if yes:
			_save())
	queue_redraw()


## a valid entry is loaded.
func _load() -> void:
	if sel < 0 or saves[sel].error:
		return
	sound("messbox\\ok")
	var slot: String = saves[sel].slot
	loading = true
	_close()
	load_requested.emit(slot)


## the name is the edited text, else the row's name (the new
## entry: empty, i.e. its default name); the shot is the frame captured when
## the game switched to its menus. Closes.
func _save() -> void:
	if sel < 0:
		return
	if not _disk_ok():
		_no_space()
		return
	var s: SaveInfo = saves[sel]
	var name := _edit if _edited else ("" if s.fresh else s.display_name())
	_close()
	save_requested.emit(s.slot, name, _frame)


##  (see above).
func _disk_ok() -> bool:
	var d := DirAccess.open("user://")
	var free := d.get_space_left() if d else 0
	return free == 0 or free >= 1000000 + _current_bytes()


func _current_bytes() -> int:
	var hud := get_parent()
	var g: Variant = hud.get("game") if hud else null
	var ses: Variant = g.get("session") if g is Object else null
	var st: Variant = ses.get("state") if ses is Object else null
	if st is Object and st.has_method("to_dict"):
		return var_to_bytes(st.to_dict()).size()
	return 0


## (…, "no_disc_space", "no_disc_space_msg", 1, 1).
func _no_space() -> void:
	_box = MessageBox.ask(self, "no_disc_space", "no_disc_space_msg", [], true)
	_box.answered.connect(func(yes: bool):
		_box = null
		if yes:
			_close()
		else:
			queue_redraw())
	queue_redraw()


func _cancel() -> void:
	sound("messbox\\cancel")
	_close()


##  (not the Save mode's new entry).
func _delete() -> void:
	if sel < 0 or (save_mode and sel == 0):
		return
	sound("save\\delete")
	_box = MessageBox.ask(self, "delete", "delete_msg")
	queue_redraw()
	_box.answered.connect(func(yes: bool):
		_box = null
		queue_redraw()
		if yes and sel >= 0:
			SaveInfo.delete(saves[sel].slot)
			_refresh_list()
			top = mini(top, _max_top())
			_select(sel))


func _gui_input(e: InputEvent) -> void:
	if not visible or is_instance_valid(_box):
		return
	if e is InputEventMouseButton:
		accept_event()
		var p := to800(e.position)
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# acc −= delta · speed / 120 over the list area.
			if e.pressed and vbar_wheel_rect(BAR_RECT).has_point(p):
				var notches: float = e.factor if e.factor > 0.0 else 1.0
				_acc -= (notches if e.button_index == MOUSE_BUTTON_WHEEL_UP else -notches) * SPEED
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if not e.pressed:
			_drag = false
			_hold = 0
			_acc = 0.0
			return
		var h := _hit(p)
		if h.is_empty():
			return
		match h[0]:
			"ok": _accept()
			"cancel": _cancel()
			"delete": _delete()
			"row":
				# another row is selected (its name
				# into the edit field); the same row keeps the edit.
				if not e.double_click:
					sound("save\\select")
				if h[1] != sel:
					_select(h[1])
				if e.double_click:
					_accept()
			"bar":
				match h[1]:
					"thumb":
						_drag = true
						_grab = p.y - vbar_y(BAR_RECT, top, _max_top())
					"up", "down":
						_hold = -1 if h[1] == "up" else 1
						_acc = 0.0
	elif e is InputEventMouseMotion and _drag:
		top = vbar_value(BAR_RECT, _max_top(), to800(e.position).y, _grab)
		queue_redraw()
		accept_event()


## a held arrow adds dt · speed · 16 rows per second; whole rows
## move the view (the wheel's too).: the slide-.
func _process(dt: float) -> void:
	if not visible:
		return
	if _slide < 1.0:
		_slide += dt / 0.5
		_place_board()
		if _slide >= 1.0:
			hide_text = false
			queue_redraw()
	if _hold != 0:
		_acc += dt * SPEED * 16.0 * _hold
	var n := 0
	while _acc >= 1.0:
		_acc -= 1.0
		n += 1
	while _acc <= -1.0:
		_acc += 1.0
		n -= 1
	if n != 0:
		top = clampi(top + n, 0, _max_top())
		queue_redraw()


##  (keys) and (characters, Save mode).
func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or is_instance_valid(_box) or not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER: _accept()
		KEY_ESCAPE: _cancel()
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			sound("save\\select")
			var d := {KEY_UP: -1, KEY_DOWN: 1, KEY_PAGEUP: -ROWS, KEY_PAGEDOWN: ROWS}[e.keycode] as int
			_select(sel + d)
		_:
			if not _edit_key(e):
				return
	get_viewport().set_input_as_handled()


## The edit field of the Save mode. Rows of quick / auto saves ignore it (the
## original edits a hidden copy there that is never shown or saved).
func _edit_key(e: InputEventKey) -> bool:
	if not save_mode:
		return false
	var editable := _editable()
	match e.keycode:
		KEY_BACKSPACE:
			if editable:
				_first_edit(true)
				if _caret > 0:
					_edit = _edit.substr(0, _caret - 1) + _edit.substr(_caret)
					_caret -= 1
		KEY_DELETE:
			if editable:
				_first_edit(true)
				if _caret < _edit.length():
					_edit = _edit.substr(0, _caret) + _edit.substr(_caret + 1)
		KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END:
			if editable:
				_first_edit(false)
				match e.keycode:
					KEY_LEFT: _caret = maxi(0, _caret - 1)
					KEY_RIGHT: _caret = mini(_edit.length(), _caret + 1)
					KEY_HOME: _caret = 0
					KEY_END: _caret = _edit.length()
		_:
			# WM_CHAR other than Backspace, Tab, Enter, Esc, skipped while the
			# interface manager's (Ctrl held: set on the key-down of scan
			# code 0x1d / 0x11d,; cleared on VK_CONTROL key-up
			# ) is set. Alt combinations reach Windows programs as
			# WM_SYSCHAR, not WM_CHAR, so they type nothing either.
			if e.unicode < 32 or e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
				return false
			if editable:
				_first_edit(true)
				if _edit.length() < NAME_MAX:
					var t := _edit.substr(0, _caret) + char(e.unicode) + _edit.substr(_caret)
					if text_width(t, 1) < NAME_W:
						_edit = t
						_caret += 1
	queue_redraw()
	return true


## The first edit of a row: a typed key clears its name, a caret key takes it.
func _first_edit(clear: bool) -> void:
	if _edited:
		return
	_edited = true
	_edit = "" if clear else (saves[sel] as SaveInfo).display_name()
	_caret = 0 if clear else _edit.length()
