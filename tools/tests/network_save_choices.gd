extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
func key(code: Key) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.pressed = true
	get_viewport().push_input(e)
	e = e.duplicate(); e.pressed = false; get_viewport().push_input(e)
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0},true)
	RenderingServer.set_render_loop_enabled(true)
	await frames(15)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	var state := CampaignState.new(); state.ensure_hero(0,"Human Hero")
	state.current_zone = "gz1g"
	for i in 64:
		var slot := "coop_fixture_%02d" % i
		state.save(SaveInfo.path(slot))
		SaveInfo.write(slot,12,"gipat","gz1g","Приключение %02d — сохранение героя" % i)
	RemakeText.lang = "ru"
	var panel := NetworkPanel.new(); add_child(panel); panel.show()
	for shape: Vector2i in [Vector2i(1280,720),Vector2i(3840,2160),Vector2i(800,600)]:
		get_window().size = shape
		for page in [NetworkPanel.HOST_COOP,NetworkPanel.JOIN_COOP]:
			panel.show_page(page); await frames()
			var choice := panel._save_choice
			check(choice.visible and choice.item_count == (65 if page == NetworkPanel.HOST_COOP else 66), "all saves listed for " + str(page))
			choice.show_popup(); await frames()
			var popup := choice.get_popup()
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(popup.position,popup.size)), "dropdown fits " + str(shape))
			popup.set_focused_item(0)
			for i in choice.item_count - 1: key(KEY_DOWN)
			await frames()
			check(popup.get_focused_item() == choice.item_count - 1, "keyboard reaches last save")
			if DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png("user://network-%d-%dx%d.png" % [page,shape.x,shape.y])
			key(KEY_ENTER); await frames()
			var slot: String = choice.get_item_metadata(choice.item_count - 1)
			check((panel.start_slot if page == NetworkPanel.HOST_COOP else CoopProgress.bring_slot) == slot, "selected row supplies original slot id")
			check(not popup.visible, "selection closes dropdown")
			choice.show_popup(); await frames()
			panel.hosting = page == NetworkPanel.HOST_COOP
			panel.joining = page == NetworkPanel.JOIN_COOP
			await frames()
			check(choice.disabled and not popup.visible, "connection locks and closes save choice")
			panel._save_selected(0)
			check((panel.start_slot if page == NetworkPanel.HOST_COOP else CoopProgress.bring_slot) == slot, "locked choice cannot change slot")
			panel.hosting = false; panel.joining = false
	panel.show_page(NetworkPanel.MODES); await frames()
	check(not panel._save_choice.visible, "mode picker has no stray save dropdown")
	panel.free()
	print("NETWORK_SAVE_CHOICES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
