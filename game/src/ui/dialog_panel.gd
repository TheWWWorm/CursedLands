class_name DialogPanel
extends Control
## The village screen's conversation box and topic list (the original village
## screen,: build, per-frame, left
## button, keys; phrases). In co-op every
## player sees the conversation; any player can advance it and the host is
## told when done. Layout in the 800×600 frame, stretched to the window like
## every CInterface3D rect: x · W/800, y · H/600; the font is
## sized by the width alone, so at 16:9 the box spans 18.75 %..
## 81.25 % of the width with large type (about 6 lines at 1920×1080):
## - phrase box (mode 3/4, controls 2-3): black over (155,416)-
##   (645,580), a 5 px "saveload" frame (150,411)-(650,585) (
##   strip UV u 2..180, v 254 outer .. 249 inner);
## - its ScrollText at (165,426)-(635,570): text 456 px wide
##   (x2 − x1 − 14), the scroll bar (texture
##   "Scrollbar") in x2−10..x2, shown only when the text overflows
## - topic list (mode 1, controls 0-1): black over (200,430)-
##   (600,570) in a frame (195,425)-(605,575) with a scroll bar at
##   (584,440)-(594,560) (rows: TopicList).
## Text (ScrollText): words with
## "\aC" colour codes, font 1 of CInterface3D (: "Times New
## Roman", W·0.14 tenths of a point normalised by a 75 pt probe -> 15 px em at
## 800 wide, 15 · W/800 px at any height), lines of the font's height, a space of height / 3, every line
## but a paragraph's last JUSTIFIED (the gap spread evenly between the words),
## each word drawn with a 1 px shadow. A phrase is
## "\aC ffb331" name ":\n" "\aC e4d7a7" text "\n" (#nolips phrases
## strings); the reward lines of the last
## phrase white (see _reward_lines). Phrases accumulate; the box keeps its view at the bottom
## (moves the position by the growth).
## Advance (mode 3): when the phrase's speech ends, or without a
## speech file after len·0.05 s (+1 s for the first phrase); a click
## or Space, shows the next phrase (buttons\base\click1.wav); Enter / Esc run
## the rest at once. The last phrase (mode 4) stays until a click / key closes
## the conversation. Esc on the topic list closes it.
## The camera shows the phrase's shot (DialogCamera) with the other actor out
## of view; the rest of the HUD is hidden.
## Wheel (WM_MOUSEWHEEL, the screen's → the
## controls under the pointer): the phrase box is a ScrollText (
## (165,426)-(635,570), speed 20.0), so one notch moves it 20
## units (: acc −= delta · speed / 120) while the pointer is over
## (165,426)-(625,570). The topic list's bar (
## (584,440)-(594,560)) has a zero-width wheel rect, so the wheel never
## scrolls the topics; its arrows and thumb do.
## In a network game Enter opens the chat line
## (ui/chat_line.gd) instead of skipping.
## **Approx.**: the ScrollText units are taken as 800×600 pixels (scaled);
## a font found on the system (no fonts shipped). Backspace in a network game
## clears the chat list (`GameHUD.clear_chat`).

const NAME_COLOR := Color8(0xff, 0xb3, 0x31)
const TEXT_COLOR := Color8(0xe4, 0xd7, 0xa7)
const NOLIPS_COLOR := Color8(0xa8, 0xa8, 0xa8)
const NOTE_COLOR := Color.WHITE
const SHADOW_COLOR := Color8(8, 8, 8)
const FONT_EM := 15.0
const FONT_NAMES := ["Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"]

const BOX := Rect2(155, 416, 490, 164)
const BOX_FRAME := Rect2(150, 411, 500, 174)
const TEXT_BOX := Rect2(165, 426, 470, 144)   # ScrollText (165,426)-(635,570)
const TEXT_WIDTH := 456.0
const TOPIC_BOX := Rect2(200, 430, 400, 140)
const TOPIC_FRAME := Rect2(195, 425, 410, 150)
const TOPIC_BAR := Rect2(584, 440, 10, 120)   #  (584,440)-(594,560)
const FRAME_UV := [2.0, 180.0, 254.0, 249.0]   # u0, u1, v outer, v inner (saveload)

enum { HIDDEN, TOPICS = 1, PLAYING = 3, LAST = 4 }

