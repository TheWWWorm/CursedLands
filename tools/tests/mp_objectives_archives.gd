extends "arena_expansion_ui.gd"
## Original .mq text, quest.reg places and live objective states in the TAB
## screen. Run separately against each localized edition's original archives.

func _ready() -> void:
	OS.add_logger(errors)
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0}, true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	var s := Session.new()
	add_child(s)
	s.set_physics_process(false)
	s.lmp = {"base":"bz1mpg", "quest":"z3q2"}
	var panel := ZoneObjectives.new()
	panel.setup(s, "z3q2", [], false, "field")
	add_child(panel)
	await frames(4)
	var count := 0
	for q: Dictionary in SideQuests.all():
		var id := String(q.id)
		var doc := SideQuests.text("quest " + id)
		check(not doc.is_empty(), id + " supplies authored quest text")
		check(SideQuests.quest_doc(id) == doc, id + " resolves its installed archive")
		var places := SideQuests.quest_places(id)
		check(not places.is_empty(), id + " supplies quest.reg markers")
		s.state.vars.clear()
		s.state.set_var(0, "q.%s.%s" % [id, id], 1)
		var lines := doc.split("\n")
		for line: String in lines:
			if line.strip_edges().begins_with("#subobj"):
				s.state.set_var(0, "q.%s.%s.%s" % [id, id, line.substr(7).strip_edges()], 1)
		panel._fill(id, [])
		check(panel.quests == PackedStringArray([id]), id + " appears in the actual objectives list")
		check(panel._desc.get_parsed_text().contains(ZoneObjectives._paragraph(lines, 1)), id + " shows its original description")
		check(panel._areas.size() == places.size(), id + " draws every authored marker")
		for i in places.size():
			check(panel._areas[i].is_equal_approx(panel._zone_point(places[i])), id + " projects marker %d onto its own map" % i)
		for i in lines.size():
			if lines[i].strip_edges().begins_with("#subobj") and i + 1 < lines.size():
				check(panel._desc.get_parsed_text().contains(lines[i + 1].strip_edges()), id + " includes active subobjective " + lines[i])
		count += 1
	check(count == 28, "all 28 original multiplayer quest archives were exercised")
	check(SideQuests.quest_places("z3q2") == PackedVector2Array([Vector2(240,210)]), "reported z3q2 marker retains its original coordinates")
	check(SideQuests.quest_places("z12q1").size() == 2, "array-valued questplaces retains both markers")
	check(SideQuests.quest_places("z13q1")[0].y == 239.75, "fractional marker coordinates are retained")
	check(SideQuests.quest_places("missing_archive").is_empty(), "missing quest metadata does not invent a marker")
	# The report's visible screen, with the actual quest state transitions.
	s.state.vars.clear()
	s.state.set_var(0, "q.z3q2.z3q2", 1)
	s.state.set_var(0, "q.z3q2.z3q2.1", 1)
	panel._fill("z3q2", [])
	var first := panel._desc.get_parsed_text()
	var original := SideQuests.quest_doc("z3q2")
	check(original == WikiQuestText.TEXTS["quest z3q2"][RemakeText.lang], "reported quest uses original " + RemakeText.lang + " translation")
	check(not first.contains(ZoneObjectives._str("obj_completed")), "unfinished objective has no completed label")
	s.state.set_var(0, "q.z3q2.z3q2.1", 2)
	s.state.set_var(0, "q.z3q2.z3q2.2", 1)
	panel._select(0)
	check(panel._desc.get_parsed_text().contains(ZoneObjectives._str("obj_completed")), "completion state appears on the original objective")
	if DisplayServer.get_name() != "headless":
		panel.set_process(false)
		panel._t = 0.0
		panel.queue_redraw()
		await frames(8)
		await RenderingServer.frame_post_draw
		var marked := get_viewport().get_texture().get_image()
		var areas := panel._areas
		var marker := Rect2i(panel._r(Rect2(areas[0] - Vector2(10,10), Vector2(20,20))))
		panel._areas = PackedVector2Array()
		panel.queue_redraw()
		await frames(3)
		await RenderingServer.frame_post_draw
		var unmarked := get_viewport().get_texture().get_image()
		var changed := 0
		for y in range(marker.position.y, marker.end.y):
			for x in range(marker.position.x, marker.end.x):
				if marked.get_pixel(x,y) != unmarked.get_pixel(x,y):
					changed += 1
		check(changed > 8, "quest cross produces visible pixels at its authored map location")
		panel._areas = areas
		panel.queue_redraw()
		await shot("mp-objectives-" + RemakeText.lang)
	# Campaign coordinates still win when an explicit map.txt record exists.
	s.campaign.quest_areas["z3q2"] = PackedVector2Array([Vector2(20, 30)])
	panel._select(0)
	check(panel._areas == PackedVector2Array([panel._zone_point(Vector2(20,30))]), "explicit map markers keep precedence over the archive fallback")
	s.campaign.quest_areas.erase("z3q2")
	var saved: Dictionary = SideQuests._by_id["z3q2"]
	var fixture: Dictionary = saved.duplicate(true)
	fixture.reg.quest.questplaces = ["broken", "{1;no}", "{1;2;3}", "{ -12.5 ; 40 }", "{nan;2}"]
	SideQuests._by_id["z3q2"] = fixture
	check(SideQuests.quest_places("z3q2") == PackedVector2Array([Vector2(-12.5,40)]), "malformed mod metadata is ignored without discarding valid coordinates")
	SideQuests._by_id["z3q2"] = saved
	panel.queue_free()
	s.queue_free()
	await frames(4)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("MP_OBJECTIVES_ARCHIVES ", JSON.stringify({"language":RemakeText.lang,"checks":checks,"failures":failures,"archives":count}))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
