extends "story_coop_traps_net.gd"
## Actual main menu and paused campaign, with original EN/RU/DE archives.

func presented() -> void:
	await frames(8)
	for i in 3: await RenderingServer.frame_post_draw

func text_rect(footer: BuildVersion) -> Rect2:
	var label := footer._label
	var font := label.get_theme_font("font")
	var size := Vector2(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x,
		label.get_combined_minimum_size().y)
	return Rect2(label.get_global_rect().end-size, size)

func verify(footer: BuildVersion, screen: Vector2i, context: String) -> void:
	var version := String(ProjectSettings.get_setting("application/config/version"))
	var expected := {"en":"Version %s", "ru":"Версия %s", "de":"Version %s"}
	check(footer.is_visible_in_tree() and footer._label.text == expected[RemakeText.lang] % version, context + ": localized packaged version is visible")
	check(Rect2(Vector2.ZERO, screen).encloses(text_rect(footer)), context + ": complete version text fits the screen")
	check(is_equal_approx(text_rect(footer).end.y, screen.y-16.0), context + ": version sits in the bottom corner")
	check(footer.mouse_filter == Control.MOUSE_FILTER_IGNORE and footer._label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		context + ": version does not intercept menu input")

func resize_to(size: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	await frames(8) # X11 applies the mode change before accepting the new size.
	get_window().size = size
	get_window().position = DisplayServer.screen_get_usable_rect().position
	await presented()
	check(get_window().size == size, "window uses " + str(size))

func shot(id: String) -> void:
	await presented()
	get_viewport().get_texture().get_image().save_png("user://build-version-" + RemakeText.lang + "-" + id + ".png")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("Run with a rendering display"); get_tree().quit(2); return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1), true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"confine_mouse":0}, true)
	await frames(24)
	await resize_to(Vector2i(1024,768))
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false
	add_child(menu)
	menu._scene.set_hour(12.0)
	menu._scene.set_process(false)
	await presented()
	var sizes := [Vector2i(800,600), Vector2i(1024,768), Vector2i(1920,1080), Vector2i(3840,2160)]
	for size: Vector2i in sizes:
		await resize_to(size)
		verify(menu._version, size, "main " + str(size))
		check(not text_rect(menu._version).grow(6).intersects(menu._utility_bar.get_global_rect()), "version clears main-menu buttons at " + str(size))
		await shot("main-%d" % size.x)
	menu._on_board("options")
	await presented()
	check(not menu._version.is_visible_in_tree(), "main-menu version hides behind options")
	menu._options._close()
	await presented()
	check(menu._version.is_visible_in_tree(), "main-menu version returns after options")
	menu.free()
	await frames()
	host = branch(false)
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	host._enter_zone("gz1g", 1, false)
	await presented()
	freeze(host)
	await until(func(): return LoadingScreen._current == null, 10.0)
	var hud := host.game.hud
	for size: Vector2i in sizes:
		await resize_to(size)
		hud._open_menu()
		await get_tree().create_timer(0.9, true, false, true).timeout
		await presented()
		verify(hud._menu._version, size, "pause " + str(size))
		check(get_tree().paused, "opening pause menu suspends gameplay")
		await shot("pause-%d" % size.x)
		hud._close_menu()
		await presented()
		check(not get_tree().paused and not hud._menu._version.is_visible_in_tree(), "resume hides version and restores gameplay")
	await resize_to(Vector2i(1024,768))
	get_tree().paused = true
	hud._open_menu()
	PadInput.active = "pad"
	PadInput.mode_changed.emit()
	await presented()
	check(text_rect(hud._menu._version).end.y < 768-40.0*768/600, "version clears gamepad hints")
	await shot("pause-gamepad")
	hud._close_menu()
	check(get_tree().paused, "closing menu preserves an existing tactical pause")
	PadInput.active = "kbm"
	PadInput.mode_changed.emit()
	get_tree().paused = false
	print("MENU_BUILD_VERSION ", RemakeText.lang, " ", checks, " checks ", failures, " failures")
	await finish()