var hud: GameHUD
var _mode := HIDDEN
var _phrases: Array = []
var _i := 0
var _id := ""
var _brief := ""
var _cast := {}
var _hidden_units: Array = []
var _hidden_hud: Array = []
var _timer := 0.0
var _voiced := false
## Quest items the conversation shows ("#show <item> N", the original
## ): slot (N-1) % 7 is centred at 800×600 point (x, y)
## tables; slots 0-6 get a translucent black 120×120
## square (colour) in a 130×130 saveload frame, higher ones none
## and from slot 8 on the figure is translucent (drawn as
## the view's alpha). The figure is figures.res initqu<N>item with skin
## quitem%04d, (x, y, 12), turned π about x. An item stays
## until "#hide", the conversation's end or its next "#show".
const SHOW_X := [300, 500, 200, 400, 600, 75, 725]
const SHOW_Y := [300, 300, 300, 300, 300, 500, 500]
var _shows_layer: Control
var _shown := {}   # item name -> [slot, Control]
var _aimed: Dictionary = {}   # the phrase the camera frames
var _cast_sig := ""
var _topics := {}   # the topic list on show (show_topics)
var _topic_list: TopicList

# ScrollText state: items are {"w": word, "c": Color} or {"nl": true}.
var _items: Array = []
var _lines: Array = []   # [from, to, paragraph end]
var _line_h := 0
var _space := 0
var _laid_k := 0.0
var _view: Control
var _bar := Bar.new(TEXT_BOX, 20.0)
var _topic_bar := Bar.new(TOPIC_BAR, 1.0)

static var _font: SystemFont
static var _ui: Texture2D
static var _sb: Texture2D


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(FONT_NAMES)
	return _font


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_panel")   # remake: the gamepad (pad_press)
	if _ui == null and GameData.is_open():
		_ui = _flipped("saveload")
		_sb = _flipped("Scrollbar")
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_text)
	add_child(_view)
	_shows_layer = Control.new()
	_shows_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shows_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(func(): if not visible: _clear_shows())
	_shows_layer.resized.connect(_layout_shows)
	_shows_layer.draw.connect(_draw_shows)
	resized.connect(_relayout)


static func _flipped(name: String) -> Texture2D:
	var img := GameData.load_image(name)
	if img == null:
		return null
	img.flip_y()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ layout

## Scale of 800×600 interface units on each axis (: x · W/800
## y · H/600; the original stretches its 4:3 layout over a wide screen).
func _kv() -> Vector2:
	return Vector2(size.x / 800.0, size.y / 600.0)


## Font scale: CInterface3D's fonts follow the screen width.
func _k() -> float:
	return size.x / 800.0


func _p(v: Vector2) -> Vector2:
	return v * _kv()


func _r(r: Rect2) -> Rect2:
	return Rect2(_p(r.position), r.size * _kv())


func _to800(p: Vector2) -> Vector2:
	return p / _kv()


# ------------------------------------------------------------------ conversations

func show_briefing(e: Dictionary) -> void:
	_topics = {}
	if _topic_list:
		_topic_list.visible = false
	_id = String(e.get("id", ""))
	_brief = String(e.get("brief", ""))
	_phrases = e.get("phrases", [])
	_cast = e.get("cast", {})
	_i = 0
	_items.clear()
	_bar.pos = 0.0
	_bar.max_pos = 0.0
	_relayout()
	_clear_shows()
	if _shows_layer.get_parent() == null:
		get_parent().add_child(_shows_layer)
		get_parent().move_child(_shows_layer, get_index())
		_shows_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	_hide_hud(true)
	if _phrases.is_empty():
		_finish()
		return
	_show()


## An NPC's conversation list (the original): one row per entry the
## host sent (Briefings.interact) plus "goodbye" (texts.res "briefing goodbye",
## first line). Layout from the original: click rows
## at 800×600 x 210..570, y 440 + 24·i, five visible, scrolled by the bar
## (range count − 5; not by the wheel, see the header); draws each row's text
## ("string topic_prefix" + " " + title; the prefix is empty in the shipped
## texts) in a 365 × 22 rect (font 1, 1 px shadow), colour
## COLORREF (beige), the row under the mouse white; the
## list's box and scroll bar are drawn by the panel (mode 1). The NPC's name
## is not shown.
func show_topics(e: Dictionary) -> void:
	if visible and not _id.is_empty():
		return   # a conversation is running
	_id = ""
	_phrases = []
	_items.clear()
	var rows := []
	for o: Dictionary in e.get("options", []):
		rows.append(String(o.title))
	var bye := GameData.text("briefing goodbye").get_slice("\n", 0).strip_edges()
	rows.append(bye if bye else tr("Goodbye"))
	_topics = e
	if _topic_list == null:
		_topic_list = TopicList.new()
		_topic_list.picked.connect(_on_topic)
		get_parent().add_child(_topic_list)
		_topic_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().move_child(_topic_list, -1)
	_topic_list.rows = rows
	_topic_list.top = 0
	_topic_list.hover = -1
	_topic_list.visible = true
	_topic_list.queue_redraw()
	_mode = TOPICS
	visible = true
	_hide_hud(true)   # the list belongs to the dialog screen
	queue_redraw()


