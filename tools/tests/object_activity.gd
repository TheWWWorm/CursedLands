extends Node
## The original updates only the objects near the players in campaign zones
## (ObjectActivity). In gz3g the patrol goblin 3379 stood at its spawn for 49
## game hours in the original while Zak stayed at the entrance; the remake
## moved it and its patrol into a trap. This checks the freeze, the wake when
## the party comes near, the expiry once it leaves, and runtime spawns.
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

## Run until `u` is frozen (at most 4000 ticks).
func asleep(s: Session, u: GameUnit) -> bool:
	var n := 0
	while s.world.active_set.is_awake(u) and n < 4000:
		ticks(s, 1); n += 1
		if n % 50 == 0: await get_tree().process_frame
	return not s.world.active_set.is_awake(u)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0))
	await s.enter_zone("gz3g",1,false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	var gob: GameUnit = w.units.get(3379)
	check(gob != null, "goblin 3379 is in gz3g")
	if gob == null:
		get_tree().quit(1); return
	var spawn := gob.pos
	var entrance := hero.pos
	for i in 60:
		ticks(s, 20)
		await get_tree().process_frame
	check(w.active_set.enabled, "gz3g (a game zone) updates only its active objects")
	check(hero.pos.distance_to(spawn) > w.active_set.wake_radius(hero) + 2 * ObjectActivity.CELL,
		"the goblin is beyond the party's wake cells (%.0f m)" % hero.pos.distance_to(spawn))
	check(not w.active_set.is_awake(gob) and gob.pos == spawn, "the far goblin is frozen at its spawn")
	check(w.active_set.is_awake(hero), "the party is updated")
	# The magic trap on the goblins' patrol route sleeps too.
	var trap := -1
	for nid in w.traps.traps:
		var p: Vector3 = w.traps.traps[nid].pos
		if trap < 0 or Vector2(p.x, p.y).distance_to(spawn) < Vector2(w.traps.traps[trap].pos.x, w.traps.traps[trap].pos.y).distance_to(spawn):
			trap = nid
	check(trap >= 0 and not w.active_set.trap_awake(trap), "the trap near the patrol sleeps")
	# An object created during play starts awake.
	var rec: Dictionary = gob.info.duplicate(true)
	rec.erase("nid")
	rec.position = Vector3(spawn.x + 3, spawn.y, 0)
	var extra := w.spawn_unit(rec)
	check(extra != null and w.active_set.is_awake(extra), "a unit spawned during play is awake")
	# Woken around a point with nobody near, it sleeps again after its
	# 128-143 ticks, unless it is alert or knows a living enemy.
	w.active_set.wake_at(spawn, 1.0)
	check(w.active_set.is_awake(gob), "a wake around its cell wakes it")
	ticks(s, 120)
	check(w.active_set.is_awake(gob), "it is still awake 120 ticks later")
	ticks(s, 30)
	check(not w.active_set.is_awake(gob), "it sleeps again after its counter runs out")
	# The party comes near: it wakes and moves on its patrol. Friends, so
	# that neither side fights and the goblin can forget the party.
	w.set_relation(gob.faction, 0, 0)
	w.set_relation(0, gob.faction, 0)
	w.dialog_place(hero, w.nav.nearest_walkable(spawn + Vector2(25, 0)), 0.0)
	ticks(s, 2)
	check(w.active_set.is_awake(gob), "the goblin wakes when the party comes near")
	var moved := false
	for i in 40:
		ticks(s, 20)
		if gob.pos != spawn: moved = true; break
		await get_tree().process_frame
	check(moved, "the woken goblin moves")
	check(w.active_set.trap_awake(trap), "the trap near the patrol wakes with it")
	# The patrol leads into that trap. As in 1.06 it selects no unit, so
	# nobody is hit and its countdown does not start.
	check(int(w.traps.traps[trap].timer) == 0, "the woken trap never casts")
	# The party leaves: once the goblin forgets it, it freezes where it is,
	# standing rather than walking in place, and walks on when woken.
	w.dialog_place(hero, entrance, 0.0)
	var n := 0
	while w.active_set.is_awake(gob) and n < 2000:
		ticks(s, 1); n += 1
		if n % 50 == 0: await get_tree().process_frame
	check(not w.active_set.is_awake(gob), "the goblin sleeps again after the party left (%d ticks)" % n)
	check(not gob.action in ["walk", "run"], "a sleeping goblin stands (%s)" % gob.action)
	var at := gob.pos
	ticks(s, 100)
	check(gob.pos == at, "a sleeping goblin does not move")
	moved = false
	for i in 60:
		w.active_set.wake_at(gob.pos, 1.0)
		ticks(s, 10)
		if gob.pos != at: moved = true; break
		await get_tree().process_frame
	check(moved, "woken again, it walks on")
	# Other wakes: an attack on it, and the light of fireworks or
	# clairvoyance cast near it from afar.
	check(await asleep(s, gob), "it sleeps again")
	w.combat.blank_hit(gob, null, true)
	check(w.active_set.is_awake(gob), "an attack wakes a frozen unit")
	check(await asleep(s, gob), "it sleeps again")
	Spells.apply(w, hero, "fireworks{}", null, gob.pos + Vector2(20, 0))
	ticks(s, 2)
	check(w.active_set.is_awake(gob), "fireworks nearby wake it")
	check(await asleep(s, gob), "it sleeps again after the fireworks")
	Spells.apply(w, hero, "clairvoyence{}", null, gob.pos + Vector2(20, 0))
	ticks(s, 2)
	check(w.active_set.is_awake(gob), "clairvoyance nearby wakes it")
	print("RESULT failures=", failures)
	get_tree().quit(1 if failures else 0)
