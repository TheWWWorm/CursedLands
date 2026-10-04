class_name OrderMarks
extends MeshInstance3D
## Ground markers as in the original: with the option "select_type" on
## (SelectionType, settings), a green triangle at each selected unit
## and with "show_path" (DrawPath, settings) the path particles of a
## move order (see move_ordered).
##
## The triangle is, drawn for every object of the
## selection list when SelectionType == 1 with size CornerSize 0.5:
## with s = size / 3, r / u the camera's right and up axes (
## only their x, y are used), flat at the unit's z + 0.3, an
## outer triangle P + 3s·r + 2s·u, P − 3s·r + 2s·u, P − 5s·u and an inner one
## P + 2s·r + 1.4s·u, P − 2s·r + 1.4s·u, P − 4s·u joined into a band of six
## triangles, colour (green, half transparent). The apex points
## the viewer. With SelectionType 0 the original draws no marker (selecting only
## sets the figure's colour to white
## each part's colour is pushed and its RGB set to 1.0). The
## remake lightens the selected figures with an additive overlay
## (**approx.**: the figures' normal colour, and so how much brighter white
## is, was not traced).

var game: Game
var _im := ImmediateMesh.new()
var _sel_mat := StandardMaterial3D.new()
##  triangle band: vertices as (right, up) multiples of s and
## the index list.
const SEL_VERTS := [Vector2(3, 2), Vector2(-3, 2), Vector2(0, -5), Vector2(2, 1.4),
	Vector2(-2, 1.4), Vector2(0, -4)]
const SEL_TRIS := [0, 4, 3, 0, 1, 4, 1, 5, 4, 1, 2, 5, 2, 3, 5, 2, 0, 3]
const SEL_SIZE := 0.5   # CornerSize, settings
var _lit := {}   # GameUnit -> model it lightened (select_type 0)
var _bright := {}   # unit material -> its lightened copy
var _flash := {}    # GameUnit -> seconds of white flash left (figure ticks)
## The emissive (1) pushes (RGB 1.0).
const WHITE := 1.0


## (n): the figure's white-flash counter = max(n)
## pushing white when it was 0; the world tick counts it down and
## pops the colour ((0)) when it reaches 0. Quest vars flash 4.
func flash(u: GameUnit, ticks: int) -> void:
	if ticks > 0 and is_instance_valid(u):
		_flash[u] = maxf(float(_flash.get(u, 0.0)), ticks * GameUnit.TICK)


func _ready() -> void:
	mesh = _im
	_sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sel_mat.albedo_color = Color(0, 1, 0, 128 / 255.0)
	_sel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Path display (option "show_path", DrawPath, read only by the receiver):
## the server sends the owner of a party unit message 0x0e (:
## mode A, flag B, target x / y, unit id, length F in ticks, the path unless
## A = 3); its handler makes particle 0x2039 on a ghost of the
## unit = 1.0 / 0 / 2.0 for A = 0 / 1 / 2 (green / grey
##  orange dots, one per tick of the path up to F) and
## 0x203a (B = 0, ring) or 0x203b (B != 0, cross) at the target.
## A move to a point (from the move order): no path
## -> A 3, B 1; a path whose end is farther from the target than a tenth of
## the unit's distance to it (|unit - target|^2 x 0.01 <= |end - target|^2)
## -> A 0, B 1; else A 0, B 0; F = 1e6 (the whole path). One message per
## unit, each at its own target. The walk tick calls
##  only while the order's flag is set and clears it: once
## per order, on its first tick (the flag is only ever cleared or copied with
## the order), so a re-plan shows nothing.
## **Approx.**: shown on the clicking peer when the order is given; the path
## is the remake's nav grid prediction.
func move_ordered(p: Vector2) -> void:
	var mine := _mine()
	for i in mine.size():
		var u: GameUnit = mine[i]
		var to := p + Session.group_offset(i)
		var w := game.world
		var path := w.nav.find_path(u.pos, to, [u], [], maxf(0.0, u.body_radius() - NavGrid.R_REF), u.move_class())
		if path.is_empty():
			_show(u, to, 3, 1, PackedVector3Array(), 0.0)
			continue
		var far := u.pos.distance_squared_to(to) * 0.01 <= path[-1].distance_squared_to(to)
		var ticks := _ghost_ticks(u, path)
		_show(u, to, 0, 1 if far else 0, ticks, 1e6)


