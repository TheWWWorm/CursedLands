class_name MpCharPanel
extends Interface800
## the original's network character screens, one screen object in three states
## (s; build, draw, update
## click, button-up, keys
## (n) sets the state), in 800×600 units
## stretched to the window:
## - 9 selection: the main menu signpost's «Сетевая игра» board (unmoco2
##   MainMenu00, parts but03 + button03_multiplayer, π/2 · 1.2 at (400,350,8)),
##   panels (100,100)-(390,220) with the commands New / Change clan / Delete
##   / View on saveload plates (180,115+24i)-(310,134+24i), labels centred
##   (100,116+24i)-(390,136+24i) font 1 white, tips 40200..40203; the list
##   (100,240)-(390,500), ten rows (112,253+24k) font 1, the selected
##   one on the bar (110,250+24k)-(370,274+24k), scroll bar (110,250)-
##   (384,490) from eleven characters; the figure of the selected character
##   at px 555 (clip (410,100)-(700,500)) over the campm1..4
##   room cropped to (410,100)-(700,500), turned by the painted arrows
##   (455,470) / (625,470) at 2 rad/s; ✓ (163,526) tip 40100, ✗ (563,526) tip
##   40101 (back). Change clan: the box (558,110)-(695,126)
##   with "<name> | " right-aligned in (425,110)-(555,126)
##   Enter keeps it, Esc drops it; Delete asks
##   «lmp_deletepers» (deletes the file); ✓ without a character
##   shows «lmp_no_pers».
## - 10 creation (New): faces of databaseLMP.res's NPC rows
##   two strips — male (0,0)-(800,100), female (0,500)-(800,600), texture
##   InventoryM01, arrows (30,y+35) / (750,y+35) tips 40400 / 40401 —, the
##   name box (0,127)-(200,143) on the campinfo name plate (10 characters,
##   white, centred), Strength / Dexterity / Intelligence 15..35 with "−" / "+"
##   (x 140 / 160, rows 165 / 180 / 195), «Balance» 75 − sum (row 210),
##   «Height» 0..100 (row 240), the voices (title (10,305), eleven rows from
##   (20,325), 15 apart), the figure at px 400 on campm1..4 (200,100)-
##   (600,500) with the camp's arrows (300,470) / (470,470); Back (620,430)
##   40301, Cancel (680,430) 40302, Next (740,430) 40300 (dimmed until the
##   balance is 0 and the name is set); hover help in the
##   right column («lmp_points_left_desc», «lmp_pers_tall_desc»,
##   «lmp_select_voice_desc», the attributes' perk texts).
## - 11 equipment / skills / experience: the kit's weapons and belt items
##   (top row, campslots cells) and spells, one of each chosen (
##   the first of each preselected), the skills widget (as the camp's, 500
##   experience to spend), «camp_current_exp» / «camp_level_up» and the
##   spent "%+d" at (0,410..470); Back 40501 (skills reset), Cancel 40502,
##   Next 40500 → writes "<n>.mp" and goes back to 9.
## Remake: the screen opens from the Multiplayer screen's «Choose or create…»
## button (the original opens it from the main menu's multiplayer board and goes
## to the server screen with ✓); ✓ selects the character for the original
## multiplayer game (MpCharacter.selected), ✗ goes back to the co-op screen.
## **Approx.**: View (the original opens the camp screen on the character, which
## dresses it and spends its experience) shows state 11's layout with the
## character's own kit and its skills widget; the spell row of state 11 sits
## at the bottom (y 500, the original's position is not traced); seven
## face cells (50..750) per strip with the remake's cell highlight. Faces
## follow the native byte sort (female reversed); voices retain table order.

signal closed(accepted: bool)

const SEL := 9
const CREATE := 10
const KIT := 11
const VIEW := 12

const OK_RECT := Rect2(163, 526, 74, 48)
const CANCEL_RECT := Rect2(563, 526, 74, 48)
const ROWS := 10
const LIST_BAR := Rect2(110, 250, 274, 240)
const RENAME_EDIT := Rect2(558, 110, 137, 16)
const NAME_EDIT := Rect2(0, 127, 200, 16)
const BACK_RECT := Rect2(620, 430, 40, 40)
const RESET_RECT := Rect2(680, 430, 40, 40)
const NEXT_RECT := Rect2(740, 430, 40, 40)
const ATTR_ROWS := [["str", "strength", 165], ["dex", "dexterity", 180], ["int", "intelligence", 195]]
const VOICE_ROWS := 11
const CELLS := 7
const CARET := Color8(0xff, 0xb3, 0x31)   # COLORREF
const DIMMED := Color8(0x82, 0x82, 0x82)
const TURN_SPEED := 2.0
const SPELL_CELL_UV := [14, 142, 114, 242]

var state := SEL
var chars: Array = []      # MpCharacter.list()
var sel := -1
var top := 0
var renaming := false
var rename_text := ""
var _rename_fresh := true
var edit := {}             # the character being made / viewed
var _edit_file := ""       # VIEW: its file
var _kit_copy := {}        # state 11 / view entry: Back / Cancel restore it
var faces := [[], []]      # male / female prototypes
var face_top: Array[int] = [0, 0]
var voices := [[], []]
var voice_list := 0        # 0 male, 1 female
var voice_sel := 0
var voice_top := 0
var pick := {"weapon": "", "belt": "", "spell": ""}
var _turn := 0
var _hold := ""
var _hold_t := 0.0
var _caret_t := 0.0
var _hover_help := []
var _db_was := false
var _box: MessageBox
var _dim: Interface800.Backdrop
var _board: InterfaceBoard
var _doll: Paperdoll
var _cells: Array = []     # Portrait per face cell (male 0..6, female 7..13)
var _items: Dictionary = {}   # slot key -> ItemView
var _skill_rows: Array = []   # [rect, kind, key, desc]


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = " "
	_dim = Interface800.dim_layer()
	add_child(_dim)
	_board = InterfaceBoard.create("unmoco2", "mainmenu00", "mainmenu00labels",
		PackedStringArray(["but03", "button03_multiplayer"]), PI * 0.5 * 1.2, Vector3(400, 350, 8))
	_board.show_behind_parent = true
	add_child(_board)
	_doll = Paperdoll.new()
	_doll.camp_frame = true
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_doll)
	resized.connect(_layout)
	add_to_group("pad_panel")   # remake: gamepad snap targets (pad_targets, pad_press)


