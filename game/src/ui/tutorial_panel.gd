class_name TutorialPanel
extends Control
## The tutorial window of the original (open, layout
## close), drawn at the original's 800×600 coordinates scaled by the
## window height (k = height / 600) and centred horizontally.
## texts.res "tutorial <id>": the window title's key, then per page "#screen",
## the page head's key, optional "#position x1 y1 x2 [rows]" and
## "#rectangle x1 y1 x2 y2" lines, "#text" and the text's key (keys in
## "tutor <key>").
##   * window (x1, y1)-(x2, y2), default (200, 50)-(600, 560); x2 − x1 at least
##     300; y2 = y1 + rows · 16 + 110 with a row count, else y1 + the text's
##     height + 110; at most 600 tall;
##   * a solid background, a 5 px frame round it (x1 − 5.. x2 + 5
##     "saveload" strip UV 2,240-180,245)
##   * header (x1, y1)-(x2, y1 + 55): the page head in (0, 8)-(w, 30) and
##     "<title> (<page>/<pages>)" in (0, 30)-(w, 50), COLORREF
##   * text (x1, y1 + 55)-(x2, y2 − 55), lines of 16 px from x 15, width
##     w − 30, COLORREF
##   * footer (x1, y2 − 55)-(x2, y2): three 50×20 buttons at y2 − 30 .. y2 − 10,
##     s = (w − 150) / 6 apart from x1 + s: previous ("saveload" UV 2,51-52,71),
##     close (UV 2,93-52,113, tip 30100), next (UV 2,72-52,92), the previous /
##     next one dimmed to 0.6 on the first / last page; above them, in
##     (0, 5)-(w / 3, 25) the previous page's head (tip 30101) and in
##     (2w / 3, 5)-(w, 25) the next page's head (tip 30102);
##   * each "#rectangle" of the page: a 5 px red frame round
##     that part of the 800×600 screen, pointing at an interface element.
## Footer middle: (0x3b) finds the first key bound to
## action 0x3b "tutorial_script"; when there is one, "string show_tutorial_key"
## + " " + its key name in (w/3, 5)-(2w/3, 25) of the footer, font 0,
## COLORREF, drawn like the page heads.
## Close (Λ) plays buttons\tutorial\ok.wav; the page arrows
## buttons\tutorial\next.wav.
## Approx.: the rectangles are moved with the widgets they point at (the HUD
## keeps its left / right / centre anchoring on wide screens: x < 200 left,
## x > 600 right, else centred; the original has no anchoring and stretches its
## 800×600 rects per axis); the font
## is the system's Times New Roman (Interface800.font) at the original's sizes —
## font 2 for the page head, 1 for the title line and body, 0 for the footer:
## 19 / 15 / 14 px at 800 (scaled by the window height here).
## Pause: pushes the window (win, 1, 0); as the
## first window over the game screen it pauses outside network games
## ((1)), undone
## when only the game is left; the remake pauses in single player while the
## window is up.

const DEFAULT := Rect2(200, 50, 400, 510)
const BG := Color8(0x21, 0x1b, 0x11)
const HEAD := Color8(0xff, 0xf5, 0x82)   # COLORREF
const BODY := Color8(0xff, 0xf9, 0xbb)   # COLORREF
const RECT_COL := Color8(0xff, 0, 0, 0x82)
const FRAME_UV := Rect2(2, 240, 178, 5)
const BTN_UV := [Rect2(2, 51, 50, 20), Rect2(2, 93, 50, 20), Rect2(2, 72, 50, 20)]   # prev, close, next
const LINE := 16.0
const FONT := 15        # CInterface3D font 1: the title line and the body
const FONT_HEAD := 19   # font 2: the page head
const FONT_FOOT := 14   # font 0: the footer lines

## Off for the test tools (main.gd --tool): tutorials do not pop up and pause
## the game; H still shows them (tools/ux_test.gd turns them back on).
static var auto_show := true
##  map tutorial id → page (interface manager), loaded
## from config\tutorial.ini at start-up and written back as
## "%s %d" lines at exit. Remake: user:, tutorial.ini, written
## whenever a screen tutorial is opened or closed.
const SEEN_FILE := "user://tutorial.ini"
static var _seen := {}
## Off for test tools: the map changes only in memory (tools/ux_test.gd).
static var persist := true
## Every screen tutorial id (callers' slot-41 ids).
const SCREEN_IDS := ["options", "camp_weapons", "camp_skills", "camp_spell_trade",
	"camp_spell_constr", "camp_item_trade", "camp_item_constr", "camp_repair",
	"quest_global_map", "quest_mission"]
