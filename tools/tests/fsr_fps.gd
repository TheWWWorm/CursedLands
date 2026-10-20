extends Node
## Counter arithmetic, lifecycle and localized FPS layout. Real SDK activity
## is covered separately by fsr_render and fsr_campaign.

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var meter := FrameRateMeter.new()
	var state := {"frame_generation_active": true, "present_count_available": true, "presented_frames": 1000, "game_presents": 500}
	var rates := meter.sample(state, 1_000_000, 60)
	check(rates.presented_fps < 0, "first sample does not invent presented FPS")
	state.presented_frames += 45
	state.game_presents += 30
	rates = meter.sample(state, 1_500_000, 12)
	check(is_equal_approx(rates.presented_fps, 90) and is_equal_approx(rates.rendered_fps, 60), "90 presented and 60 rendered measured over same interval; no assumed doubling")
	state.presented_frames += 30
	state.game_presents += 20
	rates = meter.sample(state, 2_000_000, 12)
	check(is_equal_approx(rates.presented_fps, 75) and is_equal_approx(rates.rendered_fps, 50), "variable frame rate uses elapsed wall time")
	state.frame_generation_active = false
	rates = meter.sample(state, 2_250_000, 44)
	check(rates.presented_fps < 0 and rates.rendered_fps == 44 and FrameRateMeter.label_text(rates) == "44 FPS", "menu or pause removes stale generated FPS immediately")
	state.frame_generation_active = true
	check(meter.sample(state, 2_500_000, 44).presented_fps < 0, "resuming starts a fresh interval")
	state.presented_frames = 0
	state.game_presents = 0
	check(meter.sample(state, 3_000_000, 44).presented_fps < 0, "swapchain counter reset cannot yield negative FPS")
	state.presented_frames = 60
	state.game_presents = 30
	check(is_equal_approx(meter.sample(state, 3_500_000, 44).presented_fps, 120), "sampling recovers after reset")
	check(meter.sample(state, 8_000_000, 44).presented_fps < 0, "long suspension discards stale interval")
	check(meter.sample(state, 7_000_000, 44).presented_fps < 0, "backwards clock cannot produce a rate")
	state.present_count_available = false
	check(meter.sample(state, 8_000_000, 44).presented_fps < 0, "unavailable DXGI counter stays unknown")
	check(meter.sample({}, 9_000_000, 44).rendered_fps == 44, "stock engine retains normal FPS")
	state.present_count_available = true
	state.erase("game_presents")
	check(meter.sample(state, 9_500_000, 44).presented_fps < 0, "incomplete native telemetry cannot fabricate FPS")
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		for key in ["%d FPS rendered", "%d FPS presented", "Presented FPS: …", "Preparing FSR…", FsrGraphics.FG_HELP]:
			check(RemakeText.TEXTS.has(key) and not RemakeText.t(key).is_empty(), language + " translated: " + key)
	if DisplayServer.get_name() != "headless":
		GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"display_mode":0}, true)
		GameData._apply_window()
		await get_tree().create_timer(0.4).timeout
		GameData._window_gen += 1
		get_window().mode = Window.MODE_WINDOWED
		var label := GameData._fps_layer.get_child(0) as Label
		label.set_process(false)
		for size: Vector2i in [Vector2i(800, 600), Vector2i(1280, 720)]:
			get_window().size = size
			for language: String in ["en", "ru", "de"]:
				RemakeText.lang = language
				label.text = FrameRateMeter.label_text({"rendered_fps":120.0,"presented_fps":240.0,"frame_generation_active":true})
				for frame in 4: await RenderingServer.frame_post_draw
				check(get_window().get_visible_rect().encloses(label.get_global_rect()), language + " FPS bounds at " + str(size))
				check(label.get_minimum_size().x <= label.size.x and label.get_minimum_size().y <= label.size.y, language + " full FPS text fits")
				check(get_window().get_texture().get_image().save_png("user://fsr-fps-" + language + "-" + str(size.x) + ".png") == OK, "save FPS layout")
	RemakeText.lang = "en"
	var result := {"checks":checks,"failures":failures}
	FileAccess.open("user://fsr-fps.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("FSR_FPS ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
