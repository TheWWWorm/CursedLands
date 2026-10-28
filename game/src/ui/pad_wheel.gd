class_name PadWheel
extends Control
## The gamepad's radial menus (docs/gamepad_design.md §6): the action wheels
## (LB spells / actions, RB belt / weapons, paged with LB / RB), the system
## wheel (RT) and the context ring on a target (X). Drawn in the original HUD's
## look: a dark disc, bronze pie sections with gold rims, the selected
## section lit with the Options screen's bar colour, Times-style text
## (Interface800); spell pictures are the HUD's own (SpellSlots.icon), belt and
## weapon cells their 3D models (ItemView), the aimed strikes the original
## cursor_attack_* strips (the picked one animated at the cursor rate, 125 ms).
## Entries: {id, label, tip, icon: Texture2D, item: String, strip: Array,
## angle: degrees clockwise from up (optional), enabled, on (a lit state such
## as the active weapon)}.

const FRAME_SEC := 0.125
const INNER_RADIUS_RATIO := 0.52
const BRONZE := Color8(176, 124, 50)
const BRONZE_HI := Color8(238, 204, 128)
const BRONZE_DARK := Color8(58, 38, 12)
const CELL := Color8(24, 15, 4, 235)

var title := ""
var pages: PackedStringArray = []
var page := 0
var entries: Array = []
var selected := -1
## Hints along the bottom: [[button name, text], …] (PadInput glyphs).
var hints: Array = []
var _views: Array[ItemView] = []
var _t := 0.0
var _content_scale := 1.0
var _center_entry := {}
var _anchor := Vector2.INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	for i in 12:
		var v := ItemView.new()
		v.visible = false
		add_child(v)
		_views.append(v)


## An optional centre action is selected when the mouse returns inside the
## inner ring. Other wheels keep -1 as no selection.
func open(new_entries: Array, preselect := -1, content_scale := 1.0, center_entry: Dictionary = {}, anchor := Vector2.INF) -> void:
	entries = new_entries
	_content_scale = content_scale
	_center_entry = center_entry
	_anchor = anchor
	selected = preselect if preselect >= 0 and preselect < entries.size() else -1
	_t = 0.0
	visible = true
	_place_items()
	queue_redraw()


func close() -> void:
	visible = false
	for v in _views:
		v.visible = false
		v.show_item("")


func current() -> Dictionary:
	return entries[selected] if selected >= 0 and selected < entries.size() else _center_entry


## Mouse position in this control's coordinates. The whole visible centre
## selects its optional action; an ordinary wheel keeps its small dead zone.
func hover(point: Vector2) -> void:
	var g := _geom()
	var offset := point - (g[0] as Vector2)
	var inner := INNER_RADIUS_RATIO if not _center_entry.is_empty() else 0.16
	if offset.length() <= float(g[1]) * inner:
		selected = -1
		queue_redraw()
	else:
		flick(offset.normalized())


## The sector's direction, degrees clockwise from up.
func angle_of(i: int) -> float:
	var e: Dictionary = entries[i]
	if e.has("angle"):
		return float(e.angle)
	return 360.0 * i / maxf(1.0, entries.size())


## A stick flick past 0.5 picks the sector nearest its direction. Returns
## whether the stick picked one.
func flick(v: Vector2) -> bool:
	if v.length() < 0.5 or entries.is_empty():
		return false
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	var best := -1
	var bd := INF
	for i in entries.size():
		var d := absf(wrapf(a - angle_of(i), -180.0, 180.0))
		if d < bd:
			bd = d
			best = i
	# Keep the current sector near a boundary instead of alternating parts
	# with tiny stick movements. D-pad navigation remains exact.
	if selected >= 0 and absf(wrapf(a - angle_of(selected), -180.0, 180.0)) <= bd + 8.0:
		best = selected
	if best != selected:
		selected = best
		queue_redraw()
	return true


func cycle(step: int) -> void:
	if entries.is_empty(): return
	var indices := range(entries.size())
	indices.sort_custom(func(a, b): return angle_of(a) < angle_of(b))
	var i := indices.find(selected)
	selected = indices[posmod(i + step, indices.size())] if i >= 0 else indices[0 if step > 0 else -1]
	queue_redraw()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt / maxf(Engine.time_scale, 0.001)
	_place_items()
	queue_redraw()


