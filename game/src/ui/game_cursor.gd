class_name GameCursor
extends Node
## The original animated mouse cursors (textures.res "cursor_*": strips of
## 32×32 frames, loaded by the original with their hot spots: the
## pointers at (0, 0), the scroll arrows at the screen-edge side).
## The 8888 strips come out of EIMmp upside down (the scroll-up arrow points
## down), so they are flipped back here; black is transparent.
## Animation (the cursor thread's update): one frame per 125 ms
## of timeGetTime (the remainder carried over), counted in the shown strip's
## own frame index (modulo its frame count), so each cursor resumes
## at the frame it left: (set cursor by index, object)
## does not reset it. Cursor indices are the load order:
## 0 default, 1 attack, 2 spell, 3 wait, 4 use, 5–12 scroll u … ul,
## 13 cancel, 14 talk, 15 move, 16–21 attack hd / bd / lh / rh / ll / rl,
## 22 camera, 23 spellcancel, 24 steal. The game view's choice is
##  (Game._update_cursor).
##
## Size: the original always loads the full 32×32 set (is called
## with 0, so the 16×16 "sm_cursor_*" set and 16 px cell are
## unused) and draws it 1:1 in screen pixels at every resolution. Remake
## improvement (user request): the cursor is scaled with the window like the
## 800×600 HUD (height / 600, as party_faces / message_log), smoothly
## filtered, hot spot scaled with it; still the OS (hardware) cursor.

## Godot's custom cursor limit (px per side).
const MAX_PX := 256

## (timeGetTime − last) / 0x7d frames.
const FRAME_SEC := 0.125
const HOTSPOT := {
	"cursor_scroll_u": Vector2(16, 0), "cursor_scroll_ur": Vector2(31, 0),
	"cursor_scroll_r": Vector2(31, 16), "cursor_scroll_dr": Vector2(31, 31),
	"cursor_scroll_d": Vector2(16, 31), "cursor_scroll_dl": Vector2(0, 31),
	"cursor_scroll_l": Vector2(0, 16),
}
const SCROLL := {Vector2i(0, -1): "cursor_scroll_u", Vector2i(1, -1): "cursor_scroll_ur",
	Vector2i(1, 0): "cursor_scroll_r", Vector2i(1, 1): "cursor_scroll_dr", Vector2i(0, 1): "cursor_scroll_d",
	Vector2i(-1, 1): "cursor_scroll_dl", Vector2i(-1, 0): "cursor_scroll_l", Vector2i(-1, -1): "cursor_scroll_ul"}
## Aimed strike part index (Game.AIM_KEYS) -> cursor.
const AIM := ["cursor_attack_hd", "cursor_attack_bd", "cursor_attack_rh", "cursor_attack_lh",
	"cursor_attack_rl", "cursor_attack_ll"]

static var _frames := {}
## Scaled frames: "name@px" -> [Image]. Images, not textures: the OS cursor
## is built from an Image, and a texture would be read back from the GPU
## (a render-thread sync) on every frame change, 8 times a second.
static var _scaled := {}
var kind := ""
var _t := 0.0
## Frame index per cursor (the strip's), kept across switches.
var _frame := {}
var _shown := -1
var _px := 32


static func frames(name: String) -> Array:
	if _frames.has(name):
		return _frames[name]
	var out: Array = []
	var img := GameData.load_image(name) if GameData.is_open() else null
	if img:
		img.flip_y()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if maxf(c.r, maxf(c.g, c.b)) < 0.03:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
		var n := img.get_width() / 32
		for i in n:
			out.append(img.get_region(Rect2i(i * 32, 0, 32, 32)))
	_frames[name] = out
	return out


## The frames of `name` as `px`×`px` images (32 = the original size).
static func scaled(name: String, px: int) -> Array:
	var key := "%s@%d" % [name, px]
	if _scaled.has(key):
		return _scaled[key]
	var out: Array = []
	for f: Image in frames(name):
		var img: Image = f.duplicate()
		if px != 32:
			# Colour bleeds from the opaque neighbours into the keyed-out
			# pixels first, so the filtered edge does not darken to black.
			img.premultiply_alpha()
			img.resize(px, px, Image.INTERPOLATE_CUBIC if px > 32 else Image.INTERPOLATE_BILINEAR)
			_unpremultiply(img)
		out.append(img)
	_scaled[key] = out
	return out


static func _unpremultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0), minf(c.b / c.a, 1.0), clampf(c.a, 0.0, 1.0)))


## Cursor side in pixels for the current window: 32 × height / 600.
static func size_px() -> int:
	var h := DisplayServer.window_get_size().y if DisplayServer.get_name() != "headless" else 600
	return clampi(roundi(32.0 * h / 600.0), 32, MAX_PX)


func set_kind(k: String) -> void:
	if k == kind:
		return
	kind = k
	_shown = -1
	if k.is_empty():
		Input.set_custom_mouse_cursor(null)


func _process(dt: float) -> void:
	if kind.is_empty():
		return
	var px := size_px()
	if px != _px:
		_px = px
		_shown = -1
	var f := scaled(kind, px)
	if f.is_empty():
		return
	_t += dt
	var steps := int(_t / FRAME_SEC)
	_t -= steps * FRAME_SEC
	var i: int = (int(_frame.get(kind, 0)) + steps) % f.size()
	_frame[kind] = i
	if i != _shown:
		_shown = i
		var hs: Vector2 = HOTSPOT.get(kind, Vector2.ZERO) * (px / 32.0)
		hs = hs.round().clamp(Vector2.ZERO, Vector2(px - 1, px - 1))
		Input.set_custom_mouse_cursor(f[i], Input.CURSOR_ARROW, hs)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)
