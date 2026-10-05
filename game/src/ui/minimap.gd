class_name Minimap
extends Control
## Top-right minimap as in the original (the original, panel
## 615..800 × 0..165 of the 800×600 layout, scaled by the window height): the
## zone's own map picture (map.txt "#minimap", textures.res) in 620..780 ×
## 0..160 centred on the selected hero at 80 % brightness under a
## shade, a strip at 780..800 with the battle00 buttons "N" (70..100
## UV 34,118-54,148, tip 10303 default camera view), "+" (100..130, UV
## 25,62-45,92, tip 10301) and "−" (130..160, UV 3,62-23,92, tip 10302), the
## open / close spot at 780..800 × 0..30 (tip 10300), a bronze ring round
## (700,80) r 66 in 16 segments (strip UV 27,107-91,112) and a
## bronze frame (615,−5)-(805,165) 5 wide (strip UV 4,55-90,60).
## Markers: see `_draw_marks`. Two pictures (sizes: map W × H =
## sectors · 32, L = max(W, H), s = 2 / L, 80 px per unit): the whole square
## (620,0)-(780,160) shows the map unzoomed (L across 160 px, colour 0.8,
## clipped to the map) over the shade, and a 16-gon of radius 64
## round (700,80) shows it zoomed (colour 1.0); both
## use uv = world / L, EI +y up (north at the top, the picture's row 0 at the
## bottom; not turned with the camera — see `_to_map`). Zoom: 1.0 at the start (the saved value when loading,
## remake: the save's camera record "minimap_zoom", Session), "+" held multiplies it by 2.5^dt up to 0.05 L, "−" held
## divides it down to 1 (held index; press
## plays buttons\battle\click.wav), the held button drawn at 1.0, else 0.5.
## Open / close (slot): the panel
## slides right by 180 px in 0.3 s, p += real dt · dir / 0.3, offset
## = trunc(180 · e) with e = 2p² below 0.5, else 1 − 2(1 − p)²
## shifts every sprite and every hit area but the first (the Open/Close spot
## 780..800 × 0..30). Starts open (UI manager = 0
## ). Two "in25arrow" figures (HudDial.arrow, scale 0.8):
## - Open/Close marker, set when a slide starts: closing / closed turned +π/2
##   at (713, 20), opening / open −π/2 at (850, 20) — a triangle inside the
##   spot pointing left (closed) or right (open);
## - camera heading: at (694 + offset, 84), turned about +z by
##   atan2(−vx, −vy) of the camera's view axis (
## ), i.e. it rides the ring opposite the view with its apex pointing
##   the way the camera looks; v = the EI (x, y) of the Godot camera's
##   forward axis. rotates EI +z by the native quaternion
##   the renderer's camera maps that to its forward axis. A squared horizontal
##   length below 1e-6 stores v = (0, 1); no camera retains the preceding v.

const MAP := Rect2(620, 0, 160, 160)
const BUTTONS := {"toggle": [Rect2(780, 0, 20, 30), Rect2(), 10300],
	"north": [Rect2(780, 70, 20, 30), Rect2(34, 118, 20, 30), 10303],
	"in": [Rect2(780, 100, 20, 30), Rect2(25, 62, 20, 30), 10301],
	"out": [Rect2(780, 130, 20, 30), Rect2(3, 62, 20, 30), 10302]}

var game: Game
var zoom := 1.0
var _held := ""    # "in" / "out" while a zoom button is held
var open := true   # slide direction: −1 open(ing), +1 clos(ed/ing)
var _p := 0.0      # slide progress 0 open.. 1 closed
var _off := 0.0    # slide offset in 800×600 px
var _tex: Texture2D
var _atlas: Texture2D
## The four marker colours (sprite [2] UV table: battle00
## texels (240,252), (244,252), (248,252), (252,252) — 4×4 swatches at
## 238..253 × 250..253: green, yellow, red, pink).
var _mark_col: Array[Color] = []
var _size := Vector2.ONE   # map W × H in world units
var _l := 1.0              # L = max(W, H)
var _zone := ""
var _north_lit := 0.0   # seconds the N button stays lit
var _view_xy := Vector2(0, 1)


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		for i in 4:   # UVs index the image rows as stored (no V flip)
			_mark_col.append(img.get_pixel(240 + 4 * i, 252))
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)


