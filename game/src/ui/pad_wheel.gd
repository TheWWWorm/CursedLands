class_name PadWheel
extends Control
## The gamepad's radial menus (docs/gamepad_design.md §6): the action wheels
## (LB spells / actions, RB belt / weapons, paged with LB / RB), the system
## wheel (RT) and the context ring on a target (X). Drawn in the original HUD's
## look: a dark disc, bronze cells with gold rims, the selected
## cell lit with the Options screen's bar colour, Times-style text
## (Interface800); spell pictures are the HUD's own (SpellSlots.icon), belt and
## weapon cells their 3D models (ItemView), the aimed strikes the original
## cursor_attack_* strips (the picked one animated at the cursor rate, 125 ms).
## Entries: {id, label, tip, icon: Texture2D, item: String, strip: Array,
## angle: degrees clockwise from up (optional), enabled, on (a lit state such
## as the active weapon)}.

const FRAME_SEC := 0.125
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


func open(new_entries: Array, preselect := -1) -> void:
	entries = new_entries
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
	return entries[selected] if selected >= 0 and selected < entries.size() else {}


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
	var r := minf(vs.x, vs.y) * 0.25
	var c := vs * 0.5 + Vector2(0, -vs.y * 0.06)
	var cell := r * (0.34 if entries.size() <= 8 else 0.29)
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


func _draw() -> void:
	if entries.is_empty():
		return
	var g := _geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var cell: float = g[2]
	var k := size.y / 600.0
	var font := Interface800.font()
	# The backing disc and its bronze ring.
	draw_circle(c, r + cell * 1.35, Interface800.PANEL)
	draw_arc(c, r + cell * 1.35, 0.0, TAU, 96, BRONZE_DARK, 4.0 * k, true)
	draw_arc(c, r + cell * 1.3, 0.0, TAU, 96, BRONZE, 1.5 * k, true)
	draw_arc(c, r * 0.52, 0.0, TAU, 64, BRONZE, 1.5 * k, true)
	# The selection's pointer from the centre.
	if selected >= 0:
		var a := deg_to_rad(angle_of(selected))
		var dir := Vector2(sin(a), -cos(a))
		var tip := c + dir * (r * 0.52 + 6.0 * k)
		var side := dir.orthogonal() * 7.0 * k
		draw_colored_polygon(PackedVector2Array([tip + dir * 9.0 * k, tip + side, tip - side]), BRONZE_HI)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var p := _cell_center(i)
		var sel := i == selected
		var on: bool = e.get("on", false)
		var enabled: bool = e.get("enabled", true)
		draw_circle(p, cell + 3.0 * k, Color(0, 0, 0, 0.55))
		draw_circle(p, cell, Interface800.BAR if sel else CELL)
		draw_arc(p, cell, 0.0, TAU, 48, BRONZE_HI if sel or on else BRONZE, (3.0 if sel else 2.0) * k, true)
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
					cell * 2.0, int(12.0 * k), Interface800.TEXT)
		elif String(e.get("item", "")) == "":
			var short := String(e.get("short", e.get("label", "")))
			var fs := int(13.0 * k)
			var w := font.get_string_size(short, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			if w > cell * 1.8:
				fs = maxi(8, int(fs * cell * 1.8 / w))
			draw_string(font, p + Vector2(-cell, fs * 0.35), short, HORIZONTAL_ALIGNMENT_CENTER, cell * 2.0, fs,
				Interface800.TEXT if enabled else Interface800.GREY)
	# Title and page names over the wheel, the picked entry's label in the
	# centre and its tip under the wheel.
	var top := c.y - r - cell * 1.35 - 10.0 * k
	var fs_t := int(18.0 * k)
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
		var label := String(cur.get("label", ""))
		var lines := _wrap(label, font, int(15.0 * k), r * 0.95)
		var y := c.y - (lines.size() - 1) * 8.0 * k + 5.0 * k
		for ln in lines:
			draw_string(font, Vector2(c.x - r * 0.5, y), ln, HORIZONTAL_ALIGNMENT_CENTER, r, int(15.0 * k),
				Interface800.TEXT if cur.get("enabled", true) else Interface800.GREY)
			y += 17.0 * k
		var tip := String(cur.get("tip", ""))
		if tip != "":
			var ty := c.y + r + cell * 1.35 + 58.0 * k
			var tl := _wrap(tip, font, int(13.0 * k), 520.0 * k).slice(0, 4)
			var tw := 0.0
			for ln in tl:
				tw = maxf(tw, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * k)).x)
			draw_rect(Rect2(c.x - tw * 0.5 - 10.0 * k, ty - 15.0 * k, tw + 20.0 * k, (tl.size() * 15.0 + 8.0) * k), Interface800.PANEL)
			for ln in tl:
				draw_string(font, Vector2(c.x - 260.0 * k, ty), ln, HORIZONTAL_ALIGNMENT_CENTER, 520.0 * k,
					int(13.0 * k), Interface800.TEXT)
				ty += 15.0 * k
	# The button hints right under the wheel (clear of the party faces).
	PadPrompts.draw_hints(self, hints, Vector2(c.x, c.y + r + cell * 1.35 + 34.0 * k), k)


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
