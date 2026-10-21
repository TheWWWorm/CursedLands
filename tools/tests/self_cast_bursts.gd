extends "third_person_kbm.gd"
## Real shortcut routing and native cast/effect ticks. Delayed delivery below
## exercises the retry state without claiming an ENet or physical-input test.
class ProbeSession extends Session:
	var casts := 0
	var delay := false
	var delayed: Array[Dictionary] = []
	func submit(command: Dictionary) -> void:
		if command.get("t", "") in ["cast", "direct_cast"]:
			casts += 1
			if delay:
				delayed.append(_input_out.prepare(command))
				return
		super.submit(command)
	func deliver() -> void:
		for command in delayed:
			apply_command(command, 0)
			_input_out.acknowledge(int(command._input_seq))
		delayed.clear()

func press(slot := 0, modified := false) -> void:
	var event := InputEventKey.new()
	event.keycode = (KEY_1 + slot) as Key
	event.physical_keycode = event.keycode
	event.pressed = true
	event.ctrl_pressed = modified
	g._unhandled_input(event)
	event.pressed = false
	g._unhandled_input(event)

func tick() -> void:
	s.world.time += GameUnit.TICK
	s.world._logic_step += 1
	hero.tick(GameUnit.TICK)
	var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers: timers._tick(GameUnit.TICK, true)

func clean() -> void:
	reset(); hero.stop_steering(); hero.restore_gait(2)
	hero.action = "idle"; hero._hold_left = 0.0; hero._pre_left = 0.0
	hero._pose_snap = true; hero._update_pose(); hero._anim_lock = 0.0
	hero._perceive_next = INF; hero.ai_next = INF
	hero.mana = hero.max_mana; hero.hp = hero.max_hp * 0.2
	(s as ProbeSession).casts = 0
	(s as ProbeSession).delay = false
	(s as ProbeSession).delayed.clear()
	s._input_out.pending.clear()
	var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers: timers.pending.clear()

func start() -> float:
	press(); press()
	for i in 100:
		tick()
		if hero.action.begins_with("cast"): break
	check(hero.action.begins_with("cast"), "self-cast reaches its native animation")
	return hero._anim_lock

func settle() -> void:
	for i in 400:
		if hero.order.is_empty() and hero.orders.is_empty() and hero._anim_lock <= 0.0: return
		tick()
	check(false, "cast and its buffered follow-up finish")

