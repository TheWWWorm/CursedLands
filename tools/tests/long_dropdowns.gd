extends Node
## Exercise the real save/profile menus with enough entries to overflow at
## high UI scales, then reach and select the last entry using popup input.
var checks := 0
var failures := 0
var cases: Array = []
var panel: ModPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func scroll_in(node: Node) -> ScrollContainer:
	if node is ScrollContainer: return node
	for child in node.get_children(true):
		var found := scroll_in(child)
		if found: return found
	return null

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event)

func wheel(popup: PopupMenu, point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = Vector2(popup.position) + point * popup.content_scale_factor
	event.global_position = event.position
	get_viewport().push_input(event)

func last_visible(popup: PopupMenu, bar: VScrollBar) -> bool:
	# scroll_to_item reveals the row; the remaining half-separation is padding.
	return bar.value >= bar.max_value - bar.page - popup.get_theme_constant("v_separation") * 0.5 - 1

func exercise(choice: OptionButton, label: String) -> void:
	choice.select(choice.item_count - 1)
	choice.show_popup()
	await frames()
	var popup := choice.get_popup()
	var scroll := scroll_in(popup)
	check(scroll != null, label + " contains a scrolling list")
	if scroll == null: popup.hide(); return
	var bar := scroll.get_v_scroll_bar()
	check(last_visible(popup, bar), label + " first opening reveals a selection near the end")
	popup.hide()
	await frames()
	choice.select(0)
	choice.show_popup()
	await frames()
	var bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	check(bounds.encloses(Rect2(popup.position, popup.size)), label + " popup fits screen")
	check(bar.visible and bar.max_value > bar.page, label + " overflow has visible scrollbar")
	var parent_scroll := panel._scroll.scroll_vertical
	var point := scroll.get_global_rect().get_center()
	wheel(popup, point, true)
	await frames(2)
	check(bar.value > 0, label + " wheel scrolls popup entries")
	check(panel._scroll.scroll_vertical == parent_scroll, label + " wheel does not scroll underlying dialog")
	for i in 200: wheel(popup, point, false)
	await frames(2)
	check(bar.value == 0, label + " wheel reaches first entry")
	popup.set_focused_item(0)
	for i in choice.item_count - 1:
		key(KEY_DOWN)
		await frames(1)
	check(popup.get_focused_item() == choice.item_count - 1, label + " arrows reach final entry")
	check(last_visible(popup, bar), label + " focused final entry is visible")
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://dropdown-" + label + ".png")
	key(KEY_ENTER)
	await frames()
	check(choice.selected == choice.item_count - 1 and not popup.visible, label + " Enter selects final entry")
	choice.show_popup()
	await frames()
	check(last_visible(popup, bar), label + " reopening reveals current selection")
	cases.append({"label":label,"entries":choice.item_count,"size":str(popup.size),"position":str(popup.position),"content_scale":popup.content_scale_factor,"scroll_end":bar.value,"scroll_max":bar.max_value-bar.page})
	choice.select(0)
	for i in 200: wheel(popup, point, true)
	await frames()
	check(bar.value == bar.max_value - bar.page, label + " wheel reaches final entry")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(popup.position) + Vector2(point.x, scroll.get_global_rect().end.y - 16) * popup.content_scale_factor
	click.global_position = click.position
	click.pressed = true
	get_viewport().push_input(click)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click)
	await frames()
	check(not popup.visible and choice.selected == choice.item_count - 1, label + " mouse selects final scrolled entry")
	popup.hide()

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0}, true)
	RenderingServer.set_render_loop_enabled(true)
	await frames(15)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	check(ModStore.create_profile("Dropdown test").is_empty(), "create isolated profile")
	var base := CampaignProfile.save_directory(GameData.campaign_id)
	DirAccess.make_dir_recursive_absolute(base)
	for i in 64:
		var file := FileAccess.open(base.path_join("coop_worm_20261012_%06d.sav" % i), FileAccess.WRITE)
		file.store_string("UI list fixture; not a playable save")
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("171710")
	add_child(background)
	await frames()
	RemakeText.lang = "ru"
	panel = ModPanel.new()
	add_child(panel)
	for shape: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(540,960),Vector2i(800,600)]:
		get_window().size = shape
		panel.open("profiles")
		await frames()
		var saves: OptionButton
		for child in panel._body.get_children():
			if child is OptionButton: saves = child
		check(saves != null and saves.item_count == 64, "real copy-save menu contains all fixtures")
		if saves == null: continue
		panel._scroll.ensure_control_visible(saves)
		await frames()
		await exercise(saves, "%dx%d-saves" % [shape.x,shape.y])
		panel._scroll.ensure_control_visible(panel._chooser)
		await frames()
		panel._chooser.show_popup()
		await frames()
		check(panel._chooser.get_popup().size.y < 140 * panel._ui_scale, "short profile list stays compact at " + str(shape))
		panel._chooser.get_popup().hide()
	# A second opening after rotation/resizing must discard the former limits.
	get_window().size = Vector2i(1280,720)
	panel.open("profiles")
	await frames()
	for i in 40: panel._chooser.add_item("Profile %02d" % i)
	panel._scroll.ensure_control_visible(panel._chooser)
	await frames()
	await exercise(panel._chooser, "1280x720-profiles")
	panel._chooser.show_popup()
	await frames()
	get_window().size = Vector2i(540,960)
	await frames()
	check(not panel._chooser.get_popup().visible, "resize closes popup with stale geometry")
	panel._chooser.show_popup()
	await frames()
	check(Rect2(Vector2.ZERO,Vector2(540,960)).encloses(Rect2(panel._chooser.get_popup().position,panel._chooser.get_popup().size)), "reopened popup fits after resize")
	panel.free()
	print("LONG_DROPDOWNS ",JSON.stringify({"checks":checks,"failures":failures,"cases":cases}))
	get_tree().quit(1 if failures else 0)
