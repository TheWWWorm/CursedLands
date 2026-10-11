extends "third_person_kbm.gd"
## Original loaded scene, normal HUD/input/command/cast pipeline. Controlled
## actors and stepped native logic isolate repeat casting from combat AI.
var receiver: GameUnit
var samples := []

func button(code: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 42; event.button_index = code; event.pressed = down
	Input.parse_input_event(event)
	await frames(2)

func tap(code: JoyButton) -> void:
	await button(code, true); await button(code, false)

func mouse_at(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = at; event.pressed = true
	Input.parse_input_event(event); await frames(2)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = at
	Input.parse_input_event(event); await frames(2)

func logic_step() -> void:
	var w := s.world
	w._logic_step += 1; w.time += GameUnit.TICK
	hero.tick(GameUnit.TICK); receiver.tick(GameUnit.TICK)
	var timers := w.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers: timers._tick(GameUnit.TICK, true)

func settle() -> bool:
	for i in 1200:
		var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
		if hero.order.is_empty() and hero.orders.is_empty() and hero._anim_lock <= 0.0 \
				and (timers == null or timers.pending.is_empty()): return true
		logic_step()
		if i % 10 == 0: await frames(1)
	return false

func select_spell(index: int, round_index: int) -> void:
	if mode == "gamepad":
		await tap(JOY_BUTTON_LEFT_SHOULDER)
		var field := g.direct.field()
		check(field.wheel.visible and field.wheel_kind() == "actions", "LB opens the spell wheel")
		for i in 12:
			if field.wheel.current().get("id", []) == ["spell", index]: break
			await tap(JOY_BUTTON_DPAD_RIGHT)
		check(field.wheel.current().get("id", []) == ["spell", index], "D-pad selects spell slot %d" % index)
		await tap(JOY_BUTTON_A)
		check(not field.wheel.visible, "A confirms and closes the spell wheel")
	elif mode == "classic" and round_index != 1:
		var slots := g.hud._slots
		slots._process(0.0)
		await mouse_at(slots.get_global_transform_with_canvas() * slots._cell_rect(index).get_center())
	else:
		await key((KEY_1 + index) as Key)

func cast_input(index: int, round_index: int) -> void:
	var spell := String(hero.get_meta("hero").spells[index])
	var code := String(Spells.parse(spell).code)
	receiver.faction = hero.faction
	await aim(receiver)
	await select_spell(index, round_index)
	check(g.pending_spell == spell, "spell selects again: %s cast %d" % [spell, round_index + 1])
	check(not g.pending_target(receiver).is_empty(), "same living target remains eligible: " + spell)
	var old_deadline := float(receiver.buffs.get(code, {}).get("until", -1.0))
	if code == "healing": receiver.hp = receiver.max_hp * 0.4
	var hp_before := receiver.hp
	var mana_before := hero.mana
	if mode == "gamepad":
		var field := g.direct.field()
		for i in 50:
			if field.target_unit() == receiver: break
			await tap(JOY_BUTTON_DPAD_RIGHT)
		check(field.target_unit() == receiver, "D-pad acquires the repeated spell target")
		await tap(JOY_BUTTON_A)
	else:
		check(g.pick_unit(get_viewport().get_visible_rect().size * 0.5, hero) == receiver, "crosshair picks native target silhouette")
		await mouse_at(get_viewport().get_visible_rect().size * 0.5)
	check(g.pending_spell.is_empty(), "cast clears targeting for the next selection")
	check(hero.orders.size() == 1 and hero.orders[0].get("known_spell", false), "input queues one validated learned-spell command")
	var applied := false
	var spent := false
	for i in 1200:
		logic_step()
		spent = spent or hero.mana < mana_before - 0.01
		applied = receiver.hp > hp_before + 0.01 if code == "healing" else float(receiver.buffs.get(code, {}).get("until", -1.0)) > old_deadline
		if applied: break
		if i % 10 == 0: await frames(1)
	check(spent, "cast spends normal stamina: " + spell)
	check(applied, "effect applies through normal queued execution: %s cast %d" % [spell, round_index + 1])
	check(await settle(), "cast animation and pending effect finish normally")
	check(Spells.known_usable(hero, spell), "equipped spell remains available after execution")
	samples.append({"mode":mode, "spell":spell, "cast":round_index + 1, "mana_before":mana_before, "mana_after":hero.mana, "effect_ticks":receiver.effect_ticks(code)})
	if round_index == 0 and code != "healing":
		# Keep the first effect active, but reduce its timer enough to observe
		# refresh on the second cast. The third starts after natural expiry.
		for i in mini(receiver.effect_ticks(code) / 3, 100): logic_step()
	elif round_index == 1 and code != "healing":
		for i in receiver.effect_ticks(code) + 1: logic_step()
		check(not receiver.buffs.has(code), "effect expires before third cast: " + spell)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(800, 600)
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0,
		"net_directory":0, "auto_graphics":0, "control_mode":2, "pad_enabled":0, "pad_glyphs":1, "blood":0}, true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	PadInput.active = "kbm"
	s = Session.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state = CampaignState.new(); s.state.ensure_hero(0, "Human Hero")
	mode = "prepare"; await s.enter_zone("gz1g", 1, false); await prepare()
	var h: Dictionary = hero.get_meta("hero")
	h.skills = {"astral":100, "fire":100, "water":100, "air":100, "earth":100}
	h.int = 100.0; h.dex = 100.0; h.spells = ["weak{}", "slow{}", "strength{}", "healing{}"]
	Combat.hero_stats(hero, h); hero.mana = hero.max_mana
	hero.ai_next = 1e20; hero._perceive_next = 1e20
	var at := free_point(2.0)
	check(at != hero.pos, "original navigation supplies a clear nearby target location")
	receiver = body(at, 0, false)
	receiver.race = receiver.race.duplicate(true); receiver.race.health_regen = 0.0
	receiver.ai_next = 1e20; receiver._perceive_next = 1e20
	for input_mode in ["classic", "keyboard", "gamepad"]:
		mode = input_mode; reset(); hero.mana = hero.max_mana
		GameData.options.control_mode = 1 if mode == "classic" else 2
		GameData.options.pad_enabled = 1 if mode == "gamepad" else 0
		PadInput.release_all(); PadInput.active = "pad" if mode == "gamepad" else "kbm"
		g.direct.set_process(true); await frames(8); g.direct.set_process(false)
		g.direct._neutral = false
		if DisplayServer.get_name() == "headless": g.direct._captured = mode != "classic"
		for index in 4:
			for round_index in 3: await cast_input(index, round_index)
			for code in receiver.buffs.keys():
				for i in receiver.effect_ticks(code) + 1: logic_step()
	PadInput.release_all(); get_tree().paused = false
	evidence.scope = "Original native scene; injected HUD mouse clicks, spell hotkeys and LB/D-pad/A controller input; manually stepped actor and spell-timer logic. No physical-input or network claim."
	evidence.checks = checks; evidence.failures = failures; evidence.samples = samples
	FileAccess.open("user://repeated-spells-input.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("REPEATED_SPELLS_INPUT ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
