extends Node
## The esc_menu_rise option row on Remake › Gameplay: localized label, choices
## and help in EN/RU/DE that fit their columns at 720p, 1440p and 4K, above
## the page's « link (the Interface page has no free row).
var checks := 0
var failures := 0
const SIZES := [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame

func dimensions(value: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().wrap_controls = false
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = value
	get_window().size = value
	await frames(8)

func fits(options: OptionsPanel, s: String, width: float) -> bool:
	var f := Interface800.font()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, options.font_px(1)).x <= options.r8(Rect2(0, 0, width, 20)).size.x

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics": 0, "display_mode": 0, "esc_menu_rise": 0}, true)
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	var row_index: int = GameData.OPTIONS.filter(func(r: Array) -> bool: return r[0] == "esc_menu_rise")[0][4]
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		for size: Vector2i in SIZES:
			await dimensions(size)
			var options := OptionsPanel.new()
			add_child(options)
			options.open()
			options._show_group(OptionsPanel.GAMEPLAY_GROUP)
			await frames(6)
			var row: Dictionary = options._rows.get(row_index, {})
			var tag := "%s %dx%d" % [lang, size.x, size.y]
			var label := RemakeText.t(GameData.REMAKE_OPTIONS.esc_menu_rise[0])
			check(row.get("name", "") == "esc_menu_rise" and row.label == label, tag + ": the row shows the localized label")
			check(lang == "en" or label != GameData.REMAKE_OPTIONS.esc_menu_rise[0], tag + ": label is translated")
			check(String(row.get("tip", "")).contains(RemakeText.t(GameData.REMAKE_OPTIONS.esc_menu_rise[1])), tag + ": localized help")
			check(options._rows.get(OptionsPanel.BACK_ROW, {}).get("kind", "") == "link" and row_index < OptionsPanel.BACK_ROW, tag + ": the row is above the « link")
			check(fits(options, row.label, 260), tag + ": label fits its column")
			for value in [0, 1]:
				options._values.esc_menu_rise = value
				var choice := options._switch_text(row)
				# On / Off are the original's localized texts.res strings.
				var expected := options._t("string option_on", "On") if value == 1 else options._t("string option_off", "Off")
				check(choice == expected and not choice.is_empty() and fits(options, choice, 160), tag + ": choice %d is localized and fits: %s" % [value, choice])
			options._values.esc_menu_rise = 0
			options._sel = row_index
			options.queue_redraw()
			if DisplayServer.get_name() != "headless":
				await frames(4)
				await RenderingServer.frame_post_draw
				var shot := get_viewport().get_texture().get_image()
				check(shot.get_size() == size, tag + ": native-resolution capture")
				shot.save_png("user://esc-rise-option-%s-%d.png" % [lang, size.y])
			options._close() if options.has_method("_close") else options.hide()
			options.free()
	RemakeText.lang = "en"
	print("ESC_MENU_RISE_UI ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
