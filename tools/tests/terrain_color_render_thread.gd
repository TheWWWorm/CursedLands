extends Node
## Force the renderer's cooperative wait to encounter queued background work.
## A terrain bake must never execute on that latency-sensitive render worker.
class PoolGate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	func hold() -> void:
		entered.post(); release.wait()

class RenderProbe extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var done := Semaphore.new()
	var thread_id := -1
	func urgent() -> void: pass
	func run() -> void:
		thread_id = OS.get_thread_caller_id(); entered.post(); release.wait()
		var task := WorkerThreadPool.add_task(urgent,true,"Render continuation regression")
		WorkerThreadPool.wait_for_task_completion(task)
		done.post()

class BakeField extends RefCounted:
	var mutex := Mutex.new()
	var threads: Array[int] = []
	var pixels := Image.create(16,16,false,Image.FORMAT_RGBA8)
	func _init() -> void: pixels.fill(Color(0.2,0.4,0.6))
	func bake(_sector: Vector2i,_density: int) -> Image:
		mutex.lock(); threads.append(OS.get_thread_caller_id()); mutex.unlock()
		# Stand in for the measured 250–280 ms native bake, without requiring
		# a large map or a timing threshold for the correctness assertion.
		OS.delay_msec(60)
		return pixels

var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func wait_signal(signal_gate: Semaphore,timeout_ms := 3000) -> bool:
	var until := Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<until:
		if signal_gate.try_wait(): return true
		OS.delay_msec(1)
	return false
func _ready() -> void: run.call_deferred()
func run() -> void:
	var terrain := EITerrain.new(); terrain.texture_size=16; terrain.tile_size=32; terrain._atlas_source_size=16
	var node := MeshInstance3D.new()
	var field := BakeField.new()
	var cache := TerrainColorCache.new(); cache.terrain=terrain; cache._field=field; cache._enabled=true
	TerrainColorCache.clear_shared()
	for i in 2:
		var key := Vector2i(i,0)
		cache._wanted.append({"key":key,"node":node}); cache._wanted_keys[key]=true
	var probe := RenderProbe.new()
	RenderingServer.call_on_render_thread(probe.run)
	var render_entered := wait_signal(probe.entered)
	check(render_entered and probe.thread_id!=OS.get_main_thread_id(),"fixture owns the separate render worker")
	var gate := PoolGate.new(); var tasks := []
	for i in 3: tasks.append(WorkerThreadPool.add_task(gate.hold,true,"Occupied worker regression"))
	var occupied := 0
	for i in 3:
		if wait_signal(gate.entered): occupied += 1
	check(occupied==3,"other three pool workers are occupied before terrain admission")
	cache._start_jobs()
	var jobs := cache._jobs.map(func(row): return row.job)
	check(jobs.size()==2,"runtime terrain retains its bounded two-job queue")
	probe.release.post()
	var render_done := wait_signal(probe.done)
	check(render_done,"render continuation completes with other pool workers occupied")
	for i in 3: gate.release.post()
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	RenderingServer.force_sync()
	cache.clear()
	check(not field.threads.has(probe.thread_id),"background terrain never runs on the render worker; render=%d bakes=%s" % [probe.thread_id,field.threads])
	var exact := jobs.size()==2
	for job in jobs: exact=exact and job.pixels!=null and job.pixels.get_data()==field.pixels.get_data()
	check(exact,"both background results finish with unchanged pixels")
	check(cache._jobs.is_empty(),"teardown joins every background job")
	cache.free(); node.free(); terrain.free()
	print("TERRAIN_COLOR_RENDER_THREAD ",checks," checks ",failures," failures")
	get_tree().quit(int(failures>0))