func preselected_cases() -> void:
	for selection: String in ["recent shortcut", "older shortcut", "HUD slot"]:
		clean()
		if selection == "HUD slot":
			g.hud._slots.use(0, false)
		else:
			press()
			if selection == "older shortcut": g._last_spell_key.at -= 1000
		check(g.pending_spell == "healing{}" and (s as ProbeSession).casts == 0, selection + " prepares healing before the burst")
		if selection != "recent shortcut":
			press()
			check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 0, selection + " retains ordinary first-press cancellation")
		for i in 9: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1 and hero.orders.size() == 1, selection + " followed by a burst leaves one self-cast and no prepared repeat")
		var mana := hero.mana
		settle()
		check(is_equal_approx(mana - hero.mana, hero._spell_cost(Spells.parse("healing{}"))), selection + " burst pays for one cast")
	clean(); press(1)
	for i in 9: press()
	check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1 and hero.orders.size() == 1, "a different spell prepared before the burst does not affect self-cast suppression")

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":3,
		"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"spell_double_tap_self":1},true)
	PadInput.active = "kbm"
	s = ProbeSession.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, "Human Hero")
	await s.enter_zone("gz1g",1,false); await prepare()
	hero.set_process(false); hero.set_physics_process(false)
	var h: Dictionary = hero.get_meta("hero")
	h.skills = {"astral":100,"elemental":100,"sense":100,"fire":100,"water":100,"air":100,"earth":100}
	h.spells.append("healing{}")
	Combat.hero_stats(hero,h)
	hero.race = hero.race.duplicate(true)
	hero.race.health_regen = 0.0; hero.race.mana_regen = 0.0
	for camera_mode: int in [1,2,3]:
		GameData.options.control_mode = camera_mode
		hero.direct_controlled = camera_mode != 1
		mode = "camera %d" % camera_mode
		preselected_cases()
		for taps: int in [3,4,5,8,9]:
			clean()
			for i in taps: press()
			check(g.pending_spell.is_empty(), "%d opening taps leave no prepared spell" % taps)
			check((s as ProbeSession).casts == 1 and hero.orders.size() == 1, "%d opening taps submit one self-cast" % taps)
			var mana := hero.mana
			settle()
			check(is_equal_approx(mana - hero.mana, hero._spell_cost(Spells.parse("healing{}"))), "%d taps pay for one cast" % taps)
		clean(); press(3); press(3); press(3)
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "an identical spell in another slot also leaves no prepared repeat")
		clean()
		var duration := start()
		var started := s.world.time
		while s.world.time - started + GameUnit.TICK < duration * 0.5 - 0.00000001: tick()
		# Wall time cannot unlock a paused or deliberately slow cast.
		g._self_cast_key.at -= 10000
		for i in 7: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "early cast spam stays unselected even after a long wall-time gap")
		while s.world.time - started < duration * 0.5 - 0.00000001: tick()
		# LiA's healing cost can exhaust this fixture's starting stamina after
		# one cast. Isolate repeat timing; the separate case below tests waiting.
		hero.mana = hero.max_mana
		press()
		check(g.pending_spell == "healing{}" and (s as ProbeSession).casts == 1, "first press after halfway selects the spell again")
		press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 2 and hero.orders.size() == 1, "second press after halfway buffers one self-cast")
		var recovery := hero._anim_lock
		for i in 9: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 2 and hero.orders.size() == 1, "continued spam cannot arm or queue a third cast")
		check(hero._anim_lock == recovery, "repeat input leaves the committed recovery unchanged")
		settle()
		press()
		check(g.pending_spell == "healing{}", "a completed cast does not swallow the next ordinary selection")
		clean(); start(); press(1)
		check(g.pending_spell == "arrow{}", "another spell remains selectable during the early cast")
		press()
		check(g.pending_spell == "arrow{}" and (s as ProbeSession).casts == 1, "a stray tap of the casting spell preserves the other prepared spell")
		press(1)
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "the other prepared spell retains ordinary selection cancellation")
		clean(); start()
		# The fixture's starting pool only accommodates unmodified healing.
		# Give the distinct spell enough capacity without changing its rules.
		var max_stamina := hero.max_mana
		hero.max_mana = maxf(max_stamina, float(Spells.parse("healing{e1;e1}").mana))
		hero.mana = hero.max_mana
		check(Spells.known_usable(hero, "healing{e1;e1}"), "the distinct configured spell meets its native requirements")
		press(2)
		check(g.pending_spell == "healing{e1;e1}", "a differently configured healing spell remains selectable before halfway")
		press(2)
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 2 and hero.orders.size() == 1, "a differently configured healing spell double-taps into one intentional cast before halfway")
		hero.max_mana = max_stamina
		clean(); start(); press(0,true)
		check((s as ProbeSession).casts == 2, "explicit modified quick-cast remains intentional")
		clean(); g.begin_cast(0); g.cast_portrait(hero)
		for i in 7: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "a confirmed portrait/self action also absorbs the trailing key burst")
		clean(); hero.mana = 0.0; press(); press(); tick()
		for i in 9: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1 and hero.order.get("stamina_notified",false), "stamina waiting keeps one unselected request")
		clean(); (s as ProbeSession).delay = true
		press(); press(); g._self_cast_key.at -= 10000
		for i in 9: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "unacknowledged delivery suppresses duplicate selection beyond the tap window")
		s._input_out.acknowledge(s._input_out.serial)
		for i in 3: press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 1, "an acknowledgement arriving before the cast snapshot does not rearm the spell")
		(s as ProbeSession).delay = false; (s as ProbeSession).deliver()
		settle()
		check((s as ProbeSession).casts == 1, "delayed authority delivery still executes one request")
		clean(); GameData.options.spell_double_tap_self = 0
		press(); press()
		check(g.pending_spell.is_empty() and (s as ProbeSession).casts == 0, "disabled shortcut retains ordinary second-press cancellation")
		GameData.options.spell_double_tap_self = 1
	# A replica must retain the host's cast start rather than restarting its
	# halfway gate when an already-running cast first appears in a snapshot.
	clean(); hero.direct_controlled = true
	var actual_duration := start()
	var actual_start := hero._action_started_at
	for i in 8: tick()
	var snapshot := hero.snapshot()
	hero.action = "idle"; hero._remote_action_serial = -1
	hero.apply_snapshot(snapshot,false,PackedFloat64Array(),s.world.time)
	check(is_equal_approx(hero._action_started_at,actual_start), "late snapshots preserve the original cast start")
	var guard := g._self_cast_key.duplicate()
	var received_at := s.world.time
	s.world.authority = false
	for controlled: bool in [false,true]:
		hero.direct_controlled = controlled
		g._self_cast_key = guard.duplicate()
		s.world.time = received_at
		check(g._self_cast_key_blocked(0,hero,"healing{}",Time.get_ticks_msec()), "replica rejects early taps with direct control " + str(controlled))
		s.world.time = actual_start + actual_duration * 0.51
		check(not g._self_cast_key_blocked(0,hero,"healing{}",Time.get_ticks_msec()), "replica unlocks after the original midpoint with direct control " + str(controlled))
	s.world.authority = true
	s.world.time = received_at
	var tip := GameData.TipLayer.new()
	for language: String in ["en","ru","de"]:
		RemakeText.lang = language
		var help := RemakeText.t(GameData.REMAKE_OPTIONS.spell_double_tap_self[1])
		check(not help.is_empty() and (language == "en" or help != GameData.REMAKE_OPTIONS.spell_double_tap_self[1]), language + " explains burst suppression and the halfway repeat")
		var font := Interface800.font()
		var fs := roundi(800 * Interface800.FONT_EM[0])
		var lines := tip._wrap(PackedStringArray([help]),font,fs,360.0)
		check(lines.size() * font.get_height(fs) < 500.0 and Array(lines).all(func(line: String): return font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x <= 360.0), language + " help wraps inside the existing tooltip at 800x600")
	tip._panel.free(); tip.free()
	RemakeText.lang = "en"
	print("SELF_CAST_BURSTS ", JSON.stringify({"checks":checks,"failures":failures,"scope":"Injected keyboard shortcuts, native authority/effect ticks and snapshot replay in both campaigns; simulated delayed delivery, no ENet claim."}))
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
