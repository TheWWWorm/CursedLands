extends "startup_graphics_recovery.gd"
## The Android-only renderer action is exercised on desktop with
## --renderer-option, using the actual GLES renderer and an isolated profile.
var restarts := 0

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2); return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	check(RendererChoice.available() and Portability.compatibility(), "renderer recovery fixture uses the Android GLES path")
	var original := GameData.options.duplicate(true)
	RendererChoice._reset()
	GameData.save_settings()
	RendererChoice.on_restart = func(): restarts += 1
	var previous := {"session":"renderer-recovery", "zone":"(menu)", "last":"startup: main menu built; presenting loading animation"}
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		var before := GameData.options.duplicate(true)
		var settings := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
		var box := CrashReportBox.open(get_parent(), previous, true)
		await settle()
		check(box._row_defs().size() == 5, language + " renderer is reachable before the 3D menu")
		check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "no menu constructed by recovery")
		box._status = RemakeText.t("Report saved:") + " /storage/emulated/0/Download/CursedLands-report-20261015-120000.txt"
		box.queue_redraw(); await settle()
		var rects := box._rects()
		check(rects.top >= 0 and rects.ok.end.y <= 600, language + " five actions and saved path fit vertically")
		for row: Array in box._row_defs():
			check(box.text_width(RemakeText.t(row[0]), 2) <= 340, language + " row fits horizontally")
		for key: String in CrashReportBox.RENDERER_ROW + [CrashReportBox.RENDERER_PROMPT]:
			check(language == "en" or RemakeText.t(key) != key, language + " renderer action, help and prompt translated")
		get_viewport().get_texture().get_image().save_png("user://renderer-recovery-" + language + ".png")
		tap(box, 4); await settle()
		check(box._confirm != null and box._probing and not box.visible, language + " renderer selection asks before restart")
		check(GameData.options == before and not FileAccess.file_exists(RendererChoice.OVERRIDE) and not FileAccess.file_exists(RendererChoice.TRIAL), "opening confirmation has no saved side effects")
		var prompt := box._confirm
		var prompt_rects := prompt._rects()
		check(prompt_rects.top >= 0 and prompt_rects.ok.end.y <= 600, language + " restart prompt fits")
		get_viewport().get_texture().get_image().save_png("user://renderer-confirm-" + language + ".png")
		answer(prompt, false); await settle()
		check(box.visible and not box._probing and restarts == 0, "declining returns to recovery without restarting")
		check(GameData.options == before and FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == settings, "declining preserves settings byte for byte")
		box.queue_free(); await settle()
	# Normal log export and in-game crash reports must retain their two actions.
	for context: Dictionary in [{}, {"zone":"gz1h"}]:
		var box := CrashReportBox.open(get_parent(), context, true)
		check(box._row_defs().size() == 2, "in-game and export reports do not offer startup renderer changes")
		box.queue_free(); await settle()
	var box := CrashReportBox.open(get_parent(), previous, true)
	var before := GameData.options.duplicate(true)
	tap(box, 4); await settle()
	answer(box._confirm, true); await settle()
	check(restarts == 1, "accepting requests exactly one restart")
	check(RendererChoice.chosen() == 2 and GameData.option("renderer") == 2, "Mobile is selected through the existing renderer mechanism")
	var trial := RendererChoice._load(RendererChoice.TRIAL, "trial")
	var override := RendererChoice._load(RendererChoice.OVERRIDE, "rendering")
	check(trial == {"method":"mobile", "state":"pending"}, "restart retains the existing crash-recovery trial")
	check(override.get("renderer/rendering_method") == "mobile" and override.get("renderer/rendering_method.mobile") == "mobile", "both startup renderer keys select Mobile")
	for key in before:
		if key != "renderer": check(GameData.options[key] == before[key], "renderer switch preserves " + key)
	# A Vulkan startup failure follows the existing fallback on this GLES run.
	check(RendererChoice.startup() == null and RendererChoice.chosen() == 0 and RendererChoice.notice == RendererChoice.FAILED, "failed Vulkan start restores Compatibility")
	RendererChoice.notice = ""
	RendererChoice.on_restart = Callable()
	box.queue_free(); await settle()
	RendererChoice._reset()
	GameData.set_options(original)
	RemakeText.lang = "en"
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"affected_device_tested":false}
	FileAccess.open("user://startup-renderer-recovery.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("STARTUP_RENDERER_RECOVERY ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
