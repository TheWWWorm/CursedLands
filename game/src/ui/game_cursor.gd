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

## The browser's cursor (web export), by path: no class_name load order.
const WebCursor := preload("res://src/platform/web_cursor.gd")

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

static var _frames := {}
## Scaled frames: "name@px" -> [Image]. Images, not textures: the OS cursor
## is built from an Image, and a texture would be read back from the GPU
## (a render-thread sync) on every frame change, 8 times a second.
static var _scaled := {}
## Only the newest screen owns the cursor. An outgoing screen may leave
## the tree after its replacement has already set the new cursor.
static var _owner: GameCursor
var kind := ""
var _t := 0.0
## Frame index per cursor (the strip's), kept across switches.
var _frame := {}
var _shown := -1
var _px := 32
## Original camera drag (5ead50): screen position freezes
## while raw deltas continue past the window edges; release restores it.
var _camera_drag := false
var _camera_at := Vector2.ZERO
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _camera_layer: CanvasLayer
var _camera_sprite: TextureRect
static var _camera_textures := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_owner):
		_owner.end_camera_drag(false)
	_owner = self


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
			# pixels first, so the filtered edge does not darken to black
			# (natively: a per-pixel script loop stalled a frame per cursor).
			img.fix_alpha_edges()
			img.resize(px, px, Image.INTERPOLATE_CUBIC if px > 32 else Image.INTERPOLATE_BILINEAR)
		out.append(img)
	_scaled[key] = out
	return out


## Cursor side in pixels for the current window: 32 × height / 600.
static func size_px() -> int:
	var h := DisplayServer.window_get_size().y if DisplayServer.get_name() != "headless" else 600
	return clampi(roundi(32.0 * h / 600.0), 32, MAX_PX)


func set_kind(k: String) -> void:
	if k == kind:
		return
	kind = k
	_shown = -1
	if k.is_empty() and _owner == self:
		if OS.has_feature("web"):
			WebCursor.off()
		else:
			Input.set_custom_mouse_cursor(null)


func camera_drag_active() -> bool:
	return _camera_drag


func pointer_position() -> Vector2:
	return _camera_at if _camera_drag else get_viewport().get_mouse_position()


func begin_camera_drag(at: Vector2) -> void:
	if _owner != self or _camera_drag or TouchInput.enabled or DisplayServer.get_name() == "headless":
		return
	_mouse_before = Input.get_mouse_mode()
	_camera_at = at
	_camera_drag = true
	if _camera_layer == null:
		_camera_layer = CanvasLayer.new()
		_camera_layer.layer = 126
		add_child(_camera_layer)
		_camera_sprite = TextureRect.new()
		_camera_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_camera_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_camera_layer.add_child(_camera_sprite)
	_camera_sprite.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_kind("cursor_camera")
	_shown = -1
	_process(0.0)


func end_camera_drag(restore := true) -> void:
	if not _camera_drag:
		return
	_camera_drag = false
	_camera_sprite.visible = false
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(_mouse_before)
		if restore:
			# The press and painted sprite use viewport coordinates. Input's
			# warp takes physical window pixels, which differ under stretch.
			get_viewport().warp_mouse(_camera_at)
	_shown = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		end_camera_drag(false)


func _process(dt: float) -> void:
	if kind.is_empty() or _owner != self:
		return
	var k := "cursor_camera" if _camera_drag else kind
	var px := size_px()
	if px != _px:
		_px = px
		_shown = -1
	var f := scaled(k, px)
	if f.is_empty():
		return
	_t += dt
	var steps := int(_t / FRAME_SEC)
	_t -= steps * FRAME_SEC
	var i: int = (int(_frame.get(k, 0)) + steps) % f.size()
	_frame[k] = i
	if i != _shown:
		_shown = i
		var hs: Vector2 = HOTSPOT.get(k, Vector2.ZERO) * (px / 32.0)
		hs = hs.round().clamp(Vector2.ZERO, Vector2(px - 1, px - 1))
		if _camera_drag:
			var key := "%s@%d:%d" % [k, px, i]
			if not _camera_textures.has(key):
				_camera_textures[key] = ImageTexture.create_from_image(f[i])
			_camera_sprite.texture = _camera_textures[key]
			var scale := get_viewport().get_final_transform().get_scale().abs()
			_camera_sprite.position = _camera_at - hs / scale
			_camera_sprite.size = Vector2(px, px) / scale
		elif OS.has_feature("web"):
			WebCursor.show(k, i, px, hs)   # a CSS cursor: see WebCursor
		else:
			Input.set_custom_mouse_cursor(f[i], Input.CURSOR_ARROW, hs)


func _exit_tree() -> void:
	end_camera_drag()
	if _owner != self:
		return
	_owner = null
	if OS.has_feature("web"):
		WebCursor.clear()
	else:
		Input.set_custom_mouse_cursor(null)
