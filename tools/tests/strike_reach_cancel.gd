extends Node
## A blow or spell is not dealt when its action no longer reaches at the
## impact. The original (549d40) ends the action without
## finishing it when the target has left the planned reach (planned at
## 54ca40: reach + 0.5 m for a target that is not running off in front), or
## when the caster can no longer cast (Feeblemind). Real field zone, hero,
## strike timing and spell delivery.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func health(u: GameUnit) -> float:
	var sum := 0.0
	for p in u.parts: sum += p.cur
	return sum

## Ticks until the hero starts a strike that will hit; then `dodge` moves the
## target away. Returns the target's part health lost by that blow.
func strike(w: GameWorld, hero: GameUnit, t: GameUnit, dodge: bool) -> float:
	var n := 0
	while n < 3000:
		w._tick(GameUnit.TICK); n += 1
		if not hero._pending_hit.is_empty() and hero._pending_hit.get("target") == t and hero._pending_hit.roll.hit:
			break
	if hero._pending_hit.is_empty():
		return -1.0
	var before := health(t)
	if dodge:
		w.dialog_place(t, w.nav.nearest_walkable(t.pos + (t.pos - hero.pos).normalized() * 3.0), 0.0)
	while not hero._pending_hit.is_empty():
		w._tick(GameUnit.TICK)
	return before - health(t)

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
	var t := w.spawn_unit({"nid":990801, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	var side := 1
	while side == hero.faction: side += 1
	t.faction = side
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	t.ai_next = INF; t._perceive_next = INF
	for bp: UnitBodyPart in t.parts:
		bp.max = 100000.0; bp.cur = bp.max
	hero.attack(t)
	var lost := strike(w, hero, t, true)
	check(lost == 0.0, "a target that steps out of reach during the swing takes no blow (%.2f)" % lost)
	check(hero.order.get("type", "") == "attack" and hero.order.get("target") == t, "the attack order goes on")
	lost = strike(w, hero, t, false)
	check(lost > 0.0, "a target that stays takes the next landing blow (%.2f)" % lost)
	# A spell whose caster is feebleminded before the release is lost.
	t.parts[1].cur = t.parts[1].max * 0.5
	var hurt := health(t)
	Spells.cast_after(w, hero, "healing", t, t.pos, GameUnit.TICK * 3.0)
	Spells.apply(w, null, "feeblemind", hero, hero.pos)
	check(hero.cannot_cast(), "the caster is feebleminded during the cast")
	for i in 10: w._tick(GameUnit.TICK)
	check(is_equal_approx(health(t), hurt), "its spell is not released")
	hero.buffs.erase("feeblemind")
	Spells.cast_after(w, hero, "healing", t, t.pos, GameUnit.TICK * 3.0)
	for i in 10: w._tick(GameUnit.TICK)
	check(health(t) > hurt, "control: a caster that can cast releases it")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("STRIKE_REACH_CANCEL ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