## Screen px per 800×600 unit: the height's, or GameHUD.top_scale (portrait).
func _k() -> float:
	var hud := get_canvas_layer_node() as GameHUD
	return hud.top_scale() if hud else Interface800.canvas_size(self).y / 600.0


## 800×600 point -> local (the panel's left edge is x 615), shifted by the
## slide unless `fixed`.
func _pt(v: Vector2, fixed := false) -> Vector2:
	return (v - Vector2(615 - (0.0 if fixed else _off), 0)) * _k()


func _r(r: Rect2, fixed := false) -> Rect2:
	return Rect2(_pt(r.position, fixed), r.size * _k())


func _load() -> void:
	_zone = String(game.world.zone.get("id", ""))
	_tex = null
	var name := String(game.world.zone.get("minimap", "")).to_lower()
	if name.is_empty():
		return
	_tex = GameData.get_texture(name)
	var t := game.world.terrain
	if t:
		_size = Vector2(t.sectors_x, t.sectors_y) * EITerrain.SECTOR
		_l = maxf(_size.x, _size.y)
	zoom = clampf(zoom, 1.0, maxf(1.0, 0.05 * _l))


var _redraw_t := 0.0
var _drawn_key := []

func _process(_dt: float) -> void:
	_north_lit = maxf(_north_lit - _dt, 0.0)
	if _held == "in":
		zoom = minf(zoom * pow(2.5, _dt), maxf(1.0, 0.05 * _l))
	elif _held == "out":
		zoom = maxf(zoom / pow(2.5, _dt), 1.0)
	if _held != "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_held = ""   # the release (set)
	var goal := 1.0 if not open else 0.0
	if _p != goal:
		_p = clampf(_p + _dt * (1.0 if not open else -1.0) / 0.3, 0.0, 1.0)
		var e := 2.0 * _p * _p if _p < 0.5 else 1.0 - 2.0 * (1.0 - _p) * (1.0 - _p)
		_off = floorf(180.0 * e)
		queue_redraw()
	if game == null or game.world == null:
		visible = false
		return
	if String(game.world.zone.get("id", "")) != _zone:
		_load()
		visible = _tex != null   # only on a zone change: dialogs hide the HUD
	var k := _k()
	offset_left = -185.0 * k
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 165.0 * k
	# Redrawn at the 55 ms logic rate (the unit dots move per tick) or when
	# the view changes; every frame cost a pass over all units.
	_redraw_t -= _dt
	var key := [open, zoom, _north_lit > 0.0, k, _off, _heading(), _held]
	if _redraw_t <= 0.0 or key != _drawn_key:
		_redraw_t = GameUnit.TICK
		_drawn_key = key
		queue_redraw()


## The view's centre: the camera's look-at point (copies the
## camera object's / 37c, the point
## sets on a map click), else the selected hero.
func _center() -> Vector2:
	if game.rig:
		var at: Array = game.rig.pose()["at"]
		return Vector2(at[0], -at[2])   # Godot (x, −z) = EI (x, y)
	if not game.selected.is_empty() and is_instance_valid(game.selected[0]):
		return game.selected[0].pos
	var mine := game.my_units()
	return mine[0].pos if not mine.is_empty() else Vector2.ZERO


## World position -> the 800×600 point of the unzoomed square (`z` 1) or of
## the zoomed inset (`z` = zoom): 80 px per unit of n = (p − c) · 2 / L, with
## EI +y up: place vertices at (n.x, −n.y) and the
## click takes y = c.y − (py − 80) / 80 / s, so north is the top
## and the picture's row 0 (v 0, EI y 0) the bottom. `_flip` turns an EI
## (x, y) offset into the screen's.
func _to_map(p: Vector2, c: Vector2, z := 1.0) -> Vector2:
	return MAP.get_center() + _flip(p - c) * (160.0 / _l) * z


func _from_map(q: Vector2, c: Vector2, z := 1.0) -> Vector2:
	return c + _flip(q - MAP.get_center()) * _l / (160.0 * z)


static func _flip(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)


