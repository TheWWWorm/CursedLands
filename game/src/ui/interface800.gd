class_name Interface800
extends Control
## Drawing helpers shared by the original's 800×600 interface screens (the Options
## and network screens): every rect is in 800×600 units stretched to the window
## on each axis (: x · W/800, y · H/600) and the fonts follow the
## width (CInterface3D::Create: "Times New Roman", fonts 0 / 1 / 2
## = W · 0.01733 / 0.01867 / 0.024 px em, i.e. 14 / 15 / 19 px at 800 wide).
## - sprites: a rect with UVs in 256ths of the texture ("saveload"
##   "Scrollbar"; V as stored, the remake flips the images like the other screens);
## - frames: four mitred strips, saveload u 2..180, v 254 outer
##   249 inner;
## - text: one line in a rect, COLORREF colour, a 1 px
##   shadow at +1,+1, left / centred / right, from the rect's top.
## Sounds are game sfx "buttons\…\*.wav".

const TEXT := Color8(0xe4, 0xd7, 0xa7)      # COLORREF
const GREY := Color8(0xa0, 0xa0, 0xa0)      # COLORREF
const SHADOW := Color8(8, 8, 8)
const PANEL := Color(0, 0, 0, 0xa0 / 255.0)
const BAR := Color8(0xa0, 0x68, 0x00, 0xc8)  # the selection bar
const FONT_EM := [0.01733, 0.01867, 0.024]   # × screen width
const FONT_NAMES := ["Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"]

static var _font: Font
static var _tex := {}

static func canvas_size(control: CanvasItem) -> Vector2:
	var layer := control.get_canvas_layer_node()
	if layer and layer.has_method("ui_size"):
		return layer.call("ui_size")
	return control.get_viewport_rect().size

## The screen's text widget hidden: (0) on its first widget
## ([0], the GDI text surface over (100,100)-(700,500))
## while the board slides in (Options, Load / Save)
## the panels, frames, bar, sliders and buttons stay.
var hide_text := false


static func font() -> Font:
	if _font == null:
		if Portability.constrained():
			_font = load("res://fonts/LiberationSerif-Regular.ttf")
		else:
			var system_font := SystemFont.new()
			system_font.font_names = PackedStringArray(FONT_NAMES)
			_font = system_font
	return _font


## An interface texture with its rows flipped (the convention of the remake's
## other 800×600 screens; UVs below are in 256ths of that image).
static func tex(name: String) -> Texture2D:
	name = name.to_lower()
	if not _tex.has(name):
		var t: Texture2D = null
		if GameData.is_open():
			var img := GameData.load_image(name)
			if img:
				img.flip_y()
				t = ImageTexture.create_from_image(img)
		_tex[name] = t
	return _tex[name]


static func clear_cache() -> void:
	_tex.clear()


static func colorref(c: int) -> Color:
	return Color8(c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff)


# ------------------------------------------------------------------ mapping

var _touch_zoom := 1.0
var _touch_pan := Vector2.ZERO

func _safe() -> Rect2:
	# HUD screens are already inside the safe-area root. Standalone menus
	# apply the same symmetric safe area themselves.
	var layer := get_canvas_layer_node()
	return Rect2(Vector2.ZERO, size) if layer and layer.has_method("ui_size") else Portability.safe_rect(size)

func _origin() -> Vector2:
	var safe := _safe()
	return safe.position + (safe.size - safe.size * _touch_zoom) * 0.5 + _touch_pan

func kv() -> Vector2:
	return _safe().size * _touch_zoom / Vector2(800.0, 600.0)


func p8(v: Vector2) -> Vector2:
	return _origin() + v * kv()


func r8(r: Rect2) -> Rect2:
	return Rect2(p8(r.position), r.size * kv())


func to800(p: Vector2) -> Vector2:
	return (p - _origin()) / kv()


func font_px(i: int) -> int:
	return maxi(6, int(round(_safe().size.x * _touch_zoom * FONT_EM[i])))


# ------------------------------------------------------------------ drawing

## `uv` = (u0, v0, u1, v1) in 256ths at the rect's top-left
## bottom-right; `angle` turns the sprite about its centre (y down: +π/2 takes
## the texture's down to the left, as the original's horizontal scroll bar).
func sprite(t: Texture2D, r: Rect2, uv: Array, col := Color.WHITE, angle := 0.0) -> void:
	if t == null:
		return
	var c := r.get_center()
	var h := r.size * 0.5
	var pts := PackedVector2Array()
	for o: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		pts.append(p8(c + o.rotated(angle)))
	var u0 := Vector2(uv[0], uv[1]) / 256.0
	var u1 := Vector2(uv[2], uv[3]) / 256.0
	var uvs := PackedVector2Array([u0, Vector2(u1.x, u0.y), u1, Vector2(u0.x, u1.y)])
	draw_primitive(pts, PackedColorArray([col, col, col, col]), uvs, t)


