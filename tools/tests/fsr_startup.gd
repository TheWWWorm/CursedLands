extends Node
## Real SDK activation latency and frame continuity. Run with isolated shader
## caches for first-use measurements; never clear the player's shader cache.

var rows: Array[Dictionary] = []
var failures: Array[String] = []
var scene: MenuScene
var native_only := false
var require_responsive := false
var cancellation: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func status() -> Dictionary:
	return FsrGraphics.bridge().call("get_status")

func settle(frames: int) -> void:
	for i in frames: await RenderingServer.frame_post_draw

func save_result() -> void:
	var result := {"cancellation": cancellation, "rows": rows, "failures": failures, "status": status(),
		"gpu": RenderingServer.get_video_adapter_name(), "native_windows_qualified": false}
	FileAccess.open("user://fsr-startup.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("FSR_STARTUP ", JSON.stringify(result))

func activate(label: String, fg: bool) -> void:
	var before := status()
	var start := Time.get_ticks_usec()
	var last := start
	var longest := 0
	var frames := 0
	var pending_frames := 0
	var ready_usec := 0
	var preparing_shown := false
	var preparing_captured := false
	GameData.options.fsr_upscaling = 0 if native_only else 1
	GameData.options.fsr_frame_generation = 1 if fg else 0
	GameData._apply_window()
	FsrGraphics.bridge().call("set_frame_generation_version", 3 if fg else 0)
	get_tree().root.set("frame_generation", fg)
	var apply_ms := (Time.get_ticks_usec() - start) / 1000.0
	while Time.get_ticks_usec() - start < 60_000_000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		longest = maxi(longest, now - last)
		last = now
		frames += 1
		var current := status()
		var ready := int(current.get("generated_frames", 0)) > int(before.get("generated_frames", 0)) if fg else int(current.get("upscale_evaluations", 0)) > int(before.get("upscale_evaluations", 0))
		if not ready: pending_frames += 1
		if preparing_shown and not preparing_captured:
			get_window().get_texture().get_image().save_png("user://fsr-preparing.png")
			preparing_captured = true
		if not fg and not preparing_shown and current.get("temporal_shaders_initializing", false):
			var controller := get_tree().root.get_node("FsrExperiment")
			controller._process(0)
			preparing_shown = controller._preparing_label.visible
		if ready and ready_usec == 0: ready_usec = now
		if ready_usec > 0 and now - ready_usec >= 1_000_000:
			var measured: Variant = GameData._fps_layer.get_child(0).get("rates")
			if not fg or (measured is Dictionary and measured.get("presented_fps", -1) > 0) or now - ready_usec >= 3_000_000: break
	get_tree().root.get_node("FsrExperiment")._preparing_label.hide()
	if ready_usec == 0: failures.append(label + ": SDK activation timed out")
	if require_responsive and longest > 1_000_000: failures.append(label + ": frame gap exceeds one second")
	if native_only and int(status().upscale_evaluations) != 0: failures.append(label + ": standalone FG unexpectedly ran the upscaler")
	var fps_label := GameData._fps_layer.get_child(0) as Label
	var rates: Dictionary = fps_label.get("rates") if fps_label.get("rates") is Dictionary else {}
	if require_responsive and fg and (rates.get("presented_fps", -1) <= 0 or rates.get("rendered_fps", 0) <= 0): failures.append(label + ": live FPS overlay did not measure presentation")
	rows.append({"label": label, "apply_ms": apply_ms, "longest_frame_ms": longest / 1000.0,
		"activation_ms": (ready_usec - start) / 1000.0 if ready_usec else -1,
		"preparing_message_visible": preparing_shown, "frames": frames, "frames_while_initializing": pending_frames, "status": status(), "fps_overlay": rates})
	save_result()

func _run() -> void:
	native_only = OS.get_cmdline_user_args().has("--fsr-native-startup")
	require_responsive = OS.get_cmdline_user_args().has("--require-responsive")
	await settle(5)
	if not FsrGraphics.facts().sr3 or not FsrGraphics.facts().fg3:
		failures.append("FSR 3.1 hardware and runtime required")
		save_result()
		get_tree().quit(2)
		return
	get_tree().root.get_node("FsrExperiment").set_process(false)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"q_aa":0,"render_scale":4,"vsync":0,"display_mode":0,"fsr_upscaling":0,
		"fsr_quality":1,"fsr_frame_generation":0}, true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 720)
	Engine.max_fps = 120
	Gfx.ensure_globals()
	Gfx.apply_surface_options()
	scene = MenuScene.create()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(scene)
	scene.camera.current = true
	scene.set_hour(12)
	await settle(120)
	if OS.get_cmdline_user_args().has("--cancel-prepare") or OS.get_cmdline_user_args().has("--shutdown-during-prepare") or OS.get_cmdline_user_args().has("--cancel-shaders"):
		GameData.options.fsr_upscaling = 1
		GameData._apply_window()
		await settle(3)
		if not OS.get_cmdline_user_args().has("--cancel-shaders"):
			var deadline := Time.get_ticks_msec() + 60000
			while not status().upscaler_initializing and Time.get_ticks_msec() < deadline:
				await settle(1)
			if not status().upscaler_initializing: failures.append("cold cancellation fixture did not encounter context preparation")
		else:
			if not status().get("temporal_shaders_initializing", false): failures.append("cold cancellation fixture did not encounter shader preparation")
		if OS.get_cmdline_user_args().has("--shutdown-during-prepare"):
			save_result()
			get_tree().quit(0 if failures.is_empty() else 1)
			return
		var before := Time.get_ticks_usec()
		GameData.options.fsr_upscaling = 0
		GameData._apply_window()
		cancellation.apply_ms = (Time.get_ticks_usec() - before) / 1000.0
		await settle(3)
		cancellation.total_ms = (Time.get_ticks_usec() - before) / 1000.0
		if Time.get_ticks_usec() - before > 1_000_000: failures.append("disabling during preparation blocked rendering")
		if int(status().upscale_evaluations) != 0: failures.append("cancelled preparation dispatched upscaling")
		get_tree().root.size = Vector2i(960, 540)
		await activate("resized-during-preparation", false)
		var expected_creations := 1 if OS.get_cmdline_user_args().has("--cancel-shaders") else 2
		if int(status().upscaler_context_creations) != expected_creations: failures.append("stale size was not discarded before activating new size")
	elif not native_only and not OS.get_cmdline_user_args().has("--fsr-combined-startup"):
		await activate("first-upscaling", false)
	await activate("first-frame-generation", true)
	GameData.options.fsr_frame_generation = 0
	FsrGraphics.bridge().call("set_frame_generation_version", 0)
	get_tree().root.set("frame_generation", false)
	await settle(30)
	await activate("repeat-frame-generation", true)
	scene.free()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	await settle(4)
	save_result()
	get_tree().quit(0 if failures.is_empty() else 1)