func _button_at(local: Vector2) -> String:
	var p := local / _k() + Vector2(615, 0)
	for b in BUTTONS:
		var r: Rect2 = BUTTONS[b][0]
		if (r if b == "toggle" else Rect2(r.position + Vector2(_off, 0), r.size)).has_point(p):
			return b
	return ""


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	match _button_at(e.position):
		"toggle":   #  case 0
			if GameSound.instance:
				GameSound.instance.ui("buttons\\battle\\sling.wav")
			open = not open
		"north": north()
		"in", "out":   # held index 1 / 2, click.wav
			if GameSound.instance:
				GameSound.instance.ui("buttons\\battle\\click.wav")
			_held = _button_at(e.position)
		_:
			if not _goto(e.position):
				return
	accept_event()


## keyboard.ini w_minimap (M, case 0x34): buttons\battle\sling.wav
## and the slide direction flipped (= 1), as the Open/Close spot.
func key_toggle() -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\sling.wav")
	open = not open


##  cases 1 / 2: area 1 is the 16-gon (700 − 65 sin a, 80 + 65 cos a)
## a = iπ/8 (..98), area 2 the map square
## (620,0)-(780,160); the clicked point → world (px − 700, py − 80) / 80 / s
## (÷ zoom in area 1, unzoomed in area 2) about the centre, and
## when it lies on the map (0..W, 0..H) the camera's look-at jumps there
##  and stops following ((−1), &= ~8)
## no sound.
func _goto(local: Vector2) -> bool:
	if _tex == null or _off >= 180.0 or game == null or game.rig == null:
		return false
	var p := local / _k() + Vector2(615 - _off, 0)
	if not MAP.has_point(p):
		return false
	var ring := PackedVector2Array()
	for i in 16:
		ring.append(Vector2(700.0 - 65.0 * sin(i * PI / 8.0), 80.0 + 65.0 * cos(i * PI / 8.0)))
	var w := _from_map(p, _center(), zoom if Geometry2D.is_point_in_polygon(p, ring) else 1.0)
	if w.x <= 0.0 or w.y <= 0.0 or w.x >= _size.x or w.y >= _size.y:
		return false
	game.rig.focus(EISpace.pos(w.x, w.y, game.world.ground_at(w.x, w.y)))
	return true


## The N button and key camera_norm (case 5
##  case 0xc): buttons\battle\click.wav, the camera turned north
## and the button lit for 0.5 s (counts it down and draws
## the button at colour 1.0 while it runs, 0.5 otherwise).
func north() -> void:
	GameSound.instance.ui("buttons\\battle\\click.wav")
	if game.rig:
		game.rig.turn_north()
	_north_lit = 0.5


func _get_tooltip(at: Vector2) -> String:
	var b := _button_at(at)
	# hotkeys w_minimap (0x34) on the toggle, camera_norm (0xc) on "N".
	return GameData.tip_key(GameData.text("tip %d" % BUTTONS[b][2]).strip_edges(),
			{"toggle": 52, "north": 12}.get(b, 0)) if b else ""


func _has_point(point: Vector2) -> bool:
	var p := point / _k() + Vector2(615, 0)
	return Rect2(780, 0, 20, 30).has_point(p) or Rect2(780 + _off, 0, 20, 160).has_point(p) \
		or Rect2(MAP.position + Vector2(_off, 0), MAP.size).has_point(p)


func _strip(from: Vector2, to: Vector2, width: float, uv: Rect2) -> void:
	if _atlas == null:
		draw_line(_pt(from), _pt(to), Color(0.6, 0.45, 0.25), width * _k())
		return
	var d := (to - from).normalized().orthogonal() * width * 0.5
	var pts := PackedVector2Array([_pt(from - d), _pt(to - d), _pt(to + d), _pt(from + d)])
	var s := _atlas.get_size()
	var uvs := PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s,
		Vector2(uv.position.x, uv.end.y) / s])
	draw_primitive(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)


