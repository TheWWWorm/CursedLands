extends Node
## A unit put into Follow by script (builtin Follow, AI state 6) keeps its
## motivations. The original's Think (5d53b0) runs them every tick before the
## state's handler, so a follower with Aggression attacks a noticed hostile
## (the zone13 bodyguard following its master), while the calm motivation
## leaves the follow alone. Real field zone, script VM and world ticks.
var checks := 0
var failures := 0
const P := preload("res://src/game/script/script_parser.gd")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

func spawn(s: Session, nid: int, at: Vector2, proto: String) -> GameUnit:
	var p := s.world.nav.nearest_walkable(at)
	var u := s.world.spawn_unit({"nid":nid, "prototype":proto, "player":1, "position":Vector3(p.x, p.y, 0)})
	u.visible = true; u.fogged = false; u.hidden = false
	return u

func obj(u: GameUnit) -> Array:
	return [P.N_CALL, "GetObject", [[P.N_NUM, u.uid]]]

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
	# The party stays passive: only the follower's own motivations may start a fight.
	hero.aggressive = false
	var master := spawn(s, 990201, hero.pos + Vector2(10, 0), "Human Hero")
	# An armed follower: a weapon gives Aggression an attack to choose.
	var guard := spawn(s, 990202, hero.pos + Vector2(12, 0), "GoblinTutor")
	master.ai_next = INF; master._perceive_next = INF
	var side := 1
	while side == hero.faction: side += 1
	master.faction = side; guard.faction = side
	w.set_relation(hero.faction, side, 0); w.set_relation(side, hero.faction, 0)
	check(not w.is_enemy(guard, hero), "the follower starts neutral to the party")
	w.vm._call("Follow", [obj(guard), obj(master)], ScriptVM.Instance.new())
	var given: Dictionary = guard.order if not guard.order.is_empty() else guard.orders.front() if not guard.orders.is_empty() else {}
	check(given.get("type", "") == "follow" and given.get("target") == master, "Follow gives a follow order")
	# With nobody hostile, the calm motivation leaves the follow alone.
	w.dialog_place(master, w.nav.nearest_walkable(master.pos + Vector2(0, 8)), 0.0)
	ticks(s, 160)
	check(guard.order.get("type", "") == "follow" and guard.order.get("target") == master, "with nobody hostile, it keeps following")
	check(guard.pos.distance_to(master.pos) < 4.5, "and it moves after its master (%.1f m)" % guard.pos.distance_to(master.pos))
	# The party, in front of the follower, becomes hostile: Aggression ends the follow.
	# A spot in its view that the follower can walk to.
	var spot := Vector2.INF
	for a in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.2, -1.2]:
		var p := w.nav.nearest_walkable(guard.pos + Vector2.from_angle(guard.facing + a) * 3.5)
		var path := w.nav.find_path(guard.pos, p, [guard, hero], [], 0.0, guard.move_class(), true, NAN, 20.0, 0.0, true)
		if not path.is_empty() and path[-1].distance_to(p) < 1.0:
			spot = p
			break
	check(spot.is_finite(), "a reachable spot in front of the follower")
	w.dialog_place(hero, spot, 0.0)
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	check(w.is_enemy(guard, hero), "the follower is now hostile to the party")
	var n := 0
	var left := false
	# It may first buff itself; then it attacks the party.
	while n < 600 and guard.order.get("target") != hero:
		ticks(s, 1); n += 1
		if guard.order.get("type", "") != "follow": left = true
		if n % 50 == 0: await get_tree().process_frame
	check(left, "a noticed hostile ends the scripted follow")
	check(guard.order.get("type", "") in ["attack", "cast"] and guard.order.get("target") == hero, "and it attacks the party (%d ticks, %s, noticed %d)" % [n, guard.order, w.ai.enemies(guard).size()])
	check(int(guard.get_meta("ai_state", 6)) in [3, 4], "its AI state leaves Follow")
	check(hero.order.is_empty() or hero.order.get("target") != guard, "the passive party did not start the fight")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("SCRIPTED_FOLLOW_ENGAGE ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