## An order at unit `t` (the approach of order types 3 attack
## 4 / 5 casts, 6 interact / loot / steal; sent for party units only):
## no path -> A 3, B 1; already within `reach` -> A 3, B 0; else A = 2
## (orange) for an attack, 1 (grey) for the others, B = 1 when the path's end
## is still out of reach; F = the ticks until the unit is within reach,
## counted in steps of 5. `units`: the units given the order.
## **Approx.**: returns that count only for a path record
## type 2 (else 0), and the order byte keeps F = 1e6 — neither was
## traced, so the count is always used.
func unit_ordered(t: GameUnit, attack: bool, reach: float, units: Array) -> void:
	if t == null or not is_instance_valid(t):
		return
	for u: GameUnit in _mine():
		if not u in units:
			continue
		var r := u.melee_reach(t) if attack and reach < 0.0 else reach
		if attack and u.stats.get("ranged", false):
			r = float(u.stats.get("reach", r))
		_approach(u, t, t.pos, r, 2 if attack else 1)


## A cast order (types 4 / 5 through, the
## point casts): A = 2 (orange) when the spell's prototype (spells.sdb
## type_id, the school: 0 the elemental spells) is 0, else 1 (grey); reach =
## the spell's range centre to centre. `t` null: a cast at the
## point `at`.
func cast_ordered(u: GameUnit, spell: String, t: GameUnit, at: Vector2) -> void:
	if u == null or not u in _mine():
		return
	var sp := Spells.parse(spell)
	var a := 2 if int(sp.proto.get("type_id", 0)) == 0 else 1
	_approach(u, t, t.pos if t else at, float(sp.range), a)


func _approach(u: GameUnit, t: GameUnit, at: Vector2, r: float, a: int) -> void:
	var w := game.world
	if u.pos.distance_to(at) <= r:
		_show(u, at, 3, 0, PackedVector3Array(), 0.0)
		return
	var path := w.nav.find_path(u.pos, at, [u, t] if t else [u], [], maxf(0.0, u.body_radius() - NavGrid.R_REF), u.move_class())
	if path.is_empty():
		_show(u, at, 3, 1, PackedVector3Array(), 0.0)
		return
	# F counts the unit's own ticks (on the unit's path record
	# at its speed); the dots are the ghost's ticks up to F.
	var real := _ticks(u.pos, path, func(_c: Vector2, _q: Vector2) -> float: return u.speed() * GameUnit.TICK)
	var f := real.size() - 1
	var k := 0
	while k < real.size():
		if Vector2(real[k].x, real[k].y).distance_to(at) <= r:
			f = k
			break
		k += 5
	var out := Vector2(real[-1].x, real[-1].y).distance_to(at) > r
	_show(u, at, a, 1 if out else 0, _ghost_ticks(u, path), float(f))


## The first unit an interact / loot order goes to (Session: mine[0]).
func first_mine() -> Array:
	var m := _mine()
	return m.slice(0, 1)


## The selected units of this peer's player that would take an order
## (Session.apply_command's filter, in its order). A unit saying a
## "say_block" line (flag) is left out: the server's order handlers
##  skip it (Game.issue drops it too), so no path
## message 0x0e comes for it and draws nothing.
func _mine() -> Array:
	var out := []
	if game == null or game.world == null or game.session == null:
		return out
	for u: GameUnit in game.selected:
		if is_instance_valid(u) and not u.dead and u.world != null and u.controller == game.session.my_index \
				and not GameSound.blocked(u):
			out.append(u)
	return out


