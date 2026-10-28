class_name ZoneObjectives
extends Control
## The zone objectives screen that the original opens over the global map when an
## explored island piece is clicked (class s, built
##  in travel mode; init, per-zone fill
## quest rows, description and quest area
## update, mouse, keys
## entrance select, travel).
## Layout (800×600; textures "saveload", "cross" and the zone's "#maps"
## quest picture, all used with V flipped against EIMmp's rows):
##   * black panels (50,20)-(390,160) quests, (50,180)-(390,520)
##     description, (410,20)-(750,360) zone picture, (410,380)-(750,520)
##     zone text, each in a 5 px frame (strip UV 2,249-180,254) 5 px larger;
##   * ✓ (163,536)-(237,584) UV 81,2-155,50, tip 80100 "Go to Game Zone",
##     hidden when no entrance can be reached; ✗ (563,536)-(637,584) UV
##     160,2-234,50, tip 80101;
##   * five quest rows (60,30+24k)-(360,54+24k), tip 80111: GS vars
##     "q.<zone>.<quest>" ≠ 0, sorted by name; the «quest <id>» title in
##     (86,33+24k)-(370,54+24k), an icon from "cross" (62,31+24k)-(79,53+24k)
##     UV 4,164-72,252 for state 3 (X), U + 68 for state 2 (V), none else; the
##     selected row under a bar (60,30+24k)-(370,54+24k)
##   * description (60,190)-(384,510): the quest text, «string
##     obj_cost_exp» / «obj_cost_money» with the quests db experience / money
##     when > 0 (white), then per "#subobj n" whose var "q.<zone>.<q>.<n>" ≠
##     0 its title with «obj_completed» (state 2) or
##     «obj_failed» (3) and its text
##   * zone picture centred at (580,190), half size 150·(W, H)/max(W, H) (zone
##     size in sectors), UV (0, 256·(1 − H/max))-(256·W/max, 256);
##   * a zone point (x, y) maps to (580 + (x − 16W)·300/(32 max), 190 −
##     (y − 16H)·300/(32 max));
##   * entrances: every exit whose target is not "none", a 20 px triangle at its
##     deploy centre (saveload UV 240,226 / 227,254 / 253,254, pointing into the
##     map from the nearest edge; U − 32 = red when no route reaches it), tip
##     80110; the selected one ×1.2 and white with alpha (0.6 + 0.4 cos 5t),
##     the others with alpha (0.5 + 0.3 cos 2.5t); the entrance with
##     the smallest route time is selected first;
##   * the selected quest's area ("#quest" second line in map.txt): "cross" UV
##     0,0-128,128 as 20×20 crosses tinted red with alpha (0.6 + 0.4 cos 5t),
##     tip 80112;
##   * «zone <id>»: title (410,385)-(750,405) centred, text
##     (420,405)-(740,520) centred and word-wrapped.
## ✓ / Enter: buttons\tutorial\ok.wav and travel (time, entrance); ✗ / Esc:
## buttons\messbox\cancel.wav, back to the map; a quest row: objectives\
## select.wav; Up / Down / PgUp / PgDn move the selection by 1 / 5 (select.wav);
## an entrance: objectives\enter.wav, or cancel.wav when it cannot be reached.
## The bottom box (285,541)-(515,579) with «obj_0» "Travel time:" is hidden by
## every entrance selection, so it never shows.
## Other modes ((zone, route, travel, browse)):
##   * "field" (TAB / keyboard.ini "obj", or the clock dial's inner disc, in
##     a game zone: case 4, buttons\battle\click.wav first) and
##     "village" (TAB in a village, browse): only ✓ (363,536)-(437,584) UV
##     81,2-155,50, tip 80102, no ✗; ✓ / Enter / Esc: tutorial\ok.wav and
##     close, TAB: messbox\ok.wav and close. The entrances are drawn with none
##     selected, all with the unselected pulse, red when GS var
##     "z.<target zone>" = 1; a click on one only plays messbox\cancel.wav.
##   * "village": the zones with a quest var "q.<zone>.<q>" = 1 on the
##     village's allod (any allod in co-op), else the last quest's zone; the
##     screen opens on the last given quest's zone; with more than one zone
##     the arrows (414,384)-(443,404) UV 2,114-31,134 tip 80200 and
##     (717,384)-(746,404) UV 33,114-62,134 tip 80201 step through them
##     (wrapping, everything refilled, no sound).
## First row: in the village the last row named like the
## interface's last given quest (CampaignState.last_quest); else the last row
## named like the last row shown on this screen in any mode (
## `last_row`, kept across screens, not saved); else row 0.
## Scrolling: the quest list's bar (
## (60,30)-(384,150), speed 1.0, range count − 5
## ) moves one row a wheel notch over (60,30)-(374,150); the
## description is a ScrollText (at (60,190)-(384,510), speed
## 20.0, text 310 wide, its bar at x 374..384 only on overflow): 20 units a
## notch over (60,190)-(374,510).
## Both bars are the dialog box's (DialogPanel.Bar / paint_bar): "Scrollbar"
## sprites, thumb drag, held arrows at speed · 16 units a second (16 rows /
## 320 px of 800×600 a second), hidden while nothing scrolls.
## Every opener (global map, field TAB, clock dial
## village) pushes it (screen, 1, 1): the frame under
## it captured, greyed and frozen (Interface800.dim_layer), the map's own
## panels and buttons included.
## Layout fits the authored 800×600 frame uniformly inside the window; font 1
## follows that same scale. In remake co-op only the party leader has ✓
## (clients browse read-only).