static var _seen_loaded := false
var _screen_id := ""   # the screen tutorial shown (its page is kept on close)
var _pages: Array = []
var _title := ""
var _i := 0
var _win := DEFAULT   # original coordinates
var _lines := PackedStringArray()
var _atlas: Texture2D
var _paused := false
var _hover := -1


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("saveload") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)
	visibility_changed.connect(_on_visibility)


## texts.res "tutorial <id>" -> [{head, text, position, rects}], title in "title".
static func pages(id: String) -> Array:
	var out := []
	var lines := GameData.text("tutorial " + id).split("\n")
	var page := {}
	var want := ""
	var title := ""
	for raw in lines:
		var l := raw.strip_edges()
		if l.is_empty():
			continue
		if l == "#screen":
			if not page.is_empty():
				out.append(page)
			page = {"rects": []}
			want = "head"
		elif l == "#text":
			want = "text"
		elif l.begins_with("#position") or l.begins_with("#rectangle"):
			var v := Array(l.split(" ", false).slice(1)).map(func(s): return int(s))
			if l.begins_with("#position") and v.size() >= 3:
				page["position"] = v
			elif v.size() >= 4:
				page.rects.append(Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1]))
		elif l.begins_with("#"):
			continue
		elif want:
			page[want] = GameData.text("tutor " + l).strip_edges(false, true)
			want = ""
		elif page.is_empty() and title == "":
			title = GameData.text("tutor " + l).strip_edges()
	if not page.is_empty():
		out.append(page)
	out = out.filter(func(p): return String(p.get("text", "")) != "")
	for p in out:
		p["title"] = title
	return out


func show_tutorial(id: String) -> void:
	_pages = pages(id)
	_i = 0
	# Option "show_tutorial" off: the page is kept for the H key but not shown.
	if not _pages.is_empty() and GameData.option("show_tutorial") and auto_show:
		_show()


## A screen's first-visit tutorial ((0), called by the screen's
## build or at the end of its slide-; the id comes from the screen's
## slot 41, e.g. "options" for the Options screen): shown when
## the option "show_tutorial" is on and the id was not in the map yet; the
## id is entered with page 0 before the option is looked at, so a screen
## visited with the option off does not show it later either. On close
##  the page shown is stored for it.
## `forced` ((1)): the H key (keyboard.ini tutorial_script) on a
## screen that did not use the key itself (manager key-down
## screen clear) shows the screen's tutorial whatever the option and the
## map say.
func show_screen(id: String, forced := false) -> void:
	_load_seen()
	if not auto_show and not forced:   # test tools
		return
	var known := _seen.has(id)
	if not known:   # entered before the option is looked
		_seen[id] = 0
		_save_seen()
	if not forced and (known or not GameData.option("show_tutorial")):
		return
	var p := pages(id)
	if p.is_empty():
		return
	_screen_id = id
	_pages = p
	_i = 0
	_show()


static func seen(id: String) -> bool:
	_load_seen()
	return _seen.has(id)


static func _load_seen() -> void:
	if _seen_loaded:
		return
	_seen_loaded = true
	var f := FileAccess.open(SEEN_FILE, FileAccess.READ)
	if f == null:
		return
	for line in f.get_as_text().split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2:
			_seen[parts[0]] = int(parts[1])


## Test tools: the screen tutorials taken as seen (in memory only).
static func mark_all_seen() -> void:
	_load_seen()
	persist = false
	for id: String in SCREEN_IDS:
		_seen[id] = 0


static func forget(id: String) -> void:
	_load_seen()
	_seen.erase(id)


static func _save_seen() -> void:
	if not persist:
		return
	var f := FileAccess.open(SEEN_FILE, FileAccess.WRITE)
	if f == null:
		return
	var out := ""
	for k: String in _seen:
		out += "%s %d\r\n" % [k, int(_seen[k])]
	f.store_string(out)


## H on a screen with its own tutorial (e.g. the global map's "global_map"):
## shown even when the option "show_tutorial" is off.
func show_help(id: String) -> void:
	var p := pages(id)
	if not p.is_empty():
		_pages = p
		show_last()


## H key: the last tutorial again.
func show_last() -> void:
	if not _pages.is_empty():
		_i = 0
		_show()


func close() -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\tutorial\\ok.wav")
	if _screen_id != "":
		_seen[_screen_id] = _i
		_save_seen()
		_screen_id = ""
	visible = false


func _show() -> void:
	if _i >= _pages.size():
		visible = false
		return
	_i = clampi(_i, 0, _pages.size() - 1)
	_layout()
	visible = true
	queue_redraw()


