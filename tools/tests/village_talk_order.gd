extends Node
## Village NPC talk, as the original does it (checked under Wine in bz2g with
## Airy, "More about the Witch"): the click opens the topic list at once with
## the hero where he stands; picking a topic walks him to her; Space skips
## that walk and the conversation starts; afterwards he stays by her.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

func setup() -> Array:
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	s.state.set_var(0, "b.bz2g.z0", 2.0)          # the village's entry talk is done
	s.state.set_var(0, "b.daughter.z0_1", 1.0)    # Airy: "More about the Witch"
	await s.enter_zone("bz2g", 1, false)
	ticks(s, 40)
	var airy: GameUnit = null
	for u: GameUnit in s.world.unit_rows():
		if u.display_name == "Airy" or String(u.info.get("name", "")).to_lower() == "daughter": airy = u
	return [s, g, airy, s.party_units(0)[0]]

func open_and_pick(s: Session, g: Game, airy: GameUnit, hero: GameUnit) -> Vector2:
	var start := hero.pos
	g.issue({"t": "interact", "units": [hero.uid], "target": airy.uid})
	ticks(s, 2)
	check(g.hud._dialog._mode == DialogPanel.TOPICS and g.hud._dialog.visible, "the click opens the topic list at once")
	check(hero.pos.distance_to(start) < 0.01 and not hero.has_meta("interact") and hero.order.get("type", "") != "follow", "the hero stays put while the list is open")
	var opts: Array = g.hud._dialog._topics.get("options", [])
	check(opts.size() >= 1 and String(opts[0]["var"]).to_lower() == "b.daughter.z0_1", "Airy offers her topic (%s)" % str(opts.map(func(o): return o["var"])))
	g.hud._dialog._on_topic(0)
	ticks(s, 2)
	check(g.hud._dialog._mode == DialogPanel.STAGING, "picking the topic starts the walk to her")
	check(s.world.dialog_movers.has(hero) and hero.order.get("type", "") == "move", "the hero walks to his conversation mark")
	return start

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	# 1. Space skips the walk.
	var r: Array = await setup()
	var s: Session = r[0]; var g: Game = r[1]; var airy: GameUnit = r[2]; var hero: GameUnit = r[3]
	check(airy != null, "Airy is in bz2g")
	if airy == null:
		get_tree().quit(1); return
	var start := await open_and_pick(s, g, airy, hero)
	ticks(s, 3)
	var mark: Vector2 = s.world.dialog_movers[hero].to if s.world.dialog_movers.has(hero) else hero.pos
	# Another player cannot skip this player's staging.
	s.world.vm.briefings.skip_staging(1)
	check(not s.world.vm.briefings._pending_dialog.is_empty(), "another player's skip is ignored")
	var space := InputEventKey.new(); space.keycode = KEY_SPACE; space.pressed = true
	g.hud._dialog._unhandled_input(space)
	ticks(s, 2)
	check(s.world.vm.briefings._pending_dialog.is_empty() and not s.world.vm.briefings.active.is_empty(), "Space starts the conversation at once")
	check(g.hud._dialog._mode == DialogPanel.PLAYING or g.hud._dialog._mode == DialogPanel.LAST, "the first phrase shows")
	check(hero.pos.distance_to(mark) < 0.05, "the hero stands at his mark (%.2f m off)" % hero.pos.distance_to(mark))
	check(absf(angle_difference(hero.facing, (airy.pos - hero.pos).angle())) < 0.1, "the hero faces Airy")
	check(not s.world.dialog_movers.has(hero), "no walk is left over")
	g.hud._dialog._finish()
	ticks(s, 20)
	check(s.state.get_var(0, "b.daughter.z0_1") == 2.0, "the topic completes")
	check(hero.pos.distance_to(mark) < 0.3 and hero.pos.distance_to(start) > 1.0, "afterwards he stays by her, as in the original")
	s.queue_free(); g.queue_free()
	await get_tree().process_frame
	# 2. Without a skip he walks there and the conversation starts on arrival.
	r = await setup()
	s = r[0]; g = r[1]; airy = r[2]; hero = r[3]
	start = await open_and_pick(s, g, airy, hero)
	var n := 0
	while not s.world.vm.briefings._pending_dialog.is_empty() and n < 600:
		ticks(s, 1); n += 1
	check(s.world.vm.briefings._pending_dialog.is_empty() and n > 10, "without Space the walk plays out (%.1f s)" % (n * GameUnit.TICK))
	check(hero.pos.distance_to(start) > 1.0 and hero.pos.distance_to(airy.pos) < 4.0, "and ends beside Airy")
	s.queue_free(); g.queue_free()
	await get_tree().process_frame
	# 3. The first village's elder (the 2026-10-07 stall: his staging route
	# never reached its mark and waited for the 30 s timeout).
	s = Session.new(); add_child(s); g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("bz1g", 1, false)
	ticks(s, 40)
	for key: String in s.state.gs_keys(0, "b.", true): s.state.set_var(0, key, 2.0)
	s.state.set_var(0, "b.elder.s1", 1.0)
	hero = s.party_units(0)[0]; hero.blocked = false
	var elder: GameUnit = null
	for u: GameUnit in s.world.unit_rows():
		if String(u.info.get("name", "")).to_lower() == "elder": elder = u
	check(elder != null and elder.village_talk_ready(), "the elder is ready to talk")
	if elder:
		start = hero.pos
		g.issue({"t": "interact", "units": [hero.uid], "target": elder.uid})
		ticks(s, 2)
		check(g.hud._dialog._mode == DialogPanel.TOPICS and hero.pos.distance_to(start) < 0.01, "the elder's topics open at once")
		var opts: Array = g.hud._dialog._topics.get("options", [])
		var k := opts.find_custom(func(o): return String(o["var"]).to_lower() == "b.elder.s1")
		g.hud._dialog._on_topic(k)
		n = 0
		while not s.world.vm.briefings._pending_dialog.is_empty() and n < 700:
			ticks(s, 1); n += 1
		check(s.world.vm.briefings._pending_dialog.is_empty() and n * GameUnit.TICK < 15.0, "the walk to the elder ends without the 30 s timeout (%.1f s, %.1f m)" % [n * GameUnit.TICK, start.distance_to(elder.pos)])
		check(hero.pos.distance_to(elder.pos) < 5.0, "Zak stands by the elder (%.1f m)" % hero.pos.distance_to(elder.pos))
	print("VILLAGE_TALK_ORDER ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