##  for one message: dots unless A = 3, then ring / cross.
func _show(u: GameUnit, at: Vector2, a: int, b: int, ticks: PackedVector3Array, f: float) -> void:
	if not GameData.option("show_path"):
		return
	var w := game.world
	var fx := ParticleFx.of(w)
	if fx == null:
		return
	if a != 3 and ticks.size() > 0:
		var k118: float = [1.0, 0.0, 2.0][a]
		var ef := fx.spawn(0x2039, Vector3(u.pos.x, u.pos.y, w.ground_at(u.pos.x, u.pos.y)), 1.0, null,
			{"k118": k118, "k11c": minf(f, float(ticks.size() - 1)), "secs": 1.5})
		if ef:
			ef.e.set_meta("path", ticks)
	fx.spawn(0x203b if b != 0 else 0x203a, Vector3(at.x, at.y, w.ground_at(at.x, at.y)), 1.0, null, {"secs": 0.6})


## The ghost's speed: (= 0.5
##  = 1e10) on the ghost before the dots are made, which sets its
## motion base (= unit) to 0.5 and its turn rate
## to 1e10 and rebuilds the spline: each node's speed is the
## node's cell value (sent in the message) x 0.5 / 512 cells
## 0.5 m a tick. So the dots are 0.5 x 0.5 m = 0.25 m apart
## on level ground (x the terrain factor), whether the unit walks or runs
## (human run 0.24 m, walk 0.08 m a tick).
const GHOST_BASE := 0.5


## The ghost's position at every logic tick along `path` (
## tick + idx): GHOST_BASE cells a tick x the step's terrain factor for the
## unit's movement class (the node values are the unit's). **Approx.**: the
## remake's path polyline instead of the cell spline, the factor sampled at
## the start of each tick.
func _ghost_ticks(u: GameUnit, path: PackedVector2Array) -> PackedVector3Array:
	var nav: NavGrid = game.world.nav if game and game.world else null
	var cls := u.move_class()
	var flying := u.has_meta("flying")
	return _ticks(u.pos, path, func(cur: Vector2, q: Vector2) -> float:
		var f := 1.0
		if nav and not flying and cur.distance_to(q) > 0.001:
			f = nav.step_factor(cur, cur + (q - cur).normalized() * NavGrid.CELL, cls)
		return GHOST_BASE * NavGrid.CELL * f)


## Positions at every logic tick walking `path` from `from`, `step_at(cur,
## next node)` metres a tick.
static func _ticks(from: Vector2, path: PackedVector2Array, step_at: Callable) -> PackedVector3Array:
	var out := PackedVector3Array([Vector3(from.x, from.y, 0.0)])
	var cur := from
	var left := -1.0
	for q in path:
		if left < 0.0:
			left = maxf(float(step_at.call(cur, q)), 0.01)
		while cur.distance_to(q) >= left:
			cur = cur.move_toward(q, left)
			out.append(Vector3(cur.x, cur.y, 0.0))
			left = maxf(float(step_at.call(cur, q)), 0.01)
			if out.size() >= 2500:
				return out
		left -= cur.distance_to(q)
		cur = q
	if Vector2(out[-1].x, out[-1].y) != cur:
		out.append(Vector3(cur.x, cur.y, 0.0))
	return out


## Figures drawn in white: select_type 0's selected units and
## the quest-var flash. Both push white onto the figure parts'
## colour stack ((1)): each part's D3D material emissive
## (.., the material at part: diffuse alpha, specular
##  zeroed) set to 1.0, and the TL pipeline
## adds it to the lighting, clamped to 1. The unit's own materials are swapped
## for copies with that emissive; a second overlay pass z-fought and flickered.
func _update_lit() -> void:
	var want := {}
	if game and GameData.option("select_type") == 0:
		for u: GameUnit in game.selected:
			if is_instance_valid(u) and not u.dead and u.model:
				want[u] = u.model
	for u in _flash:
		if is_instance_valid(u) and u.model:
			want[u] = u.model
	for u in _lit.keys():
		if not want.has(u) or want[u] != _lit[u]:
			if is_instance_valid(_lit[u]):
				_lighten(_lit[u], false)
			_lit.erase(u)
	for u in want:
		# Re-applied every frame: parts can be rebuilt (severed, re-dressed).
		_lighten(want[u], true)
		_lit[u] = want[u]