func _draw() -> void:
	var k := _k()
	if _off < 180.0 and _tex:
		var c := _center()
		var map_px := _r(MAP)
		# The shade (depth 20) under the unzoomed picture (18, colour 0.8),
		# clipped to the square and the map.
		draw_rect(map_px, Color(0, 0, 0, 0x50 / 255.0))
		var wr := Rect2(c - Vector2(_l, _l) * 0.5, Vector2(_l, _l)).intersection(Rect2(Vector2.ZERO, _size))
		if wr.has_area():
			# uv = world / L, EI y up on the screen (`_to_map`).
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for w in [wr.position, Vector2(wr.end.x, wr.position.y), wr.end, Vector2(wr.position.x, wr.end.y)]:
				pts.append(_pt(_to_map(w, c)))
				uvs.append(w / _l)
			var grey := Color(0.8, 0.8, 0.8)
			draw_primitive(pts, PackedColorArray([grey, grey, grey, grey]), uvs, _tex)
		# The zoomed inset (depth 14, colour 1.0): the 16-gon r 64, clipped to the map.
		var gon := PackedVector2Array()
		for i in 16:
			gon.append(MAP.get_center() + Vector2.from_angle(TAU * i / 16.0) * 64.0)
		var a := _to_map(Vector2.ZERO, c, zoom)
		var b := _to_map(_size, c, zoom)
		var mr := PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])
		if not Geometry2D.is_polygon_clockwise(mr) == Geometry2D.is_polygon_clockwise(gon):
			mr.reverse()
		for poly: PackedVector2Array in Geometry2D.intersect_polygons(gon, mr):
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for q in poly:
				pts.append(_pt(q))
				uvs.append(_from_map(q, c, zoom) / _l)
			draw_colored_polygon(pts, Color.WHITE, uvs, _tex)
		_draw_marks(c)
		# Ring: 16 segments round (700,80), r 66.
		for i in 16:
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			_strip(Vector2(700, 80) + Vector2.from_angle(a0) * 66.0, Vector2(700, 80) + Vector2.from_angle(a1) * 66.0,
				3.0, Rect2(27, 107, 64, 5))
	# Button strip.
	draw_rect(_r(Rect2(780, 0, 20, 160)), Color(0, 0, 0, 0xb4 / 255.0))
	for b in BUTTONS:
		var uv: Rect2 = BUTTONS[b][1]
		if uv.has_area() and _atlas:
			# N lit while runs, + / − while held.
			var c := 1.0 if (_north_lit > 0.0 if b == "north" else _held == b) else 0.5
			draw_texture_rect_region(_atlas, _r(BUTTONS[b][0]), uv, Color(c, c, c))
	# Frame: (615,−5)-(805,165), 5 wide, sliding with the panel.
	var uvf := Rect2(4, 55, 86, 5)
	_strip(Vector2(615, 2.5 - 5), Vector2(805, 2.5 - 5), 5.0, uvf)
	_strip(Vector2(615, 162.5), Vector2(805, 162.5), 5.0, uvf)
	_strip(Vector2(617.5, -5), Vector2(617.5, 165), 5.0, uvf)
	# in25arrow figures (see the header).
	if open:
		_arrow(HudDial.arrow(850, 20, -PI * 0.5, 0.8), true)
	else:
		_arrow(HudDial.arrow(713, 20, PI * 0.5, 0.8), true)
	if _tex:
		var h := _heading()   # atan2(−vx, −vy) (h = −v)
		_arrow(HudDial.arrow(694 + _off, 84, atan2(h.x, h.y), 0.8), true)


