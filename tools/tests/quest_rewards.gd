extends Node
## Original quest database, objective text, and real QuestComplete accounting.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"show_tutorial":0,"net_lan":0,"net_directory":0,"net_upnp":0}, true)
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var s := Session.new()
	add_child(s)
	s.set_physics_process(false)
	s.state = CampaignState.new()
	s.state.ensure_hero(0, "Human Hero")
	s.state.money = 321
	var q := "q3h" if astral else "q6g"
	var row := GameData.db.find("quests", q)
	if astral:
		# Independent values from the original .qdb float fields and native
		# objectives 57aed0 (record +0xc experience, +0x14 promised money).
		for expected: Array in [["q3h",230.0,10.0],["q8h",130.0,40.0],["q6g",1500.0,550.0]]:
			var record := GameData.db.find("quests", expected[0])
			check(record.money == expected[1], "%s has its original promised money" % expected[0])
			check(record.experience == expected[2], "%s retains its original experience" % expected[0])
	else:
		check(GameData.db.table("quests").all(func(r): return float(r.get("money",0)) == 0.0),
			"base campaign's zero promised-money fields stay zero")
	var panel := ZoneObjectives.new()
	panel.session = s
	panel.zone = "gz1h" if astral else "gz6g"
	var desc := panel.description(q)
	var money_label := GameData.text("string obj_cost_money").strip_edges()
	var xp_label := GameData.text("string obj_cost_exp").strip_edges()
	if astral:
		check(desc.contains(money_label + " 230[/color]"), "Masking description promises 230")
		check(desc.contains(xp_label + " 10[/color]"), "Masking description still promises 10 experience")
		check(not desc.contains("1130758144"), "raw float bits never appear as a billion-scale reward")
		check(not panel.description("q2h").contains(money_label), "a zero-money quest omits the money line")
	else:
		check(not desc.contains(money_label), "base quest has no invented money line")
	panel.free()
	var w := GameWorld.new()
	w.session = s
	w.presentation = false
	s.world = w
	var u := GameUnit.new()
	u.world = w; u.uid = 1500000001; u.controller = 0
	var hero: Dictionary = s.state.heroes[0][0]
	hero["int"] = 25.0; hero.exp = 100.0; hero.exp_total = 100.0; hero.exp_debt = 0.0
	u.set_meta("hero", hero)
	w.set_unit(u.uid, u)
	var vm := ScriptVM.new(); vm.world = w; vm.session = s
	vm._quest_complete(q)
	check(s.state.money == 321, "QuestComplete does not pay the advertised-money field")
	check(is_equal_approx(float(hero.exp_total), 100.0 + float(row.experience)), "QuestComplete awards the original experience")
	vm.world = null; vm.session = null
	s.world = null; u.free(); w.free()
	if astral and DisplayServer.get_name() != "headless":
		s.zone_id = "bz2h"
		s.state.set_var(0, "q.gz1h.q2h", 1)
		s.leave_zone("gz1h_bz2h", 1)
		var map := TravelMap.new()
		map.setup(s, s.travel_options, true, "gz1h_bz2h")
		add_child(map)
		for i in 12: await get_tree().process_frame
		map._hover = map._piece_of("gz1h")
		map._apply_highlight(); map._hud.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://portal-map-corrected.png")
		s.state.set_var(0, "q.gz1h.q3h", 1)
		var objectives := map.open_objectives("gz1h")
		objectives._select(objectives.quests.find("q3h"))
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://masking-reward-corrected.png")
		map.queue_free()
	s.queue_free()
	for i in 10: await get_tree().process_frame
	print("QUEST_REWARDS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
