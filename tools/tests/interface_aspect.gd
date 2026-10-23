extends Node
## Render the affected menus with original localized archives. Run once per
## edition using --ei-path and an isolated profile; screenshots go to user://.
class SafePanel extends Interface800:
	var bounds := Rect2()
	func _safe() -> Rect2:
		return bounds

var checks := 0
var failures: Array[String] = []
var tag := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(tag + " " + label)
		printerr("FAIL ", tag, " ", label)

func frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func shot(label: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://aspect-" + tag + "-" + label + ".png") == OK, "capture " + label)

func click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	Input.parse_input_event(move)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TutorialPanel.auto_show = false
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"show_tutorial":0,"pad_enabled":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	RenderingServer.set_render_loop_enabled(true)
	var background := ColorRect.new()
	background.color = Color(0.12, 0.18, 0.15)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	for shape: Vector2i in [Vector2i(1152,864), Vector2i(1920,1080), Vector2i(2560,1080), Vector2i(960,1200)]:
		get_window().size = shape
		await frames(8)
		tag = RemakeText.lang + "-%dx%d" % [shape.x, shape.y]
		await character_screen()
		await options_screen()
		await pause_screen()
		await dialogue_screen()
		await objectives_screen()
	await touch_zoom()
	print("INTERFACE_ASPECT ", JSON.stringify({"checks":checks,"failures":failures,"language":RemakeText.lang}))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)

func character_screen() -> void:
	var panel := MpCharPanel.new()
	add_child(panel)
	panel.open()
	panel._press(["new"])
	await frames(8)
	check(panel.state == MpCharPanel.CREATE and panel._cells.size() == 14, "character creation loads original faces")
	for portrait: Portrait in panel._cells:
		if portrait.visible:
			check(is_equal_approx(portrait.size.x, portrait.size.y), "portrait cell remains square")
	var authored := panel._doll.camp_rect().size
	check(is_equal_approx(panel._doll.size.x / authored.x, panel._doll.size.y / authored.y), "creation preview retains its authored projection")
	var before := int(panel._hero().str)
	await click(panel.p8(Vector2(145, 170)))
	check(int(panel._hero().str) == before - 1, "attribute click follows fitted geometry")
	await click(panel.p8(Vector2(165, 170)))
	check(int(panel._hero().str) == before, "attribute increase uses matching fitted hit target")
	await shot("character")
	var centre := panel.p8(Vector2(400,300))
	panel.touch_transform(PackedVector2Array([centre-Vector2(100,0),centre+Vector2(100,0)]),
		PackedVector2Array([centre-Vector2(110,0),centre+Vector2(110,0)]))
	check(panel._doll.get_rect().is_equal_approx(panel.r8(panel._doll.camp_rect())), "pinch keeps the character preview aligned with its artwork")
	check(panel._cells[0].get_rect().is_equal_approx(panel.r8(Rect2(65,15,70,70))), "pinch keeps face buttons aligned with their artwork")
	panel._touch_zoom = 1.0
	panel._touch_pan = Vector2.ZERO
	panel._layout()
	panel._hero().name = "Test"
	panel._next_from_create()
	await frames(6)
	check(panel.state == MpCharPanel.KIT, "character creation advances to equipment and skills")
	for item: ItemView in panel._items.values():
		if item.visible:
			check(is_equal_approx(item.size.x, item.size.y), "equipment cell remains square")
	check(panel.r8(Rect2(0,0,800,600)).get_center().is_equal_approx(panel.size * 0.5), "opaque character frame is centred")
	await shot("skills")
	panel._close(false)
	panel.free()
	await frames()

func options_screen() -> void:
	var panel := OptionsPanel.new()
	add_child(panel)
	panel.open()
	panel._show_group(OptionsPanel.SCREEN_GROUP)
	await get_tree().create_timer(0.6).timeout
	await frames()
	var frame := panel.r8(Rect2(0,0,800,600))
	check(panel._board.get_rect().is_equal_approx(frame), "options board follows the same fitted frame as controls")
	check(is_equal_approx(panel.kv().x, panel.kv().y), "options artwork and fonts use one scale")
	for picker: OptionButton in panel._screen_pickers.values():
		if picker.visible:
			check(frame.encloses(picker.get_rect()), "screen dropdown stays inside fitted options")
	for group in panel._group_count():
		var label := panel._group_label(OptionsPanel.TAB_ORDER[group])
		check(Interface800.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			panel.group_font_px(OptionsPanel.TAB_ORDER[group])).x <= panel.r8(Rect2(0,0,122,20)).size.x + 1,
			"localized tab fits: " + label)
	await shot("options")
	var closed := [false]
	panel.closed.connect(func(): closed[0] = true)
	await click(panel.p8(OptionsPanel.CANCEL_RECT.get_center()))
	check(closed[0] and not panel.visible, "options Cancel is clickable at its drawn position")
	panel.free()
	await frames()

func pause_screen() -> void:
	var panel := EscSignpost.new()
	add_child(panel)
	await frames(8)
	panel._play("cidle")
	await frames(3)
	var frame := Interface800.fit_rect(Rect2(Vector2.ZERO, panel.size))
	check(is_equal_approx(float(panel._vp.size.x) / panel._vp.size.y, 4.0 / 3.0), "pause menu renders a 4:3 signpost")
	check(panel.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "pause menu displays the signpost without stretching")
	var picked: Array = []
	panel.pressed.connect(func(action): picked.append(action))
	for i in panel._rects.size():
		var native := panel._rects[i]
		if not native.has_area(): continue
		var at := frame.position + native.get_center() * frame.size / Vector2(800,600)
		check(panel.board_at(at) == panel.REG[i][1], "pause board hit follows its fitted position")
		await click(at)
		check(not picked.is_empty() and picked.back() == panel.BOARDS[panel.REG[i][1]], "pause board receives actual click")
	for target: Dictionary in panel.pad_targets():
		check(frame.encloses(target.rect), "pause gamepad target stays inside fitted frame")
	await shot("pause")
	panel.free()
	await frames()

