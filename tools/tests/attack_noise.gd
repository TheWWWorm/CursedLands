extends Node
## A fight is heard. The original (54f450) makes a noise of
## twice the attacker's hearing detectability for 26 ticks after every blow
## or shot that is not a backstab, so hostile units in hearing range that do
## not see the fight become suspicious of the spot. Real field zone, hero,
## strikes and the delayed-sound queue.
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
	var other := side + 1
	while other == hero.faction: other += 1
	for f in [side, other]:
		w.set_relation(hero.faction, f, 2); w.set_relation(f, hero.faction, 2)
	w.set_relation(side, other, 1); w.set_relation(other, side, 1)
	var p := w.nav.nearest_walkable(hero.pos + Vector2(1.5, 0))
	var t := w.spawn_unit({"nid":991101, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	t.faction = side; t.ai_next = INF; t._perceive_next = INF
	t.alert = true; t.facing = (hero.pos - t.pos).angle()   # no backstab
	for bp: UnitBodyPart in t.parts:
		bp.max = 100000.0; bp.cur = bp.max
	# A hostile listener of another side, behind the hero and facing away,
	# within the distance it hears a fight at.
	var lp := w.nav.nearest_walkable(hero.pos + Vector2(-1, 0))
	var listener := w.spawn_unit({"nid":991102, "prototype":"GoblinTutor", "player":1, "position":Vector3(lp.x, lp.y, 0)})
	listener.faction = other; listener.ai_next = INF; listener._perceive_next = INF
	var hears := listener.hear_factor() * listener.sense(3) * hero.detect(3) * 2.0
	var at := w.nav.nearest_walkable(hero.pos + Vector2(-0.4 * hears, 0))
	w.dialog_place(listener, at, 0.0)
	listener.facing = (listener.pos - hero.pos).angle()
	print("ATTACK_NOISE_RANGE ", hears, " listener at ", listener.pos.distance_to(hero.pos))
	check(listener.dist3(hero) < hears and w.relation(listener.faction, t.faction) != 0 and w.relation(t.faction, listener.faction) != 0, "the listener can hear the hero and is no friend the victim calls for help")
	w.ai._help.clear()
	hero.attack(t)
	var n := 0
	while n < 400 and (hero._pending_hit.is_empty() or hero._pending_hit.roll.backstab):
		w._tick(GameUnit.TICK); n += 1
	while not hero._pending_hit.is_empty():
		w._tick(GameUnit.TICK)
	check(not (listener.get_meta("noticed", {}) as Dictionary).has(hero.get_instance_id()), "the listener does not see the fight")
	check(w.ai._help.any(func(e: Array): return e[0] == listener), "a blow is heard by the listener")
	hero.orders.clear(); hero.order = {}
	for i in 30: w._tick(GameUnit.TICK)
	check(listener.has_meta("suspect"), "which becomes suspicious of the fight's spot")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("ATTACK_NOISE ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