signal confirmed(option: Dictionary)
signal back

const TEXT := Color8(0xe4, 0xd7, 0xa7)
const TITLE := Color8(0xff, 0xb3, 0x31)
const FRAME_UV := Rect2(2, 249, 178, 5)
const BTN_OK := [Rect2(163, 536, 74, 48), Rect2(81, 2, 74, 48), 80100]
const BTN_BACK := [Rect2(563, 536, 74, 48), Rect2(160, 2, 74, 48), 80101]
const BTN_CLOSE := [Rect2(363, 536, 74, 48), Rect2(81, 2, 74, 48), 80102]
const BTN_PREV := [Rect2(414, 384, 29, 20), Rect2(2, 114, 29, 20), 80200]
const BTN_NEXT := [Rect2(717, 384, 29, 20), Rect2(33, 114, 29, 20), 80201]
const ROWS := 5
const PIC := Vector2(580, 190)

## the name of the last quest row shown, in any mode.
static var last_row := ""

var session: Session
var zone := ""
var leader := true
## "travel" (global map), "field" (TAB in a game zone), "village" (TAB in a village).
var mode := "travel"
## Browse mode: the zones stepped through by the arrows.
var zones: PackedStringArray = []
var zone_i := 0
## Route options for this zone (Session travel_options entries).
var options: Array = []
var quests: PackedStringArray = []
var sel := 0
var top := 0
## Entrances: {n, at: Vector2 (800×600), dir: Vector2 (apex -> base), ok: bool, hours}
var entrances: Array = []
var entrance := -1
var _ui: Texture2D
var _cross: Texture2D
var _pic: Texture2D
var _pic_rect := Rect2()
var _pic_uv := Rect2()
var _areas := PackedVector2Array()
var _desc: RichTextLabel
var _zone_desc: RichTextLabel
var _title := ""
var _text := ""
var _t := 0.0
var _size := Vector2(1, 1)   # zone size in sectors
var _tutorial: TutorialPanel
##  bars (DialogPanel.Bar, "Scrollbar" sprites, hidden while
## nothing scrolls): the quest list in rows, the description in screen px.
var _list_bar := DialogPanel.Bar.new(Rect2(60, 30, 324, 120), 1.0)
var _desc_bar := DialogPanel.Bar.new(Rect2(60, 190, 324, 320), 20.0)
var _zone_bar := DialogPanel.Bar.new(Rect2(420, 405, 320, 110), 20.0)


