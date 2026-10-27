extends Node
## Exercise the configured pool, including reserved capacity for urgent work.
class Probe extends RefCounted:
	var gate := Semaphore.new()
	var mutex := Mutex.new()
	var started := 0
	var live := 0
	var peak := 0
	var urgent := false
	func background() -> void:
		mutex.lock(); started += 1; live += 1; peak = maxi(peak,live); mutex.unlock()
		gate.wait()
		mutex.lock(); live -= 1; mutex.unlock()
	func foreground() -> void:
		mutex.lock(); urgent = true; mutex.unlock()
	func state() -> Array:
		mutex.lock(); var row := [started,live,peak,urgent]; mutex.unlock(); return row

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	check(int(ProjectSettings.get_setting_with_override("threading/worker_pool/max_threads")) == 4, "desktop keeps its four-worker total")
	var probe := Probe.new(); var tasks := []
	for i in 3: tasks.append(WorkerThreadPool.add_task(probe.background,false,"Loading budget regression"))
	var until := Time.get_ticks_msec()+2000
	while int(probe.state()[0]) < 2 and Time.get_ticks_msec() < until: await get_tree().process_frame
	# Hold those jobs so a third cannot silently exceed the intended budget.
	await get_tree().create_timer(0.1).timeout
	check(probe.state().slice(0,3) == [2,2,2], "two independent background jobs run concurrently within the bound")
	var urgent := WorkerThreadPool.add_task(probe.foreground,true,"Urgent work regression")
	until = Time.get_ticks_msec()+2000
	while not bool(probe.state()[3]) and Time.get_ticks_msec() < until: await get_tree().process_frame
	check(bool(probe.state()[3]),"urgent work starts while both background jobs remain held")
	for i in 3: probe.gate.post()
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	WorkerThreadPool.wait_for_task_completion(urgent)
	check(int(probe.state()[0]) == 3 and int(probe.state()[1]) == 0,"all work joins and releases its resources")
	print("LOADING_WORKER_BUDGET ",checks," checks ",failures," failures")
	get_tree().quit(int(failures > 0))
