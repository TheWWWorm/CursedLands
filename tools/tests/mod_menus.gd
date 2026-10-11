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
	network._setup_button.pressed.emit()
	check(network.get_children().any(func(n): return n is DifficultyPanel and n.visible and not n._mods.visible), "lobby opens setup without opening mods")
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
	check(options._game_setup != null and options._game_setup.visible and not options._game_setup._mods.visible, "Options opens game setup")
	options._game_setup._mods_button.pressed.emit()
	check(options._game_setup._mods.visible, "only the setup button opens mods")
	check(GameData.option("gfx_grass") == grass, "opening setup does not apply pending graphics edits")
	options._game_setup._mods.close()
	options._game_setup._cancel()
	check(options._values.gfx_grass == 1-grass, "returning preserves pending parent options")
	options.free()
	get_tree().root.size = Vector2i(1280,720)
	panel.close()
	var menu := load("res://src/ui/main_menu.gd").new() as Control
	add_child(menu)
	await shot("main-menu")
	var before_rules: Dictionary = ModStore.effective().rules.duplicate(true)
	check(ModStore.apply_rules({"difficulty":1,"revive":0,"auto_exit":1}) == "", "seed nondefault previous run")
	var prior: Dictionary = ModStore.effective().rules.duplicate(true)
	await menu._on_board("new")
	var setup: DifficultyPanel = menu._difficulty
	check(setup.visible and not setup._mods.visible, "New Game opens setup directly, without mods")
	check(setup.level == 0 and setup._draft.rules.revive == 1 and setup._draft.rules.auto_exit == 0, "new campaign resets difficulty and rule draft to defaults")
	check(ModStore.effective().rules == prior, "opening setup does not change saved settings")
	await shot("game-setup")
	setup._mods_button.pressed.emit()
	setup._mods._rules.difficulty = 1
	setup._mods._rules.revive = 1
	check(setup._mods._accept(), "apply optional changes to new-game draft")
	setup._mods.close()
	check(setup.level == 1 and setup._draft.rules.revive == 1, "mod draft and setup difficulty stay in sync")
	check(ModStore.effective().rules == prior, "draft changes do not leak into preferences")
	setup._cancel()
	await menu._on_board("new")
	check(setup.level == 0 and setup._draft.rules.revive == 1, "cancelled customizations are not reused on another New Game")
	for viewport in [Vector2i(2560,1440), Vector2i(800,600), Vector2i(540,960)]:
		get_tree().root.size = viewport
		await shot("setup-%dx%d" % [viewport.x,viewport.y])
		check(Rect2(Vector2.ZERO, Vector2(viewport)).encloses(setup._surface.get_global_rect()), "setup stays inside viewport " + str(viewport))
		setup._mods_button.pressed.emit()
		await shot("rules-%dx%d" % [viewport.x,viewport.y])
		check(setup._mods._surface.get_global_rect().end.y <= viewport.y, "mod actions stay inside viewport " + str(viewport))
		check(setup._mods._body.size.x <= setup._mods._scroll.size.x, "rules fit viewport " + str(viewport))
		if viewport.x == 2560: check(setup._mods._ui_scale > 1.7, "1440p uses readable scaled text and controls")
		setup._mods.close()
	setup._cancel()
	menu.free()
	ModStore.apply_rules(before_rules)
	var owner := Session.new()
	get_parent().add_child(owner)
	var game := Game.new()
	game.session = owner; owner.game = game
	get_parent().add_child(game)
	check(not game.hud.visible, "HUD is hidden before a world exists")
	for i in 4: await get_tree().process_frame
	check(not game.hud.visible, "empty HUD stays hidden across rendered frames")
	game.free(); owner.free()
	var result := {"checks":checks, "failures":failures}
	ModStore.atomic_write("user://mod-menus-result.json", JSON.stringify(result).to_utf8_buffer())
	print("MOD_MENUS ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