func _ready() -> void:
	_layout()
	var dim := Interface800.dim_layer()   # (screen, 1, 1)
	add_child(dim)
	move_child(dim, 0)
	dim.capture()


func setup(s: Session, id: String, opts: Array, is_leader := true, how := "travel") -> void:
	session = s
	leader = is_leader
	mode = how
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_ui = _flipped("saveload")
	_cross = _flipped("cross")
	_desc = _scroll_text()
	_desc.bbcode_enabled = true
	_zone_desc = _scroll_text()
	# Tutorial (slot 41): "quest_global_map" when
	# opened from the global map (travel set), else "quest_mission"
	# the build ends (0) (first visit).
	_tutorial = TutorialPanel.new()
	add_child(_tutorial)
	_tutorial.ready.connect(screen_tutorial)
	resized.connect(_layout)
	if mode == "village":
		zones = browse_zones(s)
		zone_i = 0
		for i in zones.size():
			if _has_quest(s, zones[i], s.state.last_quest):
				zone_i = i
		id = zones[zone_i] if not zones.is_empty() else id
	_fill(id, opts)
	_layout()


func _scroll_text() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.scroll_active = true
	# Route wheel and drag input through this screen, including the area over
	# the invisible native scrollbar. Only the original painted bars handle it.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", Interface800.font())
	label.add_theme_color_override("default_color", TEXT)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Interface800.SHADOW)
	add_child(label)
	var vsb := label.get_v_scroll_bar()
	vsb.modulate = Color(1, 1, 1, 0)   # drawn as the original's bar instead
	vsb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The browse mode's zones: every zone with a quest var "q.<zone>.<q>" = 1
## on the current village's allod (any allod in co-op), else the last given
## quest's zone. Empty = nothing to show (the TAB pre-check).
static func browse_zones(s: Session) -> PackedStringArray:
	var allod := String(s.campaign.zone(s.zone_id).get("allod", ""))
	var out: PackedStringArray = []
	for k: String in s.state.vars:
		if not k.begins_with("0:q.") or k.get_slice_count(".") != 3 or not is_equal_approx(float(s.state.vars[k]), 1.0):
			continue
		var z := k.get_slice(".", 1)
		if out.has(z):
			continue
		if s.players.size() <= 1 and String(s.campaign.zone(z).get("allod", "")) != allod:
			continue
		out.append(z)
	if out.is_empty() and s.state.last_quest != "":
		for k: String in s.state.vars:
			if k.begins_with("0:q.") and k.get_slice_count(".") == 3 and k.get_slice(".", 2) == s.state.last_quest:
				out.append(k.get_slice(".", 1))
				break
	return out


static func _has_quest(s: Session, z: String, q: String) -> bool:
	return q != "" and s.state.vars.has("0:q.%s.%s" % [z, q])


