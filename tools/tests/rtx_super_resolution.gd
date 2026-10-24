extends Node
## Actual SDK evaluation check; unsupported hardware is a blocked run, never a pass.
## Seed the isolated settings profile with rtx_upscaling=2 before startup.

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var scene: MenuScene

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func status() -> Dictionary:
	var native := RtxGraphics.bridge()
	return native.call("get_status") if native else {}

func save_result(blocked := false) -> void:
	var result := {
		"checks": checks, "failures": failures, "blocked": blocked,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"facts": RtxGraphics.facts(), "status": status(), "rows": rows,
		"frame_generation_tested": false,
	}
	FileAccess.open("user://sr-render.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("SR_RENDER ", JSON.stringify(result))

func settle(frames: int) -> void:
	for i in frames: await RenderingServer.frame_post_draw

func sample(label: String, selection: int, moving := false) -> void:
	GameData.options[RtxGraphics.UPSCALING] = selection
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
	var delta := int(after.get("dlss_evaluations", 0)) - int(before.get("dlss_evaluations", 0))
	var image := get_tree().root.get_texture().get_image()
	var path := "user://sr-" + label + ".png"
	check(not image.is_empty() and image.get_size() == get_tree().root.size, label + ": full output image")
	check(image.save_png(path) == OK, label + ": screenshot saved")
	check(not after.get("frame_generation_active", true), label + ": frame generation stays off")
	check(int(after.get("last_error", -1)) == 0, label + ": no SDK error")
	check(delta >= 110 if selection > 0 else delta == 0, label + ": actual DLSS evaluation count")
	if selection > 0:
		check(RtxGraphics.sr_active(), label + ": DLSS remains supported")
	else:
		check(is_equal_approx(get_tree().root.scaling_3d_scale, 1.0), label + ": ordinary scale restored")
	rows.append({
		"label": label, "selection": selection, "dlss_evaluations": delta,
		"sampled_frames": 120, "elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"scale": get_tree().root.scaling_3d_scale,
		"size": [image.get_width(), image.get_height()], "status": after,
	})
	scene.camera.transform = original_camera
	save_result()

func _run() -> void:
	await settle(5)
	var capabilities := RtxGraphics.facts()
	if not capabilities.api or not capabilities.launch or not capabilities.sr:
		save_result(true)
		get_tree().quit(2)
		return
	GameData.options[RtxGraphics.FRAME_GENERATION] = 0
	GameData.options[RtxGraphics.UPSCALING] = 0
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
	await sample("off", 0)
	await sample("dlaa", 1)
	await sample("quality", 2)
	await sample("balanced", 3)
	await sample("performance", 4)
	await sample("quality-motion", 2, true)
	get_window().size = Vector2i(1600,900)
	await sample("resized", 2)
	scene.camera.position.x += 7.0
	await sample("camera-cut", 2)
	await sample("off-restored", 0)
	scene.free()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	await settle(4)
	save_result()
	get_tree().quit(1 if not failures.is_empty() else 0)
