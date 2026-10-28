extends Node
## Being hit does not delay a fighter's next blow. The original's
## reaction check (549d00) refuses a hit reaction to a unit standing in an
## attack whose next strike comes before the reaction would end; otherwise
## the reaction plays as before. Real field zone, hero and damage.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

## Reactions out of `n` blows taken with the next strike `cd` seconds away.
func reactions(hero: GameUnit, t: GameUnit, cd: float, n: int) -> int:
	var count := 0
	for i in n:
		hero._anim_lock = 0.0; hero.action = "idle"; hero._attack_cd = cd
		hero.take_damage(0.01, t)
		if hero.action == "hit": count += 1
	hero._anim_lock = 0.0; hero.action = "idle"
	return count

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
	for bp: UnitBodyPart in hero.parts:
		bp.max = 100000.0; bp.cur = bp.max
	var p := w.nav.nearest_walkable(hero.pos + Vector2(1.5, 0))
	var t := w.spawn_unit({"nid":991001, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	var side := 1
	while side == hero.faction: side += 1
	t.faction = side; t.ai_next = INF; t._perceive_next = INF
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	for bp: UnitBodyPart in t.parts:
		bp.max = 100000.0; bp.cur = bp.max
	hero.attack(t)
	var n := 0
	while n < 400 and (hero.order.get("type", "") != "attack" or hero._moving or hero._pending_hit.is_empty()):
		w._tick(GameUnit.TICK); n += 1
	while not hero._pending_hit.is_empty():
		w._tick(GameUnit.TICK)
	check(hero.order.get("type", "") == "attack" and not hero._moving, "the hero stands fighting (%d ticks)" % n)
	check(reactions(hero, t, 0.1, 40) == 0, "a blow taken just before its next strike plays no reaction")
	check(reactions(hero, t, 2.0, 40) > 0, "with its next strike far off it still reacts")
	var keep := hero.order
	hero.order = {}
	check(reactions(hero, t, 0.0, 40) > 0, "a unit not attacking reacts to blows")
	hero.order = keep
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("HIT_REACTION_TEMPO ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
