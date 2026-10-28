extends Node
## Native Windows D3D12 regression: the first main menu after a temporal mode
## (DLSS, TAA or FSR 2) is selected while its motion-vector shaders are not yet
## cached. Enabling motion vectors starts the advanced scene-shader group for
## every loaded material. 1.34.0 joined that compilation on the first menu
## frame while holding a shader version's lock (a 37 s frame on an RTX 4090
## laptop); when pipeline jobs waiting for the same lock filled the four-thread
## worker pool, the menu never appeared. Run by
## tools/run_native_d3d12_cold_start.ps1: the previous release seeds the
## profile with the same settings (`seed`), then the measured pass must present
## the menu, keep drawing while the motion-vector shaders compile in the
## background and finally use the mode. A process that never reports is killed
## by the runner.
const BUDGET_MS := 60000      # process start to presented main menu
const SETTLE_FRAMES := 30     # presented frames required after the menu
const SETTLE_MS := 90000      # background motion-vector compilation, then the mode starts
## Longest single frame allowed while the menu opens. The ordinary shaders of
## materials whose generated code changed still compile when first drawn
## (7-8 s for the 1.34.0 terrain, with or without a temporal mode); joining the
## motion-vector group as well took several times longer.
const STALL_MS := 20000
var checks := 0
var failures: Array[String] = []
var result := {}
var _last_frame_us := 0
var _longest: Array = []   # three longest frame intervals, longest first

func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_frame_us) / 1000.0
	_last_frame_us = now
	_longest.append({"ms": snappedf(ms, 0.1), "at_ms": Time.get_ticks_msec()})
	_longest.sort_custom(func(a, b): return a.ms > b.ms)
	if _longest.size() > 3: _longest.resize(3)

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}

func _scene_shader_entries() -> int:
	var count := 0
	var root := DirAccess.open("user://shader_cache/SceneForwardClusteredShaderRD")
	if root == null: return 0
	for group in root.get_directories():
		for file in DirAccess.get_files_at("user://shader_cache/SceneForwardClusteredShaderRD/" + group):
			if file.ends_with(".d3d12.cache"): count += 1
	return count

func finish(code: int, blocked := false) -> void:
	result.merge({"checks": checks, "failures": failures, "blocked": blocked,
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name()}, true)
	var file := FileAccess.open("user://d3d12-cold-menu-%s.json" % result.mode, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("D3D12_COLD_MENU ", JSON.stringify(result))
	get_tree().quit(code)

func _run() -> void:
	var mode := "dlss"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cold-menu-mode="): mode = a.trim_prefix("--cold-menu-mode=")
	result.mode = mode
	check(RenderingServer.get_current_rendering_driver_name() == "d3d12", "runs on Direct3D 12")
	if mode == "dlss" and not RtxGraphics.facts().sr:
		finish(2, true)   # no DLSS runtime: not a pass
		return
	var cached_before := _scene_shader_entries()
	result.scene_shader_entries_before = cached_before
	var vp := get_viewport()
	var main := get_parent()
	# Every presented frame from the loading screen on: the unfixed renderer
	# joined the motion-vector compilation inside one frame (tens of seconds).
	_last_frame_us = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.connect(_on_frame)
	var started := Time.get_ticks_msec()
	await main.open_menu()
	var menu_ms := Time.get_ticks_msec()
	result.process_to_menu_ms = menu_ms
	result.open_menu_ms = menu_ms - started
	check(menu_ms <= BUDGET_MS, "main menu presented within %d ms of process start (%d ms)" % [BUDGET_MS, menu_ms])
	# The menu must stay live while the motion-vector shaders finish.
	var before := status()
	var gap := 0.0
	var frames := 0
	var last := Time.get_ticks_usec()
	var evaluated := 0
	while true:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		gap = maxf(gap, (now - last) / 1000.0)
		last = now
		frames += 1
		evaluated = int(status().get("dlss_evaluations", 0)) - int(before.get("dlss_evaluations", 0))
		if frames >= SETTLE_FRAMES and (mode != "dlss" or evaluated >= SETTLE_FRAMES): break
		if Time.get_ticks_msec() - menu_ms > SETTLE_MS: break
	result.frames_after_menu = frames
	result.max_frame_gap_ms = gap
	result.dlss_evaluations = evaluated
	result.settled_ms = Time.get_ticks_msec() - menu_ms
	check(frames >= SETTLE_FRAMES, "menu keeps presenting frames (%d)" % frames)
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	result.longest_frames_ms = _longest
	var stall: float = _longest[0].ms if not _longest.is_empty() else 0.0
	if mode != "seed":
		check(stall <= STALL_MS, "no frame stalls longer than %d ms while the menu opens (%d ms at %d ms)" % [STALL_MS, stall, _longest[0].at_ms if not _longest.is_empty() else 0])
	var cached_after := _scene_shader_entries()
	result.scene_shader_entries_after = cached_after
	if mode == "seed":
		check(cached_after > 0, "ordinary scene shaders cached (%d)" % cached_after)
		finish(1 if not failures.is_empty() else 0)
		return
	# The seed pass cached the ordinary group; this mode adds motion vectors.
	check(cached_after > cached_before, "motion-vector shaders compiled in this run (%d -> %d)" % [cached_before, cached_after])
	if mode == "dlss":
		check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_DLSS, "DLSS selected on the main view")
		check(evaluated >= SETTLE_FRAMES, "DLSS evaluates once its shaders are ready (%d)" % evaluated)
		var after := status()
		check(int(after.get("last_error", -1)) == 0, "DLSS reports no SDK error")
		if GameData.option("rtx_frame_generation") > 0 and RtxGraphics.facts().fg:
			var start_presents := int(after.get("presented_frames", 0))
			for i in 90: await RenderingServer.frame_post_draw
			result.fg_presented_in_90 = int(status().get("presented_frames", 0)) - start_presents
			result.fg_active = bool(status().get("frame_generation_active", false))
			result.window_focused = get_window().has_focus()
	elif mode == "taa":
		check(vp.use_taa, "TAA selected on the main view")
	elif mode == "fsr2":
		check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2, "FSR 2 selected on the main view")
	finish(1 if not failures.is_empty() else 0)
