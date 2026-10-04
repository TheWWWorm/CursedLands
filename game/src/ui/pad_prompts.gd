class_name PadPrompts
extends Control
## The gamepad's field overlay (docs/gamepad_design.md §5, §8.4), shown only
## while the pad drives: the highlighted target (a bronze ground ring and,
## above it, the original cursor of what A will do: attack, use, talk, steal,
## spell), the ground reticle of a spell aimed at a point, and a strip of
## button prompts above the party faces ("A Attack · X More · LB Spells …").
## The glyphs are the remake's own bronze button pictures (art/pad_glyphs,
## drawn by tools/make_pad_glyphs.py), named by PadInput's family.

var field: Node   # PadField
var _tex := {}
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	_t += dt / maxf(Engine.time_scale, 0.001)
	queue_redraw()


func _cursor_tex(kind: String, frame: int) -> Texture2D:
	var key := "%s:%d" % [kind, frame]
	if not _tex.has(key):
		var f := GameCursor.frames(kind)
		_tex[key] = ImageTexture.create_from_image(f[frame % f.size()]) if not f.is_empty() else null
	return _tex[key]


func _draw() -> void:
	if field == null or not field.call("overlay_visible"):
		return
	var k := size.y / 600.0
	var mark: Dictionary = field.call("marker")
	if not mark.is_empty():
		var feet: Vector2 = mark.feet
		var head: Vector2 = mark.head
		var col: Color = mark.get("color", PadWheel.BRONZE_HI)
		_ring(feet, 16.0 * k, col, k)
		# R3 held: the world labels name everything; the ring alone marks
		# the target, so its cursor and name do not cover a label.
		var info := bool(field.get("world_info"))
		var kind := "" if info else String(mark.get("cursor", ""))
		if kind != "":
			var n := GameCursor.frames(kind).size()
			var tex := _cursor_tex(kind, int(_t / 0.125) % maxi(1, n))
			if tex:
				var s := 26.0 * k
				draw_texture_rect(tex, Rect2(head + Vector2(-s * 0.5, -s - 4.0 * k), Vector2(s, s)), false)
		var name := "" if info else String(mark.get("name", ""))
		if name != "":
			var font := Interface800.font()
			var fs := int(12.0 * k)
			draw_string_outline(font, head + Vector2(-150.0 * k, -32.0 * k), name, HORIZONTAL_ALIGNMENT_CENTER, 300.0 * k, fs, int(3.0 * k), Color(0, 0, 0, 0.8))
			draw_string(font, head + Vector2(-150.0 * k, -32.0 * k), name, HORIZONTAL_ALIGNMENT_CENTER, 300.0 * k, fs, Interface800.TEXT)
	var ret: Variant = field.call("reticle_screen")
	if ret is Vector2:
		_ring(ret, 20.0 * k, Color8(150, 200, 255), k)
		draw_line(ret + Vector2(-8, 0) * k, ret + Vector2(8, 0) * k, Color8(150, 200, 255), 1.5 * k)
		draw_line(ret + Vector2(0, -8) * k, ret + Vector2(0, 8) * k, Color8(150, 200, 255), 1.5 * k)
	draw_hints(self, field.call("hints"), Vector2(size.x * 0.5, size.y - 128.0 * k), k)


func _ring(at: Vector2, r: float, col: Color, k: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		pts.append(at + Vector2(cos(a) * r, sin(a) * r * 0.45))
	var pulse := 0.65 + 0.35 * sin(_t * 5.0)
	draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0 * k, true)
	draw_polyline(pts, Color(col, pulse), 2.0 * k, true)


## A row of [glyph][text] prompts centred at `bottom_center` (its baseline).
## hints: [[button name or "", text, enabled?], …]; a disabled one is grey.
static func draw_hints(ci: CanvasItem, hints: Array, bottom_center: Vector2, k: float) -> void:
	if hints.is_empty():
		return
	var font := Interface800.font()
	var fs := int(13.0 * k)
	var gs := 22.0 * k
	var gap := 14.0 * k
	var widths: Array = []
	var total := 0.0
	for h: Array in hints:
		var w := font.get_string_size(String(h[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var gw := 0.0
		for b in String(h[0]).split("+", false):
			gw += gs + 2.0 * k
		widths.append([gw, w])
		total += gw + w + gap
	total -= gap
	var x := bottom_center.x - total * 0.5
	var y := bottom_center.y
	ci.draw_rect(Rect2(x - 10.0 * k, y - gs - 4.0 * k, total + 20.0 * k, gs + 8.0 * k), Color(0, 0, 0, 0.45))
	for i in hints.size():
		var h: Array = hints[i]
		var on: bool = h[2] if h.size() > 2 else true
		var mod := Color.WHITE if on else Color(0.45, 0.45, 0.45, 0.8)
		for b in String(h[0]).split("+", false):
			var tex := PadInput.glyph(b)
			if tex:
				ci.draw_texture_rect(tex, Rect2(Vector2(x, y - gs), Vector2(gs, gs)), false, mod)
			else:
				ci.draw_string(font, Vector2(x, y - 6.0 * k), PadInput.label(b), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Interface800.TEXT)
			x += gs + 2.0 * k
		ci.draw_string(font, Vector2(x + 3.0 * k, y - 6.0 * k), String(h[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Interface800.TEXT if on else Interface800.GREY)
		x += float(widths[i][1]) + gap
