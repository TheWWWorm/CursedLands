class_name EnemyBars
extends Control
## Remake (option "enemy_hp_bars": Off / Auto / Always, default Auto): a small
## health bar over hostile units. the original shows a unit's health only in the
## unit panel (UnitPanel, general view) and the party faces; a
## controller or a finger has no hover to bring that panel up quickly, so
## Auto shows the bars while the input in use is a pad (PadInput.active) or
## touch (TouchInput.enabled) and hides them after mouse use (PadInput /
## TouchInput switch back after 40 px of real mouse movement or a key).
## Look: the unit panel's health bar from battle00 — its 5 px frame (UV
## 59,119-119,124, the hit-location bar frame sized for a 50 unit fill) and
## the general view's green strip (UV 64,154, 5 high) cut at the health
## fraction; enemies have no stamina bar there, so none here. The size is
## fixed on screen (the 800×600 layout's units × 0.7, by the shorter window
## side, at least 0.8 px a unit), so it stays readable at any zoom.
## Clutter (remake choice): only enemies within RANGE m of the camera's
## look-at point or of a selected party member, at most MAX of them (the
## nearest to the look-at point first). Auto shows a bar once the unit is
## hurt, and over the controller's highlighted target (PadField.target_unit)
## at full health too; Always shows every bar. Bars fade in / out over
## FADE_S. Only units that are drawn: not hidden, not in the fog of war
## (UnitFog clears `visible`), not dead, in front of the camera and on the
## screen; not on the village screen or under a movie. Drawn on a canvas
## layer below the HUD (as PlayerNames, FlyingHP), anchored a little above
## the top of the unit's "hd" part (else its figure).

const OPTION := "enemy_hp_bars"
const OFF := 0
const AUTO := 1
const ALWAYS := 2
const RANGE := 25.0
const MAX := 12
const FADE_S := 0.25
const LIFT := 10.0          # 800×600 units above the head's top
const SCALE := 0.7          # 800×600 units → screen, × the window's scale
const FRAME_UV := Rect2(59, 119, 60, 5)
const FILL_UV := Rect2(64, 154, 50, 5)

var game: Game
## The units drawn last frame (uid -> alpha), for tests.
var drawn := {}
var _atlas: Texture2D
var _alpha := {}       # uid -> current alpha
static var _tops := {}  # uid -> [height above the feet, ms measured]
var _units := {}       # uid -> [unit, target alpha] of this frame


## The node of a game (created on first use, on a canvas layer below the HUD).
static func of(g: Game) -> EnemyBars:
	var layer := g.get_node_or_null("EnemyBarsLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "EnemyBarsLayer"
		layer.layer = -1
		var n := EnemyBars.new()
		n.name = "EnemyBars"
		n.game = g
		layer.add_child(n)
		g.add_child(layer)
	return layer.get_node("EnemyBars") as EnemyBars


## Whether bars show for option value `mode` with the input in use: `pad`
## (PadInput.active == "pad") or `touch` (TouchInput.enabled).
static func shows(mode: int, pad: bool, touch: bool) -> bool:
	return mode == ALWAYS or (mode == AUTO and (pad or touch))


static func input_shows() -> bool:
	return shows(GameData.option(OPTION), PadInput.active == "pad", TouchInput.enabled)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)


func active() -> bool:
	var s := game.session if game else null
	return s != null and game.world != null and input_shows() and not s.shop_available() \
			and not (game.hud and game.hud._movie and game.hud._movie.visible)


func _process(dt: float) -> void:
	var on := active()
	if not on:
		if visible:
			visible = false
			_alpha.clear()
			drawn = {}
		return
	visible = true
	_step(dt)
	queue_redraw()


## [unit, target alpha] of the units in range, the nearest first.
func entries() -> Array:
	var out: Array = []
	var w := game.world
	var mine := game.my_units()
	if w == null or mine.is_empty():
		return out
	var lead: GameUnit = mine[0]
	var always := GameData.option(OPTION) == ALWAYS
	var hl: GameUnit = null
	if PadInput.field != null and is_instance_valid(PadInput.field) and PadInput.active == "pad":
		hl = PadInput.field.call("target_unit")
	var focus := Vector2.INF
	if game.rig:
		focus = Vector2(game.rig.position.x, -game.rig.position.z)
	var near: Array = []
	if focus != Vector2.INF:
		near.append(focus)
	for u: GameUnit in game.selected:
		if is_instance_valid(u):
			near.append(u.pos)
	for u: GameUnit in w.visible_units():
		if u.dead or u.hidden or not u.visible or u.controller >= 0 or u.model == null or u.max_hp <= 0.0:
			continue
		if not (w.is_enemy(lead, u) or w.is_enemy(u, lead)):
			continue
		var close := false
		for p: Vector2 in near:
			if p.distance_squared_to(u.pos) < RANGE * RANGE:
				close = true
				break
		if not close:
			continue
		var hurt := u.hp < u.max_hp - 0.01
		out.append([u, 1.0 if always or hurt or u == hl else 0.0,
			u.pos.distance_squared_to(focus) if focus != Vector2.INF else 0.0])
	out.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	if out.size() > MAX:
		out.resize(MAX)
	return out


