extends "startup_graphics_recovery.gd"
## Capability/fallback and localized settings checks. A passing run does NOT
## qualify SDK-rendered output; use the hardware rendering fixtures too.

func _run() -> void:
	TutorialPanel.auto_show = false
	check(GameData.option(FsrGraphics.UPSCALING) == 0, "fresh profile leaves FSR off")
	check(GameData.option(FsrGraphics.FRAME_GENERATION) == 0, "fresh profile leaves FG off")
	var supported := {"engine":true,"api":true,"launch":true,"sr3":true,"sr4":true,"fg3":true,"fg4":true}
	for version in [1, 2]:
		check(FsrGraphics.reason_for(FsrGraphics.UPSCALING, supported, version).is_empty(), "supported upscaler version " + str(version))
		check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, supported, version, version).is_empty(), "supported FG version " + str(version))
	var ampere := supported.duplicate()
	ampere.sr4 = false
	ampere.fg4 = false
	check(FsrGraphics.reason_for(FsrGraphics.UPSCALING, ampere, 2) == FsrGraphics.NEED_SR, "FSR 4 cannot silently become 3.1")
	check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, ampere, 1, 2) == FsrGraphics.NEED_FG, "FG 4 cannot silently become 3.1")
	check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, supported, 0, 1) == FsrGraphics.ENABLE_SR, "FG requires upscaling")
	for key in ["engine", "api", "launch"]:
		var unavailable := supported.duplicate()
		unavailable[key] = false
		check(not FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, unavailable, 1, 1).is_empty(), "FG rejects missing " + key)
	for text: String in FsrGraphics.SECTION + [FsrGraphics.SR_HELP, FsrGraphics.QUALITY_HELP, FsrGraphics.FG_HELP, FsrGraphics.UNAVAILABLE, FsrGraphics.START_LAUNCHER, FsrGraphics.NEED_SR, FsrGraphics.NEED_FG, FsrGraphics.ENABLE_SR] + FsrGraphics.VERSIONS + FsrGraphics.QUALITIES:
		for language in ["ru", "de"]:
			RemakeText.lang = language
			check(RemakeText.TEXTS.has(text) and not RemakeText.t(text).is_empty(), language + " translation coverage: " + text)
	var actual := FsrGraphics.facts()
	check(not actual.sr3 and not actual.sr4 and not actual.fg3 and not actual.fg4, "fallback fixture is unsupported")
	var native := FsrGraphics.bridge()
	if native:
		var status: Dictionary = native.call("get_status")
		check(not status.get("initialized", true), "ordinary renderer does not load AMD SDK")
		check(status.get("upscale_evaluations", 0) == 0, "no false SDK evaluations")
	GameData.options[FsrGraphics.UPSCALING] = 2
	GameData.options[FsrGraphics.FRAME_GENERATION] = 1
	var scale := get_window().scaling_3d_scale
	var mode := get_window().scaling_3d_mode
	FsrGraphics.apply_upscaling(get_window())
	check(get_window().scaling_3d_scale == scale and get_window().scaling_3d_mode == mode, "unsupported saved request preserves ordinary renderer")
	GameData.options[FsrGraphics.UPSCALING] = 0
	GameData.options[FsrGraphics.FRAME_GENERATION] = 0
	if DisplayServer.get_name() != "headless":
		await settle()
		GameData.options.resolution = GameData.resolutions().find(Vector2i(800, 600))
		GameData._window_state.clear()
		GameData._apply_window()
		await get_tree().create_timer(0.3).timeout
		GameData._window_gen += 1
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(800, 600)
		await settle()
		check(get_window().size == Vector2i(800, 600), "actual 800x600 layout fixture")
		for lang: String in ["en", "ru", "de"]:
			RemakeText.lang = lang
			var panel := OptionsPanel.new()
			get_parent().add_child(panel)
			panel.open()
			panel._show_group(12)
			check(panel._rows[13].to == FsrGraphics.GROUP, lang + " Screen link")
			check(panel._rows[9].name == "brightness", lang + " brightness control preserved")
			panel._show_group(FsrGraphics.GROUP)
			await settle()
			for index in [0, 1, 2]:
				var row: Dictionary = panel._rows[index]
				check(row.disabled, lang + " unsupported feature disabled")
				check(panel.text_width(row.label, 2) <= 270, lang + " option label fits")
				for choice: String in row.choices:
					check(panel.text_width(choice, 1) <= 160, lang + " choice fits: " + choice)
				panel._sel = index
				GameData._tips.delay = 0.001
				Input.warp_mouse(panel.get_global_transform_with_canvas() * panel.p8(Vector2(400, panel._row_y(index) + 10)))
				await settle()
				GameData._tips._since = 0
				GameData._tips._process(0)
				await settle()
				check(GameData._tips._panel.visible and GameData._tips._text == row.tip, lang + " help visible")
				check(get_viewport().get_visible_rect().encloses(GameData._tips._panel.get_rect()), lang + " help fits 800x600")
				get_viewport().get_texture().get_image().save_png("user://fsr-" + lang + "-" + str(index) + ".png")
			panel._values[FsrGraphics.UPSCALING] = 2
			panel._show_group(FsrGraphics.GROUP)
			check(not panel._rows[0].disabled, "stale unsupported request can be removed")
			panel._toggle(0)
			check(panel._values[FsrGraphics.UPSCALING] == 0, "stale request switches directly off")
			panel._set_value(FsrGraphics.FRAME_GENERATION, 1)
			check(panel._values[FsrGraphics.FRAME_GENERATION] == 0, "unavailable FG cannot be activated")
			panel.queue_free()
			await settle()
	RemakeText.lang = "en"
	FileAccess.open("user://fsr-check.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"facts":actual,"hardware_output_qualified":false}, "\t"))
	print("FSR_EXPERIMENT ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