## picture, entrances, quest rows and zone text of zone `id`.
func _fill(id: String, opts: Array) -> void:
	zone = id
	options = opts.filter(func(o): return String(o.zone) == id)
	entrances.clear()
	entrance = -1
	quests = PackedStringArray()
	sel = 0
	top = 0
	_pic = null
	var s := session
	var z := s.campaign.zone(id)
	var sz: Vector2i = z.get("size", Vector2i(1, 1))
	_size = Vector2(maxi(sz.x, 1), maxi(sz.y, 1))
	var m := maxf(_size.x, _size.y)
	var half := _size / m * 150.0
	_pic_rect = Rect2(PIC - half, half * 2.0)
	_pic_uv = Rect2(0, 256.0 * (1.0 - _size.y / m), 256.0 * _size.x / m, 256.0 * _size.y / m)
	if String(z.get("objtex", "")) != "":
		_pic = _flipped(String(z.objtex))
	# Entrances: reachable by the route in travel mode; with no
	# route enabled while GS var "z.<target zone>" is not 1, none selected.
	var best := INF
	var keys: Array = z.get("exits", {}).keys()
	keys.sort()
	for n: int in keys:
		var ex: Dictionary = z.exits[n]
		if String(ex.get("to", "none")) == "none" or not ex.has("deploy"):
			continue
		var c: Vector2 = (ex.deploy as Rect2).get_center()
		var o := _option(n)
		var ok := not o.is_empty() if mode == "travel" \
			else not is_equal_approx(s.state.get_var(0, "z." + String(ex.to).to_lower()), 1.0)
		if mode != "travel" and id == s.zone_id and s.world != null and s.lmp.is_empty():
			ok = s._exit_is_open(n)
		var e := {"n": n, "at": _zone_point(c), "dir": _edge_dir(c), "ok": ok,
			"hours": float(o.get("hours", 0.0))}
		if mode == "travel" and e.ok and e.hours < best:
			best = e.hours
			entrance = entrances.size()
		entrances.append(e)
	# Quests (GS vars q.<zone>.<quest> ≠ 0).
	var prefix := "0:q.%s." % id
	for k: String in s.state.vars:
		if k.begins_with(prefix) and k.get_slice_count(".") == 3 and not is_zero_approx(float(s.state.vars[k])):
			quests.append(k.get_slice(".", 2))
	quests.sort()
	var zt := GameData.text("zone " + id).split("\n")
	_title = zt[0].strip_edges() if zt.size() else id
	_text = _paragraph(zt, 1)
	_zone_desc.clear()
	_zone_desc.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_zone_desc.add_text(_text)
	_zone_desc.pop()
	_zone_desc.scroll_to_line(0)
	_zone_bar.held = 0
	_zone_bar.set_pos(0)
	# First row: the last one named like the last given quest (village) or
	# the last row shown, else row 0.
	var want := s.state.last_quest if mode == "village" else last_row
	var first := 0
	for i in quests.size():
		if String(quests[i]).to_lower() == want.to_lower():
			first = i
	_select(first)


func _flipped(name: String) -> Texture2D:
	var img := GameData.load_image(name)
	if img == null:
		return null
	img.flip_y()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _option(n: int) -> Dictionary:
	for o: Dictionary in options:
		if int(o.entrance) == n:
			return o
	return {}


func can_travel() -> bool:
	return entrance >= 0


## Zone units (32 per sector) -> 800×600 point on the picture.
func _zone_point(p: Vector2) -> Vector2:
	var w := _size.x * 32.0
	var h := _size.y * 32.0
	var m := maxf(w, h)
	return Vector2(PIC.x + (p.x - w * 0.5) * 300.0 / m, PIC.y - (p.y - h * 0.5) * 300.0 / m)


## the triangle points into the map from the nearest edge.
func _edge_dir(p: Vector2) -> Vector2:
	var dx := (p.x - _size.x * 16.0) / (_size.x * 32.0)
	var dy := (p.y - _size.y * 16.0) / (_size.y * 32.0)
	if absf(dx) <= absf(dy):
		return Vector2(0, 1) if dy <= 0.0 else Vector2(0, -1)
	return Vector2(1, 0) if dx > 0.0 else Vector2(-1, 0)


static func _paragraph(lines: PackedStringArray, from: int) -> String:
	var out := ""
	for i in range(from, lines.size()):
		var l := lines[i].strip_edges()
		if l.begins_with("#"):
			break
		if l:
			out += (" " if out else "") + l
	return out


# ------------------------------------------------------------------ quests

func _select(i: int) -> void:
	if quests.is_empty():
		sel = -1
		_areas = PackedVector2Array()
		_desc.text = ""
		queue_redraw()
		return
	# clamp and keep the row in the five visible ones.
	sel = clampi(i, 0, quests.size() - 1)
	if top + ROWS <= sel:
		top = sel - (ROWS - 1)
	if sel < top:
		top = sel
	var q := quests[sel]
	last_row = q
	_desc.text = description(q)
	_desc.scroll_to_line(0)
	_areas = PackedVector2Array()
	var places: PackedVector2Array = session.campaign.quest_areas.get(q, PackedVector2Array())
	if places.is_empty():
		places = SideQuests.quest_places(q)
	for p: Vector2 in places:
		_areas.append(_zone_point(p))
	queue_redraw()


