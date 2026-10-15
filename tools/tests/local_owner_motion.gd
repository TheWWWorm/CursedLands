extends Node
## The local owner's frame samples must not mutate authoritative state.
## Exercise the real path, direct-step and stopped-placement samplers.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func sample(u: GameUnit, expected: Vector2) -> void:
	var before := u.snapshot()
	var position := u.pos
	var path := u.path.duplicate()
	var tick := u._motion_tick
	var row := LocalHost._owner_snapshot(u)
	check(Vector2(row[1],row[2]).is_equal_approx(expected.snapped(Vector2.ONE/64.0)), "continuous owner position")
	check(u.pos == position and u.path == path and u._motion_tick == tick and u.snapshot() == before,
		"sampling leaves simulation position, path, clock and ordinary snapshot intact")
	for index in row.size():
		if index not in [1,2,3,13]:
			check(row[index] == before[index], "non-motion field %d remains authoritative" % index)
	check(NetSnapshot.unpack(NetSnapshot.pack([row]))[0] == row, "existing wire codec carries frame sample")

func _ready() -> void:
	var world := GameWorld.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	var u := GameUnit.new()
	u.world = world
	world.add_child(u)
	u.controller = 0
	u.pos = Vector2(10,20)
	u.facing = PI/2
	u.order = {"type":"move", "line":true}
	u.path = PackedVector2Array([Vector2(10,30)])
	u._draw_line_goal = u.path[0]
	u._move_speed = 5.0
	for fraction in [0.0,0.25,0.5,0.75,0.999]:
		world._logic_accumulator = GameUnit.TICK * fraction
		sample(u, u.pos + Vector2(0,5.0*GameUnit.TICK*fraction))
	u.pos = Vector2(10,29.95)
	world._logic_accumulator = GameUnit.TICK * 0.99
	sample(u,Vector2(10,30))
	u.direct_controlled = true
	u._direct_previous = Vector2(10,29.7)
	for fraction in [0.0,0.25,0.5,0.75,0.999]:
		world._logic_accumulator = GameUnit.TICK*fraction
		sample(u,u._direct_previous.lerp(u.pos,fraction))
		check(LocalHost._owner_snapshot(u)[3] == u.snapshot()[3], "direct movement retains aim facing")
	u.direct_controlled = false
	u.pos = Vector2(.25,.25)
	u.path = PackedVector2Array([Vector2(.75,.25),Vector2(1.25,.25),Vector2(1.75,.25)])
	u._motion_path = u.path
	u._draw_line_goal = Vector2.INF
	u._motion_cells.assign([Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0)])
	u._motion_count = 4
	u._motion = NavSpline.new()
	u._motion.build(u.pos,Vector2(1.75,.25),u._motion_cells,PackedInt32Array([512,512,512,512]),.2,1e10,0.0)
	u._motion_tick = 1.0
	u._draw_motion_active = true
	for fraction in [0.0,0.25,0.5,0.75,0.999]:
		world._logic_accumulator = GameUnit.TICK*fraction
		sample(u,u._motion.sample(1.0+world.logic_fraction()).p)
	u.path.clear()
	u._draw_motion_active = false
	u._move_speed = 0.0
	u.action = "idle"
	check(LocalHost._owner_snapshot(u) == u.snapshot(), "stopped actor uses the exact authoritative snapshot")
	u.pos = Vector2(400,500)
	check(LocalHost._owner_snapshot(u) == u.snapshot(), "placement without an active route never extrapolates")
	world.queue_free()
	await get_tree().process_frame
	print("LOCAL_OWNER_MOTION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