func _on_topic(k: int) -> void:
	if _topics.is_empty():
		return
	_click_sound()   #  case 1
	var opts: Array = _topics.get("options", [])
	var uid := int(_topics.get("uid", 0))
	_topics = {}
	_topic_list.visible = false
	visible = false
	if k >= 0 and k < opts.size():
		hud.game.issue({"t": "topic", "var": String(opts[k]["var"]), "uid": uid})


## A line from the game during the conversation ("Получено задание: …"),
## white as the original's "\aC ffffff %s %s\n" lines.
func note(text: String) -> void:
	if visible and _mode != TOPICS:
		_append(text, NOTE_COLOR)


func _show(quick := false) -> void:
	var p: Dictionary = _phrases[_i]
	if not quick:
		_aim_camera(p)
	_show_items(p.get("shows", []))
	var who := String(p.get("speaker", ""))
	var text := String(p.get("text", ""))
	_append_phrase(who, text, TEXT_COLOR if not p.get("nolips", false) else NOLIPS_COLOR)
	_mode = LAST if _i >= _phrases.size() - 1 else PLAYING
	if _mode == LAST and not _skipping:
		_reward_lines()
	# the phrase string's length (5 + name + 2 + 5 + text + 1) · 0.05 s.
	_timer = (13 + who.length() + text.length()) * 0.05 + (1.0 if _i == 0 else 0.0)
	_voiced = false
	if GameSound.instance:
		GameSound.instance.stop_speech()
		#  stops the speech at each phrase
		# the skip (param 1) jumps past the mp3 start, the last phrase included.
		if not quick and not _skipping:
			_voiced = GameSound.instance.speech(_brief, int(p.get("n", _i + 1)))


func _next() -> void:
	if not _topics.is_empty() or _mode == TOPICS:
		return   # pick a topic (or Goodbye)
	if _i >= _phrases.size() - 1:
		_finish()
		return
	_i += 1
	_show()


## Enter / Esc: (1) until the last phrase: the
## voice playing stops and the skipped phrases, the last one too, are silent.
func _skip() -> void:
	if _mode != PLAYING:
		return
	_skipping = true
	while _i < _phrases.size() - 1:
		_i += 1
		_show(_i < _phrases.size() - 1)
	_skipping = false


var _skipping := false

##  at the last phrase (no "#phrase" after it): the briefing
## record's (briefings.db) rewards as white lines
## "\aC ffffff %s %d" / " %s %s" / " %s"
## the labels "string brief_*": experience (> 0, brief_get_exp, whole
## number), money (> 0, brief_get_money), each given item (
## brief_get_item + its name), each taken item (brief_lost_item)
## each given quest (brief_get_quest) and completed one (
## brief_complete_quest) whose var has three parts and whose «quest <id>»
## text exists (its first line), then "string brief_get_specials_<n>" when
##  (bonus) > 0. Only when the last phrase was reached normally — the
## skip ((1)) appends nothing. Approx.: the network game's extra
## lost-item lines are left out — for a briefing whose name starts with "z"
## (case-insensitive), adds one "brief_lost_item" line per item
## of player 0's list whose class is 0x14 (which items
## that class covers is not traced; nothing removes them); an item stack
## ("id[3]") is one line.
func _reward_lines() -> void:
	var row := GameData.db.find("briefings", _brief)
	if row.is_empty():
		row = SideQuests.briefing_row(_brief)   # a quest map's briefing (quest.reg)
	if row.is_empty():
		return
	var exp := float(row.get("unknown", 0.0))
	if exp > 0.0:
		_note2("brief_get_exp", str(int(exp)))
	var money := float(row.get("money", 0.0))
	if money > 0.0:
		_note2("brief_get_money", str(int(money)))
	for spec in Briefings._list(row.get("give_items")):
		if not spec.begins_with("prototype."):
			_note2("brief_get_item", _item_name(spec))
	for spec in Briefings._list(row.get("take_items")):
		_note2("brief_lost_item", _item_name(spec))
	for field in ["give_quests", "give_quests2"]:
		for q in Briefings._list(row.get(field)):
			var parts := q.split(".")
			if parts.size() != 3:
				continue
			if not SideQuests.quest_doc(parts[2]).strip_edges().is_empty():
				_note2("brief_get_quest" if field == "give_quests" else "brief_complete_quest",
					JournalPanel._parse(parts[2]).title)
	var bonus := int(row.get("bonus", 0))
	if bonus > 0:
		_append(_label("brief_get_specials_%d" % bonus), NOTE_COLOR)


