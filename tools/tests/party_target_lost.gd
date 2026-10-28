extends Node
## A party unit's order on a unit ends with "no target" (ack 0x12) once the
## target is not known: the original (54dd70) lets it go on only
## for a unit of its side or player, one it has noticed (5cb7f0), or one in
## its player's group; here a unit another party member has noticed. Real
## field zone, hero, perception and orders.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	hero.max_hp = 100000.0; hero.hp = hero.max_hp
	var side := 1
	while side == hero.faction: side += 1
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	var p := w.nav.nearest_walkable(hero.pos + Vector2.from_angle(hero.facing) * 3.0)
	var t := w.spawn_unit({"nid":990901, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	t.faction = side; t.ai_next = INF; t._perceive_next = INF
	t.visible = true; t.fogged = false; t.hidden = false
	for bp: UnitBodyPart in t.parts:
		bp.max = 100000.0; bp.cur = bp.max
	hero.attack(t)
	for i in 12: w._tick(GameUnit.TICK)
	check((hero.get_meta("noticed", {}) as Dictionary).has(t.get_instance_id()), "the hero notices the enemy in front")
	check(hero.order.get("type", "") == "attack" and hero.order.get("target") == t, "it attacks the enemy it knows")
	# The enemy is taken far beyond the party's sight.
	var terms: PackedFloat64Array = w.ai.notice_terms(hero, float(hero.stats.sight))
	var gone := maxf(terms[0] * terms[1], terms[4] * t.detect(2)) * 1.5 + 10.0
	print("PARTY_TARGET_TERMS ", terms, " away ", gone)
	# A spot beyond the senses that the hero can still walk to.
	var far := Vector2.INF
	for a in range(16):
		var c := w.nav.nearest_walkable(hero.pos + Vector2.from_angle(a * PI / 8.0) * gone)
		if c.distance_to(hero.pos) < gone * 0.9: continue
		var route := w.nav.find_path(hero.pos, c, [hero, t], [], 0.0, hero.move_class(), true, NAN, 1e6, 0.0, false)
		if not route.is_empty() and route[-1].distance_to(c) < 1.0:
			far = c; break
	check(far.is_finite(), "a reachable spot beyond the party's senses")
	w.dialog_place(t, far, 0.0)
	var n := 0
	while n < 40 and not hero.order.is_empty():
		w._tick(GameUnit.TICK); n += 1
	check(not (hero.get_meta("noticed", {}) as Dictionary).has(t.get_instance_id()), "the party loses sight of it")
	check(hero.order.is_empty() and hero.order_failed, "the order ends with no target (%d ticks)" % n)
	# Another party member that sees the enemy keeps it known to the party.
	var q := w.nav.nearest_walkable(far + Vector2(3, 0))
	var mate := w.spawn_unit({"nid":990902, "prototype":"Human Hero", "player":1, "position":Vector3(q.x, q.y, 0)})
	mate.faction = hero.faction; mate.controller = hero.controller; mate.mode = "player"
	mate.facing = (t.pos - mate.pos).angle(); mate.aggressive = false
	for i in 12: w._tick(GameUnit.TICK)
	check((mate.get_meta("noticed", {}) as Dictionary).has(t.get_instance_id()), "a party member near the enemy notices it")
	hero.order_failed = false
	hero.attack(t)
	var k := 0
	while k < 100 and hero.order.is_empty():
		w._tick(GameUnit.TICK); k += 1
	for i in 10: w._tick(GameUnit.TICK)
	check(hero.order.get("type", "") == "attack" and hero.order.get("target") == t, "the hero's order goes on while the party knows the enemy")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("PARTY_TARGET_LOST ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
