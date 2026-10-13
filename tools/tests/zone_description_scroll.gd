extends Node
## Native localized zone text, actual GUI wheel dispatch and original bars.
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame
func mouse(at: Vector2, button: int, pressed := true) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = at
	Input.parse_input_event(motion)
	var e := InputEventMouseButton.new(); e.position = at; e.button_index = button; e.pressed = pressed
	Input.parse_input_event(e)
	await frames(1)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + label + ".png")
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0,"net_lan":0,"net_directory":0,"net_upnp":0,"show_tutorial":0},true)
	GameData._window_gen += 1; get_window().mode = Window.MODE_WINDOWED
	RenderingServer.set_render_loop_enabled(true)
	var s := Session.new(); add_child(s); s.state = CampaignState.new()
	s.state.set_var(0, "q.gz12k.q44k", 1)
	var panel := ZoneObjectives.new(); panel.setup(s, "gz12k", [], true, "field"); add_child(panel)

	for shape: Vector2i in [Vector2i(1280,720), Vector2i(1280,1024), Vector2i(3840,2160)]:
		get_window().size = shape; await frames(8); panel._fill("gz12k", []); await frames(4)
		var label := panel._zone_desc; var sb := label.get_v_scroll_bar(); var bar := panel._zone_bar
		var tag := RemakeText.lang + "-" + str(shape.x) + "x" + str(shape.y)
		print("ZONE_DESCRIPTION ", tag, " ", panel._title, " ", panel._text)
		check(label.get_parsed_text() == panel._text and panel._text.length() > 200, tag + " complete original zone text")
		check(panel._r(Rect2(410,380,340,140)).encloses(label.get_rect()), tag + " description fits inside frame")
		if bar.max_pos == 0:
			check(label.get_content_height() <= label.size.y and sb.value == 0, tag + " short translation fits without scrollbar")
			await mouse(label.position + label.size * .5, MOUSE_BUTTON_WHEEL_DOWN)
			check(sb.value == 0, tag + " fitting text does not scroll")
			await capture("zone-description-fit-" + tag)
			continue
		check(bar.max_pos > 0 and sb.value == 0, tag + " overflowing translation starts at top with scrollbar")
		await capture("zone-description-top-" + tag)
		var quest_pos := panel._desc.get_v_scroll_bar().value
		var at := label.position + label.size * .5
		await mouse(at, MOUSE_BUTTON_WHEEL_DOWN)
		check(sb.value > 0 and panel._desc.get_v_scroll_bar().value == quest_pos, tag + " real wheel scrolls only hovered description")
		await mouse(at, MOUSE_BUTTON_WHEEL_UP)
		check(sb.value == 0, tag + " wheel returns to top")
		await frames(3)
		# Drag the original thumb through the real parent GUI handler.
		await mouse(panel._p(bar.thumb_rect().get_center()), MOUSE_BUTTON_LEFT)
		var drag := InputEventMouseMotion.new(); drag.position = panel._p(Vector2(bar.rect.end.x - 5,bar.rect.end.y - 26)); drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(drag); await frames(2)
		await mouse(drag.position, MOUSE_BUTTON_LEFT, false)
		check(absf(sb.value - (sb.max_value - sb.page)) <= 1.0, tag + " scrollbar drag reaches final line")
		await capture("zone-description-end-" + tag)
		await mouse(at, MOUSE_BUTTON_WHEEL_DOWN)
		check(absf(sb.value - (sb.max_value - sb.page)) <= 1.0, tag + " wheel clamps at end")
		await mouse(panel._p(bar.up_rect().get_center()), MOUSE_BUTTON_LEFT)
		panel._process(.5); await frames(2)
		await mouse(panel._p(bar.up_rect().get_center()), MOUSE_BUTTON_LEFT, false)
		check(sb.value < sb.max_value - sb.page, tag + " held original arrow scrolls text")
		panel._desc.text = panel.description("q44k").repeat(4); await frames(4)
		var zone_pos := sb.value
		await mouse(panel._desc.position + panel._desc.size * .5, MOUSE_BUTTON_WHEEL_DOWN)
		check(panel._desc.get_v_scroll_bar().value > 0 and sb.value == zone_pos, tag + " quest wheel remains independent")
		panel._fill("gz11k", []); await frames(4)
		check(sb.value == 0 and bar.held == 0, tag + " changing zone resets text and held scrollbar")
		label.clear(); label.add_text(panel._title); await frames(4)
		check(bar.max_pos == 0, tag + " fitting text hides scrollbar")
	panel.queue_free(); s.queue_free(); await frames(); TexUpscale.shutdown()
	print("ZONE_DESCRIPTION_SCROLL ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