func _label(key: String) -> String:
	return GameData.text("string " + key).strip_edges()


func _note2(key: String, value: String) -> void:
	_append("%s %s" % [_label(key), value], NOTE_COLOR)


func _item_name(spec: String) -> String:
	var id: String = Items.from_spec(spec)[0]
	if Items.info(id).table in ["quest_items", ""]:
		var t := GameData.text("qitem " + id)
		if t.is_empty():
			t = GameData.text("questitem " + id)
		return t.get_slice("\n", 0) if t else id
	return Items.title(id)


func _finish() -> void:
	_mode = HIDDEN
	visible = false
	if GameSound.instance:
		GameSound.instance.stop_speech()
	hud.game.issue({"t": "dialog_done", "id": _id})


func _click_sound() -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\base\\click1.wav")


# ------------------------------------------------------------------ ScrollText

func _append_phrase(who: String, text: String, color: Color) -> void:
	var grow_from := _bar.max_pos
	if who:
		_add_words(who + ":", NAME_COLOR)
		_items.append({"nl": true})
	_add_text(text, color)
	_items.append({"nl": true})
	_reflow(grow_from)


func _append(text: String, color: Color) -> void:
	var grow_from := _bar.max_pos
	_add_text(text, color)
	_items.append({"nl": true})
	_reflow(grow_from)


func _add_text(text: String, color: Color) -> void:
	var paras := text.split("\n")
	for j in paras.size():
		if j > 0:
			_items.append({"nl": true})
		_add_words(paras[j], color)


func _add_words(s: String, color: Color) -> void:
	for w in s.replace("\t", " ").split(" ", false):
		_items.append({"w": w, "c": color})


## the view moves by what the text grew (stays at the bottom).
func _reflow(grow_from: float) -> void:
	_layout_text()
	_bar.set_pos(_bar.pos + _bar.max_pos - grow_from)
	_view.queue_redraw()
	queue_redraw()


func _relayout() -> void:
	if _view == null:
		return
	var k := _k()
	var r := _r(TEXT_BOX)
	_view.position = r.position
	_view.size = Vector2(TEXT_WIDTH * k, r.size.y)
	if size.x + size.y * 1e-4 != _laid_k:
		var at_end := _bar.pos >= _bar.max_pos
		var f := _bar.pos / maxf(1.0, _bar.max_pos)
		_layout_text()
		_bar.set_pos(_bar.max_pos if at_end else f * _bar.max_pos)
	_view.queue_redraw()
	queue_redraw()