## a w px frame; `r` is its outer rect.
func frame(r: Rect2, w := 5.0) -> void:
	var t := tex("saveload")
	if t == null:
		draw_rect(r8(r).grow(-w * 0.5 * kv().y), Color(0.55, 0.5, 0.4), false, w * kv().y)
		return
	var o := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var ii := [o[0] + Vector2(w, w), o[1] + Vector2(-w, w), o[2] - Vector2(w, w), o[3] + Vector2(w, -w)]
	var uo0 := Vector2(2, 254) / 256.0
	var uo1 := Vector2(180, 254) / 256.0
	var ui0 := Vector2(2, 249) / 256.0
	var ui1 := Vector2(180, 249) / 256.0
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for side in 4:
		var a: int = side
		var b: int = (side + 1) % 4
		draw_polygon(PackedVector2Array([p8(o[a]), p8(o[b]), p8(ii[b]), p8(ii[a])]), white,
			PackedVector2Array([uo0, uo1, ui1, ui0]), t)


## A black panel with its 5 px frame around it (frame = bg grown by 5).
func panel(bg: Rect2) -> void:
	draw_rect(r8(bg), PANEL)
	frame(bg.grow(5.0))


## one line from the rect's top (DrawText without DT_VCENTER)
## 1 px shadow.
## `clip`: DrawText without DT_END_ELLIPSIS (e.g. flags 0x800 DT_NOPREFIX):
## the line is cut at the rect's right edge (here at the last whole
## character that fits) instead of ending in "...".
func text(r: Rect2, s: String, font_i := 1, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, clip := false) -> void:
	if s.is_empty() or hide_text:
		return
	var f := font()
	var fs := font_px(font_i)
	var rr := r8(r)
	var y := rr.position.y + f.get_ascent(fs)
	var sh := maxf(1.0, round(kv().y))
	var w := rr.size.x
	# DT_END_ELLIPSIS-like clipping for left-aligned text that does not fit.
	if clip and align == HORIZONTAL_ALIGNMENT_LEFT:
		while s.length() > 0 and f.get_string_size(s, align, -1, fs).x > w:
			s = s.substr(0, s.length() - 1)
	elif align == HORIZONTAL_ALIGNMENT_LEFT and f.get_string_size(s, align, -1, fs).x > w:
		while s.length() > 1 and f.get_string_size(s + "...", align, -1, fs).x > w:
			s = s.substr(0, s.length() - 1)
		s += "..."
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		# DT_RIGHT: anchored at the right edge, spilling left rather than cut.
		var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > w:
			rr.position.x = rr.end.x - tw
			w = tw
	draw_string(f, Vector2(rr.position.x + sh, y + sh), s, align, w, fs, SHADOW)
	draw_string(f, Vector2(rr.position.x, y), s, align, w, fs, col)


## DrawText with DT_WORDBREAK: `s` broken into lines that fit `width` (800
## units) in font `font_i`; "\n" ends a line.
func wrap_text(s: String, width: float, font_i := 1) -> PackedStringArray:
	var f := font()
	var fs := font_px(font_i)
	var w := width * kv().x
	var out := PackedStringArray()
	for para in s.replace("\r", "").split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var t := word if line.is_empty() else line + " " + word
			if line.is_empty() or f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
				line = t
			else:
				out.append(line)
				line = word
		out.append(line)
	return out


## One font line's height in 800×600 units.
func line_h(font_i := 1) -> float:
	return font().get_height(font_px(font_i)) / kv().y


## DT_WORDBREAK text from the rect's top; returns its height (800 units).
func text_block(r: Rect2, s: String, font_i := 1, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var lines := wrap_text(s, r.size.x, font_i)
	var h := line_h(font_i)
	for i in lines.size():
		text(Rect2(r.position.x, r.position.y + h * i, r.size.x, h), lines[i], font_i, col, align)
	return h * lines.size()


func text_width(s: String, font_i := 1) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px(font_i)).x / kv().x