## The markers (one mesh: sprite [2]
## (700,80), depth 12 — in front of the pictures (14 / 18 / 20), behind the
## ring (10); 80 px per unit of n = (p − centre) · 2 / L at (n.x, −n.y), EI
## y up as `_to_map`; each vertex takes
## one colour of `_mark_col`, flat, untextured otherwise), in buffer order:
## 1. units of the player's list (alive only): a triangle, apex 0.07 along the
##    unit's facing, base corners 0.04 at ±135° from it (5.6 / 3.2 px), drawn
##    only at the zoomed point n · zoom when |n · zoom|² ≤ 0.56 (inside the
##    inset; none outside the ring); colour 0 (green) for a selected unit
##    (interface), 2 (red) when its hostility masks
##     & hold the local player's side, else 1 (yellow); the
##    Curse (id 666666) in gz20g is always 2;
## 2. quest lights (scene lights; colour 3, pink square
##    ±0.03), placed by QuestLights on map-object quest-info state 1;
## 3. zone exits whose target is not "none" (: centre of record
## .., `area`): yellow squares ±0.03 (4.8 px), at n · zoom when
##    |n · zoom|² ≤ 0.6, else at n when |n|² ≥ 0.68 and |n.x|, |n.y| ≤ 0.97;
## 4. network game only: list (world effects near the camera, map
## ), green diamonds ±0.04 — not ported.
func _draw_marks(c: Vector2) -> void:
	if _mark_col.size() < 4:
		return
	var mine := game.my_units()
	var ending := String(game.world.zone.get("id", "")) == "gz20g"
	for u: GameUnit in game.world.units.values():
		if u.dead or not UnitFog.listed(game, u):   # the player's list (UnitFog)
			continue
		var n := (u.pos - c) * 2.0 / _l * zoom
		if n.length_squared() > 0.56:
			continue
		var ci := 1
		if u in game.selected:
			ci = 0
		elif (ending and u.uid == 666666) or (not mine.is_empty() and game.world.is_enemy(u, mine[0])):
			ci = 2
		# The apex along the model's −Y (turns +Y; the original takes
		# (−x, +y) of it in screen space) = the facing, EI y up.
		var d := _flip(Vector2.from_angle(u.facing))
		var o := MAP.get_center() + _flip(n) * 80.0
		var tri := PackedVector2Array([_pt(o + d * 0.07 * 80.0),
			_pt(o + d.rotated(-0.75 * PI) * 0.04 * 80.0), _pt(o + d.rotated(0.75 * PI) * 0.04 * 80.0)])
		draw_colored_polygon(tri, _mark_col[ci])
		# Remake: a thin antialiased edge (0.5 px plus Godot's 1 px feather) so
		# the 3–9 px darts keep their shape on small screens instead of
		# losing their thin tips to the pixel grid.
		tri.append(tri[0])
		draw_polyline(tri, _mark_col[ci], 0.5, true)
	if game.quest_lights:
		for p: Vector2 in game.quest_lights.positions():
			var n := (p - c) * 2.0 / _l
			if (n * zoom).length_squared() <= 0.6:
				n *= zoom
			elif n.length_squared() < 0.68 or absf(n.x) > 0.97 or absf(n.y) > 0.97:
				continue
			var o := MAP.get_center() + _flip(n) * 80.0
			draw_rect(Rect2(_pt(o - Vector2(2.4, 2.4)), Vector2(4.8, 4.8) * _k()), _mark_col[3])
	var exits: Dictionary = game.world.zone.get("exits", {})
	for k in exits:
		var ex: Dictionary = exits[k]
		if String(ex.get("to", "none")) == "none" or not ex.has("area"):
			continue
		var n := (Rect2(ex.area).get_center() - c) * 2.0 / _l
		if (n * zoom).length_squared() <= 0.6:
			n *= zoom
		elif n.length_squared() < 0.68 or absf(n.x) > 0.97 or absf(n.y) > 0.97:
			continue
		var o := MAP.get_center() + _flip(n) * 80.0
		draw_rect(Rect2(_pt(o - Vector2(2.4, 2.4)), Vector2(4.8, 4.8) * _k()), _mark_col[1])


## EI (x, y) direction opposite the camera's view (−v for
## atan2(−vx, −vy)); (0, −1) when the view is vertical. The native update
## retains its last view axis while the global camera is absent.
func _heading() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var f := -cam.global_basis.z
		_view_xy = Vector2(f.x, -f.z)   # Godot (x, −z) = EI (x, y)
	_view_xy = _view_xy.normalized() if _view_xy.length_squared() >= 1e-6 else Vector2(0, 1)
	return -_view_xy


## One in25arrow (800×600 points, unshifted) on the battle00 atlas.
func _arrow(pts: PackedVector2Array, fixed: bool) -> void:
	if _atlas == null:
		return
	var uvs := PackedVector2Array()
	for i in 3:
		pts[i] = _pt(pts[i], fixed)
		uvs.append(Vector2(HudDial.ARROW_UV[i].x, 256.0 - HudDial.ARROW_UV[i].y) / 256.0)   # flipped atlas
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)