## a word goes on the line while the words so far plus a space
## each stay under the width (the line's first word always does); a newline
## item ends the line (a paragraph's last line is not justified).
func _layout_text() -> void:
	var k := _k()
	_laid_k = size.x + size.y * 1e-4
	var fs := _font_size()
	var f := font()
	_line_h = int(round(f.get_height(fs)))
	_space = _line_h / 3
	var width := TEXT_WIDTH * k
	_lines.clear()
	var i := 0
	var n := _items.size()
	while i < n:
		var start := i
		var acc := 0.0
		var par_end := false
		while i < n:
			var it: Dictionary = _items[i]
			if it.has("nl"):
				i += 1
				par_end = true
				break
			if not it.has("px"):
				it["px"] = 0.0
			it.px = f.get_string_size(String(it.w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			acc += it.px + _space
			if acc >= width and i > start:
				break
			i += 1
		_lines.append([start, i, par_end])
	_bar.max_pos = maxf(0.0, _lines.size() * _line_h - TEXT_BOX.size.y * _kv().y)
	_bar.unit = 1.0 / _kv().y   # px <-> 800×600-space units (vertical) for the speed and thumb


func _font_size() -> int:
	return maxi(6, int(round(FONT_EM * _k())))


## words placed with the justified gap ((width − words) / (n − 1)
## integer) or a plain space, each with a 1 px shadow.
func _draw_text() -> void:
	if _mode == TOPICS or _lines.is_empty():
		return
	var f := font()
	var fs := _font_size()
	var width := _view.size.x
	var asc := f.get_ascent(fs)
	var sh := maxf(1.0, round(_k()))
	var y := -_bar.pos
	for ln: Array in _lines:
		if y + _line_h < 0:
			y += _line_h
			continue
		if y > _view.size.y:
			break
		var words := []
		var sum := 0.0
		for j in range(ln[0], ln[1]):
			var it: Dictionary = _items[j]
			if it.has("w"):
				words.append(it)
				sum += it.px
		var gap := float(_space)
		if not ln[2] and words.size() >= 2 and ln[1] < _items.size():
			gap = floorf((width - sum) / (words.size() - 1))
		var x := 0.0
		for it: Dictionary in words:
			var s := String(it.w)
			_view.draw_string(f, Vector2(x + sh, y + asc + sh), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SHADOW_COLOR)
			_view.draw_string(f, Vector2(x, y + asc), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, it.c)
			x += it.px + gap
		y += _line_h


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _mode == TOPICS:
		draw_rect(_r(TOPIC_BOX), Color(0, 0, 0, 0x80 / 255.0))
		_frame(TOPIC_FRAME)
		if _topic_list:
			_topic_bar.max_pos = maxf(0.0, _topic_list.rows.size() - 5)
			_topic_bar.pos = _topic_list.top
			_draw_bar(_topic_bar)
	elif _mode != HIDDEN:
		draw_rect(_r(BOX), Color(0, 0, 0, 0xa0 / 255.0))
		_frame(BOX_FRAME)
		_draw_bar(_bar)


## four mitred strips, the texture's v 254 on the outer edge and
## 249 on the inner one, u 2..180 along each side.
func _frame(r: Rect2, w := 5.0, ci: CanvasItem = null, kv := Vector2.ZERO) -> void:
	if ci == null:
		ci = self
	if kv == Vector2.ZERO:
		kv = _kv()
	if _ui == null:
		ci.draw_rect(Rect2(r.position * kv, r.size * kv).grow(-w * 0.5 * kv.y), Color(0.55, 0.5, 0.4), false, w * kv.y)
		return
	var o := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var ii := [o[0] + Vector2(w, w), o[1] + Vector2(-w, w), o[2] - Vector2(w, w), o[3] + Vector2(w, -w)]
	var s := _ui.get_size()
	var uo0 := Vector2(FRAME_UV[0], FRAME_UV[2]) / s
	var uo1 := Vector2(FRAME_UV[1], FRAME_UV[2]) / s
	var ui0 := Vector2(FRAME_UV[0], FRAME_UV[3]) / s
	var ui1 := Vector2(FRAME_UV[1], FRAME_UV[3]) / s
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for side in 4:
		var a: int = side
		var b: int = (side + 1) % 4
		var pts := PackedVector2Array([o[a] * kv, o[b] * kv, ii[b] * kv, ii[a] * kv])
		ci.draw_polygon(pts, white, PackedVector2Array([uo0, uo1, ui1, ui0]), _ui)


##  sprites of texture "Scrollbar" (UVs in 256ths of the 64² map):
## track (x2−8,y1+4)-(x2−2,y2−4) UV 8,4-32,252; up (x2−10,y1)-(x2,y1+12) UV
## 40,176-80,128 (the down arrow upside down); down (x2−10,y2−12)-(x2,y2) UV
## 40,128-80,176; thumb 10×28 UV 40,8-80,120 centred at (x2−5, y1 + 26 + pos ·
## (h − 52) / max). Hidden while nothing scrolls.
func _draw_bar(b: Bar) -> void:
	paint_bar(self, b, _r)


## The same on another canvas item, `to_px` mapping an 800×600 Rect2.
static func paint_bar(ci: CanvasItem, b: Bar, to_px: Callable) -> void:
	if b.max_pos <= 0.0:
		return
	if _sb == null and GameData.is_open():
		_sb = _flipped("Scrollbar")
	if _sb == null:
		ci.draw_rect(to_px.call(b.track_rect()), Color(0.45, 0.32, 0.15))
		ci.draw_rect(to_px.call(b.thumb_rect()), Color(0.9, 0.6, 0.2))
		return
	var q := _sb.get_size().x / 256.0
	ci.draw_texture_rect_region(_sb, to_px.call(b.track_rect()), Rect2(Vector2(8, 4) * q, Vector2(24, 248) * q))
	var up: Rect2 = to_px.call(b.up_rect())
	ci.draw_texture_rect_region(_sb, Rect2(up.position, Vector2(up.size.x, -up.size.y)), Rect2(Vector2(40, 128) * q, Vector2(40, 48) * q))
	ci.draw_texture_rect_region(_sb, to_px.call(b.down_rect()), Rect2(Vector2(40, 128) * q, Vector2(40, 48) * q))
	ci.draw_texture_rect_region(_sb, to_px.call(b.thumb_rect()), Rect2(Vector2(40, 8) * q, Vector2(40, 112) * q))


# ------------------------------------------------------------------ input

func _active_bar() -> Bar:
	return _topic_bar if _mode == TOPICS else _bar


func _gui_input(e: InputEvent) -> void:
	if not visible:
		return
	var b := _active_bar()
	if e is InputEventMouseButton:
		var p := _to800(e.position)
		if e.button_index == MOUSE_BUTTON_LEFT:
			if not e.pressed:
				b.held = 0
			elif b.max_pos > 0.0 and b.press(p):
				pass
			elif _mode == PLAYING or _mode == LAST:   #  case 3 / 4
				_click_sound()
				_next()
			accept_event()
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# 20 units a notch, over the phrase box only.
			if _mode != TOPICS and Rect2(165, 426, 460, 144).has_point(p):
				var d := -1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				_bar.set_pos(_bar.pos + d * 20.0 / _bar.unit)   # 800×600 units, as hold()
				_view.queue_redraw()
				queue_redraw()
			accept_event()
	elif e is InputEventMouseMotion and b.held == 1:
		b.drag(_to800(e.position))
		_after_scroll()
		accept_event()


## Remake, the gamepad (PadUI): in the topic list the D-pad moves the lit
## row (scrolling the five shown) and A picks it; during the talk A is the
## click / Space (next phrase) and Y Enter's skip; B is Esc (the key bridge).
func pad_press(action: String, phase: String) -> bool:
	if _mode == TOPICS and _topic_list and _topic_list.visible:
		if action in ["up", "down"] and phase in ["down", "repeat"]:
			var n := _topic_list.rows.size()
			var h := _topic_list.hover
			h = 0 if h < 0 else clampi(h + (1 if action == "down" else -1), 0, n - 1)
			_topic_list.hover = h
			if h < _topic_list.top:
				_set_topic_top(h)
			elif h >= _topic_list.top + 5:
				_set_topic_top(h - 4)
			_topic_bar.set_pos(_topic_list.top)
			_topic_list.queue_redraw()
			queue_redraw()
			return true
		if action == "interact":
			if phase == "down" and _topic_list.hover >= 0:
				_on_topic(_topic_list.hover)
			elif phase == "down":
				_topic_list.hover = 0
				_topic_list.queue_redraw()
			return true
		return false
	if action == "interact" and (_mode == PLAYING or _mode == LAST):
		if phase == "down":
			_click_sound()
			_next()
		return true
	if action == "pause" and phase == "down":
		if _mode == PLAYING:
			_click_sound()
			_skip()
		elif _mode == LAST:
			_click_sound()
			_finish()
		return true
	return false


func pad_right_stick(v: Vector2, dt: float) -> bool:
	if _mode == TOPICS or absf(v.y) < 0.3:
		return true
	_bar.set_pos(_bar.pos + v.y * 300.0 * dt / _bar.unit)
	_view.queue_redraw()
	queue_redraw()
	return true


func pad_targets() -> Array:
	return []


func _set_topic_top(t: int) -> void:
	if _topic_list:
		_topic_list.top = clampi(t, 0, maxi(0, _topic_list.rows.size() - 5))
		_topic_list.queue_redraw()


func _after_scroll() -> void:
	if _mode == TOPICS:
		_set_topic_top(int(round(_topic_bar.pos)))
	_view.queue_redraw()
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_SPACE:
			if _mode == PLAYING or _mode == LAST:
				_click_sound()
				_next()
		KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
			if e.keycode != KEY_ESCAPE and hud.game.session.online:
				hud.chat_line.open()   # Enter opens the chat in a network game
			elif _mode == PLAYING:
				_click_sound()
				_skip()
			elif _mode == LAST:
				_click_sound()
				_finish()
			elif _mode == TOPICS and e.keycode == KEY_ESCAPE:
				_topics = {}
				_topic_list.visible = false
				visible = false
		KEY_BACKSPACE:   # network only: clears the chat list
			if not hud.game.session.online:
				return
			hud.clear_chat()
		_:
			return
	get_viewport().set_input_as_handled()


## Re-frames the phrase while an actor still walks to its spot; held scroll
## arrows; the phrase's timer / speech end.
func _process(dt: float) -> void:
	if not visible or hud == null:
		return
	var b := _active_bar()
	if b.held >= 2:
		if b.hold(dt):
			_after_scroll()
	if _mode == PLAYING:
		if _voiced:
			if GameSound.instance == null or not GameSound.instance.speaking():
				_next()
		else:
			_timer -= dt
			if _timer < 0.0:
				_next()
	if _aimed.is_empty() or hud.game.world == null:
		return
	if _cast_signature() != _cast_sig:
		_aim_camera(_aimed)


## A scroll bar (the original "Scrollbar" class) over the owner's
## 800×600 rect; positions in the owner's units (text: pixels, topics: rows).
class Bar:
	var rect: Rect2
	var speed := 1.0   # dt · speed · 16 units per second
	var max_pos := 0.0
	var pos := 0.0
	var unit := 1.0    # owner units -> 800-space units
	var held := 0      # 1 thumb, 2 up, 3 down
	var _grab := 0.0
	var _acc := 0.0

	func _init(r: Rect2, s: float) -> void:
		rect = r
		speed = s

	func up_rect() -> Rect2:
		return Rect2(rect.end.x - 10, rect.position.y, 10, 12)

	func down_rect() -> Rect2:
		return Rect2(rect.end.x - 10, rect.end.y - 12, 10, 12)

	func track_rect() -> Rect2:
		return Rect2(rect.end.x - 8, rect.position.y + 4, 6, rect.size.y - 8)

	func thumb_y() -> float:
		var y0 := rect.position.y + 26.0
		var y1 := rect.end.y - 26.0
		return y0 + (floorf(pos) * (y1 - y0) / max_pos if max_pos > 0.0 else 0.0)

	func thumb_rect() -> Rect2:
		return Rect2(rect.end.x - 10, thumb_y() - 14, 10, 28)

	func set_pos(v: float) -> void:
		pos = clampf(v, 0.0, max_pos)

	func press(p: Vector2) -> bool:
		if thumb_rect().has_point(p):
			held = 1
			_grab = p.y - thumb_y()
		elif up_rect().has_point(p):
			held = 2
		elif down_rect().has_point(p):
			held = 3
		else:
			return false
		_acc = 0.0
		return true

	func drag(p: Vector2) -> void:
		var y0 := rect.position.y + 26.0
		var y1 := rect.end.y - 26.0
		set_pos((p.y - _grab - y0) / (y1 - y0) * max_pos)

	func hold(dt: float) -> bool:
		_acc += dt * speed * 16.0 / unit * (-1.0 if held == 2 else 1.0)
		var step := int(_acc)
		if step == 0:
			return false
		_acc -= step
		set_pos(pos + step)
		return true


class TopicList extends Control:
	signal picked(index: int)
	const TEXT := Color8(0xe4, 0xd7, 0xa7)   # COLORREF
	const HOVER := Color.WHITE
	var rows: Array = []
	var top := 0
	var hover := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _k() -> float:
		return size.x / 800.0   # fonts follow the width

	func _row_rect(i: int) -> Rect2:
		var kx := size.x / 800.0
		var ky := size.y / 600.0
		return Rect2(210.0 * kx, (440.0 + 24.0 * i) * ky, 360.0 * kx, 24.0 * ky)

	func _index_at(p: Vector2) -> int:
		for i in 5:
			if top + i < rows.size() and _row_rect(i).has_point(p):
				return top + i
		return -1

	func _has_point(p: Vector2) -> bool:
		var r := _row_rect(0).merge(_row_rect(4))
		return visible and r.has_point(p)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var h := _index_at(e.position)
			if h != hover:
				hover = h
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed:
			match e.button_index:
				MOUSE_BUTTON_LEFT:
					var i := _index_at(e.position)
					if i >= 0:
						picked.emit(i)
				# No wheel: the topic bar's wheel rect is empty (see the header).
			accept_event()

	func _redraw_all() -> void:
		queue_redraw()
		for c in get_parent().get_children():
			if c is DialogPanel:
				c.queue_redraw()

	func _draw() -> void:
		var f := DialogPanel.font()
		var k := _k()
		var fs := maxi(6, int(round(DialogPanel.FONT_EM * k)))
		var sh := maxf(1.0, round(k))
		for i in 5:
			var n := top + i
			if n >= rows.size():
				break
			# the surface at (200,430)-(600,570), row i
			# at (15, 12 + 24·i)-(380, 34 + 24·i), DT_LEFT | DT_TOP (format 0).
			var ky := size.y / 600.0
			var rr := Rect2(215.0 * k, (442.0 + 24.0 * i) * ky, 365.0 * k, 22.0 * ky)
			var y := rr.position.y + f.get_ascent(fs)
			var s := " " + String(rows[n])
			draw_string(f, Vector2(rr.position.x + sh, y + sh), s, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x, fs, DialogPanel.SHADOW_COLOR)
			draw_string(f, Vector2(rr.position.x, y), s, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x, fs, HOVER if n == hover else TEXT)


# ------------------------------------------------------------------ quest items

func _clear_shows() -> void:
	for n in _shown:
		_shown[n][1].queue_free()
	_shown.clear()
	_shows_layer.queue_redraw()


func _show_items(shows: Array) -> void:
	for sh: Array in shows:
		var name := String(sh[0])
		var slot := int(sh[1]) - 1
		if _shown.has(name):
			_shown[name][1].queue_free()
			_shown.erase(name)
		if slot < 0 or Items.info(name).table != "quest_items" or Items.look(name).is_empty():
			continue
		var v := ItemView.new()
		v.quest = true
		if slot > 7:
			v.modulate = Color(1, 1, 1, 0x82 / 255.0)
		_shows_layer.add_child(v)
		_shown[name] = [slot, v]
	_layout_shows()


## slots 0–6 get a black square (x ± 60, y ± 60, colour
## ) and a saveload frame (x ± 65, 5 wide
##  with the dialog box's UVs) under the figure.
func _draw_shows() -> void:
	var kv := _shows_layer.size / Vector2(800.0, 600.0)
	for n in _shown:
		var slot: int = _shown[n][0]
		if slot >= 7:
			continue
		var c := Vector2(SHOW_X[slot], SHOW_Y[slot])
		_shows_layer.draw_rect(Rect2((c - Vector2(60, 60)) * kv, Vector2(120, 120) * kv), Color(0, 0, 0, 0xa0 / 255.0))
		_frame(Rect2(c - Vector2(65, 65), Vector2(130, 130)), 5.0, _shows_layer, kv)


## The figure: (x, y, 12) at scale 1, turned π about x, in the
## original's perspective (ItemView.screen_at); the view is not clipped.
func _layout_shows() -> void:
	var vs := _shows_layer.size
	var kv := vs / Vector2(800.0, 600.0)   # stretched like every interface rect
	for n in _shown:
		var slot: int = _shown[n][0]
		var c := Vector2(SHOW_X[slot % 7], SHOW_Y[slot % 7])
		var v: ItemView = _shown[n][1]
		v.size = Vector2(240, 240) * kv
		v.position = c * kv - v.size * 0.5
		v.unit_px = kv.y * 400.0 / ItemView.K / 12.0
		v.screen_at = Vector3(c.x, c.y, 12.0)
		v.item = "~"
		v.show_item(n)
	_shows_layer.queue_redraw()


# ------------------------------------------------------------------ camera / HUD

func _cast_signature() -> String:
	var out := ""
	for k in ["a", "b", "c"]:
		var u: GameUnit = hud.game.world.units.get(int(_cast.get(k, -1)))
		if u:
			out += "%.1f,%.1f;" % [u.pos.x, u.pos.y]
	return out


func _aim_camera(p: Dictionary) -> void:
	_aimed = p
	var g := hud.game
	_cast_sig = _cast_signature() if g.world else ""
	if g.world == null or g.rig == null:
		return
	_show_units()
	var s := DialogCamera.shot(g.world, _cast, p, _i == 0)
	if s.size() < 2:
		return
	g.rig.hold_view(EISpace.pos(s[0].x, s[0].y, s[0].z), EISpace.pos(s[1].x, s[1].y, s[1].z))
	for k: String in (s[2] if s.size() > 2 else []):
		var u: GameUnit = g.world.units.get(int(_cast.get(k, -1)))
		if u and u.visible:
			u.visible = false
			_hidden_units.append(u)


func _show_units() -> void:
	for u in _hidden_units:
		if is_instance_valid(u):
			u.visible = true
	_hidden_units.clear()


func _hide_hud(on: bool) -> void:
	if on:
		# HUD controls live inside SafeArea. Hide the surrounding widgets,
		# never a container that also contains this conversation.
		var siblings := get_parent().get_children()
		if get_parent() != hud:
			siblings.append_array(hud.get_children())
		for c in siblings:
			if c == self or c == _shows_layer or c == _topic_list or c.is_ancestor_of(self):
				continue
			if c is CanvasItem and c.visible and not c is MoviePlayer:
				c.visible = false
				_hidden_hud.append(c)
	else:
		for c in _hidden_hud:
			if is_instance_valid(c):
				c.visible = true
		_hidden_hud.clear()


func _end_view() -> void:
	_aimed = {}
	_show_units()
	_hide_hud(false)
	if hud.game.rig:
		hud.game.rig.release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and hud:
		_mode = HIDDEN
		if _topic_list:
			_topic_list.visible = false
		_end_view()
