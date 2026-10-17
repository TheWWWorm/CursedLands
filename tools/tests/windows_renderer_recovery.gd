extends "startup_graphics_recovery.gd"
## Windows policy exercised with real rendering on a desktop isolated profile.
var restarts := 0

func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameData.options.confine_mouse = 0
	GameData.options.display_mode = 0
	await settle()
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(800, 600)
	check(RendererChoice.windows() and RendererChoice.available(), "Windows renderer policy active")
	check(not Portability.compatibility(), "Forward+ recovery entry fixture")
	check(RendererChoice.chosen() == WindowsRenderer.AUTO, "fresh Windows profile defaults to Automatic")
	check(CrashReport.instance.info.render_thread == "safe", "report records actual Safe thread mode")
	var original := GameData.options.duplicate(true)
	RendererChoice.on_restart = func(): restarts += 1
	var previous := {"session":"windows-recovery", "zone":"(menu)"}
	for lang: String in ["en", "ru", "de"]:
		check(get_window().size == Vector2i(800, 600), "actual 800x600 window")
		RemakeText.lang = lang
		var before := GameData.options.duplicate(true)
		var box := CrashReportBox.open(get_parent(), previous, true)
		await settle()
		check(box._row_defs().size() == 5, lang + " recovery is available before the 3D menu")
		check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "no 3D scene during recovery")
		box._status = RemakeText.t("Report saved:") + " C:/Users/Player/Downloads/CursedLands-report-20261017-203000.txt"
		box.queue_redraw(); await settle()
		var rects := box._rects()
		check(rects.top >= 0 and rects.ok.end.y <= 600, lang + " recovery fits vertically")
		for row: Array in box._row_defs():
			check(box.text_width(RemakeText.t(row[0]), 2) <= 340, lang + " recovery label fits")
		for key: String in CrashReportBox.WINDOWS_RENDERER_ROW + [CrashReportBox.WINDOWS_RENDERER_PROMPT, RendererChoice.WINDOWS_HELP, RendererChoice.WINDOWS_FAILED, RendererChoice.WINDOWS_CRASHED, RendererChoice.WINDOWS_CHOICES[0]]:
			check(lang == "en" or RemakeText.t(key) != key, lang + " dynamic text translated")
		get_viewport().get_texture().get_image().save_png("user://windows-recovery-" + lang + ".png")
		tap(box, 4); await settle()
		check(box._confirm != null and not box.visible, "restart prompts before applying")
		check(GameData.options == before, "asking does not change options")
		var prompt := box._confirm
		check(prompt._rects().top >= 0 and prompt._rects().ok.end.y <= 600, lang + " prompt fits")
		get_viewport().get_texture().get_image().save_png("user://windows-prompt-" + lang + ".png")
		answer(prompt, false); await settle()
		check(box.visible and restarts == 0 and GameData.options == before, "cancel leaves settings and current session untouched")
		box.queue_free(); await settle()
		var panel := OptionsPanel.new(); get_parent().add_child(panel); panel.open()
		panel._show_group(12); await settle()
		var row: Dictionary = panel._rows[12]
		check(row.name == "renderer" and row.choices.size() == 4, "Windows offers Automatic, Direct3D 12, Vulkan and OpenGL")
		for choice: String in row.choices:
			check(panel.text_width(choice, 1) <= 160, lang + " renderer choice fits")
		check(row.tip.contains(RemakeText.t(RendererChoice.WINDOWS_HELP)), lang + " Windows-specific help")
		get_viewport().get_texture().get_image().save_png("user://windows-option-" + lang + ".png")
		panel._set_value("renderer", 0)
		await settle()
		get_viewport().get_texture().get_image().save_png("user://windows-option-compat-" + lang + ".png")
		panel._set_value("renderer", 1)
		check(panel._box == null, "Windows Forward+ does not show the phone experiment warning")
		panel._sel = 12
		GameData._tips.delay = 0.001
		Input.warp_mouse(panel.get_global_transform_with_canvas() * panel.p8(Vector2(400, panel._row_y(12) + 10)))
		await settle(); GameData._tips._since = 0; GameData._tips._process(0)
		await settle()
		check(GameData._tips._panel.visible and GameData._tips._text == row.tip, lang + " help displayed")
		check(get_viewport().get_visible_rect().encloses(GameData._tips._panel.get_rect()), lang + " help fits 800x600")
		get_viewport().get_texture().get_image().save_png("user://windows-help-" + lang + ".png")
		panel.queue_free(); await settle()
		var detector := RendererDetector.new(); get_parent().add_child(detector)
		detector._status.text = RemakeText.t(RendererDetector.STATUS) % "Vulkan"
		await settle()
		check(detector._status.get_global_rect().position.x >= 0 and detector._status.get_global_rect().end.x <= 800, lang + " detector status fits")
		get_viewport().get_texture().get_image().save_png("user://windows-detector-" + lang + ".png")
		detector.queue_free(); await settle()
	var box := CrashReportBox.open(get_parent(), previous, true)
	tap(box, 4); await settle(); answer(box._confirm, true); await settle()
	check(restarts == 1 and RendererChoice.chosen() == 0, "accepting requests one restart into Compatibility")
	check(GfxDetect.original_look_on(GameData.options) and GameData.option("auto_graphics") == 0, "recovery disables enhancements and automatic calibration")
	var cfg := RendererChoice._load(RendererChoice.OVERRIDE, "rendering")
	check(cfg.get("renderer/rendering_method") == "gl_compatibility" and cfg.get("renderer/rendering_method.windows") == "gl_compatibility", "Compatibility saved in both early override keys")
	check(cfg.get("driver/threads/thread_model.windows") == 1, "recovery uses Safe thread")
	check(not FileAccess.file_exists(RendererChoice.TRIAL), "Compatibility is not a risky trial")
	for k in original:
		if k not in Array(GfxDetect.keys()) + ["auto_graphics", "fps_limit", "graphics_preset", "renderer"]:
			check(original[k] == GameData.options[k], "preserves " + k)
	box.queue_free(); await settle()
	var args := RendererChoice.restart_args()
	check(not args.has("--rendering-method") and not args.has("--rendering-driver"), "restart removes stale engine driver overrides")
	check(args.has("--render-thread") and args[args.find("--render-thread") + 1] == "safe", "restart forces Safe thread")
	check(not Array(args).any(func(a): return a.begins_with("--tool=") or a == "--compatibility-recovery"), "restart cannot replay tool or compatibility launcher")
	RendererChoice.on_restart = Callable()
	RemakeText.lang = "en"
	FileAccess.open("user://windows-renderer-recovery.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"platform":OS.get_name(),"affected_hardware_tested":false}, "\t"))
	print("WINDOWS_RENDERER_RECOVERY ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
