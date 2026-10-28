extends Node
## Charm and taming follow the original (551ae0): each stage needs a
## power above the current stage x 10 + the creature's tame value, whatever its
## level; every success stops its action; a failure undoes a taming the
## tamer's side had begun (552280) and counts as an attack (455680), as any
## attempt on a unit a player owns does. Real field zone and prototypes.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func spawn(s: Session, nid: int, proto: String, at: Vector2, side: int) -> GameUnit:
	var p := s.world.nav.nearest_walkable(at)
	var u := s.world.spawn_unit({"nid":nid, "prototype":proto, "player":1, "position":Vector3(p.x, p.y, 0)})
	u.faction = side
	u.ai_next = INF; u._perceive_next = INF
	return u

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	# The highest-level creature prototype placed in the zone.
	var proto := ""
	var level := -1
	for u: GameUnit in w.unit_rows():
		if u.controller < 0 and not u.has_meta("hero") and int(u.proto.get("base_level", 0)) > level:
			level = int(u.proto.get("base_level", 0)); proto = String(u.info.get("prototype", ""))
	var side := 1
	while side == hero.faction: side += 1
	w.set_relation(hero.faction, side, 1); w.set_relation(side, hero.faction, 1)
	var a := spawn(s, 990401, proto, hero.pos + Vector2(3, 0), side)
	var tame := float(a.proto.get("tame_skills", 0.0))
	print("CHARM_PROTOTYPE ", proto, " level ", level, " tame ", tame)
	check(level >= 3, "a creature of level 3 or more (%d)" % level)
	# Power tame + 25: enough for all three stages, far below level x 10.
	var power := tame + 25.0
	a.order = {"type": "move", "to": a.pos + Vector2(5, 0)}
	check(Spells.tame(w, hero, a, power), "stage 1 needs only more than the tame value")
	check(int(a.get_meta("tame_stage", 0)) == 1 and not w.is_enemy(a, hero), "it stops being hostile to the tamer")
	check(a.order.is_empty() and a.orders.is_empty(), "the success stops its action")
	a.order = {"type": "move", "to": a.pos + Vector2(5, 0)}
	check(Spells.tame(w, hero, a, power), "stage 2 needs more than tame + 10")
	check(a.faction == hero.faction and a.order.is_empty(), "it takes the tamer's side and stops again")
	check(Spells.tame(w, hero, a, power), "stage 3 needs more than tame + 20")
	check(CampaignState.is_pet(a) and a.controller == hero.controller, "the creature becomes the party's pet")
	# Power tame + 15 passes two stages; the third fails and undoes the taming.
	var b := spawn(s, 990402, proto, hero.pos + Vector2(-3, 0), side)
	var power2 := tame + 15.0
	check(Spells.tame(w, hero, b, power2) and Spells.tame(w, hero, b, power2), "tame + 15 passes two stages")
	check(int(b.get_meta("tame_stage", 0)) == 2 and b.faction == hero.faction, "the creature has taken the tamer's side")
	check(not Spells.tame(w, hero, b, power2), "the third stage needs more than tame + 20")
	check(int(b.get_meta("tame_stage", 0)) == 0 and b.faction == side and not b.has_meta("peace"), "the failure undoes the taming")
	check(w.is_enemy(b, hero), "and the creature turns on the tamer")
	# A failure with no taming begun leaves no stage but still provokes.
	var c := spawn(s, 990403, proto, hero.pos + Vector2(0, 3), side)
	check(not Spells.tame(w, hero, c, tame) and int(c.get_meta("tame_stage", 0)) == 0, "power equal to the tame value fails")
	check(w.is_enemy(c, hero), "a failed attempt is an attack")
	# A unit another player owns always resists, and is provoked.
	var d := spawn(s, 990404, proto, hero.pos + Vector2(0, -3), side)
	d.controller = hero.controller + 1
	check(not Spells.tame(w, hero, d, 1000000.0), "a unit a player owns cannot be charmed")
	check(w.is_enemy(d, hero), "the owned unit takes the attempt as an attack")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("CHARM_TAMING ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
