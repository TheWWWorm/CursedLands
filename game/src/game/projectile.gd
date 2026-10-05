class_name Projectile
extends Node3D
## An arrow/bolt flying from a unit to its target. On the host it applies the
## hit when it arrives; on clients it is only a visual.

const SPEED := 28.0

var world: GameWorld
var source: GameUnit
var target: GameUnit
var apply_hit := true
## The strike's hit record (Combat.strike_roll), decided at the strike's
## start, with the damage part (Combat.strike_record) added at the launch: the
## missile carries its copy (object).
var roll := {}:
	set(v):
		roll = v.duplicate()
		if not roll.is_empty() and is_instance_valid(source) and world:
			roll.merge(world.combat.strike_record(source))
var _mesh: MeshInstance3D


static func launch(w: GameWorld, a: GameUnit, b: GameUnit, hit: bool) -> Projectile:
	var p := Projectile.new()
	p.world = w
	p.source = a
	p.target = b
	p.apply_hit = hit
	w.add_child(p)
	p.global_position = a.global_position + Vector3.UP * 1.3
	return p


## The shaft's material (also drawn by ShaderWarmup).
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.15)
	return mat


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.015
	m.bottom_radius = 0.015
	m.height = 0.9
	m.material = material()
	_mesh.mesh = m
	_mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(_mesh)


func _physics_process(dt: float) -> void:
	if world and world.session and world.session.lmp_travel:
		if world.session.lmp_travel.can_tick(world):
			world.session.lmp_travel.with_world(world, _tick.bind(dt))
		return
	_tick(dt)


func _tick(dt: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		queue_free()   # the target left the world (zone change, removed body)
		return
	var goal := target.global_position + Vector3.UP * 1.0
	var d := goal - global_position
	var step := SPEED * dt
	if d.length() <= step:
		# the target's with the shooter looked up by id
		# (); a shooter gone by now is 0, and the carried
		# record still hits (Combat.melee with no attacker).
		if apply_hit and not target.dead:
			world.combat.melee(source if is_instance_valid(source) else null, target, roll)
		queue_free()
		return
	look_at(goal, Vector3.UP)
	global_position += d.normalized() * step
