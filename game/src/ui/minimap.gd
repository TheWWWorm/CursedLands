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
## Party members are green, enemies the party sees are red, other units
## yellow. The picture covers 32 px per sector of the larger map side.
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
##   the way the camera looks. **Approx.**: derived for the remake's map
##   orientation (`_to_map`) rather than from the original's world axes.

const MAP := Rect2(620, 0, 160, 160)
const BUTTONS := {"toggle": [Rect2(780, 0, 20, 30), Rect2(), 10300],
	"north": [Rect2(780, 70, 20, 30), Rect2(34, 118, 20, 30), 10303],
	"in": [Rect2(780, 100, 20, 30), Rect2(25, 62, 20, 30), 10301],
	"out": [Rect2(780, 130, 20, 30), Rect2(3, 62, 20, 30), 10302]}

var game: Game
var zoom := 1.5
var open := true   # slide direction: −1 open(ing), +1 clos(ed/ing)
var _p := 0.0      # slide progress 0 open.. 1 closed
var _off := 0.0    # slide offset in 800×600 px
var _tex: Texture2D
var _atlas: Texture2D
var _scale := 1.0   # texture pixels per world unit
var _zone := ""
var _north_lit := 0.0   # seconds the N button stays lit
## Enemy uid -> seen by the party, refreshed every SEEN_REFRESH seconds (the
## sight test walks the ground between the units; every enemy every frame
## cost ~2 ms in a 200-unit zone).
const SEEN_REFRESH := 100   # ms
var _seen := {}
var _seen_at := 0


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)


func _k() -> float:
	return get_viewport_rect().size.y / 600.0


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
	if _tex and t:
		_scale = float(_tex.get_width()) / (maxi(t.sectors_x, t.sectors_y) * EITerrain.SECTOR)


var _redraw_t := 0.0
var _drawn_key := []

func _process(_dt: float) -> void:
	_north_lit = maxf(_north_lit - _dt, 0.0)
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
	var key := [open, zoom, _north_lit > 0.0, k, _off, _heading()]
	if _redraw_t <= 0.0 or key != _drawn_key:
		_redraw_t = GameUnit.TICK
		_drawn_key = key
		queue_redraw()


func _center() -> Vector2:
	if not game.selected.is_empty() and is_instance_valid(game.selected[0]):
		return game.selected[0].pos
	var mine := game.my_units()
	return mine[0].pos if not mine.is_empty() else Vector2.ZERO


## World position -> 800×600 point inside the map square.
func _to_map(p: Vector2, c: Vector2) -> Vector2:
	return MAP.get_center() + (p - c) * _scale * zoom * 160.0 / 190.0


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
		"in": zoom = clampf(zoom * 1.4, 0.6, 5.0)
		"out": zoom = clampf(zoom / 1.4, 0.6, 5.0)
		_: return
	accept_event()


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
	return GameData.text("tip %d" % BUTTONS[b][2]).strip_edges() if b else ""


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
		# The picture, clipped to the map square.
		var tl := _to_map(Vector2.ZERO, c)
		var sz := _tex.get_size() * zoom * 160.0 / 190.0
		var src := Rect2(Vector2.ZERO, _tex.get_size())
		var dst := Rect2(tl, sz)
		var clip := dst.intersection(MAP)
		if clip.has_area():
			var f := _tex.get_size() / sz
			draw_texture_rect_region(_tex, _r(clip), Rect2((clip.position - tl) * f, clip.size * f),
				Color(0.8, 0.8, 0.8))
		draw_rect(map_px, Color(0, 0, 0, 0x50 / 255.0))
		var mine := game.my_units()
		var now := Time.get_ticks_msec()
		if now - _seen_at >= SEEN_REFRESH or now < _seen_at:
			_seen.clear()
			_seen_at = now
		for u: GameUnit in game.world.units.values():
			if u.dead or u.hidden or not u.visible:
				continue
			var sp := _to_map(u.pos, c)
			if not MAP.has_point(sp):
				continue
			var col := Color(1, 0.9, 0.2)
			if u.controller >= 0:
				col = Color(0.2, 1, 0.3)
			elif not mine.is_empty() and game.world.is_enemy(mine[0], u):
				if not _seen.has(u.uid):
					_seen[u.uid] = mine.any(func(m): return is_instance_valid(m) and game.world.ai.can_notice(m, u, float(m.stats.get("sight", 15.0))))
				if not _seen[u.uid]:
					continue   # only enemies the party can see
				col = Color(1, 0.25, 0.2)
			draw_circle(_pt(sp), (2.5 if u.controller >= 0 else 2.0) * k, col)
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
			var c := 1.0 if b != "north" or _north_lit > 0.0 else 0.5
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
		var h := _heading()
		_arrow(HudDial.arrow(694 + _off, 84, atan2(h.x, -h.y), 0.8), true)


## Screen direction on the map opposite the camera's view (
## atan2(−vx, −vy)); (0, 1) when the view is vertical.
func _heading() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0, 1)
	var f := -cam.global_basis.z
	var d := -Vector2(f.x, -f.z)   # Godot (x, −z) = EI (x, y), as _to_map draws them
	return d.normalized() if d.length() > 1e-6 else Vector2(0, 1)


## One in25arrow (800×600 points, unshifted) on the battle00 atlas.
func _arrow(pts: PackedVector2Array, fixed: bool) -> void:
	if _atlas == null:
		return
	var uvs := PackedVector2Array()
	for i in 3:
		pts[i] = _pt(pts[i], fixed)
		uvs.append(HudDial.ARROW_UV[i] / 256.0)
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)
