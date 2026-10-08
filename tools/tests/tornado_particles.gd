extends "fire_particles.gd"
## Compare complete ticks, including controls, RNG, delayed removal and every
## interpolation field. The retained callbacks are the independent reference.

class Ground extends FxGround:
	func at(x: float, y: float) -> float:
		return 2.0 + x * 0.15 - y * 0.03

var _reported := false

func exact(a: FxEmitter, b: FxEmitter, label: String) -> void:
	if not _reported and a.parts != b.parts:
		_reported = true
		for i in mini(a.parts.size(), b.parts.size()):
			if a.parts[i] == b.parts[i]: continue
			for j in a.parts[i].size():
				var x: Variant = a.parts[i][j]
				var y: Variant = b.parts[i][j]
				if var_to_bytes(x) != var_to_bytes(y):
					print("TORNADO_FIELD ", label, " particle=", i, " field=", j, " native=", var_to_bytes(x).hex_encode(), " script=", var_to_bytes(y).hex_encode())
			break
	compare(a, b, label)
	check(var_to_bytes(a.parts) == var_to_bytes(b.parts), label + " exact serialized particle fields")
	check(var_to_bytes(a.cp) == var_to_bytes(b.cp), label + " exact control fields")
	check(a.flags == b.flags, label + " emission flags")

func _ready() -> void:
	var expect_native := not OS.get_cmdline_user_args().has("--expect-script")
	var fa := ParticleFx.new()
	var fb := ParticleFx.new()
	var ground := Ground.new()
	var random := RandomNumberGenerator.new()
	random.seed = 524900
	var native_us := 0
	var script_us := 0
	for trial in 24:
		var a := FxTypes.create(fa, 0x200a)
		var b := FxTypes.create(fb, 0x200a)
		b.rng.seed = a.rng.seed
		check((a._spell_kernel != null) == expect_native, "factory selects supported tornado batch or fallback")
		var values := {"d0": [1,4,16,51][trial % 4], "d8": [8,50,400,800][trial % 4],
			"cc": [0,40,51,88,100,100][trial % 6], "d4": [0.0,0.01,1000.0][trial % 3],
			"s": [0.15,1.0,3.0][trial % 3], "ground_src": ground,
			"e4": [0x19000000,0x19498c00,0x19ffffff][trial % 3]}
		for key in values: a.set(key, values[key]); b.set(key, values[key])
		for e in [a,b]:
			e.cp[0][9] = [0.5,12.0,50.0][trial % 3]
			e.cp[0][10] = [0.0,0.5,1.5][trial % 3]
			e.cp[0][11] = [0.97,0.99,1.01][trial % 3]
		for tick in 180:
			var live := {"wp": Vector3(random.randf_range(-400,400),random.randf_range(-400,400),random.randf_range(-20,90)),
				"dl": Vector3(random.randf_range(-1,1),random.randf_range(-1,1),random.randf_range(-0.3,0.3)),
				"moved": float(tick % 4) * 0.03, "has_carrier": tick % 7 != 0,
				"flags": (1 | (2 if trial % 2 else 0) | (4 if trial % 3 else 0)) if tick < 110 else (4 if trial % 3 else 0)}
			for key in live: a.set(key, live[key]); b.set(key, live[key])
			var start := Time.get_ticks_usec()
			var alive_a := a.update_sim()
			native_us += Time.get_ticks_usec() - start
			start = Time.get_ticks_usec()
			var alive_b := b.update_sim_script()
			script_us += Time.get_ticks_usec() - start
			var label := "%d/%d" % [trial,tick]
			check(alive_a == alive_b, label + " lifetime")
			exact(a,b,label)
	# A modified callback must retain the general script implementation.
	for field in ["spawn_fn","upd_fn","ctl_fn"]:
		var a := FxTypes.create(fa, 0x200a)
		var b := FxTypes.create(fb, 0x200a)
		b.rng.seed = a.rng.seed
		a.ground_src = ground; b.ground_src = ground
		a.update_sim(); b.update_sim_script()
		var callback: Callable
		match field:
			"spawn_fn": callback = func(_e: FxEmitter, p: Array, _i: int) -> bool: p[3] = 123.0; return true
			"upd_fn": callback = func(_e: FxEmitter, p: Array) -> bool: p[3] = 321.0; return true
			_: callback = func(_e: FxEmitter, point: Array) -> void: point[0] = 33.0
		a.set(field, callback); b.set(field, callback)
		for tick in 10:
			check(a.update_sim() == b.update_sim_script(), "custom lifetime " + field)
			exact(a,b,"custom " + field)
	# Concurrent emitters own their particle arrays, controls and random streams.
	var jobs := []
	for i in 24:
		var a := FxTypes.create(fa, 0x200a)
		var b := FxTypes.create(fb, 0x200a)
		b.rng.seed = a.rng.seed
		a.wp = Vector3(i*4,i*-3,7); b.wp = a.wp
		a.ground_src = ground; b.ground_src = ground
		a.has_carrier = true; b.has_carrier = true
		jobs.append([a,b])
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		for tick in 180:
			jobs[i][0].update_sim()
			jobs[i][1].update_sim_script()
	, jobs.size(), 4)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for pair in jobs: exact(pair[0],pair[1],"parallel emitter")
	fa.free(); fb.free()
	print("TORNADO_PARTICLES checks=", checks, " failures=", failures, " native_us=", native_us, " script_us=", script_us,
		" native_expected=", expect_native)
	get_tree().quit(1 if failures else 0)
