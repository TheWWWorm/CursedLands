extends Node
## Actual SDK SR and FG check. Requires FSR 3.1 support; no simulated success.
## Uses the real menu scene with controlled camera motion in an isolated profile.
## Screenshots capture rendered frames; generated-frame counts come from SDK dispatches.

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var scene: MenuScene
var fg_tested := false

func _ready() -> void:
	check(not OS.get_cmdline_user_args().has("--experimental-fsr"), "normal executable enables FSR without a special launch flag")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func status() -> Dictionary:
	var native := FsrGraphics.bridge()
	return native.call("get_status") if native else {}

func save_result(blocked := false) -> void:
	var result := {
		"checks": checks, "failures": failures, "blocked": blocked,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"facts": FsrGraphics.facts(), "status": status(), "rows": rows,
		"frame_generation_tested": fg_tested,
	}
	FileAccess.open("user://fsr-render.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("FSR_RENDER ", JSON.stringify(result))

func settle(frames: int) -> void:
	for i in frames: await RenderingServer.frame_post_draw

func sample(label: String, selection: int, moving := false, generate := false) -> void:
	GameData.options[FsrGraphics.UPSCALING] = 1 if selection >= 0 else 0
	GameData.options[FsrGraphics.QUALITY] = maxi(selection, 0)
	GameData.options[FsrGraphics.FRAME_GENERATION] = 1 if generate else 0
	FsrGraphics.bridge().call("set_frame_generation_version", 3 if generate else 0)
	get_tree().root.set("frame_generation", generate)
	GameData._apply_window()
	Engine.max_fps = 120
	await settle(40)
	var before := status()
	var start := Time.get_ticks_usec()
	var original_camera := scene.camera.transform
	for i in 120:
		if moving:
			scene.camera.position.x = original_camera.origin.x + sin(float(i) * 0.035) * 0.15
		await RenderingServer.frame_post_draw
	var after := status()
	var delta := int(after.get("upscale_evaluations", 0)) - int(before.get("upscale_evaluations", 0))
	var image := get_tree().root.get_texture().get_image()
	var path := "user://fsr-" + label + ".png"
	check(not image.is_empty() and image.get_size() == get_tree().root.size, label + ": full output image")
	check(image.save_png(path) == OK, label + ": screenshot saved")
	check(after.get("frame_generation_active", false) == generate, label + ": expected frame-generation activity")
	var generated := int(after.get("generated_frames", 0)) - int(before.get("generated_frames", 0))
	var presented := int(after.get("presented_frames", 0)) - int(before.get("presented_frames", 0))
	check(after.get("present_count_available", false), label + ": real DXGI presentation counts available")
	check(presented >= 220 and presented <= 250 if generate else presented >= 110 and presented <= 130, label + ": real DXGI presentation rate")
	check(generated >= 100 if generate else generated == 0, label + ": actual generated-frame count")
	if generate:
		check(String(after.get("frame_generation_provider", "")).begins_with("3.1."), label + ": actual FSR 3.1 FG provider")
		fg_tested = true
	check(int(after.get("last_error", -1)) == 0, label + ": no SDK error")
	check(delta >= 110 if selection >= 0 else delta == 0, label + ": actual FSR evaluation count")
	if selection >= 0:
		check(FsrGraphics.sr_active(), label + ": FSR remains supported")
		check(String(after.get("upscaler_provider", "")).begins_with("3.1."), label + ": actual FSR 3.1 SR provider")
	else:
		check(is_equal_approx(get_tree().root.scaling_3d_scale, 1.0), label + ": ordinary scale restored")
	rows.append({
		"label": label, "selection": selection, "upscale_evaluations": delta, "generated_frames": generated, "presented_frames": presented,
		"sampled_frames": 120, "elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"scale": get_tree().root.scaling_3d_scale,
		"size": [image.get_width(), image.get_height()], "status": after,
	})
	scene.camera.transform = original_camera
	save_result()

func _run() -> void:
	await settle(5)
	var capabilities := FsrGraphics.facts()
	if not capabilities.api or not capabilities.sr3 or not capabilities.fg3:
		save_result(true)
		get_tree().quit(2)
		return
	get_tree().root.get_node("FsrExperiment").set_process(false)
	GameData.options[FsrGraphics.FRAME_GENERATION] = 0
	GameData.options[FsrGraphics.UPSCALING] = 0
	GameData.options.confine_mouse = 0
	GameData.options.show_fps = 1
	GameData.options.volume_sfx = 0
	GameData.options.volume_stream = 0
	GameData.options.volume_voice = 0
	GameData.options.q_aa = 0
	GameData.options.render_scale = 4
	GameData.options.display_mode = 0
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280, 720))
	GameData.options.vsync = 0
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData._window_state.clear()
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 720)
	Gfx.ensure_globals()
	Gfx.apply_surface_options()
	Gfx.set_foliage_wind(false)
	scene = MenuScene.create()
	check(scene != null, "real game scene created")
	if scene == null:
		save_result()
		get_tree().quit(1)
		return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(scene)
	scene.set_hour(12)
	scene.camera.current = true
	check(scene.find_children("*", "MeshInstance3D", true, false).size() >= 160, "real game geometry loaded")
	await sample("off", -1)
	await sample("native-aa", 0)
	await sample("quality", 1)
	await sample("balanced", 2)
	await sample("performance", 3)
	await sample("quality-motion", 1, true)
	await sample("fg-quality-motion", 1, true, true)
	if OS.get_cmdline_user_args().has("--fsr-capture"):
		print("FSR_CAPTURE_READY")
		for frame in 1200:
			scene.camera.position.x += sin(frame * 0.07) * 0.003
			await RenderingServer.frame_post_draw
	await sample("fg-disabled", 1, true, false)
	await sample("off-restored", -1)
	get_tree().root.size = Vector2i(960, 540)
	await sample("fg-resized", 1, true, true)
	check(get_tree().root.size == Vector2i(960, 540), "resize changes the actual swapchain")
	# Keep generation enabled through shutdown to exercise context lifetime.

	scene.free()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	await settle(4)
	save_result()
	get_tree().quit(1 if not failures.is_empty() else 0)