# ------------------------------------------------------------------ layout

func _k() -> float:
	return get_viewport_rect().size.y / 600.0


## Exe point -> screen, centred horizontally.
func _p(v: Vector2) -> Vector2:
	var k := _k()
	return Vector2((v.x - 400.0) * k + get_viewport_rect().size.x * 0.5, v.y * k)


func _r(r: Rect2) -> Rect2:
	return Rect2(_p(r.position), r.size * _k())


## A HUD rectangle: left / right widgets stay at their screen edge.
func _hud_rect(r: Rect2) -> Rect2:
	var k := _k()
	var w := get_viewport_rect().size.x
	var c := r.get_center().x
	var x := r.position.x * k if c < 200.0 else w - (800.0 - r.position.x) * k if c > 600.0 else _p(r.position).x
	return Rect2(x, r.position.y * k, r.size.x * k, r.size.y * k)


func _font() -> Font:
	return Interface800.font()   # Times New Roman, as CInterface3D's fonts


func _layout() -> void:
	var p: Dictionary = _pages[_i]
	var pos: Array = p.get("position", [])
	var x1 := DEFAULT.position.x
	var y1 := DEFAULT.position.y
	var x2 := DEFAULT.end.x
	var rows := -1
	if pos.size() >= 3:
		x1 = pos[0]
		y1 = pos[1]
		x2 = pos[2]
		if pos.size() >= 4:
			rows = pos[3]
	if x2 - x1 < 300:
		x2 = x1 + 300
	var w := x2 - x1
	_lines = _wrap(String(p.get("text", "")), w - 30.0)
	var y2: float
	if rows >= 0:
		y2 = y1 + rows * LINE + 110
	else:
		y2 = y1 + _lines.size() * LINE + 110
	if y2 - y1 > 600:
		y2 = y1 + 600
	_win = Rect2(x1, y1, w, y2 - y1)