## The original's scroll bar class (texture "Scrollbar") laid out
## horizontally (: layout, thumb) over
## (x0,y0)-(x1,y1) = r: the track 6 px high and x1 − x0 − 8 long centred at
## ((x0 + x1) / 2, y1 − 5) (UV 8,4-32,252), the arrows 12 × 10 at x0 + 6 (UV
## 40,128-80,176) and x1 − 6 (UV 40,176-80,128), the thumb 28 × 10 (UV
## 40,8-80,120) centred at x0 + 26 + pos · (x1 − x0 − 52) / max, y0 + 5 — all
## the vertical bar's sprites turned by π/2.
func hslider(r: Rect2, pos: float, max_pos: float) -> void:
	var t := tex("Scrollbar")
	var x0 := r.position.x
	var x1 := r.end.x
	var y1 := r.end.y
	if t == null:
		draw_rect(r8(Rect2(x0, y1 - 8, x1 - x0, 6)), Color(0.45, 0.32, 0.15))
		draw_rect(r8(Rect2(hslider_x(r, pos, max_pos) - 14, r.position.y, 28, 10)), Color(0.9, 0.6, 0.2))
		return
	var a := PI * 0.5
	var c := Vector2((x0 + x1) * 0.5, y1 - 5)
	var len := x1 - x0 - 8
	sprite(t, Rect2(c - Vector2(3, len * 0.5), Vector2(6, len)), [8, 4, 32, 252], Color.WHITE, a)
	sprite(t, Rect2(Vector2(x0 + 6, y1 - 5) - Vector2(5, 6), Vector2(10, 12)), [40, 128, 80, 176], Color.WHITE, a)
	sprite(t, Rect2(Vector2(x1 - 6, y1 - 5) - Vector2(5, 6), Vector2(10, 12)), [40, 176, 80, 128], Color.WHITE, a)
	var tc := Vector2(hslider_x(r, pos, max_pos), r.position.y + 5)
	sprite(t, Rect2(tc - Vector2(5, 14), Vector2(10, 28)), [40, 8, 80, 120], Color.WHITE, a)


## The same scroll bar upright over r = (x1, y1)-(x2, y2): track
## (x2−8,y1+4)-(x2−2,y2−4) UV 8,4-32,252, up (x2−10,y1)-(x2,y1+12) UV
## 40,176-80,128, down (x2−10,y2−12)-(x2,y2) UV 40,128-80,176, thumb 10×28 UV
## 40,8-80,120 centred at (x2−5, y1 + 26 + pos·(h − 52)/max); hidden when
## max ≤ 0.
func vbar(r: Rect2, pos: float, max_pos: float) -> void:
	if max_pos <= 0.0:
		return
	var t := tex("Scrollbar")
	var x2 := r.end.x
	var y1 := r.position.y
	var y2 := r.end.y
	if t == null:
		return
	sprite(t, Rect2(x2 - 8, y1 + 4, 6, y2 - y1 - 8), [8, 4, 32, 252])
	sprite(t, Rect2(x2 - 10, y1, 10, 12), [40, 176, 80, 128])
	sprite(t, Rect2(x2 - 10, y2 - 12, 10, 12), [40, 128, 80, 176])
	sprite(t, Rect2(x2 - 10, vbar_y(r, pos, max_pos) - 14, 10, 28), [40, 8, 80, 120])


static func vbar_y(r: Rect2, pos: float, max_pos: float) -> float:
	return r.position.y + 26.0 + (pos * (r.size.y - 52.0) / max_pos if max_pos > 0.0 else 0.0)


## The parts of vbar a click hits: the thumb rect first (it
## starts a drag), then the click rects — 0 the up arrow
## (x2−10,y1)-(x2,y1+12), 1 the down arrow (x2−10,y2−12)-(x2,y2) — which
## scroll while held; "track" elsewhere in the 10 px column (no click rect
## there, so the original does nothing), "" outside it.
static func vbar_hit(r: Rect2, pos: float, max_pos: float, p: Vector2) -> String:
	if not Rect2(r.end.x - 10, r.position.y, 10, r.size.y).has_point(p):
		return ""
	var ty := vbar_y(r, pos, max_pos)
	if max_pos > 0.0 and p.y >= ty - 14.0 and p.y < ty + 14.0:   # PtInRect
		return "thumb"
	if p.y < r.position.y + 12:
		return "up"
	if p.y >= r.end.y - 12:
		return "down"
	return "track"


## The list area of a vertical bar, third click rect
## (x1,y1)-(x2−10,y2): the mouse wheel scrolls only over it.
static func vbar_wheel_rect(r: Rect2) -> Rect2:
	return Rect2(r.position, Vector2(r.size.x - 10, r.size.y))


## while the thumb is dragged, pos = (int)((y − grab − (y1 +
## 26)) · max / (h − 52)), clamped to 0..max by the setter; `grab` is how far
## below the thumb's centre it was pressed.
static func vbar_value(r: Rect2, max_pos: float, y: float, grab := 0.0) -> int:
	var y0 := r.position.y + 26.0
	var y1 := r.end.y - 26.0
	return clampi(int((y - grab - y0) * max_pos / (y1 - y0)), 0, int(max_pos))


