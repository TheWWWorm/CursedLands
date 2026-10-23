extends Node
## Phone routing for the Screen dropdowns (1.22.0 made Resolution and Render
## scale dropdowns): a finger tap must open the list and a second tap must
## choose an entry. Run with --touch so TouchInput owns the gestures.
var checks := 0
var failures := 0
var panel: OptionsPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func tap(point: Vector2, hold := 0.0) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await frames(1)
		if down and hold > 0.0: await get_tree().create_timer(hold).timeout
	await frames(3)

## The centre of entry `i` of an open popup, in viewport coordinates.
func item_point(popup: PopupMenu, i: int) -> Vector2:
	var scroll := scroller(popup)
	var content := scroll.get_child(0, true) as Control
	var row_h := content.size.y / popup.item_count
	var y := scroll.get_global_rect().position.y + row_h * (i + 0.5) - scroll.scroll_vertical
	return Vector2(popup.position) + Vector2(popup.size.x * 0.5, y * popup.content_scale_factor)

func scroller(popup: PopupMenu) -> ScrollContainer:
	return TouchInput._popup_scroller(popup)

func drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = from
	Input.parse_input_event(down)
	await frames(1)
	for k in range(1, 11):
		var move := InputEventScreenDrag.new()
		move.position = from.lerp(to, k / 10.0)
		move.relative = (to - from) / 10.0
		Input.parse_input_event(move)
		await frames(1)
	var up := InputEventScreenTouch.new()
	up.position = to
	Input.parse_input_event(up)
	await frames(3)

func _ready() -> void:
	TutorialPanel.auto_show = false
	await frames(5)
	# Also run at a large screen (RES=1920x1080): the lists are scaled up there.
	print("touch enabled=", TouchInput.enabled, " screen=", DisplayServer.screen_get_size(), " choices=", GameData.option_choices("resolution"))
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		for name: String in ["resolution", "render_scale"]:
			GameData.set_options({name: 0 if name == "resolution" else 4})
			panel = OptionsPanel.new()
			add_child(panel)
			panel.open()
			await get_tree().create_timer(0.7).timeout
			panel._show_group(OptionsPanel.SCREEN_GROUP)
			await frames(3)
			var picker: OptionButton = panel._screen_pickers[name]
			check(picker.visible and picker.item_count > 1, language + " " + name + " has choices (%d)" % picker.item_count)
			var before := int(GameData.option(name))
			await tap(picker.get_global_rect().get_center())
			var popup := picker.get_popup()
			check(popup.visible, language + " tapping the " + name + " dropdown opens it")
			print("popup scale ", popup.content_scale_factor)
			if popup.visible:
				get_viewport().get_texture().get_image().save_png("user://mobile-" + name + "-" + language + ".png")
				var scroll := scroller(popup)
				var target := 1 if before != 1 else 2
				await tap(item_point(popup, target))
				check(not popup.visible, language + " " + name + " list closes after a choice")
				check(int(panel._values.get(name, -1)) == target, language + " the tapped " + name + " entry is chosen (%s)" % panel._values.get(name))
				await tap(picker.get_global_rect().get_center())
				check(popup.visible, language + " list reopens")
				await tap(Vector2(20, get_viewport().get_visible_rect().size.y - 20))
				check(not popup.visible, language + " a tap outside closes the list")
			await frames(3)
			print(language, " ", name, " before=", before, " after=", GameData.option(name), " panel=", panel._values.get(name))
			check(int(panel._values.get(name, before)) != before, language + " tapping an entry changes " + name)
			popup.hide()
			panel.queue_free()
			await frames(3)
	RemakeText.lang = "en"
	await long_list()
	print("MOBILE_SCREEN_DROPDOWN ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)

## Any dropdown longer than the screen scrolls under a finger; a drag never
## chooses, a following tap does.
func long_list() -> void:
	var picker := ScrollOptionButton.new()
	for i in 40: picker.add_item("Entry %d" % i, i)
	picker.position = Vector2(200, 40)
	picker.size = Vector2(240, 30)
	add_child(picker)
	await frames(2)
	await tap(picker.get_global_rect().get_center())
	var popup := picker.get_popup()
	check(popup.visible, "long list opens by touch")
	var scroll := scroller(popup)
	check(scroll.get_v_scroll_bar().max_value > scroll.size.y + 1, "long list is taller than the screen")
	var area := Rect2(popup.position, popup.size)
	var low := area.position + area.size * Vector2(0.5, 0.8)
	var high := area.position + area.size * Vector2(0.5, 0.2)
	await drag(low, high)
	check(popup.visible and scroll.scroll_vertical > 0, "a finger drag scrolls the list (%d)" % scroll.scroll_vertical)
	check(picker.selected == 0, "scrolling does not choose an entry")
	var first := scroll.scroll_vertical
	await drag(high, low)
	check(scroll.scroll_vertical < first, "dragging down scrolls back")
	var target := 20
	for i in 8:
		if area.grow(-area.size.y * 0.1).has_point(item_point(popup, target)): break
		await drag(low, high)
	check(area.has_point(item_point(popup, target)), "entry %d scrolled into view" % target)
	get_viewport().get_texture().get_image().save_png("user://mobile-long-list.png")
	await tap(item_point(popup, target))
	check(not popup.visible and picker.selected == target, "tapping a scrolled entry chooses it (%d)" % picker.selected)
	picker.queue_free()
