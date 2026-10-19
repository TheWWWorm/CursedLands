extends Node
## Local diagnostics must observe worlds without creating or retaining them.
var checks := 0
var failures := []

class RecordingSampler extends PerformanceLog:
	var calls := 0
	func sample(_reason: String) -> void:
		calls += 1


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(n := 3) -> void:
	for i in n: await get_tree().process_frame


func wall(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	await frames(8)
	var cr := CrashReport.instance
	var sampler := cr._performance
	check(sampler != null and sampler.is_inside_tree(), "ordinary diagnostic export owns the sampler")
	if sampler == null: get_tree().quit(1); return
	check(sampler._timer.wait_time == 30.0 and sampler._timer.ignore_time_scale,
		"normal cadence is thirty wall-clock seconds")
	var baseline := sampler.snapshot("before")
	var w := GameWorld.new()
	w.authority = true
	w.presentation = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	var before_children := w.get_child_count()
	var wr: WeakRef = weakref(w)
	var row := sampler.snapshot("empty authority")
	check(row.world_count == baseline.world_count + 1, "world enters diagnostic registry")
	check(w.get_child_count() == before_children and w.get_node_or_null("ParticleFx") == null,
		"sampling never creates authority-side effects")
	check(row.worlds[-1].units == 0 and not row.worlds[-1].presentation and row.worlds[-1].authority,
		"world metadata identifies an empty authority")
	remove_child(w)
	check(sampler.snapshot("detached").world_count == baseline.world_count, "detached world leaves registry")
	add_child(w)
	check(sampler.snapshot("returned").world_count == baseline.world_count + 1, "reentered world rejoins registry")
	var fx := ParticleFx.of(w)
	fx._later(3600.0, func(): pass)
	var u := GameUnit.new()
	u.world = w
	w.add_child(u)
	w.set_unit(7, u)
	fx.magic_fx({"uid":7, "code":"weak", "secs":3600.0, "replay":true})
	var options := GameData.options.duplicate(true)
	var recorded := sampler.snapshot("effects")
	check(recorded.worlds[-1].units == 1 and recorded.worlds[-1].effects.delayed == 2
		and recorded.worlds[-1].effects.magic_endings == 1, "effect snapshot reflects pending endings")
	check(GameData.options == options and w.time == 0.0 and fx._delayed.size() == 2,
		"sampling changes neither quality nor simulation/effect state")
	check(recorded.has("video_allocated_bytes") and recorded.has("texture_bytes")
		and recorded.has("cache_entries") and recorded.has("frame_limit"), "report distinguishes allocation, caches and frame cap")
	check(PerformanceLog._available(0.0) == null and PerformanceLog._available(-1.0) == null
		and PerformanceLog._available(123.0) == 123.0, "unavailable counters are not presented as zero allocation")
	w.free()
	await frames()
	check(wr.get_ref() == null and sampler.snapshot("freed").world_count == baseline.world_count,
		"saved diagnostic values cannot retain a world")
	check(recorded.worlds[-1].units == 1, "earlier samples remain plain immutable observations after teardown")
	# Bound record size even when diagnosing an abnormal number of worlds.
	var worlds: Array[GameWorld] = []
	for i in PerformanceLog.MAX_WORLDS + 2:
		var world := GameWorld.new()
		world.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(world)
		worlds.append(world)
	row = sampler.snapshot("many worlds")
	check(row.world_count == PerformanceLog.MAX_WORLDS + 2 + baseline.world_count
		and row.worlds.size() == PerformanceLog.MAX_WORLDS, "world detail is bounded while total count remains exact")
	for world in worlds: world.free()
	worlds.clear()
	var probe := RecordingSampler.new()
	add_child(probe)
	probe._timer.start(0.16)
	Engine.time_scale = 2.0
	await wall(0.1)
	check(probe.calls == 0, "2x simulation does not double diagnostic cadence")
	await wall(0.1)
	check(probe.calls == 1, "wall-clock deadline records once")
	get_tree().paused = true
	await wall(0.18)
	check(probe.calls == 2, "diagnostics remain available while gameplay is paused")
	probe.stop()
	await wall(0.2)
	check(probe.calls == 2, "stopping diagnostics cancels periodic callbacks")
	get_tree().paused = false
	Engine.time_scale = 1.0
	probe.free()
	# Use the existing report path, with no additional export or network API.
	CrashReport.save_dir_override = "user://performance-reports"
	var path := cr.save_report({})
	check(not path.is_empty(), "existing Export log action saves the diagnostic report")
	var report := FileAccess.get_file_as_string(path)
	check(report.contains("PERFORMANCE ") and report.contains('"reason":"report"')
		and report.contains('"world_count"'), "exported log includes a current performance snapshot")
	var result := {"checks":checks,"failures":failures,"export":path}
	FileAccess.open("user://performance-log-tests.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PERFORMANCE_LOG_TESTS ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