##  text, as BBCode.
func description(q: String) -> String:
	var lines := SideQuests.quest_doc(q).split("\n")
	var s := "[color=#e4d7a7]%s[/color]\n" % _paragraph(lines, 1)
	var row: Dictionary = GameData.db.find("quests", q) if GameData.db else {}
	if row.is_empty():
		var record: Dictionary = SideQuests.get_quest(q).get("reg", {}).get("quest", {})
		row = {"experience": record.get("exp", 0), "money": record.get("money", 0)}
	for f: Array in [["experience", "obj_cost_exp"], ["money", "obj_cost_money"]]:
		var v := float(row.get(f[0], 0.0))
		if v > 0.0:
			s += "[color=#ffffff]%s %d[/color]\n" % [_str(f[1]), int(v)]
	for i in lines.size():
		var l := lines[i].strip_edges()
		if not l.begins_with("#subobj"):
			continue
		var n := l.substr(7).strip_edges()
		var st := int(session.state.get_var(0, "q.%s.%s.%s" % [zone, q, n]))
		if st == 0:
			continue
		var title := lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
		s += "[color=#ffb331]%s[/color] " % title
		match st:
			2: s += "[color=#74dc01]%s[/color]" % _str("obj_completed")
			3: s += "[color=#ff6048]%s[/color]" % _str("obj_failed")
		s += "\n\n[color=#e4d7a7]%s[/color]\n\n" % _paragraph(lines, i + 2)
	return s


static func _str(key: String) -> String:
	return GameData.text("string " + key).strip_edges()


# ------------------------------------------------------------------ layout

func _k() -> float:
	return UiScale.fit(size)


func _kv() -> Vector2:
	return Vector2.ONE * _k()


func _origin() -> Vector2:
	return Interface800.fit_rect(Rect2(Vector2.ZERO, size)).position


func _r(r: Rect2) -> Rect2:
	return Rect2(_p(r.position), r.size * _kv())


func _p(p: Vector2) -> Vector2:
	return _origin() + p * _kv()


func _layout() -> void:
	for pair: Array in [[_desc, _desc_bar], [_zone_desc, _zone_bar]]:
		var label: RichTextLabel = pair[0]
		if not is_instance_valid(label):
			continue
		var r := _r(pair[1].rect)
		r.size.x -= 10.0 * _k()
		label.position = r.position
		label.size = r.size
		label.add_theme_font_size_override("normal_font_size", _font_px())


func _process(frame_dt: float) -> void:
	var dt := UiTime.real(frame_dt)   # interface animations keep real time
	_t += dt
	_list_bar.max_pos = maxf(0.0, quests.size() - ROWS)
	if _list_bar.held >= 2:
		_list_bar.hold(dt)
	if _list_bar.held:
		top = int(_list_bar.pos)
	else:
		_list_bar.set_pos(top)
	for pair: Array in [[_desc, _desc_bar], [_zone_desc, _zone_bar]]:
		var sb: VScrollBar = pair[0].get_v_scroll_bar()
		var bar: DialogPanel.Bar = pair[1]
		bar.unit = 1.0 / _k()
		bar.max_pos = maxf(0.0, sb.max_value - sb.page)
		if bar.held >= 2:
			bar.hold(dt)
		if bar.held:
			sb.value = bar.pos
		else:
			bar.set_pos(sb.value)
	queue_redraw()


