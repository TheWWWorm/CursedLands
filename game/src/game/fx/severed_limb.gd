class_name SeveredLimb
extends Node3D
## Remake-only (option gfx_severed_limbs): a severed limb thrown off the body.
## the original has nothing like it: a severed part stays on the figure with wound
## level 3 and the hit blood (see GameUnit._show_severed and
## .md "Severed limbs"). Every value here is the remake's:
## a copy of the part chain's meshes (the unit's own materials, so its skin,
## armour and wounds) leaves the body with an outward and upward push, tumbles
## under gravity, bounces once on the ground, lies there and then sinks away.

const GRAVITY := 9.8          # m/s² (the game's units are metres)
const PUSH := Vector2(1.2, 2.2)   # outward speed range, m/s
const LIFT := Vector2(1.8, 2.8)   # upward speed range, m/s
const SPIN := Vector2(5.0, 9.0)   # rad/s
const BOUNCE := 0.3           # vertical speed kept on the first contact
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
var _corners: Array[Vector3] = []   # local box corners of the meshes
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
			var b: AABB = copy.transform * copy.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			if c is Node3D and (c as Node3D).visible:
				stack.append(c)
	if first:
		limb.free()
		return null
	# Pivot at the middle of the limb so it tumbles about its centre.
	var mid := box.get_center()
	for c in limb.get_children():
		(c as Node3D).position -= mid
	for i in 8:
		limb._corners.append(box.get_endpoint(i) - mid)
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


func _ground() -> float:
	var p := global_position
	return world.ground_at(p.x, -p.z) if is_instance_valid(world) else -INF


## Lowest point of the meshes' box, in world space.
func _low() -> float:
	var y := INF
	for c in _corners:
		y = minf(y, (global_transform * c).y)
	return y


func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	if resting:
		rest_t += dt
		if rest_t > REST_TIME:
			var k := clampf((rest_t - REST_TIME) / SINK_TIME, 0.0, 1.0)
			global_position.y = _sink_from - SINK_DEPTH * k
			if k >= 1.0:
				queue_free()
		return
	# Fixed 1/60 s steps, so a long frame (a shader compile) keeps the arc.
	var n := mini(ceili(dt * 60.0), 30)
	for i in n:
		if resting:
			return
		_step(dt / n)


func _step(dt: float) -> void:
	vel.y -= GRAVITY * dt
	global_position += vel * dt
	if spin > 0.0:
		global_rotate(spin_axis, spin * dt)
	var g := _ground()
	var low := _low()
	if low < g:
		global_position.y += g - low
		bounces += 1
		if bounces >= 2 or absf(vel.y) < 1.0:
			resting = true
			_sink_from = global_position.y
			return
		vel.y = -vel.y * BOUNCE
		vel.x *= 0.5
		vel.z *= 0.5
		spin *= 0.4