func _geom() -> Array:
	var vs := size
	var r := minf(vs.x, vs.y) * 0.25 * _content_scale
	var c := vs * 0.5 + Vector2(0, -vs.y * 0.06)
	var cell := r * (0.34 if entries.size() <= 8 else 0.29)
	if _anchor.is_finite():
		var k := UiScale.by_min_side(vs) * _content_scale
		var outer := r + cell * 1.35
		# Reserve room for the title and the four-line help below the disc.
		var half_width := maxf(outer + 4.0 * k, 300.0 * k)
		var above := outer + (48.0 if pages.size() > 1 else 26.0) * k
		var below := outer + 120.0 * k
		c = Vector2(clampf(_anchor.x, half_width, maxf(half_width, vs.x - half_width)),
			clampf(_anchor.y, above, maxf(above, vs.y - below)))
	return [c, r, cell]


func _cell_center(i: int) -> Vector2:
	var g := _geom()
	var a := deg_to_rad(angle_of(i))
	return (g[0] as Vector2) + Vector2(sin(a), -cos(a)) * float(g[1])


func _place_items() -> void:
	var g := _geom()
	var cell: float = g[2]
	for i in _views.size():
		var v := _views[i]
		var item := ""
		if i < entries.size():
			item = String((entries[i] as Dictionary).get("item", ""))
		v.visible = item != ""
		if item != "":
			var c := _cell_center(i)
			v.position = c - Vector2(cell, cell) * 0.85
			v.size = Vector2(cell, cell) * 1.7
			v.unit_px = 0.0
			v.spin = i == selected
			if v.item != item:
				v.show_item(item)
			v.modulate = Color.WHITE if (entries[i] as Dictionary).get("enabled", true) else Color(0.45, 0.45, 0.45)


## Boundaries follow the same nearest-angle sectors used by flick().
func _draw_sectors(c: Vector2, inner: float, outer: float, k: float) -> void:
	for i in entries.size():
		var e: Dictionary = entries[i]
		var angle := angle_of(i)
		var before := 360.0
		var after := 360.0
		for j in entries.size():
			if i == j: continue
			before = minf(before, fposmod(angle - angle_of(j), 360.0))
			after = minf(after, fposmod(angle_of(j) - angle, 360.0))
		var start := deg_to_rad(angle - before * 0.5)
		var end := deg_to_rad(angle + after * 0.5)
		var points := PackedVector2Array()
		for step in 17:
			var a := lerpf(start, end, step / 16.0)
			points.append(c + Vector2(sin(a), -cos(a)) * outer)
		for step in 17:
			var a := lerpf(end, start, step / 16.0)
			points.append(c + Vector2(sin(a), -cos(a)) * inner)
		var enabled: bool = e.get("enabled", true)
		var on: bool = e.get("on", false)
		var fill := Interface800.BAR if i == selected else CELL
		if not enabled: fill = fill.darkened(0.45)
		draw_colored_polygon(points, fill)
		points.append(points[0])
		draw_polyline(points, BRONZE_HI if i == selected else BRONZE, (2.5 if i == selected else 1.5) * k, true)
		# The equipped weapon/current gait remains marked after moving focus.
		if on:
			draw_arc(c, outer - 4.0 * k, start - PI * 0.5 + 0.03, end - PI * 0.5 - 0.03,
				32, BRONZE_HI, 3.0 * k, true)