func dialogue_screen() -> void:
	var panel := DialogPanel.new()
	add_child(panel)
	panel._mode = DialogPanel.LAST
	panel.visible = true
	var source := GameData.text("zone gz12k").strip_edges()
	check(not source.is_empty(), "original localized dialogue fixture text exists")
	panel._append_phrase(GameData.text("pers elder").get_slice("\n",0), source.repeat(4), DialogPanel.TEXT_COLOR)
	panel._relayout()
	panel._bar.set_pos(0)
	await frames(4)
	check(is_equal_approx(panel._kv().x, panel._kv().y), "dialogue scrollbar retains its authored proportions")
	check(panel._r(DialogPanel.TEXT_BOX).encloses(panel._view.get_rect()), "dialogue text lies inside the original box")
	check(panel._bar.max_pos > 0, "long localized dialogue has a scrollbar")
	var bar := panel._bar
	var down := InputEventMouseButton.new()
	down.pressed = true
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = panel._p(bar.thumb_rect().get_center())
	panel._gui_input(down)
	var move := InputEventMouseMotion.new()
	move.position = panel._p(Vector2(bar.rect.end.x-5, bar.rect.end.y-26))
	panel._gui_input(move)
	down.pressed = false
	panel._gui_input(down)
	check(is_equal_approx(bar.pos, bar.max_pos), "dialogue thumb drag reaches the final line at fitted coordinates")
	await shot("dialogue")
	var topics := DialogPanel.TopicList.new()
	add_child(topics)
	topics.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	topics.rows = [source.get_slice("\n",0)]
	await frames()
	check(topics._row_rect(0).position.is_equal_approx(panel._p(Vector2(210,440))), "topic input and dialogue use the same fitted origin")
	check(topics._index_at(topics._row_rect(0).get_center()) == 0, "topic row remains clickable")
	topics.free()
	panel.free()
	await frames()

func objectives_screen() -> void:
	var session := Session.new()
	add_child(session)
	session.state = CampaignState.new()
	session.state.set_var(0,"q.gz12k.q44k",1)
	var panel := ZoneObjectives.new()
	panel.setup(session,"gz12k",[],true,"field")
	add_child(panel)
	await frames(6)
	check(is_equal_approx(panel._kv().x, panel._kv().y), "objectives map and frame have equal axis scales")
	check(panel._r(Rect2(410,380,340,140)).encloses(panel._zone_desc.get_rect()), "objective description stays in its fitted panel")
	check(panel._hit(panel._r(panel.BTN_CLOSE[0]).get_center()) == ["close"], "objectives Close hit follows its drawn position")
	check(panel._r(Rect2(0,0,800,600)).get_center().is_equal_approx(panel.size * 0.5), "objectives frame is centred")
	await shot("objectives")
	# Original translations can fit completely after the aspect correction.
	# Extend the real text to exercise the painted scrollbar's GUI routing too.
	panel._desc.text = panel.description("q44k").repeat(8)
	await frames(4)
	var bar := panel._desc_bar
	check(bar.max_pos > 0, "extended localized objective text scrolls")
	var down := InputEventMouseButton.new()
	down.pressed = true
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = panel._p(bar.thumb_rect().get_center())
	Input.parse_input_event(down)
	await frames(1)
	var move := InputEventMouseMotion.new()
	move.position = panel._p(Vector2(bar.rect.end.x-5, bar.rect.end.y-26))
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await frames(2)
	down.pressed = false
	down.position = move.position
	Input.parse_input_event(down)
	await frames(2)
	check(absf(panel._desc.get_v_scroll_bar().value - bar.max_pos) <= 1.0,
		"actual pointer drag reaches final objective line at fitted coordinates")
	panel.free()
	session.free()
	await frames()

func touch_zoom() -> void:
	var panel := SafePanel.new()
	add_child(panel)
	panel.size = Vector2(2560,1080)
	panel.bounds = Portability.inset_rect(panel.size, Vector4(0.06,0.02,0.03,0.04), true)
	var centre := panel._safe().get_center()
	var fitted := panel.r8(Rect2(0,0,800,600))
	check(panel.bounds.encloses(fitted), "interface fits inside asymmetric cutout and home-indicator insets")
	check(fitted.get_center().is_equal_approx(centre), "safe-area interface remains centred")
	var before := PackedVector2Array([centre - Vector2(100,0),centre + Vector2(100,0)])
	var after := PackedVector2Array([centre - Vector2(150,0),centre + Vector2(150,0)])
	panel.touch_transform(before, after)
	check(panel.p8(Vector2(400,300)).is_equal_approx(centre), "pinch preserves the interface point under its centre")
	check(is_equal_approx(panel.kv().x,panel.kv().y), "pinch retains uniform proportions")
	check(is_zero_approx(panel._touch_pan.x), "pinch does not pan into unused widescreen margin")
	var projected := panel.p8(Vector2(620,430))
	check(panel.to800(projected).is_equal_approx(Vector2(620,430)), "zoomed drawing and hit test round trip")
	panel.free()