func _draw() -> void:
	for p: Array in [[Rect2(50, 20, 340, 140), Rect2(45, 15, 350, 150)], [Rect2(50, 180, 340, 340), Rect2(45, 175, 350, 350)],
			[Rect2(410, 20, 340, 340), Rect2(405, 15, 350, 350)], [Rect2(410, 380, 340, 140), Rect2(405, 375, 350, 150)]]:
		_panel(p[0], p[1])
	# Buttons.
	if _ui:
		if mode != "travel":
			draw_texture_rect_region(_ui, _r(BTN_CLOSE[0]), Interface800.atlas_region(_ui, BTN_CLOSE[1]))
			if zones.size() > 1:
				draw_texture_rect_region(_ui, _r(BTN_PREV[0]), Interface800.atlas_region(_ui, BTN_PREV[1]))
				draw_texture_rect_region(_ui, _r(BTN_NEXT[0]), Interface800.atlas_region(_ui, BTN_NEXT[1]))
		else:
			if leader and can_travel():
				draw_texture_rect_region(_ui, _r(BTN_OK[0]), Interface800.atlas_region(_ui, BTN_OK[1]))
			draw_texture_rect_region(_ui, _r(BTN_BACK[0]), Interface800.atlas_region(_ui, BTN_BACK[1]))
	# Quest rows.
	for row in ROWS:
		var i := top + row
		if i >= quests.size():
			break
		var y := 30.0 + 24.0 * row
		if i == sel:
			draw_rect(_r(Rect2(60, y, 310, 24)), Color8(0xa0, 0x68, 0x00, 0xc8))
		var st := int(session.state.get_var(0, "q.%s.%s" % [zone, quests[i]]))
		if _cross and st in [2, 3]:
			var u := 68.0 if st == 2 else 0.0
			var s := _cross.get_size() / 256.0
			draw_texture_rect_region(_cross, _r(Rect2(62, y + 1, 17, 22)), Rect2(Vector2(4 + u, 164) * s, Vector2(68, 88) * s))
		var title := SideQuests.quest_doc(quests[i]).get_slice("\n", 0).strip_edges()
		_label(Rect2(86, y + 3, 284, 21), title if title else quests[i], TEXT)
	DialogPanel.paint_bar(self, _list_bar, _r)
	DialogPanel.paint_bar(self, _desc_bar, _r)
	DialogPanel.paint_bar(self, _zone_bar, _r)
	# Zone picture, quest area, entrances.
	if _pic:
		var s := _pic.get_size() / 256.0
		draw_texture_rect_region(_pic, _r(_pic_rect), Rect2(_pic_uv.position * s, _pic_uv.size * s))
	var a2 := 0.6 + 0.4 * cos(_t * 5.0)
	var a1 := 0.5 + 0.3 * cos(_t * 2.5)
	if _cross:
		var s := _cross.get_size() / 256.0
		for p: Vector2 in _areas:
			draw_texture_rect_region(_cross, _r(Rect2(p - Vector2(10, 10), Vector2(20, 20))), Rect2(Vector2.ZERO, Vector2(128, 128) * s), Color(1, 0, 0, a2))
	for i in entrances.size():
		var e: Dictionary = entrances[i]
		var on := i == entrance
		var col := Color(1, 1, 1, a2) if on else Color8(0xc8, 0xc8, 0xc8, int(a1 * 255.0))
		var u := 0.0 if on or e.ok else -32.0
		_triangle(e.at, e.dir, 1.2 if on else 1.0, u, col)
	# Zone text.
	_label(Rect2(410, 385, 340, 20), _title, TITLE, HORIZONTAL_ALIGNMENT_CENTER)


## Entrance marker: apex at `at`, base 20 px along `dir`, 20 px wide.
func _triangle(at: Vector2, dir: Vector2, scale: float, u: float, col: Color) -> void:
	if _ui == null:
		return
	var side := dir.orthogonal()
	var pts := PackedVector2Array([_p(at), _p(at + (dir * 20.0 - side * 10.0) * scale), _p(at + (dir * 20.0 + side * 10.0) * scale)])
	var s := Vector2(256, 256)
	var uvs := PackedVector2Array([Vector2(240 + u, 226) / s, Vector2(227 + u, 254) / s, Vector2(253 + u, 254) / s])
	draw_primitive(pts, PackedColorArray([col, col, col]), uvs, _ui)