## Word wrap in original pixels (the font measured at k = 1).
func _wrap(t: String, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var f := _font()
	for para in t.split("\n"):
		var line := ""
		var lead := para.length() - para.lstrip(" ").length()
		var words := para.strip_edges().split(" ", false)
		line = " ".repeat(lead)
		var first := true
		for wd in words:
			var cand := line + ("" if first else " ") + wd
			if not first and f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x > width:
				out.append(line)
				line = wd
			else:
				line = cand
			first = false
		out.append(line)
	return out


## Footer buttons in original coordinates: 0 previous, 1 close, 2 next.
func _button_rect(i: int) -> Rect2:
	var s := floorf((_win.size.x - 150.0) / 6.0)
	var x := _win.position.x + s + i * (2.0 * s + 50.0)
	return Rect2(x, _win.end.y - 30.0, 50.0, 20.0)


func _label_rect(i: int) -> Rect2:
	var w := _win.size.x
	var y := _win.end.y - 55.0 + 5.0
	return Rect2(_win.position.x, y, w / 3.0, 20.0) if i == 0 else Rect2(_win.position.x + 2.0 * w / 3.0, y, w / 3.0, 20.0)


func _enabled(i: int) -> bool:
	match i:
		0: return _i > 0
		2: return _i < _pages.size() - 1
	return true


func _hit(at: Vector2) -> int:
	var k := _k()
	for i in 3:
		if _r(_button_rect(i)).has_point(at):
			return i
	if _i > 0 and _r(_label_rect(0)).has_point(at):
		return 10
	if _i < _pages.size() - 1 and _r(_label_rect(1)).has_point(at):
		return 12
	return -1


# ------------------------------------------------------------------ input

func _has_point(at: Vector2) -> bool:
	return visible and _r(_win.grow(5)).has_point(at)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _hit(e.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		match _hit(e.position):
			0, 10:
				if _i > 0:
					_i -= 1
					_page_sound()
					_show()
			2, 12:
				if _i < _pages.size() - 1:
					_i += 1
					_page_sound()
					_show()
			1:
				close()
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _get_tooltip(at: Vector2) -> String:
	var tip := {1: 30100, 10: 30101, 12: 30102}.get(_hit(at), 0) as int
	return GameData.text("tip %d" % tip).strip_edges() if tip else ""


## The close button's centre on screen (tests).
func close_point() -> Vector2:
	return _r(_button_rect(1)).get_center()


func _online() -> bool:
	var hud := get_parent() as GameHUD
	return hud == null or hud.game == null or hud.game.session == null or hud.game.session.online


## A movie that paused the tree before the window opened unpauses it when it
## ends; the window then takes the pause over.
func _process(_dt: float) -> void:
	if visible and not _paused and not get_tree().paused and not _online():
		get_tree().paused = true
		_paused = true


func _on_visibility() -> void:
	# Single player: the world stands still while the window is up.
	if not is_inside_tree():
		return
	if visible and not _online() and not get_tree().paused:
		get_tree().paused = true
		_paused = true
	elif not visible and _paused:
		_paused = false
		get_tree().paused = false


func _exit_tree() -> void:
	if _paused:
		get_tree().paused = false
		_paused = false


# ------------------------------------------------------------------ drawing

func _region(dst: Rect2, uv: Rect2, mod := Color.WHITE) -> void:
	if _atlas:
		draw_texture_rect_region(_atlas, dst, uv, mod)


func _strip(from: Vector2, to: Vector2, width: float) -> void:
	var a := _p(from)
	var b := _p(to)
	var d := (b - a).normalized().orthogonal() * width * _k() * 0.5
	if _atlas == null:
		draw_line(a, b, Color(0.6, 0.45, 0.25), width * _k())
		return
	var s := _atlas.get_size()
	var uv := FRAME_UV
	draw_primitive(PackedVector2Array([a - d, b - d, b + d, a + d]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s, Vector2(uv.position.x, uv.end.y) / s]), _atlas)


func _text(r: Rect2, s: String, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, size := FONT) -> void:
	var k := _k()
	var f := _font()
	var fs := int(round(size * k))
	var sr := _r(r)
	var y := sr.position.y + (sr.size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	draw_string(f, Vector2(sr.position.x + k, y + k), s, align, sr.size.x, fs, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(sr.position.x, y), s, align, sr.size.x, fs, col)


func _draw() -> void:
	if _pages.is_empty():
		return
	var p: Dictionary = _pages[_i]
	var k := _k()
	# Red frames round the interface parts the page talks about.
	for r: Rect2 in p.get("rects", []):
		draw_rect(_hud_rect(r).grow(-2.5 * k), RECT_COL, false, 5.0 * k)
	var w := _win
	draw_rect(_r(w), BG)
	var x1 := w.position.x - 2.5
	var y1 := w.position.y - 2.5
	var x2 := w.end.x + 2.5
	var y2 := w.end.y + 2.5
	for seg in [[Vector2(x1 - 2.5, y1), Vector2(x2 + 2.5, y1)], [Vector2(x1 - 2.5, y2), Vector2(x2 + 2.5, y2)],
			[Vector2(x1, y1), Vector2(x1, y2)], [Vector2(x2, y1), Vector2(x2, y2)]]:
		_strip(seg[0], seg[1], 5.0)
	var ww := w.size.x
	_text(Rect2(w.position.x, w.position.y + 8, ww, 22), String(p.get("head", "")), HEAD, HORIZONTAL_ALIGNMENT_CENTER, FONT_HEAD)
	_text(Rect2(w.position.x, w.position.y + 30, ww, 20), "%s (%d/%d)" % [p.get("title", ""), _i + 1, _pages.size()], HEAD,
		HORIZONTAL_ALIGNMENT_CENTER)
	var y := w.position.y + 55.0
	var bottom := w.end.y - 55.0
	for line in _lines:
		if y + LINE > bottom + 0.5:
			break
		_text(Rect2(w.position.x + 15, y, ww - 30, LINE), line, BODY)
		y += LINE
	for i in 3:
		var mod := Color.WHITE if _enabled(i) else Color(0.6, 0.6, 0.6)
		if _hover == i and _enabled(i):
			mod = Color(1.15, 1.1, 0.95)
		_region(_r(_button_rect(i)), BTN_UV[i], mod)
	if _i > 0:
		_text(_label_rect(0), String(_pages[_i - 1].get("head", "")), HEAD if _hover != 10 else Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT, FONT_FOOT)
	if _i < _pages.size() - 1:
		_text(_label_rect(1), String(_pages[_i + 1].get("head", "")), HEAD if _hover != 12 else Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT, FONT_FOOT)
	var keys := EIKeymap.keys_for("tutorial_script")
	if not keys.is_empty():
		_text(Rect2(w.position.x + ww / 3.0, w.end.y - 55.0 + 5.0, ww / 3.0, 20.0),
			GameData.text("string show_tutorial_key").strip_edges() + " " + keys[0], HEAD,
			HORIZONTAL_ALIGNMENT_LEFT, FONT_FOOT)


func _page_sound() -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\tutorial\\next.wav")
