extends "arena_expansion_ui.gd"
## Inspect the actual emitted selection mesh while unit heading, camera pitch
## and drawn placement change. The controlled ground has a nonzero slope.
class Field extends GameWorld:
	func _ready() -> void: pass
	func ground_at(x: float, y: float) -> float: return x * 0.1 + y * 0.2
class View extends Game:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
class Unit extends GameUnit:
	func _process(_dt: float) -> void: pass
	func _physics_process(_dt: float) -> void: pass

func vertices(marks: OrderMarks) -> PackedVector3Array:
	return marks.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _ready() -> void:
	OS.add_logger(errors)
	GameData.options.merge({"auto_graphics":0,"select_type":1,"show_tutorial":0}, true)
	var game := View.new()
	var world := Field.new()
	game.world = world
	add_child(game)
	game.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var unit := Unit.new()
	world.add_child(unit)
	unit.world = world
	unit.set_process(false)
	unit.set_physics_process(false)
	unit.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.selected = [unit]
	var marks := OrderMarks.new()
	marks.game = game
	game.add_child(marks)
	marks.set_process(false)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.current = true
	camera.position = Vector3(4, 6, 6)
	camera.look_at(Vector3.ZERO)
	var center := Vector2(2, 3)
	for step in 16:
		var angle := step * TAU / 16.0
		unit.facing = angle
		unit.pos = center
		unit.transform = Transform3D(Basis(Vector3.UP, angle + GameUnit.MODEL_YAW_OFFSET), EISpace.pos(center.x,center.y,world.ground_at(center.x,center.y)))
		marks._process(0.0)
		check(marks.mesh.get_surface_count() == 1, "selected alive unit has a marker")
		var points := vertices(marks)
		check(points.size() == 18, "triangle retains its six-sided band")
		var apex: Vector3 = points[10] # outer apex in the fourth triangle
		var direction := (Vector2(apex.x,-apex.z) - center).normalized()
		check(direction.dot(Vector2.from_angle(angle)) > 0.99999, "marker follows figure heading %d" % step)
		var height := world.ground_at(center.x,center.y) + 0.3
		check(Array(points).all(func(p): return is_equal_approx(p.y,height)), "marker is flat at ground beneath the unit")
		var left := points[0] - apex
		var right := points[4] - apex
		check(absf(rad_to_deg(left.angle_to(right)) - 46.397181) < 0.01, "forward apex retains the original narrow angle")
		camera.position = Vector3(-4, 1 + step, -2)
		camera.look_at(Vector3.ZERO)
		marks._process(0.0)
		check(vertices(marks) == points, "camera yaw/pitch cannot rotate or stretch the ground marker")
	# A replica's drawn transform may differ from the latest authority snapshot.
	unit.pos = Vector2(100,100)
	unit.facing = PI
	marks._process(0.0)
	var apex: Vector3 = vertices(marks)[10]
	check(Vector2(apex.x,-apex.z).distance_to(center) < 1.0, "marker stays under drawn figure during snapshot interpolation")
	camera.current = false
	marks._process(0.0)
	check(marks.mesh.get_surface_count() == 1, "marker geometry does not depend on an active camera")
	unit.dead = true
	marks._process(0.0)
	check(marks.mesh.get_surface_count() == 0, "dead unit has no marker")
	unit.dead = false
	GameData.options.select_type = 0
	marks._process(0.0)
	check(marks.mesh.get_surface_count() == 0, "disabled marker option removes geometry")
	game.world = null
	unit.world = null
	game.queue_free()
	await frames(4)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("SELECTION_MARKER_FACING ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
