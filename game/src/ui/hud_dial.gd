class_name HudDial
extends Control
## The two corner dials of the battle HUD, drawn from the original atlas
## textures.res "battle00" with the original's geometry (800×600 layout, scaled):
## - "move" (bottom left, 0..80 × 520..600): four 22.5° sectors
##   crawl / sneak / walk / run (tips 10501-10504) cut from the atlas dial
##   (UV centre 2,254, radius 80), unselected ones at 0.7 brightness
## the selected one marked by the triangle pointer at radius
##   73; the inner disc (radius 32) is Aggressive/Defensive (tip 10500):
##   the atlas disc at centre (2 + du, 254), du (sprite) = 0 sword when
##   the selected units are all Aggressive, 86 shield when all Defensive, 123
##   blank when mixed or none.
## - "clock" (bottom right): the sun / moon ring (UV centre
##   174,81, radius 65 / 80) with three 30° sectors pause / normal speed /
##   accelerated speed (tips 10400, 10402, 10403; speed only in single
##   player; accelerated = 27 ms logic tick instead of 55 ms)
##   and the inner part for the Quests screen (tip 10401).
## Atlas V is flipped against EIMmp images (image y = 256 - v).
## The sky ring turns with the client clock: hour =
## fmod(ticks · rate + offset, 24), angle (hour + 15) · π/12 clockwise, i.e.
## game_hud.gd's π/4 + (hour − 12) · π/12 in this UV convention.
## Clock hands (sprites 2..5, figures.res "in25arrow": one
## triangle, model base (0.1288, −0.9239) / (−0.1175, −0.9239), apex
## (0.0057, −0.7106), z −0.204, UV + (57, 36)/256 on the widget atlas): each
## frame θ += real dt · 0.5 at normal speed, · 1 accelerated, unchanged
## paused, wrapped below π/6; hand k is turned about +z by
## a = θ − π/12 − k · π/6 and placed at (800 + 30 sin a, 600 − 30 cos a),
## depth 8.106086, scale 0.4, projected as does (camera x =
## (sx · 0.0025 − 1) · 0.48157462 · z) — four teeth crawling clockwise at the
## sky ring's rim.

signal sector_pressed(index: int)
signal inner_pressed

const R := 80.0
var kind := "move":
	set(v):
		kind = v
		_update_process()
## Selected sector; on the clock 0 = paused.
var selected := -1:
	set(v):
		selected = v
		_update_process()
## Aggressive / Defensive disc: 1 all aggressive, 0 all defensive, else blank.
var aggression := -1:
	set(v):
		if aggression == v: return
		aggression = v
		queue_redraw()
var _tex: Texture2D
var _hover := -2
var ring_angle := 0.0:
	set(v):
		if ring_angle == v: return
		ring_angle = v
		queue_redraw()
## Quest-disc pulse: set by a quest notification
## (dial), cleared when the disc is clicked
## the disc colour is cos(2π·phase)·0.3 + 0.7 with the phase
## advanced by frame seconds mod 1.
var pulse := false:
	set(v):
		pulse = v
		_update_process()
		queue_redraw()
var _phase := 0.0
var _last_ms := 0
var _theta := 0.0   # clock hands
var _hands_layer: HandsLayer


## The hands and speed pointer overlay the face. Their animation does not
## rebuild the face's three textured fans or change its update cadence.
class HandsLayer extends Control:
	var dial: HudDial
	func _draw() -> void:
		dial._draw_hands(self)


func _redraw_all() -> void:
	queue_redraw()
	if _hands_layer:
		_hands_layer.visible = kind == "clock"
		_hands_layer.queue_redraw()


func _ready() -> void:
	_tex = GameData.get_texture("battle00")
	_hands_layer = HandsLayer.new()
	_hands_layer.dial = self
	_hands_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hands_layer)
	resized.connect(_redraw_all)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS   # the paused clock keeps blinking
	_update_process()


func _update_process() -> void:
	var on := pulse or kind == "clock"   # the clock's hands turn every frame
	if on and not is_processing():
		_last_ms = Time.get_ticks_msec()
	set_process(on)
	_redraw_all()


## The phase advances by the frame's real seconds (
## ms · 0.001, not the game speed) mod 1.
func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := (now - _last_ms) * 0.001
	_phase = fmod(_phase + dt, 1.0)
	_last_ms = now
	if kind == "clock" and selected != 0:
		_theta += dt * (1.0 if selected == 2 else 0.5)
		while _theta > PI / 6.0:
			_theta -= PI / 6.0
	if pulse or (kind == "clock" and selected == 0):
		queue_redraw()
	if kind == "clock" and _hands_layer:
		_hands_layer.queue_redraw()


func _scale() -> float:
	return size.y / R


