extends Node
## Compare scheduling only: identical emitter streams and packed draw buffers.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func distribution(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value: int in values: total += value
	return {"mean_us":total/values.size(),"p50_us":values[values.size()/2],"p95_us":values[int(values.size()*.95)],"p99_us":values[int(values.size()*.99)],"max_us":values.back()}

func run_case(count: int, tasks: int) -> Array:
	var fx := ParticleFx.new()
	var job := ParticleFx.SimJob.new()
	job.has_cam = true; job.eye = Vector3(10,3,7); job.fwd = Vector3.FORWARD
	for i in count:
		var effect := ParticleFx.Effect.new()
		effect.e = FxTypes.create(fx, [0x2001,0x2003,0x2004][i%3])
		effect.e.rng.seed = 9173+i
		effect.e.d0 = 12; effect.e.d8 = 200; effect.e.cc = 100
		effect.e.wp = Vector3(i*3,-i*2,1)
		effect.want_fill = true
		job.efs.append(effect)
	var times := []
	for tick in 300:
		job.tick = tick
		var start := Time.get_ticks_usec()
		if tasks == 0:
			for i in count:job.run(i)
		else:
			var group := WorkerThreadPool.add_group_task(job.run,count,tasks,true,"particle scheduling check")
			WorkerThreadPool.wait_for_group_task_completion(group)
		if tick >= 60:times.append(Time.get_ticks_usec()-start)
	var state := []
	var parts := 0
	for effect in job.efs:
		parts += effect.e.parts.size()
		state.append([effect.e.parts.duplicate(true),effect.e.rng.state,effect.buf.to_byte_array(),effect.pre_aabb,effect.pre_reach,effect.ok])
	rows.append({"emitters":count,"tasks":tasks,"particles":parts,"rounds":times.size(),"time":distribution(times)})
	fx.free()
	return state

func _ready() -> void:
	for count in [3,8,32]:
		var reference := run_case(count,0)
		check(run_case(count,-1)==reference,"full-pool output equals serial for "+str(count)+" emitters")
		check(run_case(count,mini(count,ParticleFx.PAR_MAX_TASKS))==reference,"bounded-pool output equals serial for "+str(count)+" emitters")
	FileAccess.open("user://particle-workers.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"processors":OS.get_processor_count(),"rows":rows},"\t"))
	print("PARTICLE_WORKERS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
