extends Node
## The moved option rows in EN/RU/DE at 720p, 1440p and 4K: the skill reset
## button on Remake › Interface beside the camp options, and Keep mouse in
## window on the Sensitivity page with the mouse settings. Labels, choices
## and help are localized and fit their columns; native-resolution captures
## are saved as user://options-rows-<lang>-<h>-<page>.png.
var checks := 0
var failures := 0
const SIZES := [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MOVED := ["skill_reset_button", "confine_mouse"]

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
	GameData.options.merge({"auto_graphics": 0, "display_mode": 0}, true)
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		for size: Vector2i in SIZES:
			await dimensions(size)
			for name: String in MOVED:
				var o: Array = GameData.OPTIONS.filter(func(r: Array) -> bool: return r[0] == name)[0]
				var options := OptionsPanel.new()
				add_child(options)
				# A plain backdrop: open() otherwise freezes the previous capture behind the board.
				var backdrop := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
				backdrop.fill(Color.BLACK)
				options.open(backdrop)
				options._show_group(int(o[3]))
				await frames(6)
				var tag := "%s %dx%d %s" % [lang, size.x, size.y, name]
				var row: Dictionary = options._rows.get(int(o[4]), {})
				var label := RemakeText.t(GameData.REMAKE_OPTIONS[name][0])
				check(row.get("name", "") == name and row.get("label", "") == label, tag + ": the row shows the localized label")
				check(lang == "en" or label != GameData.REMAKE_OPTIONS[name][0], tag + ": label is translated")
				check(String(row.get("tip", "")).contains(RemakeText.t(GameData.REMAKE_OPTIONS[name][1])), tag + ": localized help")
				check(fits(options, label, 260), tag + ": label fits its column")
				var keep: int = int(options._values.get(name, 1))
				for value in [0, 1]:
					options._values[name] = value
					var choice := options._switch_text(row)
					# Options with their own choice texts (DISPLAY_CHOICES) show those,
					# translated; plain switches use the original texts.res On/Off.
					var expected := RemakeText.t(GameData.DISPLAY_CHOICES[name][value]) if GameData.DISPLAY_CHOICES.has(name) \
						else (options._t("string option_on", "On") if value == 1 else options._t("string option_off", "Off"))
					check(choice == expected and not choice.is_empty() and fits(options, choice, 160), tag + ": choice %d is localized and fits: %s" % [value, choice])
				options._values[name] = keep
				options._sel = int(o[4])
				options.queue_redraw()
				if DisplayServer.get_name() != "headless":
					await frames(4)
					await RenderingServer.frame_post_draw
					var shot := get_viewport().get_texture().get_image()
					check(shot.get_size() == size, tag + ": native-resolution capture")
					shot.save_png("user://options-rows-%s-%d-%s.png" % [lang, size.y, name])
				options.free()
	RemakeText.lang = "en"
	print("OPTIONS_ROWS_REACHABLE_UI ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