## Sector 0..n-1 counted from the horizontal edge, -1 = inner, -2 = outside.
func _hit(p: Vector2) -> int:
	var s := _scale()
	var o := Vector2(0, size.y) if kind == "move" else size
	var d := (p - o) / s
	d.x = absf(d.x)
	d.y = -d.y
	var r := d.length()
	if r > R or d.y < 0:
		return -2
	if r < 32.0:
		return -1
	var n := 4 if kind == "move" else 3
	return clampi(int(atan2(d.y, d.x) / (PI * 0.5) * n), 0, n - 1)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _hit(e.position)
		if h != _hover:
			_hover = h
			tooltip_text = _tip(h)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(e.position)
		if h == -1:
			inner_pressed.emit()
		elif h >= 0:
			sector_pressed.emit(h)
		if h >= -1:
			accept_event()


func _has_point(p: Vector2) -> bool:
	return _hit(p) >= -1


func _tip(h: int) -> String:
	var id := -1
	if kind == "move":
		id = 10500 if h == -1 else 10501 + h if h >= 0 else -1
	else:
		id = 10401 if h == -1 else [10400, 10402, 10403][h] if h >= 0 else -1
	# Hotkeys: swarm (0x1b) on the inner disc, crawl..run (0x17..0x1a)
	#  pause / decel / accel (1..3), obj (4) on the centre.
	var key := 0
	if id >= 10500:
		key = 27 if id == 10500 else 22 + id - 10500
	elif id >= 0:
		key = {10400: 1, 10401: 4, 10402: 2, 10403: 3}[id]
	return GameData.tip_key(GameData.text("tip %d" % id).strip_edges(), key) if id >= 0 else ""


## Remake (gamepad movement-mode ring, PadField): the figure of the move
## dial's sector `g` (0 crawl, 1 kneel, 2 walk, 3 run) cut out of battle00 as
## the dial shows it (V flipped, upright): a 28 px square round the sector's
## middle at radius 58, the dial's stone kept only inside the sector
## (radius 36..76, the sector's 22.5° plus 1°) so the neighbours' figures
## stay out.
static var _gait_icons := {}

static func gait_icon(g: int) -> Texture2D:
	if _gait_icons.has(g):
		return _gait_icons[g]
	var tex: Texture2D = null
	var src := GameData.load_image("battle00")
	if src and g >= 0 and g < 4:
		if src.is_compressed():
			src.decompress()
		const S := 28
		var a0 := g * 22.5
		var am := deg_to_rad(a0 + 11.25)
		var c := Vector2(cos(am), sin(am)) * 58.0   # dial offset, y up
		var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
		for y in S:
			for x in S:
				var d := Vector2(c.x - S * 0.5 + x + 0.5, c.y + S * 0.5 - y - 0.5)
				var r := d.length()
				var ang := rad_to_deg(atan2(d.y, d.x))
				if r < 36.0 or r > 76.0 or ang < a0 - 1.0 or ang > a0 + 23.5:
					continue
				# Image row = 256 - v, v = 254 - d.y (see _uv).
				var px := Vector2i(int(2.0 + d.x), int(2.0 + d.y))
				if px.x >= 0 and px.y >= 0 and px.x < src.get_width() and px.y < src.get_height():
					img.set_pixel(x, y, src.get_pixelv(px))
		tex = ImageTexture.create_from_image(img)
	_gait_icons[g] = tex
	return tex


## Atlas point in original UV space -> normalized image UV.
func _uv(u: float, v: float) -> Vector2:
	return Vector2(u / 256.0, (256.0 - v) / 256.0)


func _draw() -> void:
	if _tex == null:
		return
	var s := _scale()
	if kind == "move":
		var o := Vector2(0, size.y)
		for i in 4:
			var a0 := i * PI / 8.0
			var a1 := (i + 1) * PI / 8.0
			var c := Color.WHITE if i == selected else Color(0.7, 0.7, 0.7)
			_tri(o, o + Vector2(cos(a0), -sin(a0)) * R * s, o + Vector2(cos(a1), -sin(a1)) * R * s,
				_uv(2, 254), _uv(cos(a0) * R + 2, 254 - sin(a0) * R), _uv(cos(a1) * R + 2, 254 - sin(a1) * R), c)
		var du := 0.0 if aggression == 1 else 86.0 if aggression == 0 else 123.0
		_disc(o, 32.0 * s, Vector2(2 + du, 254), 32.0, 0.0, PI * 0.5, 0.0)
		if selected >= 0:
			var a := (selected * 2 + 1) * PI / 16.0
			_pointer(o + Vector2(cos(a), -sin(a)) * 73.0 * s, a, s)
	else:
		# Bronze speed arc (radius 80), sky ring turned by the time of day
		# (radius 65), quest scroll in the middle (radius 32), all around
		# atlas point 174,81.
		# Paused: the sky ring at 1.4 − f
		# and the pointer on the pause sector (165°) shown only while the
		# phase is over 0.5 (a 1 s blink); f = cos(2π·phase)·0.3 + 0.7.
		var o := size
		var f := cos(TAU * _phase) * 0.3 + 0.7
		var paused := selected == 0
		var g := 1.4 - f if paused else 1.0
		_disc(o, R * s, Vector2(174, 81), R, PI * 0.5, PI, 0.0)
		_disc(o, 65.0 * s, Vector2(174, 81), 65.0, PI * 0.5, PI, ring_angle, Color(g, g, g))
		var q := f if pulse else 1.0
		_disc(o, 32.0 * s, Vector2(174, 81), 32.0, PI * 0.5, PI, 0.0, Color(q, q, q))


