extends Node
## Hostility spreads through a group (original 552e00 / 552d00): an attacked
## unit trades its hostile sides with the diplomacy friends in its observer
## list within its help radius. A claim joins the friend's own hostility 30
## ticks later and then travels on from that friend. Seeing the attack is not
## required; units of another side and friends out of range stay neutral.
## Real field zone and world ticks; the units' own AI is held still.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func spawn(s: Session, nid: int, at: Vector2, side: int, facing: float) -> GameUnit:
	var p := s.world.nav.nearest_walkable(at)
	var u := s.world.spawn_unit({"nid":nid, "prototype":"PigF0", "player":1, "position":Vector3(p.x, p.y, 0)})
	u.faction = side; u.facing = facing
	u.visible = true; u.fogged = false; u.hidden = false
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
	hero.max_hp = 100000.0; hero.hp = hero.max_hp; hero.aggressive = false
	var side := 1
	while side == hero.faction: side += 1
	var other := side + 1
	while other == hero.faction: other += 1
	for f in [side, other]:
		w.set_relation(hero.faction, f, 1); w.set_relation(f, hero.faction, 1)
	w.set_relation(side, other, 1); w.set_relation(other, side, 1)
	var at := hero.pos + Vector2(4, 0)
	var victim := spawn(s, 990301, at, side, 0.0)
	# The help radius: the.mob logic radius, or ai.reg CallForHelpRadius.
	var r := float(w.ai.logic(victim).get("help_radius", GameData.ai_value("Logic", "CallForHelpRadius", 7.0)))
	if r == GameData.ai_value("Logic", "CallForHelpRadiusDefault", 7.0):
		r = GameData.ai_value("Logic", "CallForHelpRadius", 7.0)
	print("HOSTILITY_HELP_RADIUS ", r)
	# The near friend faces away from the attack; the chained one is beyond
	# the victim's radius but within the near friend's.
	var near := spawn(s, 990302, at + Vector2(0.5 * r, 0), side, 0.0)
	var chained := spawn(s, 990303, at + Vector2(1.1 * r, 0), side, 0.0)
	var far := spawn(s, 990304, at + Vector2(0, 3.0 * r), side, 0.0)
	var stranger := spawn(s, 990305, at + Vector2(0, 0.3 * r), other, 0.0)
	# Let the spawned units enter each other's (8–11 tick) candidate lists.
	for i in 12: w._tick(GameUnit.TICK)
	check(near.pos.distance_to(victim.pos) < r and chained.pos.distance_to(victim.pos) >= r \
		and chained.pos.distance_to(near.pos) < r, "the friends stand inside and beyond the victim's help radius (%.1f m)" % r)
	check(near in w.ai._notice_candidates(victim), "the near friend is in the victim's observer list")
	for u in [victim, near, chained, far, stranger]:
		check(not w.is_enemy(u, hero), "unit %d starts neutral" % u.uid)
	victim.take_damage(0.5, hero)
	check(w.is_enemy(victim, hero), "the attacked unit turns hostile at once")
	check(not w.is_enemy(near, hero), "its friend is not hostile at the moment of the attack")
	var near_at := -1
	var chained_at := -1
	for n in range(1, 101):
		w._tick(GameUnit.TICK)
		if near_at < 0 and w.is_enemy(near, hero): near_at = n
		if chained_at < 0 and w.is_enemy(chained, hero): chained_at = n
	print("HOSTILITY_TICKS near=", near_at, " chained=", chained_at)
	check(near_at == 31, "the friend in range turns hostile 30 ticks later without seeing the attack (%d)" % near_at)
	check(chained_at >= near_at + 30 and chained_at <= near_at + 32, "the hostility travels on to the next friend 30 ticks after that (%d)" % chained_at)
	check(not w.is_enemy(far, hero), "a friend beyond every radius stays neutral")
	check(not w.is_enemy(stranger, hero), "a nearby unit of another side stays neutral")
	check(not w.is_enemy(near, victim) and not w.is_enemy(victim, near), "the friends stay friends")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("HOSTILITY_SPREAD ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
