extends Node
## Geometry contacts, ballistic flight, slopes, hitch recovery and real figures.
var checks := 0
var failures := 0
var cases := []

class FloorWorld extends GameWorld:
	var slope := Vector2.ZERO
	var ledge := false
	func ground_at(x: float, y: float) -> float:
		return slope.dot(Vector2(x, -y)) + (2.0 if ledge and x < 0.0 else 0.0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func clearance(limb: SeveredLimb) -> float:
	var gap := INF
	for child in limb.get_children():
		if not child is MeshInstance3D: continue
		for surface in child.mesh.get_surface_count():
			for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = child.global_transform * vertex
				gap = minf(gap, p.y - limb.world.ground_at(p.x, -p.z))
	return gap

func simulate(limb: SeveredLimb, dt: float, label: String) -> void:
	var from := limb.global_position
	var lowest := INF
	var elapsed := 0.0
	while elapsed < 8.0 and not limb.resting:
		limb._process(dt)
		elapsed += dt
		lowest = minf(lowest, clearance(limb))
	check(limb.resting, label + ": settles within eight seconds")
	check(limb.bounces > 0, label + ": bounces before sleeping")
	check(limb.global_position.distance_to(from) > 0.5, label + ": leaves the body")
	check(absf(clearance(limb)) < 0.045, label + ": visible mesh touches the floor")
	check(lowest > -0.06, label + ": no visible tunnelling through the floor")
	check(limb.vel == Vector3.ZERO and limb.spin == 0.0, label + ": sleep removes remaining motion")
	cases.append({"case":label,"seconds":elapsed,"bounces":limb.bounces,"gap":clearance(limb),"min_gap":lowest})
	var at := limb.global_transform
	limb._process(1.0)
	check(limb.global_transform == at, label + ": resting pose is stable")
	limb.rest_t = SeveredLimb.REST_TIME + SeveredLimb.SINK_TIME * 0.5
	limb._process(0.01)
	check(limb.global_position.y < at.origin.y - 0.1, label + ": sinks after resting")
	limb.rest_t = SeveredLimb.REST_TIME + SeveredLimb.SINK_TIME
	limb._process(0.01)
	check(limb.is_queued_for_deletion(), label + ": expires")

func _ready() -> void:
	seed(151031)
	GameData.options["gfx_severed_limbs"] = 1
	var world := FloorWorld.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	var unit := GameUnit.new()
	check(unit.setup(world, {"prototype":"Human Hero","nid":450001,"player":0}), "original human figure loads")
	world.add_child(unit)
	unit.position = Vector3(0, 1.0, 0)
	unit.model.flush_pending_pose()
	for slope in [Vector2.ZERO, Vector2(0.2, -0.15)]:
		world.slope = slope
		for part in ["hd", "lh1", "rh1", "ll1", "rl1"]:
			for dt in [1.0/30.0, 1.0/144.0]:
				seed(4501)
				var limb := SeveredLimb.throw(unit, part)
				check(limb != null, "detaches " + part)
				if limb == null: continue
				check(limb._corners.size() <= 26, "contact cost is bounded")
				check(limb.launch.y > 0 and Vector2(limb.launch.x,limb.launch.z).length() >= 2.0, "launch pushes outward")
				simulate(limb, dt, "%s slope=%s dt=%.4f" % [part,slope,dt])
	world.slope = Vector2.ZERO
	var hitch := SeveredLimb.throw(unit, "rl1")
	hitch._process(0.3)
	check(hitch.global_position.is_finite() and not hitch.resting, "300 ms hitch preserves flight")
	simulate(hitch, 1.0/60.0, "hitch")
	var rising := SeveredLimb.throw(unit, "rh1")
	rising.global_position.y -= rising._low() + 0.01
	rising.vel = Vector3(2,2,0);rising.spin=0;rising.bounces=1
	rising._step(0.001)
	check(not rising.resting and rising.vel.y > 0, "second contact while rising does not freeze or reverse flight")
	rising.free()
	world.ledge=true
	var falling:=SeveredLimb.throw(unit,"ll1")
	falling.global_position=Vector3(-1,3.3,0);falling.vel=Vector3(4,0,0)
	simulate(falling,1.0/60.0,"platform edge")
	check(falling.global_position.x>0 and falling.global_position.y<1,"leaving a platform falls to lower ground")
	world.ledge=false
	var invalid := SeveredLimb.throw(unit, "hd")
	var before := invalid.global_transform
	invalid._process(NAN);invalid._process(INF);invalid._process(-1)
	check(invalid.global_transform == before, "invalid frame times cannot corrupt geometry")
	invalid.world=null;invalid._process(0.1)
	check(invalid.is_queued_for_deletion(), "orphan limb cleans up")
	# Exercise the production visibility/replica path, including saved masks.
	for child in world.get_children():
		if child is SeveredLimb and not child.is_queued_for_deletion():child.queue_free()
	await get_tree().process_frame
	var arm := unit.model.find_child("rh1",true,false) as Node3D
	unit._show_severed(1 << 3,true)
	var thrown := 0
	for child in world.get_children():
		if child is SeveredLimb and not child.is_queued_for_deletion():thrown+=1
	check(not arm.visible and thrown==1,"live severing hides the chain and launches one limb")
	unit._show_severed(1 << 3,true)
	var repeated := 0
	for child in world.get_children():
		if child is SeveredLimb and not child.is_queued_for_deletion():repeated+=1
	check(repeated==1,"repeated snapshot cannot throw a second limb")
	GameData.options.gfx_severed_limbs=0;unit._show_severed(1 << 3,true)
	check(arm.visible,"disabled effect restores original body chain")
	GameData.options.gfx_severed_limbs=1;unit._show_severed(1 << 3,false)
	check(not arm.visible,"loading a severed mask hides its chain without a new flight")
	FileAccess.open("user://severed-limb-physics.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "))
	world.queue_free()
	await get_tree().process_frame
	print("SEVERED_LIMB_PHYSICS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