func _draw_hands(canvas: CanvasItem) -> void:
	if _tex == null or kind != "clock": return
	var o := size
	var s := _scale()
	for k in 4:
		_hand(o, _theta - PI / 12.0 - k * PI / 6.0, s, canvas)
	if selected >= 0 and (selected != 0 or _phase > 0.5):
		var a := PI - (selected * 2 + 1) * PI / 12.0
		_pointer(o + Vector2(cos(a), -sin(a)) * 73.0 * s, a, s, canvas)


func _tri(a: Vector2, b: Vector2, c: Vector2, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, canvas: CanvasItem = null) -> void:
	(canvas if canvas else self).draw_polygon(PackedVector2Array([a, b, c]), PackedColorArray([col, col, col]),
		PackedVector2Array([ua, ub, uc]), _tex)


## Quarter disc fan over screen angles a0..a1 (from +x, upwards), sampling
## the atlas like the original's round sprites: original UV = centre + (cos, -sin)·r
## turned by `rot`.
func _disc(o: Vector2, r: float, uc: Vector2, ur: float, a0: float, a1: float, rot: float,
		col := Color.WHITE) -> void:
	var pts := PackedVector2Array([o])
	var uvs := PackedVector2Array([_uv(uc.x, uc.y)])
	var n := 16
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(o + Vector2(cos(a), -sin(a)) * r)
		uvs.append(_uv(uc.x + cos(a + rot) * ur, uc.y - sin(a + rot) * ur))
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	draw_polygon(pts, cols, uvs, _tex)


## figures.res "in25arrow" as the HUD widgets place it (
## see the header): the three corners (base, apex, base)
## 800×600 points for a pivot (sx, sy) at depth z, turned about +z by `a`
## (the model's up, local −y, goes to screen (sin a, −cos a); the apex points
## back at the pivot) and scaled by `scale`.
const ARROW_V := [Vector2(0.1288, -0.9239), Vector2(0.0057, -0.7106), Vector2(-0.1175, -0.9239)]
## Their atlas points in the original's pixel UVs (model UV + (57, 36)/256); unlike
## the 2D sprites' they address the image rows unflipped (the gold triangle at
## battle00 x 231..254, y 227..247).
const ARROW_UV := [Vector2(253.5, 246.7), Vector2(242.2, 227.1), Vector2(230.9, 246.7)]
const ARROW_Z := 8.106086

static func arrow(sx: float, sy: float, a: float, scale: float, z := ARROW_Z) -> PackedVector2Array:
	const K := 0.48157462
	var cam := Vector2((sx * 0.0025 - 1.0) * K * z, (sy * 0.0025 - 0.75) * K * z)
	var zv := z - 0.204 * scale
	var out := PackedVector2Array()
	for v: Vector2 in ARROW_V:
		var c := cam + Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)) * scale
		out.append(Vector2((c.x / (zv * K) + 1.0) / 0.0025, (c.y / (zv * K) + 0.75) / 0.0025))
	return out


## One clock hand: pivot (800 + 30 sin a, 600 − 30 cos a), scale 0.4.
func _hand(o: Vector2, a: float, s: float, canvas: CanvasItem = null) -> void:
	var pts := arrow(800.0 + 30.0 * sin(a), 600.0 - 30.0 * cos(a), a, 0.4)
	var uvs := PackedVector2Array()
	for i in 3:
		pts[i] = o + (pts[i] - Vector2(800, 600)) * s
		uvs.append(ARROW_UV[i] / 256.0)   # image rows as they are (no V flip)
	(canvas if canvas else self).draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _tex)


## The triangle pointer sprite (: points (0,0) (17,11) (17,-11)
## atlas 104,19 / 115,2 / 93,2), its tip towards the dial centre.
func _pointer(p: Vector2, a: float, s: float, canvas: CanvasItem = null) -> void:
	var fwd := Vector2(cos(a), -sin(a))
	var side := Vector2(-fwd.y, fwd.x)
	_tri(p, p + (fwd * 17.0 + side * 11.0) * s, p + (fwd * 17.0 - side * 11.0) * s,
		_uv(104, 19), _uv(115, 2), _uv(93, 2), Color.WHITE, canvas)