func _draw() -> void:
	if entries.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var g := _geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var cell: float = g[2]
	var k := UiScale.by_min_side(size) * _content_scale
	var font := Interface800.font()
	# The backing disc and its bronze ring.
	draw_circle(c, r + cell * 1.35, Interface800.PANEL)
	_draw_sectors(c, r * INNER_RADIUS_RATIO, r + cell * 1.3, k)
	if not _center_entry.is_empty():
		draw_circle(c, r * INNER_RADIUS_RATIO, Interface800.BAR if selected < 0 else CELL)
	draw_arc(c, r + cell * 1.35, 0.0, TAU, 96, BRONZE_DARK, 4.0 * k, true)
	draw_arc(c, r + cell * 1.3, 0.0, TAU, 96, BRONZE, 1.5 * k, true)
	draw_arc(c, r * INNER_RADIUS_RATIO, 0.0, TAU, 64,
		BRONZE_HI if selected < 0 and not _center_entry.is_empty() else BRONZE, 1.5 * k, true)
	# The selection's pointer from the centre.
	if selected >= 0:
		var a := deg_to_rad(angle_of(selected))
		var dir := Vector2(sin(a), -cos(a))
		var tip := c + dir * (r * INNER_RADIUS_RATIO + 6.0 * k)
		var side := dir.orthogonal() * 7.0 * k
		draw_colored_polygon(PackedVector2Array([tip + dir * 9.0 * k, tip + side, tip - side]), BRONZE_HI)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var p := _cell_center(i)
		var sel := i == selected
		var enabled: bool = e.get("enabled", true)
		var mod := Color.WHITE if enabled else Color(0.4, 0.4, 0.4)
		var tex: Texture2D = e.get("icon")
		var strip: Array = e.get("strip", [])
		if not strip.is_empty():
			tex = strip[int(_t / FRAME_SEC) % strip.size()] if sel else strip[0]
		if tex:
			var caption := String(e.get("caption", ""))
			var s := cell * (1.25 if caption.is_empty() else 0.95)
			var centre := p if caption.is_empty() else p - Vector2(0, cell * 0.18)
			draw_texture_rect(tex, Rect2(centre - Vector2(s, s) * 0.5, Vector2(s, s)), false, mod)
			if not caption.is_empty():
				draw_string(font, p + Vector2(-cell, cell * 0.68), caption, HORIZONTAL_ALIGNMENT_CENTER,
					cell * 2.0, maxi(10, int(12.0 * k)), Interface800.TEXT if enabled else Interface800.GREY)
		elif String(e.get("item", "")) == "":
			var short := String(e.get("short", e.get("label", "")))
			var fs := maxi(8, int(13.0 * k))
			var lines := _wrap(short, font, fs, cell * 1.8)
			while fs > 8 and (lines.size() > 2 or _widest(lines, font, fs) > cell * 1.8):
				fs -= 1
				lines = _wrap(short, font, fs, cell * 1.8)
			var y := p.y + fs * 0.35 - (lines.size() - 1) * fs * 0.575
			for line in lines:
				draw_string(font, Vector2(p.x - cell, y), line, HORIZONTAL_ALIGNMENT_CENTER, cell * 2.0, fs,
					Interface800.TEXT if enabled else Interface800.GREY)
				y += fs * 1.15
	# Title and page names over the wheel, the picked entry's label in the
	# centre (or its persistent action) and the picked entry's tip below.
	var top := c.y - r - cell * 1.35 - 10.0 * k
	var fs_t := maxi(1, int(18.0 * k))
	if title != "":
		draw_string(font, Vector2(c.x - 300.0 * k, top - (22.0 * k if pages.size() > 1 else 0.0)), title,
			HORIZONTAL_ALIGNMENT_CENTER, 600.0 * k, fs_t, Interface800.TEXT)
	if pages.size() > 1:
		var parts: Array = []
		for i in pages.size():
			parts.append(("[%s]" if i == page else "%s") % pages[i])
		draw_string(font, Vector2(c.x - 300.0 * k, top), "   ".join(parts), HORIZONTAL_ALIGNMENT_CENTER, 600.0 * k,
			int(14.0 * k), Interface800.TEXT)
	var cur := current()
	if not cur.is_empty():
		var label := String((_center_entry if not _center_entry.is_empty() else cur).get("label", ""))
		var fs := maxi(10, int(15.0 * k)) if not _center_entry.is_empty() else int(15.0 * k)
		var line_height := fs * 1.15
		var lines := _wrap(label, font, fs, r * 0.95)
		var y := c.y - (lines.size() - 1) * line_height * 0.5 + fs / 3.0
		for ln in lines:
			draw_string(font, Vector2(c.x - r * 0.5, y), ln, HORIZONTAL_ALIGNMENT_CENTER, r, fs,
				Interface800.TEXT if cur.get("enabled", true) else Interface800.GREY)
			y += line_height
		var tip := String(cur.get("tip", ""))
		if tip != "":
			var fs_tip := maxi(10, int(13.0 * k)) if not _center_entry.is_empty() else int(13.0 * k)
			var tip_height := maxf(fs_tip * 1.15, 15.0 * k)
			var ty := c.y + r + cell * 1.35 + 58.0 * k
			var tl := _wrap(tip, font, fs_tip, 520.0 * k).slice(0, 4)
			var tw := 0.0
			for ln in tl:
				tw = maxf(tw, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_tip).x)
			draw_rect(Rect2(c.x - tw * 0.5 - 10.0 * k, ty - tip_height, tw + 20.0 * k, tl.size() * tip_height + 8.0 * k), Interface800.PANEL)
			for ln in tl:
				draw_string(font, Vector2(c.x - 260.0 * k, ty), ln, HORIZONTAL_ALIGNMENT_CENTER, 520.0 * k,
					fs_tip, Interface800.TEXT)
				ty += tip_height
	# The button hints right under the wheel (clear of the party faces).
	PadPrompts.draw_hints(self, hints, Vector2(c.x, c.y + r + cell * 1.35 + 34.0 * k), k)


static func _widest(lines: PackedStringArray, font: Font, fs: int) -> float:
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return width


static func _wrap(s: String, font: Font, fs: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for w in para.split(" ", false):
			var t := w if line == "" else line + " " + w
			if line != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				out.append(line)
				line = w
			else:
				line = t
		if line != "":
			out.append(line)
	return out