func _step(dt: float) -> void:
	var want := {}
	for e: Array in entries():
		want[(e[0] as GameUnit).uid] = [e[0], float(e[1])]
	var rate := dt / FADE_S
	for uid in _alpha.keys():
		if not want.has(uid):
			_alpha[uid] = float(_alpha[uid]) - rate
			if float(_alpha[uid]) <= 0.0:
				_alpha.erase(uid)
				_tops.erase(uid)
	for uid in want:
		var a := float(_alpha.get(uid, 0.0))
		var t: float = want[uid][1]
		a = minf(a + rate, t) if a < t else maxf(a - rate, t)
		if a > 0.0:
			_alpha[uid] = a
		else:
			_alpha.erase(uid)
	_units = want


func _draw() -> void:
	drawn = {}
	var cam := get_viewport().get_camera_3d()
	if cam == null or game == null or game.world == null:
		return
	var vs := get_viewport_rect().size
	var k := maxf(minf(vs.x, vs.y) / 600.0 * SCALE, 0.8)
	var size := FRAME_UV.size * k
	for uid in _alpha:
		var a := float(_alpha[uid])
		var e: Array = _units.get(uid, [])
		var u: GameUnit = e[0] if not e.is_empty() else game.world.units.get(uid)
		if a <= 0.0 or u == null or not is_instance_valid(u) or u.dead or not u.visible or u.model == null:
			continue
		var top := u.global_position + Vector3.UP * head_top(u)
		if cam.is_position_behind(top):
			continue
		var at := cam.unproject_position(top) - Vector2(0.0, LIFT * k)
		var r := Rect2(at - Vector2(size.x * 0.5, size.y), size)
		if r.end.x < 0.0 or r.position.x > vs.x or r.end.y < 0.0 or r.position.y > vs.y:
			continue
		var f := clampf(u.hp / maxf(u.max_hp, 0.01), 0.0, 1.0)
		var mod := Color(1, 1, 1, a)
		_region(r, FRAME_UV, mod, Color(0.05, 0.05, 0.05))
		var fill := Rect2(r.position + Vector2(5.0, 0.0) * k, Vector2(FILL_UV.size.x * f, FILL_UV.size.y) * k)
		if f > 0.0:
			_region(fill, Rect2(FILL_UV.position, Vector2(FILL_UV.size.x * f, FILL_UV.size.y)), mod, Color(0.25, 0.8, 0.2))
		drawn[uid] = a


func _region(dst: Rect2, uv: Rect2, mod: Color, plain: Color) -> void:
	if _atlas:
		draw_texture_rect_region(_atlas, dst, uv, mod)
	else:
		draw_rect(dst, Color(plain, mod.a))


## Screen pixels from a unit's head top to just above its bar, for marks
## stacked over it (the gamepad target's cursor and name, PadPrompts).
static func stack_px(vs: Vector2) -> float:
	var k := maxf(minf(vs.x, vs.y) / 600.0 * SCALE, 0.8)
	return (LIFT + FRAME_UV.size.y + 3.0) * k


## Height of the unit's head top above its feet, measured every half second
## (it follows the pose: crouching, lying).
static func head_top(u: GameUnit) -> float:
	var uid := u.uid
	var now := Time.get_ticks_msec()
	var c: Array = _tops.get(uid, [])
	if c.is_empty() or now - int(c[1]) > 500:
		var best := -INF
		var hd := u.model.find_child("hd", true, false) as Node3D
		for mi: Node in (hd.get_children() if hd else u.model.find_children("*", "MeshInstance3D", true, false)):
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh and (mi as MeshInstance3D).is_visible_in_tree():
				var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				best = maxf(best, b.end.y)
		c = [best - u.global_position.y if best != -INF else 1.9, now]
		_tops[uid] = c
	return float(c[0])