## Opens on the selection (state 9). `capture` false keeps the frozen
## picture of the screen it opens over (a modal over a modal).
func open(capture := true) -> void:
	_db_was = GameData.lmp_db
	GameData.use_lmp_database(true)   # (1)
	if capture:
		_dim.capture()
	faces = MpCharacter.faces()
	voices = MpCharacter.voices()
	_reload(MpCharacter.selected_file())
	visible = true
	_set_state(SEL)
	grab_focus()


func _close(accepted: bool) -> void:
	renaming = false
	visible = false
	_doll.visible = false
	if not _db_was:
		GameData.use_lmp_database(false)
	closed.emit(accepted)


## The list from disk; `want` the file to select (else the first).
func _reload(want := "") -> void:
	chars = MpCharacter.list()
	sel = 0 if not chars.is_empty() else -1
	for i in chars.size():
		if String(chars[i].file) == want:
			sel = i
	_clamp_sel()


func _clamp_sel() -> void:
	sel = clampi(sel, -1 if chars.is_empty() else 0, chars.size() - 1)
	if sel >= 0:
		top = clampi(top, sel - ROWS + 1, sel)
	top = clampi(top, 0, maxi(0, chars.size() - ROWS))


func _set_state(s: int) -> void:
	state = s
	_turn = 0
	_hold = ""
	_doll.camp_angle = 0.0
	_board.visible = s == SEL
	_layout()
	queue_redraw()


func selected_record() -> Dictionary:
	return chars[sel].data if sel >= 0 and sel < chars.size() else {}


func _hero() -> Dictionary:
	return MpCharacter.hero_of(edit) if state != SEL else MpCharacter.hero_of(selected_record())


static func _txt(key: String, fallback: String) -> String:
	var t := GameData.text(key).get_slice("\n", 0).strip_edges() if GameData.is_open() else ""
	return t if t else fallback


static func _desc(key: String) -> String:
	var t := GameData.text(key).strip_edges() if GameData.is_open() else ""
	return " ".join(Array(t.split("\n")).map(func(x): return String(x).strip_edges())).strip_edges()


