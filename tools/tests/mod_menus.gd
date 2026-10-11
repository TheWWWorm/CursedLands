extends Node
## Focused rendered controls, keyboard/controller and narrow viewport checks.
var checks := 0
var failures := 0
var panel: ModPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames() -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await frames()
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	TutorialPanel.auto_show = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import public example")
	check(ModStore.create_profile("Recovery and experiments", true) == "", "create UI profile")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "mount public example")
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	panel = ModPanel.new()
	add_child(panel)
	panel.open("options")
	await shot("mod-options-wide")
	check(panel._values.size() == 2, "two generated numeric options")
	var slider: HSlider
	for control in panel._controls:
		if control is HSlider: slider = control; break
	slider.grab_focus()
	var before := slider.value
	panel.pad_press("right", "down")
	check(slider.value == before + slider.step, "controller changes focused slider")
	panel.close()
	check(ModStore.capability("revival.seconds") == before, "Cancel discards unapplied value")
	panel.open("options")
	panel._values["example.quick-recovery:seconds"] = 8.5
	check(panel._accept() and ModStore.capability("revival.seconds") == 8.5, "Apply commits generated value")
	panel._show_page("profiles")
	await shot("mod-profiles-wide")
	panel._show_page("sandbox")
	panel._rules.sandbox_invulnerable = 1
	check(panel._accept() and GameData.option("sandbox_invulnerable") == 1, "sandbox toggle applies in isolated profile")
	await shot("mod-sandbox-wide")
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(540,960)
	await frames()
	check(get_viewport().get_visible_rect().size == Vector2(540,960), "narrow test really renders at 540 by 960")
	for page in ["profiles", "rules", "options"]:
		panel._show_page(page)
		await shot("mod-" + page + "-narrow")
		check(panel._scroll.size.x <= panel.size.x and panel._body.size.x <= panel._scroll.size.x, page + " fits narrow width")
		check(panel._apply.get_global_rect().end.y <= panel.size.y, page + " keeps actions on screen")
	var s := Session.new()
	get_parent().add_child(s)
	s.is_host = false
	panel.open("options")
	for control in panel._controls:
		if control is HSlider:
			control.grab_focus()
			before = control.value
			panel.pad_press("right", "down")
			check(control.value == before and not control.editable, "guest controller cannot edit locked option")
	panel.close()
	s.free()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE; event.pressed = true
	panel.open()
	panel._input(event)
	check(not panel.visible, "Escape closes modal")
	var network := NetworkPanel.new()
	add_child(network)
	network.visible = true
	network._mods_button.pressed.emit()
	check(network.get_children().any(func(n): return n is ModPanel and n.visible), "lobby entry opens mod panel")
	network.free()
	var options := OptionsPanel.new()
	add_child(options)
	var background := Image.create(32,32,false,Image.FORMAT_RGB8)
	background.fill(Color.BLACK)
	options.open(background)
	var grass := GameData.option("gfx_grass")
	options._set_value("gfx_grass", 1-grass)
	options._show_group(OptionsPanel.REMAKE_GROUP)
	options._toggle(10)
	check(options._mods_panel != null and options._mods_panel.visible, "Options entry opens the common editor")
	check(GameData.option("gfx_grass") == grass, "opening mod settings does not apply pending graphics edits")
	options._mods_panel.close()
	check(options._values.gfx_grass == 1-grass, "returning preserves pending parent options")
	options.free()
	get_tree().root.size = Vector2i(1280,720)
	var menu := load("res://src/ui/main_menu.gd").new() as Control
	add_child(menu)
	await shot("mod-main-menu")
	menu._mods_button.pressed.emit()
	check(menu._mods.visible, "main menu opens profile manager")
	menu._mods._profile_name.text = "A new rules profile"
	menu._mods._create(false)
	menu._mods.close()
	check(menu._mods_button.text.contains("A new rules profile"), "main menu refreshes a newly created profile")
	await menu._on_board("new")
	check(menu._mods.visible and menu._mods._continue.visible, "New Game includes rules review")
	menu._mods._rules.difficulty = 1
	menu._mods._continue.pressed.emit()
	check(menu._difficulty.visible and menu._difficulty.level == 1, "rules choice reaches the original difficulty screen")
	menu.free()
	var owner := Session.new()
	get_parent().add_child(owner)
	var game := Game.new()
	game.session = owner; owner.game = game
	get_parent().add_child(game)
	game.hud.toggle_menu()
	await shot("mod-esc-menu")
	check(game.hud._mods_btn.get_global_rect().position.y >= 0 and game.hud._mods_btn.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "Esc entry is on screen")
	game.hud._mods_btn.pressed.emit()
	check(game.hud._mods_panel.visible, "Esc entry opens common editor")
	game.hud._mods_panel.close()
	game.free(); owner.free()
	var result := {"checks":checks, "failures":failures}
	ModStore.atomic_write("user://mod-menus-result.json", JSON.stringify(result).to_utf8_buffer())
	print("MOD_MENUS ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
