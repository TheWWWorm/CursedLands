class_name SeveredLimb
extends Node3D
## Remake-only (option gfx_severed_limbs): a severed limb thrown off the body.
## the original has nothing like it: a severed part stays on the figure with wound
## level 3 and the hit blood (see GameUnit._show_severed and
## .md "Severed limbs"). Every value here is the remake's:
## a copy of the part chain's meshes (the unit's own materials, so its skin,
## armour and wounds) leaves the body with an outward and upward push, tumbles
## under gravity, bounces and slides on terrain, settles flat and then sinks away.

const GRAVITY := 9.8          # m/s² (the game's units are metres)
const PUSH := Vector2(2.0, 3.4)   # outward speed range, m/s
const LIFT := Vector2(1.2, 2.1)   # upward speed range, m/s
const SPIN := Vector2(5.0, 9.0)   # rad/s
const BOUNCE := 0.28          # restitution along the contact normal
const FRICTION := 0.65
const STEP := 1.0 / 120.0
const CONTACT_MARGIN := 0.008
const SLEEP_SPEED := 0.12
const SLEEP_DELAY := 0.25
const REST_TIME := 30.0       # seconds on the ground before it sinks
const SINK_TIME := 2.0
const SINK_DEPTH := 0.35

var world: GameWorld
var vel := Vector3.ZERO
var launch := Vector3.ZERO   # the starting velocity (tools/sever_test.gd)
var spin_axis := Vector3.UP
var spin := 0.0
var bounces := 0
var resting := false
var rest_t := 0.0
var _corners: Array[Vector3] = []   # actual mesh support points, not an enclosing box
var _rest_axis := Vector3.UP
var _quiet_time := 0.0
var _sink_from := 0.0


## Copies the chain of `unit`'s model starting at part node `part` (call it
## before the chain is hidden) and launches it. Returns null if the model has
## no such node or no mesh under it.
static func throw(unit: GameUnit, part: String) -> SeveredLimb:
	if unit == null or unit.model == null or unit.world == null or unit.get_parent() == null:
		return null
	unit.model.flush_pending_pose()
	var root := unit.model.find_child(part, true, false) as Node3D
	if root == null or not root.is_visible_in_tree():
		return null
	var limb := SeveredLimb.new()
	limb.name = "SeveredLimb"
	limb.world = unit.world
	var origin := root.global_transform
	var inv := origin.affine_inverse()
	var body := unit.model.find_child("Body", true, false) as MeshInstance3D
	var box := AABB()
	var points := PackedVector3Array()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var copy: MeshInstance3D = null
		if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).visible:
			var src := n as MeshInstance3D
			copy = MeshInstance3D.new()
			copy.mesh = src.mesh
			copy.material_override = src.material_override
			for s in src.get_surface_override_material_count():
				copy.set_surface_override_material(s, src.get_surface_override_material(s))
			copy.layers = src.layers
			copy.cast_shadow = src.cast_shadow
			copy.transform = inv * src.global_transform
		elif n is Node3D and n.has_meta("weld_mesh"):
			var wm: Array = n.get_meta("weld_mesh")
			copy = MeshInstance3D.new()
			copy.mesh = wm[0]
			copy.material_override = wm[1]
			if body:
				copy.layers = body.layers
				copy.cast_shadow = body.cast_shadow
			copy.transform = inv * (n as Node3D).global_transform
		if copy:
			limb.add_child(copy)
			for point in _mesh_support(copy.mesh):
				points.append(copy.transform * point)
			var b: AABB = copy.transform * copy.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			if c is Node3D and (c as Node3D).visible:
				stack.append(c)
	if first or points.is_empty():
		limb.free()
		return null
	# Pivot at the middle of the limb so it tumbles about its centre.
	var mid := box.get_center()
	for c in limb.get_children():
		(c as Node3D).position -= mid
	# A union AABB has empty corners far outside bent arms and legs. Using
	# those corners as feet left the visible meshes hanging above the floor.
	for point in _support(points):
		limb._corners.append(point - mid)
	var size := box.size
	limb._rest_axis = Vector3.RIGHT if size.x <= size.y and size.x <= size.z \
		else Vector3.UP if size.y <= size.z else Vector3.BACK
	unit.get_parent().add_child(limb)
	limb.global_transform = origin * Transform3D(Basis(), mid)
	# Outward from the body's axis, plus a little randomness.
	var out := origin.origin - unit.global_position
	out.y = 0.0
	if out.length() < 0.05:
		out = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	out = out.normalized()
	limb.vel = out * randf_range(PUSH.x, PUSH.y) + Vector3.UP * randf_range(LIFT.x, LIFT.y)
	limb.launch = limb.vel
	limb.spin_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if limb.spin_axis == Vector3.ZERO:
		limb.spin_axis = Vector3.RIGHT
	limb.spin = randf_range(SPIN.x, SPIN.y)
	return limb


