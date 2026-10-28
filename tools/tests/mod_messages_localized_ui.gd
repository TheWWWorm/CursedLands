extends Node
## The translated mod-profile and save messages fit their status labels in
## EN/RU/DE at 1280x720, 2560x1440 and 3840x2160, with native-resolution
## captures. Uses the real ModPanel and DifficultyPanel. Isolated --mod-tests only.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames() -> void:
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func fits(label: Label, host: Control, what: String) -> void:
	check(label.visible and not label.text.is_empty(), what + " is shown")
	check(label.get_line_count() == label.get_visible_line_count(), what + " wraps without clipping")
	var inside := host.get_global_rect().grow(1.0)
	check(inside.encloses(label.get_global_rect()), what + " stays inside its panel")
	check(label.get_global_rect().end.x <= get_viewport().get_visible_rect().size.x + 1.0, what + " stays on screen")

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	TutorialPanel.auto_show = false
	RenderingServer.set_render_loop_enabled(true)
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var original_language := RemakeText.lang
	var font_sizes := {}
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		# The longest composed message and the plain save message, as the game builds them.
		var composed := ModStore.values_error({"example.bogus_option": 1})
		var setup := RemakeText.t("Required setup: %s. Select a matching mod profile first.") % "example.revival 1.0, example.textures 2.1"
		var save := RemakeText.t("The save cannot be read.")
		if language != "en":
			check(not composed.begins_with("Unknown mod option") and composed.contains("example.bogus_option"), language + " composed message is translated and keeps the option id")
			check(not save.begins_with("The save"), language + " save message is translated")
		for shape: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440), Vector2i(3840,2160)]:
			get_tree().root.size = shape
			await frames()
			var panel := ModPanel.new()
			add_child(panel)
			panel.open("profiles")
			panel._status.text = setup
			await frames()
			fits(panel._status, panel, "%s %dp mod profile message" % [language, shape.y])
			# SettingsDialog scales its surface and rasterizes the font at that scale (oversampling).
			font_sizes[[language, shape.y, "mod"]] = panel._status.get_theme_font_size("font_size") * panel._ui_scale
			get_viewport().get_texture().get_image().save_png("user://mod-message-%s-%d.png" % [language, shape.y])
			panel._status.text = RemakeText.t(composed)
			await frames()
			fits(panel._status, panel, "%s %dp unknown option message" % [language, shape.y])
			panel.close(); panel.free()
			var difficulty := DifficultyPanel.new()
			add_child(difficulty)
			difficulty.open(false)
			difficulty._status.text = RemakeText.t(save)
			await frames()
			fits(difficulty._status, difficulty, "%s %dp save message" % [language, shape.y])
			font_sizes[[language, shape.y, "save"]] = difficulty._status.get_theme_font_size("font_size") * difficulty._ui_scale
			get_viewport().get_texture().get_image().save_png("user://save-message-%s-%d.png" % [language, shape.y])
			difficulty.free()
	for language: String in ["en", "ru", "de"]:
		for kind in ["mod", "save"]:
			check(font_sizes[[language, 2160, kind]] >= font_sizes[[language, 720, kind]] * 2.5,
				"%s %s message text is rasterized at least 2.5x larger at 2160p than at 720p" % [language, kind])
	RemakeText.lang = original_language
	print("MOD_MESSAGES_LOCALIZED_UI ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