func _panel(bg: Rect2, frame: Rect2) -> void:
	draw_rect(_r(bg), Color(0, 0, 0, 0xa0 / 255.0))
	if _ui == null:
		return
	var w := 5.0
	var f := frame
	for seg: Array in [[Vector2(f.position.x, f.position.y + w * 0.5), Vector2(f.end.x, f.position.y + w * 0.5)],
			[Vector2(f.position.x, f.end.y - w * 0.5), Vector2(f.end.x, f.end.y - w * 0.5)],
			[Vector2(f.position.x + w * 0.5, f.position.y), Vector2(f.position.x + w * 0.5, f.end.y)],
			[Vector2(f.end.x - w * 0.5, f.position.y), Vector2(f.end.x - w * 0.5, f.end.y)]]:
		var d: Vector2 = (seg[1] - seg[0]).normalized().orthogonal() * w * 0.5
		var pts := PackedVector2Array()
		for p: Vector2 in [seg[0] - d, seg[1] - d, seg[1] + d, seg[0] + d]:
			pts.append(_p(p))
		var s := Vector2(256, 256)
		var uv := FRAME_UV
		draw_primitive(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
			PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s, Vector2(uv.position.x, uv.end.y) / s]), _ui)


## one line with a 1 px shadow, vertically centred.
func _label(r: Rect2, s: String, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := Interface800.font()
	var fs := _font_px()
	var rr := _r(r)
	var y := rr.position.y + (rr.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(rr.position.x + 1, y + 1), s, align, rr.size.x, fs, Interface800.SHADOW)
	draw_string(font, Vector2(rr.position.x, y), s, align, rr.size.x, fs, col)


## The screen's texts are all CInterface3D font 1 (the draws
##  and the ScrollText): Times New Roman
## 0.01867 × fitted interface width em.
func _font_px() -> int:
	return UiScale.font_px(_k(), 1)


# ------------------------------------------------------------------ input

##  order of the original's buttons: 0 ✓, 1 ✗, 4..8 rows, 9.. entrances.
func _hit(p: Vector2) -> Array:
	if mode != "travel":
		if _r(BTN_CLOSE[0]).has_point(p):
			return ["close"]
		if zones.size() > 1 and _r(BTN_PREV[0]).has_point(p):
			return ["prev"]
		if zones.size() > 1 and _r(BTN_NEXT[0]).has_point(p):
			return ["next"]
	else:
		if leader and can_travel() and _r(BTN_OK[0]).has_point(p):
			return ["ok"]
		if _r(BTN_BACK[0]).has_point(p):
			return ["back"]
	for row in ROWS:
		if top + row < quests.size() and _r(Rect2(60, 30 + 24 * row, 300, 24)).has_point(p):
			return ["row", top + row]
	for i in entrances.size():
		var e: Dictionary = entrances[i]
		var c: Vector2 = e.at + e.dir * 10.0
		if _r(Rect2(c - Vector2(10, 10), Vector2(20, 20))).has_point(p):
			return ["entrance", i]
	for c: Vector2 in _areas:
		if _r(Rect2(c - Vector2(10, 10), Vector2(20, 20))).has_point(p):
			return ["area"]
	return []


func _get_tooltip(at: Vector2) -> String:
	var h := _hit(at)
	if h.is_empty():
		return ""
	var tip: int = {"ok": 80100, "back": 80101, "close": 80102, "prev": 80200, "next": 80201,
		"row": 80111, "entrance": 80110, "area": 80112}[h[0]]
	return GameData.text("tip %d" % tip).strip_edges()


func _gui_input(e: InputEvent) -> void:
	var p800: Vector2 = (e.position - _origin()) / _kv() if e is InputEventMouse else Vector2.ZERO
	for b: DialogPanel.Bar in [_list_bar, _desc_bar, _zone_bar]:
		if e is InputEventMouseMotion and b.held == 1:
			b.drag(p800)
			if b != _list_bar:
				(_desc if b == _desc_bar else _zone_desc).get_v_scroll_bar().value = b.pos
			else:
				top = int(b.pos)
			accept_event()
			return
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			b.held = 0
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				for b: DialogPanel.Bar in [_list_bar, _desc_bar, _zone_bar]:
					if b.max_pos > 0.0 and b.press(p800):
						accept_event()
						return
				press(_hit(e.position))
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				for pair: Array in [[_desc, _desc_bar], [_zone_desc, _zone_bar]]:
					if _r(pair[1].rect).has_point(e.position):
						_text_wheel(e, pair[0])
						return
				if _r(Rect2(60, 30, 314, 120)).has_point(e.position):   #  rect
					var d := -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
					top = clampi(top + d, 0, maxi(0, quests.size() - ROWS))
					queue_redraw()
		accept_event()


## The description's wheel: 20 units a notch (speed 20.0).
func _text_wheel(e: InputEvent, label: RichTextLabel) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var sb := label.get_v_scroll_bar()
		sb.value += (-20.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 20.0) * _k()
		accept_event()


func press(h: Array) -> void:
	if h.is_empty():
		return
	match h[0]:
		"ok": travel()
		"close": close("tutorial\\ok")
		"prev", "next":   #  cases 2 / 3: no sound
			zone_i = posmod(zone_i + (1 if h[0] == "next" else -1), zones.size())
			_fill(zones[zone_i], [])
		"back":
			_sound("messbox\\cancel")
			back.emit()
		"row":
			_sound("objectives\\select")
			_select(h[1])
		"entrance":
			if mode == "travel" and leader and entrances[h[1]].ok:
				_sound("objectives\\enter")
				entrance = h[1]
			else:
				_sound("messbox\\cancel")


## the selected entrance's route (time, entrance).
func travel() -> void:
	_sound("tutorial\\ok")
	if leader and can_travel():
		confirmed.emit(_option(int(entrances[entrance].n)))


## Closes a field / village screen (`back`).
func close(snd: String) -> void:
	_sound(snd)
	back.emit()


func screen_tutorial(forced := false) -> void:
	_tutorial.show_screen("quest_global_map" if mode == "travel" else "quest_mission", forced)


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not (e is InputEventKey and e.pressed):
		return
	if _tutorial.blocks_input():
		return   # the tutorial window has the keys
	if not e.echo and EIKeymap.event_action(e) == "tutorial_script":
		screen_tutorial(true)   # (1)
		get_viewport().set_input_as_handled()
		return
	if mode != "travel":
		if e.echo:
			return
		if UiInput.is_confirm(e) or UiInput.is_cancel(e):
			close("tutorial\\ok")
			get_viewport().set_input_as_handled()
			return
		var direct := session.game.direct if session.game else null
		var quests_key := EIKeymap.direct_event(e) == "direct_quests" if direct and direct.active() else EIKeymap.event_action(e) == "obj"
		if quests_key:
			close("messbox\\ok")
			get_viewport().set_input_as_handled()
			return
	if UiInput.is_cancel(e):
		_sound("messbox\\cancel")
		back.emit()
	elif UiInput.is_confirm(e):
		travel()
	else:
		match e.keycode:
			KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
				_sound("objectives\\select")
				_select(sel + {KEY_UP: -1, KEY_DOWN: 1, KEY_PAGEUP: -5, KEY_PAGEDOWN: 5}[e.keycode])
			_:
				return
	get_viewport().set_input_as_handled()


func _sound(name: String) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.stream = EIAudio.sfx("buttons\\%s.wav" % name)
	add_child(s)
	s.play()
	s.finished.connect(s.queue_free)


func wiki_context() -> Dictionary:
	if _tutorial.blocks_input(): return {}
	var p := get_local_mouse_position()
	var hit := _hit(p)
	if not hit.is_empty() and hit[0] == "row":
		return {"key": "quest/" + String(quests[int(hit[1])]).uri_encode()}
	if not quests.is_empty() and _r(_desc_bar.rect).has_point(p):
		return {"key": "quest/" + String(quests[clampi(sel, 0, quests.size() - 1)]).uri_encode()}
	if _r(Rect2(420, 30, 320, 485)).has_point(p): return {"key": "map/" + zone.uri_encode()}
	return {}