## Cached on the shared mesh: extracting vertices may synchronize with the
## renderer. Subsequent severings of the same figure reuse its small hull.
static func _mesh_support(mesh: Mesh) -> PackedVector3Array:
	if mesh.has_meta(&"sever_support"):
		return mesh.get_meta(&"sever_support")
	var vertices := PackedVector3Array()
	for surface in mesh.get_surface_count():
		vertices.append_array(EIFigure.surface_geometry(mesh, surface)[0])
	var points := _support(vertices)
	mesh.set_meta(&"sever_support", points)
	return points


## At most 26 actual surface vertices keep contacts cheap, including on slopes.
static func _support(vertices: PackedVector3Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	if vertices.is_empty():
		return points
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if x == 0 and y == 0 and z == 0:
					continue
				var direction := Vector3(x, y, z)
				var best := vertices[0]
				var projection := best.dot(direction)
				for point in vertices:
					var value := point.dot(direction)
					if value > projection:
						best = point
						projection = value
				if not points.has(best):
					points.append(best)
	return points


func _ground() -> float:
	var p := global_position
	return world.ground_at(p.x, -p.z) if is_instance_valid(world) else -INF


func _low() -> float:
	var y := INF
	var pose := global_transform
	for point in _corners:
		y = minf(y, (pose * point).y)
	return y


## Lowest clearance at each support vertex, including ramps and platform edges.
func _contact() -> Vector4:
	var contact := Vector4(0.0, 0.0, 0.0, INF)
	var pose := global_transform
	for point in _corners:
		var p := pose * point
		var gap := p.y - world.ground_at(p.x, -p.z)
		if gap < contact.w:
			contact = Vector4(p.x, p.y, p.z, gap)
	return contact


func _normal(p: Vector3) -> Vector3:
	const SAMPLE := 0.08
	var dx := world.ground_at(p.x + SAMPLE, -p.z) - world.ground_at(p.x - SAMPLE, -p.z)
	var dz := world.ground_at(p.x, -p.z - SAMPLE) - world.ground_at(p.x, -p.z + SAMPLE)
	return Vector3(-dx, 2.0 * SAMPLE, -dz).normalized()


func _process(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	if not is_instance_valid(world):
		queue_free()
		return
	if resting:
		rest_t += dt
		if rest_t > REST_TIME:
			var k := clampf((rest_t - REST_TIME) / SINK_TIME, 0.0, 1.0)
			global_position.y = _sink_from - SINK_DEPTH * k
			if k >= 1.0:
				queue_free()
		return
	# Bound cosmetic catch-up after a stall; never enlarge a collision step.
	var remaining := minf(dt, 0.5)
	while remaining > 0.000001 and not resting:
		var step := minf(remaining, STEP)
		_step(step)
		remaining -= step


func _step(dt: float) -> void:
	vel.y -= GRAVITY * dt
	global_position += vel * dt
	if spin > 0.0:
		global_rotate(spin_axis, spin * dt)
	var contact := _contact()
	if contact.w > CONTACT_MARGIN:
		_quiet_time = 0.0
		return
	global_position.y -= minf(contact.w, 0.0)
	var normal := _normal(Vector3(contact.x, contact.y, contact.z))
	var impact := vel.dot(normal)
	if impact < -0.8:
		# Rotation can touch the ground while the centre is rising. Only
		# incoming velocity may bounce; repeated contacts never freeze flight.
		vel -= normal * (1.0 + BOUNCE) * impact
		spin *= 0.65
		bounces += 1
		_quiet_time = 0.0
		return
	if impact < 0.0:
		vel -= normal * impact
	var tangent := vel - normal * vel.dot(normal)
	vel -= tangent - tangent.move_toward(Vector3.ZERO, FRICTION * GRAVITY * normal.y * dt)
	spin *= exp(-8.0 * dt)
	# A low-energy contact tips the short axis toward the surface, letting
	# the limb roll down instead of balancing indefinitely on its end.
	var up := (global_basis * _rest_axis).normalized()
	if up.dot(normal) < 0.0:
		up = -up
	var axis := up.cross(normal)
	var angle := up.angle_to(normal)
	if axis.length_squared() > 0.000001:
		global_rotate(axis.normalized(), angle * (1.0 - exp(-10.0 * dt)))
	contact = _contact()
	# Settling rotation may lower OR raise its support point. Keep contact
	# only within the small rolling step; an edge drop resumes free flight.
	if contact.w < CONTACT_MARGIN:
		global_position.y -= contact.w
	if vel.length() < SLEEP_SPEED and spin < 0.15 and angle < 0.02 \
			and absf(contact.w) < 0.03:
		_quiet_time += dt
		if _quiet_time >= SLEEP_DELAY:
			resting = true
			vel = Vector3.ZERO
			spin = 0.0
			_sink_from = global_position.y
	else:
		_quiet_time = 0.0
