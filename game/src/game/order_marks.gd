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

const MotionSpline = preload("res://src/game/nav_spline.gd")
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
## pops the colour ((0)) when it reaches 0. Electrical hits flash 4.
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


## The original owner-only path message.
## Input handlers retain these call sites, but only the authoritative first
## command tick supplies the path, mode, ring/cross and ghost cutoff.
func move_ordered(_p: Vector2) -> void:
	pass


func unit_ordered(_t: GameUnit, _attack: bool, _reach: float, _units: Array) -> void:
	pass


func cast_ordered(_u: GameUnit, _spell: String, _t: GameUnit, _at: Vector2) -> void:
	pass


func on_path(e: Dictionary) -> void:
	if game == null or game.world == null:
		return
	var u: GameUnit = game.world.units.get(int(e.get("uid", -1)))
	if u == null:
		return
	var start := _point(e.get("start", []), u.pos)
	var at := _point(e.get("target", []), u.pos)
	_show(u, at, clampi(int(e.get("mode", 3)), 0, 3), int(e.get("cross", 0)),
		_ghost_ticks(e), float(e.get("ticks", 0.0)), start)


static func _point(row, fallback: Vector2) -> Vector2:
	return Vector2(float(row[0]), float(row[1])) if row is Array and row.size() == 2 else fallback


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
func _show(u: GameUnit, at: Vector2, a: int, b: int, ticks: PackedVector3Array, f: float, start := Vector2.INF) -> void:
	if not GameData.option("show_path"):
		return
	var w := game.world
	var fx := ParticleFx.of(w)
	if fx == null:
		return
	if start == Vector2.INF:
		start = u.pos
	if a != 3 and ticks.size() > 0:
		var k118: float = [1.0, 0.0, 2.0][a]
		var ef := fx.spawn(0x2039, Vector3(start.x, start.y, w.ground_at(start.x, start.y)), 1.0, null,
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


## Native ghost base0.5 and turn1e10 rebuild the complete transmitted cell
## spline, independent of the hero's gait and the current client's map.
func _ghost_ticks(e: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cells: Array[Vector2i] = []
	for row in e.get("cells", []):
		if row is Array and row.size() == 2:
			cells.append(Vector2i(int(row[0]), int(row[1])))
	if cells.is_empty():
		return out
	var spline := MotionSpline.new()
	spline.build(_point(e.get("start", []), Vector2.ZERO), _point(e.get("end", []), Vector2.ZERO),
		cells, PackedInt32Array(e.get("values", [])), GHOST_BASE, 1e10, float(e.get("heading", 0.0)))
	var ticks := mini(int(ceil(spline.duration)), 2499) if is_finite(spline.duration) else 0
	for tick in ticks + 1:
		var p: Vector2 = spline.sample(tick).p
		out.append(Vector3(p.x, p.y, 0.0))
	return out


## Figures drawn in white: select_type 0's selected units and
## the electrical-hit flash and active quest lights
## . These push white onto the figure parts'
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
	if game and game.quest_lights:
		for u: GameUnit in game.quest_lights.white_units():
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
