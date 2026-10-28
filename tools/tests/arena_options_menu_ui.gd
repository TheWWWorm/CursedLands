extends "arena_expansion_ui.gd"
## The autochess menu opens the campaign Options screen (graphics, sound,
## controls) and returns to the board. Runs at 1280x720, 2560x1440 and
## 3840x2160 in the language given by --lang=; saves
## user://options-menu-<lang>-<h>-<state>.png.

const SIZES := [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]


func dimensions(value: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().size = value
	get_window().position = Vector2i.ZERO
	await frames(14)


func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://options-menu-" + label + ".png")
	print("CAPTURE ", label, " ", image.get_size())


func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData.arena_mode = 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): lang = arg.trim_prefix("--lang=")
	RemakeText.lang = lang
	await dimensions(SIZES[0])
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(16)
	while ShaderCompilationScreen.active(): await frames(2)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run, 1)
	await frames(18)
	while ShaderCompilationScreen.active(): await frames(2)
	check(lang == "en" or RemakeText.TEXTS.has("Options"), "Options label has RU/DE text")
	for size: Vector2i in SIZES:
		await dimensions(size)
		var tag := "%s %dx%d" % [lang, size.x, size.y]
		screen._show_menu()
		await frames(8)
		var button: Button = screen._menu_items.get(6)
		check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, tag + ": menu offers Options")
		if not is_instance_valid(button): continue
		check(button.text == RemakeText.t("Options"), tag + ": Options label is localized")
		check(button.get_minimum_size().x <= button.size.x + 0.5, tag + ": Options label is not clipped")
		var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		check(view.encloses(button.get_global_rect()), tag + ": Options button is on screen")
		check(button.get_global_rect().size.y >= 32.0 * screen._ui_scale - 1.0, tag + ": Options hit target scales with the interface")
		await capture("%s-%d-menu" % [lang, size.y])
		button.pressed.emit()
		await frames(30)
		var options: OptionsPanel = screen._options
		check(is_instance_valid(options) and options.visible, tag + ": Options screen opens")
		check(screen._modal_layer.visible and not screen._modal_panel.visible, tag + ": arena menu stays behind the Options screen")
		await capture("%s-%d-options" % [lang, size.y])
		if is_instance_valid(options): options._close()
		await frames(8)
		check(not screen._modal_layer.visible and not options.visible, tag + ": closing Options returns to the board")
		check(screen.battle.phase == ArenaMatch.Phase.DEPLOY, tag + ": preparation continues after Options")
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "no engine errors: " + "; ".join(errors.messages.slice(0, 4)))
	print("ARENA_OPTIONS_MENU_UI ", JSON.stringify({"checks":checks,"failures":failures}))
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
