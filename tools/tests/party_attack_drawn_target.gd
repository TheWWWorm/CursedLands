extends Node
## 1.36.0 regression: a click on a boar the player is shown but the party has
## not noticed (behind the hero, inside the unit fog's 2 x sight + 5 radius)
## acknowledged the attack and then ended it with "no target" (ack 0x12) on
## the first tick, so the hero never moved. A target the player is shown is
## known to the party (GameUnit.party_knows / UnitFog.shown_to); one that
## leaves what the player sees still ends the order. Real field zone, hero,
## boar, perception and orders.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _reachable(w: GameWorld, a: GameUnit, b: Vector2, t: GameUnit) -> bool:
	var route := w.nav.find_path(a.pos, b, [a, t], [], 0.0, a.move_class(), true, NAN, 1e6, 0.0, false)
	return not route.is_empty() and route[-1].distance_to(b) < 1.0

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0,"unit_fog":1},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	hero.max_hp = 100000.0; hero.hp = hero.max_hp
	# Past the opening, when the hero takes orders.
	for i in 120: w._tick(GameUnit.TICK)
	check(UnitFog.sight_active(s), "unit fog (the default) decides what the player is shown")
	var fog := UnitFog.range_of(hero)
	var terms: PackedFloat64Array = w.ai.notice_terms(hero, float(hero.stats.sight))
	print("DRAWN_TARGET_TERMS fog ", fog, " notice ", terms)
	# A boar behind the hero, well inside the fog radius and out of its cone.
	var t := w.spawn_unit({"nid":990951, "prototype":"boarredf1", "position":Vector3(hero.pos.x, hero.pos.y, 0)})
	t.ai_next = INF; t._perceive_next = INF
	var spot := Vector2.INF
	for d in [8.0, 7.0, 9.0, 6.0]:
		for a in [PI, PI * 0.9, PI * 1.1, PI * 0.8, PI * 1.2]:
			var c := w.nav.nearest_walkable(hero.pos + Vector2.from_angle(hero.facing + a) * d)
			if c.distance_to(hero.pos) < 5.0 or not _reachable(w, hero, c, t): continue
			w.dialog_place(t, c, 0.0)
			if UnitFog.shown_to(s, hero.controller, t) and not w.ai.can_notice_with(hero, t, terms):
				spot = c; break
		if spot.is_finite(): break
	check(spot.is_finite(), "a reachable spot behind the hero that the player sees")
	for i in 6: w._tick(GameUnit.TICK)
	check(not (hero.get_meta("noticed", {}) as Dictionary).has(t.get_instance_id()), "the party has not noticed the boar")
	var start := hero.pos.distance_to(t.pos)
	hero.attack(t)
	# A clip lock may hold the queued order for a moment first.
	for i in 20: w._tick(GameUnit.TICK)
	check(not hero.order_failed, "the attack order is not ended with no target")
	check(hero.order.get("type", "") == "attack" and hero.order.get("target") == t, "the hero goes on attacking the boar it was ordered to")
	check(hero.pos.distance_to(t.pos) < start - 0.5, "the hero moves to it (%.1f -> %.1f m)" % [start, hero.pos.distance_to(t.pos)])
	# The boar is taken beyond what the player is shown: the order ends.
	var far := Vector2.INF
	for a in range(16):
		var c := w.nav.nearest_walkable(hero.pos + Vector2.from_angle(a * PI / 8.0) * (fog + 12.0))
		if c.distance_to(hero.pos) < fog + 6.0 or not _reachable(w, hero, c, t): continue
		far = c; break
	check(far.is_finite(), "a reachable spot beyond the party's sight")
	t.pos = far
	var n := 0
	while n < 40 and not hero.order.is_empty():
		w._tick(GameUnit.TICK); n += 1
	check(not UnitFog.shown_to(s, hero.controller, t), "the player no longer sees the boar")
	check(hero.order.is_empty() and hero.order_failed, "the order ends with no target (%d ticks)" % n)
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("PARTY_ATTACK_DRAWN_TARGET ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