func _lighten(root: Node, on: bool) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override or mi.has_meta("unlit"):
			# The unit model's own material sits in material_override.
			if not on:
				if mi.has_meta("unlit"):
					mi.material_override = mi.get_meta("unlit")
					mi.remove_meta("unlit")
			elif mi.material_override not in _bright.values():
				mi.set_meta("unlit", mi.material_override)
				mi.material_override = _bright_of(mi.material_override)
			continue
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var cur := mi.get_surface_override_material(i)
			if not on:
				if cur in _bright.values():
					mi.set_surface_override_material(i, _bright.find_key(cur) if not mi.has_meta("unlit%d" % i) else mi.get_meta("unlit%d" % i))
					mi.remove_meta("unlit%d" % i)
				continue
			if cur in _bright.values():
				continue
			var base := cur if cur else mi.mesh.surface_get_material(i)
			mi.set_meta("unlit%d" % i, cur)
			mi.set_surface_override_material(i, _bright_of(base))


## A lightened copy of a unit material (cached).
func _bright_of(base: Material) -> Material:
	if base is EIUnitModel.LitMaterial:
		if not _bright.has(base):
			var lit := base.duplicate() as EIUnitModel.LitMaterial
			lit.set_shader_parameter("unit_emission", Vector3.ONE * WHITE)
			_bright[base] = lit
		var lit: EIUnitModel.LitMaterial = _bright[base]
		if lit.albedo_texture != base.albedo_texture:
			lit.albedo_texture = base.albedo_texture
		return lit
	var sm := base as StandardMaterial3D
	if sm == null:
		return base
	if not _bright.has(sm):
		var m := sm.duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = Color(WHITE, WHITE, WHITE)
		m.emission_texture = sm.albedo_texture
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_bright[sm] = m
	var b: StandardMaterial3D = _bright[sm]
	if b.albedo_texture != sm.albedo_texture:   # re-skinned meanwhile (UnitWounds)
		b.albedo_texture = sm.albedo_texture
		b.emission_texture = sm.albedo_texture
	return b


func _process(dt: float) -> void:
	_im.clear_surfaces()
	for u in _flash.keys():
		_flash[u] -= dt
		if _flash[u] <= 0.0 or not is_instance_valid(u):
			_flash.erase(u)
	_update_lit()
	if game == null or game.world == null:
		return
	var w := game.world
	var tris := PackedVector3Array()
	var cam := get_viewport().get_camera_3d()
	if GameData.option("select_type") == 1 and cam:
		# Camera axes in EI space (x, y): Godot (x, y, z) = EI (x, z, −y).
		var bx := cam.global_basis.x
		var by := cam.global_basis.y
		var s := SEL_SIZE / 3.0
		var r := Vector2(bx.x, -bx.z) * s
		var up := Vector2(by.x, -by.z) * s
		for u: GameUnit in game.selected:
			if not is_instance_valid(u) or u.dead:
				continue
			var z := w.ground_at(u.pos.x, u.pos.y) + 0.3
			for i: int in SEL_TRIS:
				var v: Vector2 = SEL_VERTS[i]
				var p: Vector2 = u.pos + r * v.x + up * v.y
				tris.append(EISpace.pos(p.x, p.y, z))
	for pass_ in [[tris, Mesh.PRIMITIVE_TRIANGLES, _sel_mat]]:
		var vs: PackedVector3Array = pass_[0]
		if vs.is_empty():
			continue
		_im.surface_begin(pass_[1], pass_[2])
		for v in vs:
			_im.surface_add_vertex(v)
		_im.surface_end()

