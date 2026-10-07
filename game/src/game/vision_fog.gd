class_name VisionFog
extends Node3D
## "Field of vision" (spell vision_fog, texts: "Allows you to see what the
## spell's target is seeing"). the original case 0x17 makes a fog
## object (type 0x5e) holding caster and target; each update
##  it fills a cell grid with what the target
## sees: its sight radius x sight factors inside its vision arc, cut by the
## terrain, then life sense and the front peripheral arc. A new
## cast replaces the caster's old fog. Shown only to the caster's player.
## Approx.: the grid is drawn as a translucent ground overlay rather than
## the original cloud figure, and is redrawn every 0.3 seconds.

const CELL := 0.5
static var _by_player := {}

var world: GameWorld
var target: GameUnit
var caster: GameUnit
var _caster_required := false
var until := 0.0
var elapsed := 0.0
var _mm: MultiMeshInstance3D
var _next := 0.0


static func open(w: GameWorld, t: GameUnit, secs: float, player: int, c: GameUnit = null) -> void:
	var old = _by_player.get(player)   # untyped: the old fog may be freed already
	if old != null and is_instance_valid(old):
		old.queue_free()
	var f := VisionFog.new()
	f.world = w
	f.target = t
	f.caster = c
	f._caster_required = c != null
	# Counter reaches -1 at duration+1, state3 at duration+2, then deletes
	# the attached grid at duration+3 (case0x17).
	f.until = maxf(secs, 0.0) + 3.0 * GameUnit.TICK
	w.add_child(f)
	_by_player[player] = f


func _ready() -> void:
	_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(CELL, CELL) * 0.92
	q.material = material()
	mm.mesh = q
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)


## The overlay's material (also drawn by ShaderWarmup).
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.75, 1.0, 0.28)
	mat.no_depth_test = false
	return mat


func _physics_process(dt: float) -> void:
	if world.session and world.session.lmp_travel and not world.session.lmp_travel.can_tick(world):
		return
	elapsed += dt
	if elapsed >= until or not is_instance_valid(target) or target.dead \
			or (_caster_required and not is_instance_valid(caster)):
		queue_free()
		return
	if elapsed < _next:
		return
	_next = elapsed + 0.3
	var cells := visible_cells(world, target, caster)
	var mm := _mm.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2 = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis(), EISpace.pos(c.x, c.y, world.ground_at(c.x, c.y) + 0.08)))


## the target observes, using the caster's visibility
## detection and posed height as its reference. The optional reference
## keeps old event packets and diagnostic callers usable.
static func visible_cells(w: GameWorld, u: GameUnit, reference: GameUnit = null) -> Array:
	var cells := {}
	var visible := reference.vis_factor() if is_instance_valid(reference) else 1.0
	var detection := reference.detect(0) if is_instance_valid(reference) else 1.0
	var life_detection := reference.detect(2) if is_instance_valid(reference) else 1.0
	var height := reference.eye_z() - w._stand_z(reference.pos) if is_instance_valid(reference) else 1.0
	var sight := _f32(visible * u.sight_factor() * detection * (float(u.stats.get("sight", 10.0)) + u.sense_bonus(0)))
	var cosine := _f32(cos(deg_to_rad(float(u.race.get("vision_arc", 180.0))) * 0.5))
	_paint(w, u, maxf(sight, 0.0), cosine, height, cells)
	var life := _f32(u.sense(2) * life_detection)
	if life != 0.0:
		_paint(w, u, life, -1.0, -1000.0, cells)
	var peripheral := float(u.proto.get("peripheral_skills", 0.0))
	if peripheral != 0.0:
		_paint(w, u, peripheral, 0.0, height, cells)
	var out := cells.keys()
	out.sort_custom(func(a: Vector2, b: Vector2): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


##  global half-metre samples, nearest-even bounds, inclusive
## radius/cone tests and distance-scaled terrain ray. Life sense bypasses
## terrain; peripheral vision keeps the forward half circle and occlusion.
static func _paint(w: GameWorld, u: GameUnit, radius: float, cosine: float, height: float, cells: Dictionary) -> void:
	var centre := Vector2i(GameUnit._fistp(_f32(u.pos.x * 2.0 - 0.5)), GameUnit._fistp(_f32(u.pos.y * 2.0 - 0.5)))
	var n := GameUnit._fistp(_f32(radius * 2.0 - 0.5)) + 1
	var forward := Vector2.from_angle(u.facing)
	var eye := u.eye_z()
	for iy in range(centre.y - n, centre.y + n):
		for ix in range(centre.x - n, centre.x + n):
			if ix < 0 or iy < 0 or ix >= w.nav.size.x or iy >= w.nav.size.y:
				continue
			var point := Vector2(ix, iy) * CELL
			var delta := point - u.pos
			var distance := _f32(sqrt(float(delta.x) * delta.x + float(delta.y) * delta.y))
			if distance > radius or (cosine > -1.0 and float(delta.x) * forward.x + float(delta.y) * forward.y < distance * cosine):
				continue
			if height >= -100.0:
				var i := iy * w.nav.size.x + ix
				var ground := float(w.nav._hq[i]) / w.nav._alt if i < w.nav._hq.size() else w.ground_at(point.x, point.y)
				if w.terrain_ray(u.pos, eye, point, _f32(ground + height)) * radius < distance:
					continue
			cells[point] = true


static func _f32(v: float) -> float:
	return float(PackedFloat32Array([v])[0])
