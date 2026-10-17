extends Node
const MainMenu = preload("res://src/ui/main_menu.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame
func shot(name: String) -> void:
	await frames(); await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://menu-wiki-" + name + ".png")
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lang="): RemakeText.lang = arg.get_slice("=", 1)
	GameData.options.confine_mouse = 0
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	await frames()
	var wanted := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-size="):
			var parts := arg.get_slice("=",1).split(","); wanted = Vector2i(int(parts[0]), int(parts[1]))
	get_window().size = wanted
	get_window().position = DisplayServer.screen_get_usable_rect().position + Vector2i(100, 100)
	await frames()
	var menu := MainMenu.new(); menu.detect_graphics = false; add_child(menu)
	await frames(20)
	check(menu._arena_pve_button.visible and menu._arena_pve_button.text == RemakeText.t("Trials of the Allods"), "original campaign has renamed Trials button")
	check(menu.campaign_pad_targets().any(func(t): return t.id == "campaign_arena_pve"), "original controller can reach Trials")
	check(menu._utility_bar.position.y > wanted.y * 0.8, "utility buttons sit at the bottom")
	check(is_equal_approx(menu._mods_button.position.y, menu._arena_pve_button.position.y), "utility buttons share one row")
	var at := menu._arena_pve_button.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion)
	GameData._tips.delay = 0.05
	for attempt in 12:
		Input.warp_mouse(at); Input.parse_input_event(motion.duplicate())
		await frames(3)
		if GameData._tips._panel.visible: break
	check(GameData._tips._panel.visible, "menu hint appears on hover")
	check(GameData._tips._fs() <= 32 and GameData._tips._panel.size.x <= 665, "menu hint has bounded font and measure")
	await shot("tooltip")
	var key := InputEventKey.new(); key.keycode = KEY_F7; key.physical_keycode = KEY_F7; key.pressed = true
	get_viewport().push_input(key); await frames(20)
	check(menu._wiki.visible, "F7 opens the wiki from the main menu")
	check(menu._utility_bar.get_child_count() == 2, "standalone wiki button is removed")
	var panel: WikiPanel = menu._wiki
	panel.navigate("creature/toadm2"); await frames()
	check(Rect2(Vector2.ZERO, Vector2(wanted)).encloses(panel.get_global_rect()), "wiki fits physical viewport")
	check(panel._results._buttons.size() < 40, "wiki only renders visible search results")
	var gap := panel._actions.get_theme_constant("h_separation")
	check(gap >= 8 and panel._sidebar.get_child(1) is HFlowContainer, "wiki navigation wraps with deliberate gaps")
	for group: Control in [panel._sidebar.get_child(0), panel._sidebar.get_child(1), panel._actions]:
		var buttons := group.get_children().filter(func(c): return c is Button and c.visible)
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				check(not buttons[i].get_global_rect().grow(2).intersects(buttons[j].get_global_rect().grow(2)), "navigation buttons do not touch")
	await shot("article")
	panel.dismiss(); menu.queue_free(); await frames()
	# Availability depends on the selected campaign, including fallback menus.
	var root := GameData.root; var campaign := GameData.campaign_id
	GameData.root = ""; GameData.campaign_id = CampaignProfile.ASTRAL
	menu = MainMenu.new(); menu.detect_graphics = false; add_child(menu); await frames()
	check(not menu._arena_pve_button.visible, "Lost in Astral has no Trials entry")
	check(not menu.campaign_pad_targets().any(func(t): return t.id == "campaign_arena_pve"), "hidden Trials has no controller target")
	menu.queue_free(); await frames()
	GameData.root = root; GameData.campaign_id = campaign
	print("MENU_WIKI_UI ", RemakeText.lang, " ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
