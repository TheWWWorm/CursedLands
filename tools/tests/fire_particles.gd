extends Node
## Native fire batches against the retained original callbacks, including
## every interpolation field and the emitter's future random stream.
var checks := 0
var failures := 0
var labels := 0

class SampleGround extends FxGround:
	func at(x: float, y: float) -> float:
		return sin(x * 0.7) + y * 0.13

func ground(trial: int) -> FxGround:
	if trial % 3 == 0: return SampleGround.new()
	var g := FxGround.new()
	g.grid_w = 4; g.cells_w = 3; g.cells_h = 3; g.valid = true
	g.heights = PackedFloat32Array([0,1,2,3,2,3,4,5,4,5,6,7,6,7,8,9])
	g.surface = PackedFloat32Array([0,3,0,5,0,7,0,9,0])
	if trial % 3 == 2:
		g.floors[Vector2i.ZERO] = [[1, {"centre":Vector3(2,2,10), "radius":4.0,
			"origin":Vector3(0,0,10), "normal":Vector3(0,0,1), "a":Vector3(1,0,0),
			"b":Vector3(0,1,0), "length_a":4.0, "length_b":4.0}]]
	return g

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if labels < 12:
			labels += 1
			printerr("FAIL ", label)

func compare(a: FxEmitter, b: FxEmitter, label: String) -> void:
	check(a.parts == b.parts, label + " particle records")
	if a.parts != b.parts and labels < 12:
		for i in mini(a.parts.size(), b.parts.size()):
			if a.parts[i] != b.parts[i]:
				printerr("ROW ", i, " native=", a.parts[i], " script=", b.parts[i])
				break
	check(a.rng.state == b.rng.state, label + " random state")

func _ready() -> void:
	check(ClassDB.class_exists("FireParticleKernel"), "native fire available")
	if failures: get_tree().quit(1); return
	var fa := ParticleFx.new()
	var fb := ParticleFx.new()
	var random := RandomNumberGenerator.new()
	random.seed = 1840911
	for kind in [0x2000, 0x2001, 0x2003, 0x2004, 0x2010]:
		for trial in 24:
			var a := FxTypes.create(fa, kind)
			var b := FxTypes.create(fb, kind)
			check(a._fire_kernel != null, "factory selects native fire")
			var values := {"d0": trial % 9, "d8": [1, 12, 57, 250][trial % 4],
				"d4": [0.0, 0.03, 0.8, 1000.0][trial % 4], "cc": [-1, 0, 40, 51, 88, 100][trial % 6],
				"ec": [-1, 1, 4, 32][trial % 4], "e4": [0, 1, 2, 4][trial % 4],
				"dc": [1, 8, 9, 15][trial % 4], "s": random.randf_range(0.02, 9.0),
				"a110": random.randf_range(0.0, 2.0), "m114": random.randf_range(0.5, 1.2),
				"vmin": Vector3(-0.32, -0.27, 0.0), "vmax": Vector3(0.24, 0.17, 0.0),
				"ground_src": ground(trial), "v130": Vector3(2.1, -0.8, 0.0), "k128": 0.6}
			for key in values: a.set(key, values[key]); b.set(key, values[key])
			for tick in 90:
				var live := {"wp": Vector3(random.randf_range(-400, 400), random.randf_range(-400, 400), random.randf_range(-20, 90)),
					"wind": Vector3(0.37, -0.42, 0.08), "wind_s": float(tick % 5) * 0.2,
					"moved": float(tick % 4) * 0.06, "has_carrier": tick % 7 != 0,
					"flags": (1 | (2 if trial % 2 else 0) | (4 if trial % 3 else 0)) if tick < 60 else (4 if trial % 3 else 0)}
				for key in live: a.set(key, live[key]); b.set(key, live[key])
				if kind == 0x2010 and tick % 2 == 0:
					a.wp = Vector3(float(tick % 10)*0.4, 1.5, 0.0); b.wp = a.wp
				for emitter in [a, b]:
					emitter.dl = Vector3(0.03, 0.04, -0.01) * (tick % 4)
					emitter.sd = Vector3(0.8, -0.6, 0.0)
					emitter.upv = emitter.dl.cross(emitter.sd).normalized()
				check(a.update_sim() == b.update_sim_script(), "emitter lifetime")
				compare(a, b, "%s/%s/%s" % [kind, trial, tick])
				check(a.cp == b.cp and a.d0 == b.d0, "control state")
	# Custom callbacks keep the script path even after factory preparation.
	var custom := FxTypes.create(fa, 0x2001)
	custom.cc = 100; custom.d0 = 1
	custom.spawn_fn = func(_e: FxEmitter, particle: Array, _index: int) -> bool:
		particle[3] = 123.0
		return true
	custom.update_sim()
	check(custom.parts.size() == 1 and custom.parts[0][3] == 123.0, "custom callback fallback")
	# Independent emitters share the worker pool, never particle arrays or RNG.
	var jobs: Array = []
	for i in 32:
		var a := FxTypes.create(fa, [0x2000, 0x2001, 0x2003, 0x2004, 0x2010][i % 5])
		var b := FxTypes.create(fb, a.type)
		b.rng.seed = a.rng.seed
		a.wp = Vector3(i * 4, i * -3, 7); b.wp = a.wp
		a.ground_src = SampleGround.new(); b.ground_src = a.ground_src
		jobs.append([a, b])
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		for tick in 40:
			jobs[i][0].update_sim()
			jobs[i][1].update_sim_script()
	, jobs.size(), 4)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for pair in jobs: compare(pair[0], pair[1], "parallel emitter")
	var wall := FxTypes.create(fa, 0x2010)
	wall.ctl_fn = func(e: FxEmitter, _c: Array) -> void: e.d0 = 0; e.cc = 0
	wall.update_sim()
	check(wall.parts.is_empty(), "custom fire control fallback")
	# Diagnostic throughput; equality above is the acceptance gate.
	var a := FxTypes.create(fa, 0x2001)
	var b := FxTypes.create(fb, 0x2001)
	b.rng.seed = a.rng.seed
	a.d0 = 160; b.d0 = 160; a.d8 = 4096; b.d8 = 4096
	var start := Time.get_ticks_usec()
	for tick in 60: a.update_sim()
	var native_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for tick in 60: b.update_sim_script()
	var script_us := Time.get_ticks_usec() - start
	compare(a, b, "throughput fixture")
	print("FIRE_PARTICLES checks=", checks, " failures=", failures, " native_us=", native_us, " script_us=", script_us)
	fa.free(); fb.free()
	get_tree().quit(1 if failures else 0)