## A perk text's [title, description] ("perk strength" ...).
static func _perk(code: String) -> Array:
	var t := GameData.text("perk " + code) if GameData.is_open() else ""
	var ls := Array(t.split("\n"))
	var ttl := String(ls.pop_front()).strip_edges() if not ls.is_empty() else code
	return [ttl, " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()]


# ------------------------------------------------------------------ 3D children

func _layout() -> void:
	if not is_inside_tree():
		return
	var h := _hero()
	_board.visible = visible and state == SEL and not MessageBox.is_up(_box)
	var show_fig := visible and not h.is_empty() and state in [SEL, CREATE] and not MessageBox.is_up(_box)
	_doll.visible = show_fig
	if show_fig:
		if state == SEL:
			_doll.set_camp_place(555.0, Rect2(410, 100, 290, 400))
		else:
			_doll.set_camp_place(400.0, Rect2(200, 100, 400, 400))
		var r := r8(_doll.camp_rect())
		_doll.position = r.position
		_doll.size = r.size
		_doll.view_size = Vector2i(r.size.round())
		_doll.show_info({"prototype": h.prototype, "complexion": h.complexion,
			"armors": PackedStringArray(h.get("armors", [])), "weapons": PackedStringArray(h.get("weapons", []).slice(0, 1))})
		_doll._camp_transform()
	_layout_faces()
	_layout_items()


func _layout_faces() -> void:
	var on := visible and state == CREATE and not MessageBox.is_up(_box)
	if on and _cells.is_empty():
		for i in CELLS * 2:
			var p := Portrait.new()
			p.view_size = Vector2i(96, 96)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(p)
			_cells.append(p)
	for i in _cells.size():
		var p: Portrait = _cells[i]
		var g := i / CELLS
		var k := face_top[g] + i % CELLS
		p.visible = on and k < (faces[g] as Array).size()
		if not p.visible:
			continue
		var r := r8(Rect2(50 + (i % CELLS) * 100 + 5, (0 if g == 0 else 500) + 5, 90, 90))
		p.position = r.position
		p.size = r.size
		p.show_proto(String(faces[g][k]))


func _layout_items() -> void:
	var want := {}
	if visible and state in [KIT, VIEW] and not MessageBox.is_up(_box):
		for c: Array in _item_cells():
			want[c[0]] = c
	for k in _items.keys():
		if not want.has(k):
			_items[k].queue_free()
			_items.erase(k)
	var s := kv().y
	for k: String in want:
		var c: Array = want[k]
		var v: ItemView = _items.get(k)
		if v == null:
			v = ItemView.new()
			v.camp = true
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(v)
			_items[k] = v
		var r: Rect2 = c[1]
		var ctr := r.get_center()
		v.unit_px = 37.5 * s
		v.screen_at = Vector3(ctr.x, ctr.y, 400.0 / ItemView.K / 37.5)
		v.size = Vector2.ONE * 100.0 * s
		v.position = p8(ctr) - v.size * 0.5
		v.add_color = Color8(0x40, 0x40, 0x40) if state == KIT and String(pick.get(c[2], "")) == String(c[3]) else Color(0, 0, 0)
		v.show_item(("spell:" + String(c[3])) if c[2] == "spell" else String(c[3]))


## State 11 / view cells: [key, rect, kind, item].
func _item_cells() -> Array:
	var h := _hero()
	var out := []
	if h.is_empty():
		return out
	var w: Array = h.get("weapons", [])
	var q: Array = h.get("quick", [])
	var sp: Array = h.get("spells", [])
	for i in mini(4, w.size()):
		out.append(["w%d" % i, Rect2(i * 100, 0, 100, 100), "weapon", w[i]])
	for i in mini(4, q.size()):
		out.append(["b%d" % i, Rect2(700 - i * 100, 0, 100, 100), "belt", q[i]])
	for i in mini(8, sp.size()):
		out.append(["s%d" % i, Rect2(i * 100, 500, 100, 100), "spell", sp[i]])
	return out


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if MessageBox.is_up(_box):
		return
	match state:
		SEL: _draw_select()
		CREATE: _draw_create()
		_: _draw_kit()
	_draw_pad_glyphs()


func _draw_select() -> void:
	var ui := tex("saveload")
	# campm1..4 cropped to the right panel.
	sprite(tex("campm1"), Rect2(410, 100, 145, 200), [83, 28, 228, 228])
	sprite(tex("campm2"), Rect2(555, 100, 145, 200), [28, 28, 173, 228])
	sprite(tex("campm3"), Rect2(410, 300, 145, 200), [83, 28, 228, 228])
	sprite(tex("campm4"), Rect2(555, 300, 145, 200), [28, 28, 173, 228])
	frame(Rect2(405, 95, 300, 410))
	panel(Rect2(100, 100, 290, 120))
	panel(Rect2(100, 240, 290, 260))
	var labels := [_txt("string lmp_pers_new", "New"), _txt("string lmp_pers_rename", "Change clan"),
		_txt("string lmp_pers_delete", "Delete"), _txt("string lmp_pers_redress", "View")]
	for i in 4:
		sprite(ui, Rect2(180, 115 + 24 * i, 130, 19), [122, 108, 252, 127])
		text(Rect2(100, 116 + 24 * i, 290, 20), labels[i], 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	for k in ROWS:
		var i := top + k
		if i >= chars.size():
			break
		if i == sel:
			draw_rect(r8(Rect2(110, 250 + 24 * k, 260, 24)), BAR)
		text(Rect2(112, 253 + 24 * k, 253, 20), String(MpCharacter.hero_of(chars[i].data).get("name", "")), 1, TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true)
	vbar(LIST_BAR, top, chars.size() - ROWS)
	if renaming:
		var full := String(MpCharacter.hero_of(selected_record()).get("name", ""))
		text(Rect2(425, 110, 130, 16), MpCharacter.name_part(full) + MpCharacter.CLAN_SEP, 1, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_edit_line(RENAME_EDIT, rename_text, TEXT, false)
	sprite(ui, OK_RECT, [81, 2, 155, 50])
	sprite(ui, CANCEL_RECT, [160, 2, 234, 50])


func _draw_backdrop(cols: Array) -> void:
	var t := tex("campinfo")
	for x: float in cols:
		for xi in 2:
			for yi in 4:
				sprite(t, Rect2(x + xi * 100, 100 + yi * 100, 100, 100), [14, 14, 114, 114])
		for yi in 4:
			sprite(t, Rect2(x, 100 + yi * 100, 21, 100), [254, 76, 233, 176])
			sprite(t, Rect2(x + 179, 100 + yi * 100, 21, 100), [233, 76, 254, 176])
		sprite(t, Rect2(x, 100, 100, 30), [254, 2, 154, 32])
		sprite(t, Rect2(x + 100, 100, 100, 30), [154, 2, 254, 32])
		sprite(t, Rect2(x, 470, 100, 30), [254, 32, 154, 2])
		sprite(t, Rect2(x + 100, 470, 100, 30), [154, 32, 254, 2])


## (y): the left column's divider (two mirrored halves, 40 high).
func _divider(y: float) -> void:
	var t := tex("campinfo")
	sprite(t, Rect2(0, y - 20, 100, 40), [254, 34, 154, 74])
	sprite(t, Rect2(100, y - 20, 100, 40), [154, 34, 254, 74])


## The name plate of the info panel: campinfo UV 145,76-231,136
## the left half mirrored.
func _name_plate() -> void:
	var t := tex("campinfo")
	sprite(t, Rect2(14, 110, 86, 50), [231, 76, 145, 136])
	sprite(t, Rect2(100, 110, 86, 50), [145, 76, 231, 136])


func _icons(dim_next: bool) -> void:
	var t := tex("campinfo")
	sprite(t, BACK_RECT, [2, 152, 42, 192])
	sprite(t, RESET_RECT, [84, 152, 124, 192])
	sprite(t, NEXT_RECT, [43, 152, 83, 192], Color(0.5, 0.5, 0.5) if dim_next else Color.WHITE)


func _draw_create() -> void:
	var h := _hero()
	_draw_backdrop([0.0, 600.0])
	for q in 4:
		sprite(tex("campm%d" % (q + 1)), Rect2(200 + (q % 2) * 200, 100 + (q / 2) * 200, 200, 200), [28, 28, 228, 228])
	_divider(300)
	# Face strips: cells on InventoryM01, end caps with the arrows.
	var inv := tex("inventorym01")
	for g in 2:
		var y0 := 0.0 if g == 0 else 500.0
		for i in CELLS:
			sprite(inv, Rect2(50 + i * 100, y0, 100, 100), [14, 14, 114, 114])
			var k: int = face_top[g] + i
			if k < (faces[g] as Array).size() and String(faces[g][k]) == String(h.get("prototype", "")):
				draw_rect(r8(Rect2(52 + i * 100, y0 + 2, 96, 96)), BAR)
		sprite(inv, Rect2(0, y0, 50, 100), [192, 14, 142, 114])
		sprite(inv, Rect2(750, y0, 50, 100), [142, 14, 192, 114])
		for side in [[Vector2(40, y0 + 50), -1.0], [Vector2(760, y0 + 50), 1.0]]:
			var c: Vector2 = side[0]
			var d: float = side[1]
			draw_colored_polygon(PackedVector2Array([p8(c + Vector2(d * 8, 0)), p8(c + Vector2(-d * 6, -12)),
				p8(c + Vector2(-d * 6, 12))]), Color(0.85, 0.7, 0.35))
	_name_plate()
	_edit_line(NAME_EDIT, String(h.get("name", "")), Color.WHITE, true)
	# Attributes, balance, height.
	for a: Array in ATTR_ROWS:
		var v := int(h.get(a[0], 25))
		text(Rect2(20, a[2], 120, 15), _perk(a[1])[0], 0, TEXT)
		text(Rect2(20, a[2], 110, 15), "%d" % v, 0, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_pm(a[2], v > MpCharacter.ATTR_MIN, v < MpCharacter.ATTR_MAX and MpCharacter.points_left(h) >= 1)
	text(Rect2(20, 210, 160, 15), _txt("string lmp_points_left", "Balance"), 0, TEXT)
	text(Rect2(20, 210, 110, 15), "%d" % MpCharacter.points_left(h), 0, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	var ht := MpCharacter.height_of(h)
	text(Rect2(20, 240, 120, 15), _txt("string lmp_pers_tall", "Height"), 0, TEXT)
	text(Rect2(20, 240, 110, 15), "%d" % ht, 0, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_pm(240, ht >= 1, ht <= 99)
	# Voices.
	text(Rect2(10, 305, 180, 15), _txt("string lmp_voices", "Select voice"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var vl: Array = voices[voice_list]
	var lbl := _txt("string lmp_female_voice" if voice_list == 1 else "string lmp_male_voice", "Voice:")
	for i in VOICE_ROWS:
		var k := voice_top + i
		if k >= vl.size():
			break
		if k == voice_sel:
			draw_rect(r8(Rect2(15, 325 + 15 * i, 165, 15)), BAR)
		text(Rect2(20, 325 + 15 * i, 155, 15), "%s %d" % [lbl, k + 1], 0, TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	vbar(Rect2(10, 325, 180, 165), voice_top, vl.size() - VOICE_ROWS)
	_icons(not MpCharacter.can_continue(h))
	_draw_help()


## "−" / "+" of a row (x 140 / 160, 20×15 plates UV 144,177-164,192), the
## glyph when it cannot move.
func _pm(y: float, minus_ok: bool, plus_ok: bool) -> void:
	var t := tex("campinfo")
	for i in 2:
		sprite(t, Rect2(140 + 20 * i, y, 20, 15), [144, 177, 164, 192])
		var ok := minus_ok if i == 0 else plus_ok
		text(Rect2(140 + 20 * i, y - 1, 20, 15), "-" if i == 0 else "+", 0, TEXT if ok else DIMMED, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_help() -> void:
	if _hover_help.is_empty():
		return
	text_block(Rect2(615, 110, 170, 30), String(_hover_help[0]), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text_block(Rect2(615, 140, 170, 340), String(_hover_help[1]), 0, TEXT, HORIZONTAL_ALIGNMENT_CENTER)


## The edit box: text and, while editing, the caret.
func _edit_line(r: Rect2, s: String, col: Color, centred: bool) -> void:
	var al := HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
	text(r, s, 1, col, al)
	if fmod(_caret_t, 1.0) < 0.5:
		var w := text_width(s, 1)
		var x := r.position.x + (r.size.x + w) * 0.5 if centred else r.position.x + w + 1
		draw_line(p8(Vector2(x, r.position.y)), p8(Vector2(x, r.end.y)), CARET, maxf(1.0, round(kv().x)))


func _draw_kit() -> void:
	var h := _hero()
	_draw_backdrop([0.0, 200.0, 400.0, 600.0])
	_divider(400)
	var slots := tex("campslots")
	for i in 8:
		sprite(slots, Rect2(i * 100, 0, 100, 100), [14, 14, 114, 114] if i < 4 else [142, 14, 242, 114])
		sprite(slots, Rect2(i * 100, 500, 100, 100), SPELL_CELL_UV)
	_name_plate()
	text(NAME_EDIT, String(h.get("name", "")), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 165.0
	for row: Array in _info_rows(h):
		text(Rect2(20, y, 160, 15), String(row[0]), 0, TEXT)
		text(Rect2(20, y, 160, 15), String(row[1]), 0, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 15.0
	var start := float(MpCharacter.hero_of(_kit_copy).get("exp", 0.0))
	var xp := float(h.get("exp", 0.0))
	text(Rect2(0, 410, 200, 20), "%s %d" % [_txt("string camp_current_exp", "Experience:"), int(xp)], 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(Rect2(0, 430, 200, 20), _txt("string camp_level_up", ""), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(Rect2(0, 450, 200, 20), "0" if int(start - xp) == 0 else "%+d" % -int(start - xp), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_skills(h)
	_icons(false)
	_draw_help()


##  mode 11: effective attributes, a gap, Health / Stamina
## Actions / Experience / Encumbrance. These are the same derived hero
## values as Combat.hero_stats; the editor has no simulated world unit.
func _info_rows(h: Dictionary) -> Array:
	var tot := float(h.get("exp_total", 0.0))
	var out := []
	for a: Array in ATTR_ROWS:
		out.append([_perk(a[1])[0], "%d" % int(float(h.get(a[0], 25)) + Perks.attr_bonus(h, a[0]))])
	var strength := float(h.get("str", 25)) + Perks.attr_bonus(h, "str")
	var dexterity := float(h.get("dex", 25)) + Perks.attr_bonus(h, "dex")
	out.append(["", ""])
	out.append([_perk("health")[0], "%d" % int(Skills.base_pool(tot, strength) * (1.0 + Perks.best(h, "health") / 100.0))])
	out.append([_perk("mana")[0], "%d" % int(Skills.base_pool(tot, dexterity, "MP") * (1.0 + Perks.best(h, "mana") / 100.0))])
	out.append([_perk("actions")[0], "%d" % int((dexterity * 0.2 + 10.0) * (1.0 + Perks.best(h, "quickness") / 100.0))])
	out.append([_perk("experience")[0], "%d" % int(tot)])
	var weight := 0.0
	for k in ["weapons", "armors", "quick"]:
		for it in h.get(k, []):
			var st := Items.parse_stack(String(it))
			weight += Items.weight(st[0]) * int(st[1])
	var limit := strength * 12.0 * (1.0 + Perks.best(h, "lift") / 100.0)
	out.append([_perk("encumbrance")[0], "%d/%d" % [int(weight), int(limit)]])
	out.append(["", CampView._str("infounit_17") if weight > limit else ""])
	return out


## The skills widget (as CampView._draw_skills): skills with
## their price, the known and the available abilities; a click raises / learns.
func _draw_skills(h: Dictionary) -> void:
	_skill_rows.clear()
	var xp := float(h.get("exp", 0.0))
	var t := tex("campinfo")
	var o := Vector2(200, 100)
	text(Rect2(o + Vector2(0, 10), Vector2(200, 15)), CampView._str("skills"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(Rect2(o + Vector2(0, 205), Vector2(200, 15)), CampView._str("perks"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(Rect2(o + Vector2(200, 10), Vector2(200, 15)), CampView._str("perks_av"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var ys := {"melee": 35, "archery": 50, "science": 65, "elemental": 95, "sense": 110, "astral": 125}
	for sk: String in Skills.LIST:
		var r := Rect2(o + Vector2(15, ys[sk]), Vector2(165, 15))
		var lv := Skills.level(h, sk)
		var c := Skills.cost(h, sk)
		text(r, Skills.title(sk), 0, TEXT)
		text(Rect2(r.position - Vector2(40, 0), r.size), "%d" % lv, 0, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		if lv < 100:
			sprite(t, Rect2(350, r.position.y, 40, 15), [124, 138, 164, 153])
			text(r, CampView._cost_text(c), 0, TEXT if xp >= c else DIMMED, HORIZONTAL_ALIGNMENT_RIGHT)
		_skill_rows.append([r, "skill", sk, _perk(sk)])
	var y := 230.0
	for code: String in h.get("perks", []):
		if y > 470.0:
			break
		text(Rect2(215, y, 165, 15), Perks.title(code), 0, TEXT)
		y += 15.0
	var avail := Perks.available(h).filter(func(code): return String(code).ends_with("1"))
	y = 135.0
	for i in mini(avail.size(), 23):
		var code: String = avail[i]
		var r := Rect2(415, y, 165, 15)
		var c := Perks.cost(code, h)
		text(r, CampView._perk_family(code.rstrip("0123456789")), 0, TEXT)
		sprite(t, Rect2(550, y, 40, 15), [124, 138, 164, 153])
		text(r, CampView._cost_text(c), 0, TEXT if xp >= c else DIMMED, HORIZONTAL_ALIGNMENT_RIGHT)
		_skill_rows.append([r, "perk", code, [Perks.title(code), _perk(code)[1]]])
		y += 15.0


# ------------------------------------------------------------------ input

func _hit(p: Vector2) -> Array:
	match state:
		SEL:
			if OK_RECT.has_point(p): return ["ok"]
			if CANCEL_RECT.has_point(p): return ["back"]
			if Rect2(455, 470, 30, 30).has_point(p): return ["turn", 1]
			if Rect2(625, 470, 30, 30).has_point(p): return ["turn", 2]
			for i in 4:
				if Rect2(180, 112 + 24 * i, 130, 24).has_point(p):
					return [["new", "clan", "delete", "view"][i]]
			var vb := vbar_hit(LIST_BAR, top, chars.size() - ROWS, p)
			if vb in ["up", "down"]:
				return ["list_scroll", -1 if vb == "up" else 1]
			for k in ROWS:
				if Rect2(110, 250 + 24 * k, 260, 24).has_point(p) and top + k < chars.size():
					return ["row", top + k]
		CREATE:
			if BACK_RECT.has_point(p): return ["back"]
			if RESET_RECT.has_point(p): return ["reset"]
			if NEXT_RECT.has_point(p): return ["next"]
			if Rect2(300, 470, 30, 30).has_point(p): return ["turn", 1]
			if Rect2(470, 470, 30, 30).has_point(p): return ["turn", 2]
			for g in 2:
				var y0 := 0.0 if g == 0 else 500.0
				if Rect2(30, y0 + 35, 20, 30).has_point(p): return ["face_scroll", g, -1]
				if Rect2(750, y0 + 35, 20, 30).has_point(p): return ["face_scroll", g, 1]
				if Rect2(50, y0, 700, 100).has_point(p):
					var k: int = face_top[g] + int((p.x - 50) / 100)
					if k < (faces[g] as Array).size():
						return ["face", g, k]
			for a: Array in ATTR_ROWS:
				if Rect2(20, a[2], 120, 15).has_point(p): return ["help_attr", a[1]]
				if Rect2(140, a[2], 20, 15).has_point(p): return ["attr", a[0], -1]
				if Rect2(160, a[2], 20, 15).has_point(p): return ["attr", a[0], 1]
			if Rect2(140, 240, 20, 15).has_point(p): return ["height", -1]
			if Rect2(160, 240, 20, 15).has_point(p): return ["height", 1]
			if Rect2(20, 210, 160, 15).has_point(p): return ["help", "string lmp_points_left"]
			if Rect2(20, 240, 120, 15).has_point(p): return ["help", "string lmp_pers_tall"]
			var vb := vbar_hit(Rect2(10, 325, 180, 165), voice_top, (voices[voice_list] as Array).size() - VOICE_ROWS, p)
			if vb in ["up", "down"]:
				return ["voice_scroll", -1 if vb == "up" else 1]
			for i in VOICE_ROWS:
				if Rect2(10, 325 + 15 * i, 170, 15).has_point(p) and voice_top + i < (voices[voice_list] as Array).size():
					return ["voice", voice_top + i]
			if NAME_EDIT.grow(4).has_point(p):
				return ["name"]
		_:
			if BACK_RECT.has_point(p): return ["back"]
			if RESET_RECT.has_point(p): return ["reset"]
			if NEXT_RECT.has_point(p): return ["next"]
			for c: Array in _item_cells():
				if (c[1] as Rect2).has_point(p):
					return ["item", c[2], c[3]]
			for r: Array in _skill_rows:
				if (r[0] as Rect2).has_point(p):
					return ["train", r[1], r[2], r[3]]
	return []


func _get_tooltip(at: Vector2) -> String:
	if MessageBox.is_up(_box):
		return ""
	var h := _hit(to800(at))
	if h.is_empty():
		return ""
	var tip := -1
	match state:
		SEL:
			tip = {"ok": 40100, "back": 40101, "new": 40200, "clan": 40201, "delete": 40202, "view": 40203}.get(h[0], -1)
		CREATE:
			tip = {"back": 40301, "reset": 40302, "next": 40300}.get(h[0], -1)
			if h[0] == "face_scroll":
				tip = 40400 if h[2] < 0 else 40401
		KIT:
			tip = {"back": 40501, "reset": 40502, "next": 40500}.get(h[0], -1)
	return GameData.text("tip %d" % tip).strip_edges() if tip >= 0 else ""


func _gui_input(e: InputEvent) -> void:
	if not visible or MessageBox.is_up(_box):
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press(_hit(to800(e.position)))
		else:
			_turn = 0
			_hold = ""
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if state == SEL:
			top = clampi(top + d, 0, maxi(0, chars.size() - ROWS))
		elif state == CREATE:
			voice_top = clampi(voice_top + d, 0, maxi(0, (voices[voice_list] as Array).size() - VOICE_ROWS))
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion:
		_update_help(_hit(to800(e.position)))
	elif e is InputEventKey and e.pressed:
		_key(e)
		accept_event()


func _update_help(h: Array) -> void:
	var help := []
	if not h.is_empty():
		match h[0]:
			"help_attr": help = _perk(h[1])
			"help": help = [_txt(h[1], ""), _desc(String(h[1]) + "_desc")]
			"voice": help = [_txt("string lmp_select_voice", ""), _desc("string lmp_select_voice_desc")]
			"train": help = h[3]
			"item": help = [Items.title(("spell:" + String(h[2])) if h[1] == "spell" else String(h[2])), ""]
	if help != _hover_help:
		_hover_help = help
		queue_redraw()


func _press(h: Array) -> void:
	if h.is_empty():
		return
	match state:
		SEL: _press_select(h)
		CREATE: _press_create(h)
		_: _press_kit(h)
	_layout()
	queue_redraw()


func _press_select(h: Array) -> void:
	if renaming:
		return   #  returns at once while the clan box is active
	match h[0]:
		"back":
			sound("messbox\\cancel")
			_close(false)
		"ok":
			_accept()
		"turn":
			sound("camp\\move")
			_turn = h[1]
		"new":
			sound("save\\select")
			var male: Array = faces[0]
			if male.is_empty():
				return
			edit = MpCharacter.create(String(male[0]))
			_voice_for(String(male[0]))
			_set_state(CREATE)
		"clan":
			sound("save\\select")
			if sel >= 0:
				renaming = true
				_rename_fresh = true
				rename_text = MpCharacter.clan_part(String(MpCharacter.hero_of(selected_record()).get("name", "")))
				if TouchInput.enabled:
					TouchTextEdit.open(self, rename_text, MpCharacter.NAME_MAX, func(v): rename_text = _filter(v); queue_redraw(), "Clan")
		"delete":
			sound("save\\select")
			if sel >= 0:
				_box = MessageBox.ask(get_parent(), "lmp_deletepers", "lmp_deletepers_msg")
				_box.answered.connect(func(yes: bool):
					if yes:
						MpCharacter.delete_file(String(chars[sel].file))
						_reload("" if sel + 1 >= chars.size() else String(chars[sel + 1].file))
					_layout()
					queue_redraw(), CONNECT_ONE_SHOT)
		"view":
			sound("save\\select")
			if sel >= 0:
				edit = (selected_record() as Dictionary).duplicate(true)
				_edit_file = String(chars[sel].file)
				_kit_copy = edit.duplicate(true)
				_set_state(VIEW)
		"row":
			sound("save\\select")
			sel = h[1]
			_doll.camp_angle = 0.0
		"list_scroll":
			top = clampi(top + int(h[1]), 0, maxi(0, chars.size() - ROWS))


## ✓ — no character: «lmp_no_pers» (✓ only); else the chosen
## one is the player's.
func _accept() -> void:
	sound("messbox\\ok")
	if sel < 0 or sel >= chars.size():
		_box = MessageBox.ask(get_parent(), "lmp_no_pers", "lmp_no_pers_msg", [], true)
		_box.answered.connect(func(_y): _layout(); queue_redraw(), CONNECT_ONE_SHOT)
		_layout()
		return
	MpCharacter.select(String(chars[sel].file))
	_close(true)


func _press_create(h: Array) -> void:
	var hero := _hero()
	match h[0]:
		"back":
			sound("messbox\\cancel")
			_set_state(SEL)
		"reset":   #  case 4: the first male face, 25s, 0.7, no name
			sound("messbox\\cancel")
			var male: Array = faces[0]
			if not male.is_empty():
				edit = MpCharacter.create(String(male[0]))
				_voice_for(String(male[0]))
		"next":
			_next_from_create()
		"turn":
			sound("camp\\move")
			_turn = h[1]
		"face_scroll":
			var g: int = h[1]
			face_top[g] = clampi(face_top[g] + int(h[2]), 0, maxi(0, (faces[g] as Array).size() - CELLS))
		"face":
			sound("battle\\on_off")
			var proto := String(faces[h[1]][h[2]])
			edit = MpCharacter.change_face(edit, proto)
			_voice_for(proto)
		"attr":
			sound("camp\\perk")
			MpCharacter.step_attr(hero, h[1], h[2])
			_hold = "%s:%d" % [h[1], h[2]]
			_hold_t = -0.5
		"height":
			sound("camp\\perk")
			MpCharacter.step_height(hero, h[1])
			_hold = "height:%d" % h[1]
			_hold_t = -0.5
		"voice":
			sound("save\\select")
			voice_sel = h[1]
			_apply_voice(true)
		"voice_scroll":
			voice_top = clampi(voice_top + int(h[1]), 0, maxi(0, (voices[voice_list] as Array).size() - VOICE_ROWS))
		"name":
			if TouchInput.enabled:
				TouchTextEdit.open(self, String(hero.get("name", "")), MpCharacter.NAME_MAX,
					func(v): hero.name = _filter(v); queue_redraw(), "Name")


## on to the kit with the balance 0 and a name, else cancel.wav.
func _next_from_create() -> void:
	var hero := _hero()
	if not MpCharacter.can_continue(hero):
		sound("messbox\\cancel")
		return
	sound("messbox\\ok")
	pick = {"weapon": _first(hero.weapons), "belt": _first(hero.quick), "spell": _first(hero.spells)}
	_kit_copy = edit.duplicate(true)
	_set_state(KIT)


static func _first(a) -> String:
	return String(a[0]) if a is Array and not a.is_empty() else ""


## a face picks the voice list of its sex, its first voice.
func _voice_for(proto: String) -> void:
	voice_list = 1 if (faces[1] as Array).has(proto) else 0
	voice_sel = 0
	voice_top = 0
	_apply_voice(false)


## The chosen voice's NPC name goes on the hero; a click plays one of its
## acknowledgements.
func _apply_voice(preview: bool) -> void:
	var vl: Array = voices[voice_list]
	if voice_sel >= vl.size():
		return
	var hero := _hero()
	hero.voice = String(vl[voice_sel])
	if preview:
		var ls := EIAcks.lines([hero.voice], EIAcks.SELECTED)
		if ls.is_empty():
			ls = EIAcks.lines([hero.voice], EIAcks.MOVE)
		if not ls.is_empty():
			var line: Dictionary = ls[randi() % ls.size()]
			var s := AudioStreamPlayer.new()
			s.bus = "SFX"
			s.stream = EIAudio.sfx(String(line.get("wav", "")))
			if s.stream:
				add_child(s)
				s.play()
				s.finished.connect(s.queue_free)
			else:
				s.free()


func _press_kit(h: Array) -> void:
	var hero := _hero()
	match h[0]:
		"back":
			sound("messbox\\cancel")
			if state == VIEW:
				_save_view()
				_set_state(SEL)
			else:   # (0, 0): the skills as they were; back to 10
				edit = _kit_copy.duplicate(true)
				_set_state(CREATE)
		"reset":
			sound("messbox\\cancel")
			edit = _kit_copy.duplicate(true)
			if state == KIT:
				var hr := _hero()
				pick = {"weapon": _first(hr.weapons), "belt": _first(hr.quick), "spell": _first(hr.spells)}
		"next":
			sound("messbox\\ok")
			if state == VIEW:
				_save_view()
				_set_state(SEL)
			else:
				_finish()
		"item":
			if state == KIT:
				sound("messbox\\ok")
				pick[h[1]] = String(h[2])
		"train":
			var ok := false
			if h[1] == "skill":
				ok = Skills.raise(hero, String(h[2]))
			else:
				ok = Perks.learn(hero, String(h[2]))
			sound("camp\\perk" if ok else "messbox\\cancel")


## the kit cut to the chosen pieces, "<n>.mp" written, back to
## the selection with the new character selected.
func _finish() -> void:
	MpCharacter.finish(edit, pick.weapon, pick.belt, pick.spell)
	var f := MpCharacter.next_file()
	MpCharacter.save_file(f, edit)
	_reload(f)
	_set_state(SEL)


##  after the character's camp screen: its record saved back.
func _save_view() -> void:
	if _edit_file:
		MpCharacter.save_file(_edit_file, edit)
	_reload(_edit_file)


static func _filter(v: String) -> String:
	var out := ""
	for c in v:
		if MpCharacter.name_char_ok(c) and out.length() < MpCharacter.NAME_MAX:
			out += c
	return out


func _key(e: InputEventKey) -> void:
	match state:
		SEL:
			if renaming:
				_rename_key(e)
				return
			match e.keycode:
				KEY_ESCAPE:
					sound("messbox\\cancel")
					_close(false)
				KEY_ENTER, KEY_KP_ENTER:
					_accept()
				KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
					# ±1 / ±10, clamped, kept in view.
					if chars.is_empty():
						return
					sound("save\\select")
					sel += {KEY_UP: -1, KEY_DOWN: 1, KEY_PAGEUP: -ROWS, KEY_PAGEDOWN: ROWS}[e.keycode]
					_clamp_sel()
		CREATE:
			var hero := _hero()
			match e.keycode:
				KEY_ESCAPE:
					sound("messbox\\cancel")
					_set_state(SEL)
				KEY_ENTER, KEY_KP_ENTER:
					_next_from_create()
				KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
					var n := (voices[voice_list] as Array).size()
					if n == 0:
						return
					voice_sel = clampi(voice_sel + {KEY_UP: -1, KEY_DOWN: 1, KEY_PAGEUP: -VOICE_ROWS, KEY_PAGEDOWN: VOICE_ROWS}[e.keycode], 0, n - 1)
					voice_top = clampi(voice_top, voice_sel - VOICE_ROWS + 1, voice_sel)
					_apply_voice(true)
				KEY_BACKSPACE:
					var s := String(hero.get("name", ""))
					hero.name = s.substr(0, s.length() - 1)
				_:
					var c := char(e.unicode) if e.unicode >= 32 else ""
					var s := String(hero.get("name", "")) + c
					if c and MpCharacter.name_char_ok(c) and s.length() <= MpCharacter.NAME_MAX \
							and text_width(s, 1) < NAME_EDIT.size.x and not e.ctrl_pressed:
						hero.name = s
		_:
			match e.keycode:
				KEY_ESCAPE:
					_press_kit(["back"])
				KEY_ENTER, KEY_KP_ENTER:
					_press_kit(["next"])
	_layout()
	queue_redraw()


## The clan box: the first key replaces the
## text; Enter keeps "name | clan" and saves the file; Esc drops the edit.
func _rename_key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_ESCAPE:
			renaming = false
		KEY_ENTER, KEY_KP_ENTER:
			renaming = false
			var data: Dictionary = selected_record()
			var hero := MpCharacter.hero_of(data)
			hero.name = MpCharacter.with_clan(String(hero.get("name", "")), rename_text)
			MpCharacter.save_file(String(chars[sel].file), data)
		KEY_BACKSPACE:
			rename_text = "" if _rename_fresh else rename_text.substr(0, rename_text.length() - 1)
			_rename_fresh = false
		_:
			var c := char(e.unicode) if e.unicode >= 32 else ""
			if c and MpCharacter.name_char_ok(c) and not e.ctrl_pressed:
				var s := (c if _rename_fresh else rename_text + c)
				if s.length() <= MpCharacter.NAME_MAX and text_width(s, 1) < RENAME_EDIT.size.x:
					rename_text = s
				_rename_fresh = false
	queue_redraw()


func _process(dt: float) -> void:
	if not visible:
		return
	if state in [SEL, CREATE] and _turn != 0:
		_doll.turn_camp_by((TURN_SPEED if _turn == 1 else -TURN_SPEED) * dt)
	# a held "−" / "+" steps again every frame from 0.75 s .
	if _hold and state == CREATE:
		_hold_t += dt
		if _hold_t >= 0.25:
			var parts := _hold.split(":")
			var ok := MpCharacter.step_height(_hero(), int(parts[1])) if parts[0] == "height" \
				else MpCharacter.step_attr(_hero(), parts[0], int(parts[1]))
			if not ok:
				_hold = ""
			_layout()
			queue_redraw()
	if (state == CREATE or renaming):
		_caret_t += dt
		queue_redraw()
	if _box != null and not MessageBox.is_up(_box):
		_box = null
		_layout()
		queue_redraw()


# ------------------------------------------------------------------ gamepad

## Remake (gamepad, PadUI; docs/gamepad_design.md §7): the screen's buttons,
## list rows, faces, "−" / "+", voices, kit cells and skill rows are snap
## targets clicked at their centre (A held holds the mouse button, so the
## turn arrows and "−" / "+" repeat as under the mouse). In the character
## and voice lists D-pad ↑ / ↓ moves the selection as the arrow keys do,
## scrolling the list. Y is ✓ / Next; B is Esc (the key bridge). While the
## clan box or a message box is up the keys go to it (pad_active false).
func pad_active() -> bool:
	return not MessageBox.is_up(_box) and not renaming


func pad_targets() -> Array:
	var t := {}
	match state:
		SEL:
			t["ok"] = OK_RECT
			t["back"] = CANCEL_RECT
			t["turn:1"] = Rect2(455, 470, 30, 30)
			t["turn:2"] = Rect2(625, 470, 30, 30)
			for i in 4:
				t[["new", "clan", "delete", "view"][i]] = Rect2(180, 112 + 24 * i, 130, 24)
			for k in ROWS:
				if top + k < chars.size():
					t["row:%d" % (top + k)] = Rect2(110, 250 + 24 * k, 260, 24)
		CREATE:
			t["back"] = BACK_RECT
			t["reset"] = RESET_RECT
			t["next"] = NEXT_RECT
			t["turn:1"] = Rect2(300, 470, 30, 30)
			t["turn:2"] = Rect2(470, 470, 30, 30)
			for g in 2:
				var y0 := 0.0 if g == 0 else 500.0
				t["face_scroll:%d:-1" % g] = Rect2(30, y0 + 35, 20, 30)
				t["face_scroll:%d:1" % g] = Rect2(750, y0 + 35, 20, 30)
				for k in CELLS:
					if face_top[g] + k < (faces[g] as Array).size():
						t["face:%d:%d" % [g, face_top[g] + k]] = Rect2(50 + 100 * k, y0, 100, 100)
			for a: Array in ATTR_ROWS:
				t["attr:%s:-1" % a[0]] = Rect2(140, a[2], 20, 15)
				t["attr:%s:1" % a[0]] = Rect2(160, a[2], 20, 15)
			t["height:-1"] = Rect2(140, 240, 20, 15)
			t["height:1"] = Rect2(160, 240, 20, 15)
			t["name"] = NAME_EDIT
			for i in VOICE_ROWS:
				if voice_top + i < (voices[voice_list] as Array).size():
					t["voice:%d" % (voice_top + i)] = Rect2(10, 325 + 15 * i, 170, 15)
		_:
			t["back"] = BACK_RECT
			t["reset"] = RESET_RECT
			t["next"] = NEXT_RECT
			var cells := _item_cells()
			for i in cells.size():
				t["item:%d" % i] = cells[i][1]
			for i in _skill_rows.size():
				t["train:%d" % i] = _skill_rows[i][0]
	var out: Array = []
	for id: String in t:
		out.append({"rect": pad_rect(t[id]), "id": id})
	return out


func pad_focus() -> Variant:
	match state:
		SEL: return "row:%d" % sel if sel >= 0 else "new"
		CREATE: return "next"
	return "next"


func pad_press(action: String, phase: String) -> bool:
	var ui: PadUI = PadInput.ui
	var f := String(ui.focus_id()) if ui and ui.focus_id() != null and ui.pointer_on else ""
	match action:
		"pause":   # Y = ✓ (the selection) / Next
			if phase == "down":
				_press(["ok"] if state == SEL else ["next"])
			return true
		"up", "down":
			if not phase in ["down", "repeat"]:
				return false
			var d := -1 if action == "up" else 1
			# Inside a list the arrow keys' rule: the selection
			# moves and stays in view, the focus follows it.
			if state == SEL and f.begins_with("row:") and sel + d >= 0 and sel + d < chars.size():
				_list_key(KEY_UP if d < 0 else KEY_DOWN)
				_pad_focus_on("row:%d" % sel)
				return true
			if state == CREATE and f.begins_with("voice:") and voice_sel + d >= 0 \
					and voice_sel + d < (voices[voice_list] as Array).size():
				_list_key(KEY_UP if d < 0 else KEY_DOWN)
				_pad_focus_on("voice:%d" % voice_sel)
				return true
		"interact":
			# No keyboard: A on the empty name field puts the player's name in
			# (it can still be typed over).
			if phase == "down" and state == CREATE and f == "name":
				var hero := _hero()
				if String(hero.get("name", "")).is_empty():
					hero.name = _filter(GameData.player_name)
					queue_redraw()
	return false


func _list_key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	_key(e)


func _pad_focus_on(id: String) -> void:
	for t: Dictionary in pad_targets():
		if t.id == id:
			PadInput.ui.focus_target(id, t.rect)
			return


## The controller's buttons beside ✓ / Next (Y) and ✗ / Back (B) while it drives.
func _draw_pad_glyphs() -> void:
	if PadInput.active != "pad":
		return
	var y := PadInput.glyph(PadInput.button_of("pause"))
	var b := PadInput.glyph(PadInput.button_of("cancel"))
	if state == SEL:
		if y:
			draw_texture_rect(y, r8(Rect2(OK_RECT.position + Vector2(-26, 13), Vector2(22, 22))), false)
		if b:
			draw_texture_rect(b, r8(Rect2(CANCEL_RECT.position + Vector2(-26, 13), Vector2(22, 22))), false)
	else:
		if y:
			draw_texture_rect(y, r8(Rect2(NEXT_RECT.position + Vector2(9, 42), Vector2(22, 22))), false)
		if b:
			draw_texture_rect(b, r8(Rect2(BACK_RECT.position + Vector2(9, 42), Vector2(22, 22))), false)
