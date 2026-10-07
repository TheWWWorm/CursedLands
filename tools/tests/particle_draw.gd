extends Node

var checks := 0
var failures := 0

class PackJob extends RefCounted:
	var effect: ParticleFx.Effect
	var eye := Vector3(8.5, -11.2, 3.25)
	var forward := Vector3(.5, .25, -.75)
	func run() -> void:
		for tick in 40:
			ParticleFx._fill_calc(effect, true, eye, forward, tick)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func make_effect() -> ParticleFx.Effect:
	var effect := ParticleFx.Effect.new()
	effect.e = FxEmitter.new()
	return effect

func particles(rng: RandomNumberGenerator, count: int) -> Array:
	var result := []
	for i in count:
		var p := []
		p.resize(24)
		p.fill(0)
		for k in 8:
			p[k] = rng.randf_range(-90, 90)
		p[18] = rng.randi_range(-32, 32)
		p[22] = int(rng.randi()) - 2147483648
		p[23] = int(rng.randi())
		result.append(p)
	return result

func same(a: ParticleFx.Effect, b: ParticleFx.Effect, label: String) -> void:
	check(a.buf.to_byte_array() == b.buf.to_byte_array(), label + " all instance bytes")
	check(a.cap == b.cap and a.pre_k == b.pre_k and a.pre == b.pre, label + " capacity/count/tick")
	check(a.pre_aabb == b.pre_aabb, label + " exact bounds")
	check(a.pre_reach == b.pre_reach, label + " exact reach")

func _ready() -> void:
	check(ClassDB.class_exists("ParticleDrawBuffer"), "native writer registered")
	if failures:
		get_tree().quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 245897
	var a := make_effect()
	var b := make_effect()
	var mm: MultiMesh
	if DisplayServer.get_name() != "headless":
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = QuadMesh.new()
	var cases := [0, 1, 2, 17, 64, 65, 4, 0, 131, 10, 400, 201]
	for tick in 240:
		var count: int = cases[tick % cases.size()] if tick < 24 else rng.randi_range(0, 300)
		a.e.parts = particles(rng, count)
		# Projection ties must retain the original index as their tie breaker.
		if tick % 7 == 0:
			for p: Array in a.e.parts:
				p[0] = 1.0; p[1] = 2.0; p[2] = 3.0
		a.e.add = tick % 2
		a.e.d8 = [-5, 0, 12, 64, 500][tick % 5]
		a.e.wp = Vector3(rng.randf_range(-200, 200), rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		b.e = a.e
		var old_a := a.buf
		var snapshot := old_a.duplicate()
		var old_bytes := snapshot.to_byte_array()
		var submitted_bytes := PackedByteArray()
		if mm:
			mm.instance_count = a.cap
			mm.buffer = a.buf
			# Compatibility stores colors at its own precision on upload.
			submitted_bytes = mm.buffer.to_byte_array()
		var eye := Vector3(rng.randf_range(-100, 100), rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		var fwd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var before := a.e.parts.duplicate(true)
		ParticleFx._fill_calc(a, tick % 3 != 0, eye, fwd, tick)
		ParticleFx._fill_calc_script(b, tick % 3 != 0, eye, fwd, tick)
		same(a, b, "case " + str(tick))
		check(old_a.to_byte_array() == old_bytes, "native returned buffer remains immutable")
		check(snapshot.to_byte_array() == old_bytes, "copied snapshot remains immutable")
		if mm:
			check(mm.buffer.to_byte_array() == submitted_bytes, "submitted MultiMesh remains immutable until apply")
		check(before == a.e.parts, "simulation records remain unchanged")
	# Empty draws keep the last valid culling bounds, or repair invalid bounds.
	a.e.parts.clear()
	a.pre_aabb = AABB(Vector3(INF, 0, 0), Vector3.ONE)
	b.pre_aabb = a.pre_aabb
	ParticleFx._fill_calc(a, true, Vector3.ZERO, Vector3.FORWARD, 241)
	ParticleFx._fill_calc_script(b, true, Vector3.ZERO, Vector3.FORWARD, 241)
	same(a, b, "empty invalid previous box")
	var writer: RefCounted = ClassDB.instantiate("ParticleDrawBuffer")
	check(writer.pack([[1, 2]], false, Vector3.ZERO, Vector3.ZERO, 64, Vector3.ZERO, AABB(), -1.0).is_empty(), "short custom record falls back")
	var invalid := particles(rng, 2)
	invalid[0][0] = NAN
	check(writer.pack(invalid, true, Vector3.ZERO, Vector3.ONE, 64, Vector3.ZERO, AABB(), -1.0).is_empty(), "nonfinite sort falls back")
	# Each worker owns its emitter and buffer; compare every completed result.
	var tasks := []
	var jobs: Array[PackJob] = []
	for i in 8:
		var job := PackJob.new()
		job.effect = make_effect()
		job.effect.e.parts = particles(rng, 200 + i * 13)
		jobs.append(job)
		tasks.append(WorkerThreadPool.add_task(job.run))
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	for job in jobs:
		var scalar := make_effect()
		scalar.e = job.effect.e
		ParticleFx._fill_calc_script(scalar, true, job.eye, job.forward, 39)
		same(job.effect, scalar, "independent worker")
	# Timings are an inner-loop diagnostic, not a whole-game performance result.
	a = make_effect(); b = make_effect()
	a.e.parts = particles(rng, 1000); b.e = a.e
	var start := Time.get_ticks_usec()
	for tick in 50:
		ParticleFx._fill_calc(a, true, Vector3.ZERO, Vector3.FORWARD, tick)
	var native_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for tick in 50:
		ParticleFx._fill_calc_script(b, true, Vector3.ZERO, Vector3.FORWARD, tick)
	var script_us := Time.get_ticks_usec() - start
	same(a, b, "benchmark result")
	print("PARTICLE_DRAW checks=", checks, " failures=", failures, " native_us=", native_us, " script_us=", script_us)
	get_tree().quit(1 if failures else 0)
