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


func pacing_checks() -> void:
	var window := PerformanceLog.FrameWindow.new()
	check(window.summary() == {"frames":0}, "empty pacing is unavailable rather than invented zero milliseconds")
	window.record(0,0);window.record(-10,1)
	check(window.summary() == {"frames":0}, "nonpositive clock intervals are ignored")
	for i in 95: window.record(10000,10000*(i+1))
	for i in 4: window.record(60000,950000+60000*(i+1))
	window.record(180000,1370000)
	var stats := window.summary()
	check(stats.frames == 100 and is_equal_approx(stats.mean_ms,13.7), "pacing keeps the actual arithmetic frame-time mean")
	check(stats.max_ms == 180 and stats.max_at_uptime_s == 1.37, "worst hitch keeps its duration and clock position")
	check(stats.over_25ms == 5 and stats.over_50ms == 5 and stats.over_100ms == 1,
		"brief stalls survive a healthy interval FPS average")
	check(stats.p95_upper_ms == 11.112, "percentile reports an explicitly labelled histogram upper bound")
	window.record(2000000,3370000)
	check(window.summary().max_ms == 2000 and window.buckets.size() == PerformanceLog.FRAME_BUCKET_US.size()+1,
		"arbitrarily long frames do not grow histogram storage")
	var all_slow := PerformanceLog.FrameWindow.new()
	all_slow.record(2000000,2000000)
	check(all_slow.summary().p95_upper_ms == 2000, "overflow percentile remains a finite upper bound")
	var boundary := PerformanceLog.FrameWindow.new()
	for t in [25000,50000,100000]: boundary.record(t,t)
	check(boundary.summary().over_25ms == 2 and boundary.summary().over_50ms == 1
		and boundary.summary().over_100ms == 0, "hitch thresholds are strictly greater than their labelled duration")
	var sampler := PerformanceLog.new()
	sampler._reset_pacing()
	sampler._observe_frame(100000,"foreground")
	sampler._observe_frame(116000,"foreground")
	sampler._observe_frame(1116000,"background")
	sampler._observe_frame(1216000,"background")
	sampler._observe_frame(2216000,"foreground")
	sampler._observe_frame(2232000,"foreground")
	var observed := sampler._pacing_snapshot()
	check(observed.foreground.frames == 2 and observed.foreground.max_ms == 16
		and observed.background.frames == 1 and observed.background.max_ms == 100,
		"focus changes cannot turn a background pause into a foreground hitch")
	sampler._observe_frame(3232000,"loading")
	sampler._observe_frame(4232000,"loading")
	check(sampler._pacing_snapshot().loading.frames == 1
		and sampler._pacing_snapshot().foreground.frames == 2, "loading intervals have their own bounded window")
	sampler._reset_pacing()
	check(sampler._pacing_snapshot().foreground.frames == 0 and observed.foreground.frames == 2,
		"sampling resets counters without modifying previously exported values")
	sampler._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(sampler._last_frame_usec == 0, "focus notification discards a gap even if focus toggles twice between frames")
	sampler.free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	pacing_checks()
	await frames(8)
	var cr := CrashReport.instance
	var sampler := cr._performance
	check(sampler != null and sampler.is_inside_tree(), "ordinary diagnostic export owns the sampler")
	if sampler == null: get_tree().quit(1); return
	check(sampler._timer.wait_time == 30.0 and sampler._timer.ignore_time_scale,
		"normal cadence is thirty wall-clock seconds")
	var baseline := sampler.snapshot("before")
	check(baseline.frame_pacing.foreground.frames > 0, "live callbacks contribute unscaled wall-clock intervals")
	check(baseline.has("driver") and baseline.render_options.has("pt_mode")
		and baseline.render_options.has("rtx_frame_generation") and baseline.render_options.has("fsr_upscaling"),
		"logs preserve driver and requested upscaling/frame-generation context")
	sampler.sample("before injected hitch")
	await frames(2)
	OS.delay_msec(120)
	await frames(3)
	check(sampler.snapshot("after injected hitch").frame_pacing.foreground.over_100ms >= 1,
		"an actual main-thread stall survives into the next diagnostic snapshot")
	var camera := Camera3D.new()
	add_child(camera);camera.make_current();camera.position=Vector3(3,4,5);camera.fov=61
	var camera_sample: Dictionary = sampler.snapshot("camera").camera
	check(camera_sample.position == [3.0,4.0,5.0] and camera_sample.fov == 61,
		"camera metadata identifies the observed view without rendering or readback")
	camera.free()
	check(not sampler.snapshot("camera removed").has("camera"), "camera sampling retains no camera reference")
	# A synchronous scene transition can begin and end within one callback.
	var saved_info := cr.info.duplicate(true)
	GameData.trace("zone load performance-test (from host)")
	check(sampler._last_frame_usec == 0, "real zone-load trace resets a frame boundary")
	GameData.trace("zone ready performance-test (from host)")
	check(sampler._last_frame_usec == 0, "real zone-ready trace excludes the blocking load gap")
	cr.info = saved_info
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
	check(not probe.is_processing(), "stopping diagnostics also stops frame observation")
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
	check(report.contains('"frame_pacing"') and report.contains('"over_50ms"')
		and report.contains('"p95_upper_ms"'), "ordinary exported report includes bounded hitch statistics")
	var result := {"checks":checks,"failures":failures,"export":path}
	FileAccess.open("user://performance-log-tests.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PERFORMANCE_LOG_TESTS ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
