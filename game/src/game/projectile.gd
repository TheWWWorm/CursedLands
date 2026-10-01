class_name Projectile
extends Node3D
## An arrow/bolt flying from a unit to its target. On the host it applies the
## hit when it arrives; on clients it is only a visual.

const SPEED := 28.0

var world: GameWorld
var source: GameUnit
var target: GameUnit
var apply_hit := true
## The strike's hit record (Combat.strike_roll), decided at the strike's start.
var roll := {}
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


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.015
	m.bottom_radius = 0.015
	m.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.15)
	m.material = mat
	_mesh.mesh = m
	_mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(_mesh)


func _physics_process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var goal := target.global_position + Vector3.UP * 1.0
	var d := goal - global_position
	var step := SPEED * dt
	if d.length() <= step:
		if apply_hit and is_instance_valid(source) and not target.dead:
			world.combat.melee(source, target, roll)
		queue_free()
		return
	look_at(goal, Vector3.UP)
	global_position += d.normalized() * step
