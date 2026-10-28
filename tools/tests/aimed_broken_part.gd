extends Node
## An aimed attack stops aiming at a part that is no longer intact. The
## original (549ec0) makes the order unaimed once the struck
## aimed part is broken or severed, and 554b30 gives such an aim
## no effect, so the fight goes on against the other parts. Real field zone,
## hero, strike timing and damage.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func given(u: GameUnit) -> Dictionary:
	return u.order if not u.order.is_empty() else u.orders.front() if not u.orders.is_empty() else {}

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
	var p := w.nav.nearest_walkable(hero.pos + Vector2(1.5, 0))
	var t := w.spawn_unit({"nid":990501, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	var side := 1
	while side == hero.faction: side += 1
	t.faction = side
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	t.ai_next = INF; t._perceive_next = INF
	const AIM := 2
	check(t.parts.size() >= 6, "the target has the six aimable parts")
	# The aimed part breaks at the first blow it takes; the rest hold out.
	for i in t.parts.size():
		var bp: UnitBodyPart = t.parts[i]
		bp.max = 0.01 if i == AIM else 100000.0
		bp.cur = bp.max
	hero.attack(t, false, AIM)
	check(int(given(hero).get("aim", -1)) == AIM, "the attack is aimed at the intact part")
	var n := 0
	while n < 2000 and int(t.parts[AIM].state) == 3:
		w._tick(GameUnit.TICK); n += 1
	check(int(t.parts[AIM].state) != 3, "a blow breaks the aimed part (%d ticks)" % n)
	check(hero.order.get("type", "") == "attack" and hero.order.get("target") == t, "the attack goes on")
	check(int(hero.order.get("aim", -1)) == -1, "and its later blows are unaimed")
	var others := func() -> float:
		var sum := 0.0
		for i in t.parts.size():
			if i != AIM: sum += t.parts[i].cur
		return sum
	var before: float = others.call()
	n = 0
	while n < 2000 and others.call() >= before:
		w._tick(GameUnit.TICK); n += 1
	check(others.call() < before, "a later blow damages another part (%d ticks)" % n)
	hero.orders.clear(); hero.order = {}
	hero.attack(t, false, AIM)
	check(int(given(hero).get("aim", -2)) == -1, "an order aimed at the broken part is unaimed")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("AIMED_BROKEN_PART ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