static func hslider_x(r: Rect2, pos: float, max_pos: float) -> float:
	var x0 := r.position.x + 26.0
	var x1 := r.end.x - 26.0
	return x0 + (floorf(pos) * (x1 - x0) / max_pos if max_pos > 0.0 else 0.0)


## Hit parts of a horizontal slider: "left" / "right" arrows (rects
## (x0, y1−10)-(x0+12, y1) and (x1−12, y1−10)-(x1, y1)), "thumb", "track".
static func hslider_hit(r: Rect2, pos: float, max_pos: float, p: Vector2) -> String:
	var g := r.grow_individual(0, 3, 0, 3)
	if not g.has_point(p):
		return ""
	if p.x < r.position.x + 12:
		return "left"
	if p.x >= r.end.x - 12:
		return "right"
	if absf(p.x - hslider_x(r, pos, max_pos)) <= 14:
		return "thumb"
	return "track"


static func hslider_value(r: Rect2, max_pos: float, x: float) -> int:
	var x0 := r.position.x + 26.0
	var x1 := r.end.x - 26.0
	return clampi(int(round((x - x0) / (x1 - x0) * max_pos)), 0, int(max_pos))


func sound(name: String) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.stream = EIAudio.sfx("buttons\\%s.wav" % name)
	if s.stream == null:
		s.free()
		return
	add_child(s)
	s.play()
	s.finished.connect(s.queue_free)


## The screen under a modal interface screen (with capture:
## Options, Load / Save, the difficulty and network screens, message boxes):
##  copies the rendered frame once when the first modal opens
## greys it in place (: 565 u = (2·G6 + 2·R5 + B5)
## >> 4, 32-bit u = (2R + 4G + B) >> 4 — about 0.125 R + 0.25 G + 0.0625 B, so
## also darker) and blits that frozen picture opaque under the screen every
## frame. call capture in open.
static func dim_layer() -> Backdrop:
	var c := Backdrop.new()
	c.show_behind_parent = true   # drawn before the screen's own panels
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_SCALE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	COLOR = vec4(vec3(dot(c, vec3(0.125, 0.25, 0.0625))), 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	c.material = m
	return c


class Backdrop extends TextureRect:
	func _process(_dt: float) -> void:
		# The modal's artwork is inset; its captured world background remains
		# full bleed, including behind the cutouts and home indicator.
		if TouchInput.enabled:
			set_anchors_preset(Control.PRESET_TOP_LEFT)
			global_position = Vector2.ZERO
			size = get_viewport_rect().size

	## The frame as it is now (the modal itself is not drawn yet).
	func capture() -> void:
		if DisplayServer.get_name() == "headless":
			return
		use(get_viewport().get_texture().get_image())

	## A frame captured earlier: a screen opened over another modal one
	## (with first set and more than the game on the stack) takes
	## no new capture and keeps the frozen picture of the game.
	func use(img: Image) -> void:
		texture = ImageTexture.create_from_image(img) if img and not img.is_empty() else null


func touch_transform(before: PackedVector2Array, after: PackedVector2Array) -> void:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var old_mid := inverse * ((before[0] + before[1]) * 0.5)
	var mid := inverse * ((after[0] + after[1]) * 0.5)
	var anchor := to800(old_mid)
	_touch_zoom = clampf(_touch_zoom * after[0].distance_to(after[1]) / maxf(16.0, before[0].distance_to(before[1])), 1.0, 2.5)
	var safe := _safe()
	_touch_pan = mid - anchor * kv() - safe.position - (safe.size - safe.size * _touch_zoom) * 0.5
	var limit := safe.size * (_touch_zoom - 1.0) * 0.5
	_touch_pan = _touch_pan.clamp(-limit, limit)
	queue_redraw()

func touch_scroll(point: Vector2, delta: Vector2) -> void:
	TouchInput.button(point, true, MOUSE_BUTTON_WHEEL_UP if delta.y > 0 else MOUSE_BUTTON_WHEEL_DOWN)
	TouchInput.button(point, false, MOUSE_BUTTON_WHEEL_UP if delta.y > 0 else MOUSE_BUTTON_WHEEL_DOWN)

func touch_draggable(point: Vector2) -> bool:
	# Preserve the original thumb dragging instead of turning it into a list
	# scroll. The screen-specific hit test already knows its sliders and bars.
	if not has_method("_hit"):
		return false
	var hit: Array = call("_hit", to800(get_global_transform_with_canvas().affine_inverse() * point))
	return not hit.is_empty() and str(hit[0]) in ["slider", "bar", "scroll", "max"]
