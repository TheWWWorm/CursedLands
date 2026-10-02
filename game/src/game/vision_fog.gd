class_name VisionFog
extends Node3D
## "Field of vision" (spell vision_fog, texts: "Allows you to see what the
## spell's target is seeing"). the original case 0x17 makes a fog
## object (type 0x5e) holding caster and target; each update
##  it fills a cell grid with what the target
## sees: its sight radius x sight factors inside its vision arc, cut by the
## terrain, then a full circle of its peripheral range. A new
## cast replaces the caster's old fog. Shown only to the caster's player.
## Approx.: 1.5 m cells, a translucent ground overlay, redrawn every 0.3 s;
## the original's third pass is left out.

const CELL := 1.5
static var _by_player := {}

var world: GameWorld
var target: GameUnit
var until := 0.0
var _mm: MultiMeshInstance3D
var _next := 0.0


static func open(w: GameWorld, t: GameUnit, secs: float, player: int) -> void:
	var old = _by_player.get(player)   # untyped: the old fog may be freed already
	if old != null and is_instance_valid(old):
		old.queue_free()
	var f := VisionFog.new()
	f.world = w
	f.target = t
	f.until = Time.get_ticks_msec() / 1000.0 + secs
	w.add_child(f)
	_by_player[player] = f


func _ready() -> void:
	_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(CELL, CELL) * 0.92
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.75, 1.0, 0.28)
	mat.no_depth_test = false
	q.material = mat
	mm.mesh = q
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= until or target == null or not is_instance_valid(target) or target.dead:
		queue_free()
		return
	if now < _next:
		return
	_next = now + 0.3
	var cells := visible_cells(world, target)
	var mm := _mm.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2 = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis(), EISpace.pos(c.x, c.y, world.ground_at(c.x, c.y) + 0.08)))


## Cell centres the unit sees.
static func visible_cells(w: GameWorld, u: GameUnit) -> Array:
	var out := []
	var sight := (float(u.stats.get("sight", 10.0)) + u.sense_bonus(0)) * u.sight_factor()
	var side := maxf(float(u.proto.get("peripheral_skills", 0.0)), 0.0)
	var r := maxf(sight, side)
	var arc := deg_to_rad(float(u.race.get("vision_arc", 180.0))) * 0.5
	var n := ceili(r / CELL)
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var p := u.pos + Vector2(ix, iy) * CELL
			var d := p.distance_to(u.pos)
			if d > r:
				continue
			var ang := absf(wrapf((p - u.pos).angle() - u.facing, -PI, PI))
			if d < side or (d <= sight and ang <= arc and w.sight_ray_point(u, p) > 0.0):
				out.append(p)
	return out
