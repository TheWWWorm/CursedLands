extends "third_person_kbm.gd"
## Native HUD input, authority orders, and standing/catching-up followers.
var companion: GameUnit

func portrait_point(u: GameUnit) -> Vector2:
	var faces := g.hud._faces
	for i in faces._cells.size():
		if faces._cells[i][0] == u:
			return faces.get_global_transform_with_canvas() * faces._r(faces._cell(i)).get_center()
	return Vector2(-1, -1)

func portrait_click(u: GameUnit, double := false) -> void:
	# Changing the selection refreshes the adjacent HUD strips and the face
	# strip's fit. Resolve its hit point after that layout has settled.
	await frames(4)
	var point := portrait_point(u)
	check(point.x >= 0, "target has a visible portrait")
	get_viewport().warp_mouse(point)
	await frames(4)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames(2)
	if g.pending_spell == Game.FOLLOW:
		var expected := "cursor_cancel" if u.dead else "cursor_move"
		if DisplayServer.get_name() == "headless":
			check(g.pending_cursor(u) == expected, "portrait target resolves the follow cursor")
		else:
			g._update_cursor()
			check(g.cursor.kind == expected, "portrait shows the follow target cursor")
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.double_click = double
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventMouseButton.new()
	event.position = point; event.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(event)
	await frames(2)

func clear_orders() -> void:
	for u in [hero, companion]:
		u.order = {}; u.orders.clear(); u.path = PackedVector2Array(); u._anim_lock = 0.0
		u._pending_hit = {}; u._attack_cd = 0.0; u.ai_next = 1e20; u._perceive_next = 1e20
		u.direct_steering.clear(); u.action = "idle"
	g.cancel_touch_target()

func queued_follow(u: GameUnit, target: GameUnit) -> bool:
	return u.orders.size() == 1 and u.orders[0].get("type") == "follow" and u.orders[0].get("target") == target

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":1,
		"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0}, true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	PadInput.active = "kbm"
	s = Session.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, "Human Hero")
	await s.enter_zone("gz1g", 1, false)
	mode = "follow portraits " + RemakeText.lang
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear(); g.get_node("UnitFog").set_process(false)
	hero = s.party_units(0)[0]; hero.blocked = false; g.selected.assign([hero]); g.rig.release()
	var h: Dictionary = hero.get_meta("hero")
	h.skills = {"astral":100}; h.spells = ["healing{}"]; h.int = 25.0
	Combat.hero_stats(hero, h)
	await frames(8); g.rig.set_process(false); g.direct.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	companion = body(free_point(3.0), 900001, false)
	companion.controller = s.my_index
	companion.set_meta("hero", hero.get_meta("hero").duplicate(true))
	await frames(5)
	for double in [false, true]:
		clear_orders(); g.selected.assign([companion])
		g._key_action("follow")
		check(g.pending_spell == Game.FOLLOW, "follow action arms target selection")
		await portrait_click(hero, double)
		if not queued_follow(companion, hero):
			print("FOLLOW_STATE ", companion.order, " queued=", companion.orders)
		check(queued_follow(companion, hero), "portrait click queues follow through authority, double=" + str(double))
		check(g.selected == [companion] and g.pending_spell.is_empty(), "target click preserves the follower selection and ends targeting")
	# Group targeting keeps the leader selected but never orders it to follow itself.
	clear_orders(); g.selected.assign([hero, companion]); g._key_action("follow")
	await portrait_click(hero)
	check(queued_follow(companion, hero) and hero.orders.is_empty(), "group portrait follow excludes its own target")
	check(g.selected == [hero, companion], "group target click preserves the whole selection")
	# A stale/dead portrait consumes the click without changing the selection.
	clear_orders(); g.selected.assign([companion]); g._key_action("follow")
	g.hud._faces.set_process(false); hero.dead = true
	await portrait_click(hero)
	check(companion.orders.is_empty() and g.selected == [companion] and g.pending_spell == Game.FOLLOW,
		"dead portrait retains targeting and follower selection")
	hero.dead = false; g.hud._faces.set_process(true)
	clear_orders(); g.selected.assign([companion])
	await portrait_click(hero)
	check(g.selected == [hero], "ordinary portrait clicks still select")
	clear_orders(); g.selected.assign([hero]); hero.mana = hero.max_mana
	g.begin_cast(0)
	await portrait_click(companion)
	check(hero.orders.size() == 1 and hero.orders[0].get("type") == "cast" and hero.orders[0].get("target") == companion,
		"spell targeting still uses the portrait")
	check(g.selected == [hero] and g.pending_spell.is_empty(), "portrait spell preserves its caster and clears targeting")
	# Real follow lifecycle: resting nearby, moving to catch up, then resting again.
	clear_orders(); g.selected.assign([companion]); g.pending_spell = Game.FOLLOW
	g.cast_on(hero)
	s.mod_config = ModStore.snapshot(); s.mod_config.rules.stamina_regen = 0
	companion.race = companion.race.duplicate(true); companion.race.mana_regen = 0.1
	companion.mana = companion.max_mana * 0.25; companion._regen_t = 0.0
	var start := companion.pos
	var before := companion.mana
	for i in 20: companion.tick(GameUnit.TICK)
	check(companion.pos.distance_to(start) < 0.01 and companion.order.get("type") == "follow",
		"nearby follower remains stationary with the follow command active")
	check(companion.mana > before, "native ticks regenerate stamina while waiting near the leader")
	companion._follow_walk(hero.pos)
	before = companion.mana; companion._regen_t = 0.0
	for i in 15: companion._regenerate(GameUnit.TICK)
	check(companion.mana == before, "catch-up movement retains normal stamina restriction")
	companion.pos = hero.pos + (start - hero.pos).normalized() * 1.5
	companion._follow_n = 8; companion._regen_t = 0.0
	for i in 20: companion.tick(GameUnit.TICK)
	check(not companion.order.has("walk") and companion.mana > before, "recovery resumes when the follower reaches the leader")
	g.selected.assign([companion]); g.cancel_touch_target()
	await frames(4)
	if DisplayServer.get_name() != "headless":
		g.hud._open_menu()
		await get_tree().create_timer(0.8, true, false, true).timeout
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("user://follow-menu.png") == OK, "capture localized menu and portraits")
		g.hud._close_menu()
	FileAccess.open("user://follow-portraits.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"assertions":evidence.assertions}, "  "))
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("FOLLOW_PORTRAITS ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
