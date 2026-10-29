extends Node
## A save keeps what NPCs are doing (the original's AIBrain::Save 5d8860 /
## Load 5d8310: the AI state, its point and glances, the motivations with
## their own data — PatrolMode 5d1a40 / 5d1930 its current point, Aggression
## 5d27a0 / 5d2770 its enemy — the noticed lists and the combat flag). Real
## Gipath zone (gz3g), real perception, combat and patrol motivations, full
## Session save/load:
## - two neighbouring patrolling goblins keep their patrol point, walk,
##   glances and remaining look time, then go on to the following points;
## - a brigand swordsman and a brigand archer that chase the fleeing hero keep
##   their attack on it and their combat stance through the load, also while
##   a saved attack clip still runs.
## - a zone stored on leaving and revisited keeps the segment but resumes no
##   fight with the party that walked out (only a game load does).
var checks := 0
var failures := 0
var s: Session
var g: Game
var wake: Array[int] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func freeze() -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	g.rig.set_process(false)
	for u: GameUnit in s.world.unit_rows():
		u.set_process(false); u.set_physics_process(false)

## The goblins patrol far from the party: keep them in the active set as the
## party's presence would (ObjectActivity wake pass).
func ticks(n: int) -> void:
	for i in n:
		for uid in wake:
			var u: GameUnit = s.world.units.get(uid)
			if u: s.world.active_set.wake_unit(u)
		s.world._tick(GameUnit.TICK)
		if i % 25 == 0: await get_tree().process_frame

func reload(slot: String) -> void:
	check(s.save_game(slot) == OK, slot + ": save succeeds")
	check(s.load_game(slot), slot + ": load succeeds")
	freeze()

func hero() -> GameUnit:
	return s.party_units(0)[0]

func toughen(u: GameUnit) -> void:
	for bp: UnitBodyPart in u.parts:
		bp.max = 100000.0; bp.cur = bp.max
	u.refresh_max_hp()

func calm(u: GameUnit) -> Dictionary:
	return u.get_meta("calm", {})

## The unit's order, or the one posted for its next tick.
func current(u: GameUnit) -> Dictionary:
	return u.order if not u.order.is_empty() else (u.orders[0] if not u.orders.is_empty() else {})

func attacking(u: GameUnit, t: GameUnit) -> bool:
	var o := current(u)
	return o.get("type", "") == "attack" and o.get("target") == t

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"net_lan":0,"net_upnp":0,"net_directory":0}, true)
	TutorialPanel.auto_show = false
	s = Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero"); s.state.world_time = 12.0; s.state.set_var(0,"q.gz3g.q1g",1)
	g = Game.new(); g.session=s; s.game=g; add_child(g)
	await s.enter_zone("gz3g",1,false); freeze()
	await _patrols()
	await _chase(3472, "swordsman")
	await _chase(3324, "archer")
	g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown()
	print("NPC_ACTION_SAVE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)


## Goblins 3363 (4 points) and 3364 (6 points) patrol side by side.
func _patrols() -> void:
	var ids: Array[int] = [3363, 3364]
	wake = ids
	for id in ids:
		var u: GameUnit = s.world.units[id]
		check(int(s.world.ai.logic(u).get("logic_model", 0)) == 2 and s.world.ai._patrol_points(u).size() >= 4,
			"goblin %d is an authored multi-point patrol" % id)
	# Walk until both are well into their routes and walking to a point.
	var n := 0
	while n < 3000:
		await ticks(5); n += 5
		var ready := true
		for id in ids:
			var u: GameUnit = s.world.units[id]
			if int(calm(u).get("patrol_i", 0)) < 2 or not u.order.get("calm", false) or u.order.get("type", "") != "move" \
					or u.pos.distance_to(calm(u).get("dest", u.pos)) < 3.0:
				ready = false
		if ready: break
	var before := {}
	for id in ids:
		var u: GameUnit = s.world.units[id]
		before[id] = {"c": calm(u).duplicate(true), "pos": u.pos, "to": u.order.get("to", Vector2.INF)}
		print("PATROL_BEFORE ", id, " ", u.pos, " ", calm(u), " order ", u.order.get("type", ""), " ", u.order.get("to", ""))
	check(n < 3000, "both goblins walk to a later patrol point (%d ticks)" % n)
	await reload("npc-patrol-walk")
	for id in ids:
		var u: GameUnit = s.world.units[id]
		var b: Dictionary = before[id]
		var c := calm(u)
		print("PATROL_AFTER ", id, " ", u.pos, " ", c, " order ", u.order.get("type", ""), " ", u.order.get("to", ""))
		check(u.pos.distance_to(b.pos) < 0.01, "goblin %d is where it was saved" % id)
		check(int(c.get("patrol_i", -1)) == int(b.c.patrol_i), "goblin %d keeps its patrol point (%d)" % [id, int(b.c.patrol_i)])
		check(c.get("dest", Vector2.INF) == b.c.dest and c.get("busy", false), "goblin %d keeps walking to that point" % id)
		check(var_to_str(c.get("look", [])) == var_to_str(b.c.look), "goblin %d keeps the glances planned at the point" % id)
		check(current(u).get("type", "") == "move" and current(u).get("calm", false) and current(u).get("to") == b.to,
			"goblin %d's calm walk order survives" % id)
	# Each goes on to the point after the saved one, not back to point 1.
	for id in ids:
		var u: GameUnit = s.world.units[id]
		var i0 := int(before[id].c.patrol_i)
		var pts: Array = s.world.ai._patrol_points(u)
		var k := 0
		while k < 1500 and int(calm(u).get("patrol_i", -1)) == i0:
			await ticks(5); k += 5
		var want := (i0 + 1) % pts.size()
		check(int(calm(u).get("patrol_i", -1)) == want and calm(u).get("dest") == pts[want][0],
			"goblin %d then walks to patrol point %d (%d ticks)" % [id, want, k])
	# A save during the look round at a point keeps the remaining hold.
	var u: GameUnit = s.world.units[ids[0]]
	var m := 0
	while m < 1500 and not (calm(u).get("busy", false) and float(calm(u).get("until", -1.0)) - s.world.time > 0.5):
		await ticks(1); m += 1
	var held := float(calm(u).get("until", -1.0)) - s.world.time
	var looks := (calm(u).get("look", []) as Array).size()
	check(m < 1500 and held > 0.5, "goblin %d holds a glance at its point (%.2f s left)" % [ids[0], held])
	await reload("npc-patrol-look")
	u = s.world.units[ids[0]]
	var left := float(calm(u).get("until", -1.0)) - s.world.time
	check(absf(left - held) < 0.001 and (calm(u).get("look", []) as Array).size() == looks,
		"the remaining glance time and glances survive (%.2f s, %d)" % [left, looks])
	wake = []


## A hostile brigand hit by the hero fights back (the production damage path:
## hit hook, noticed list, Aggression) and chases the hero when it runs off.
func _chase(uid: int, who: String) -> void:
	var u: GameUnit = s.world.units[uid]
	var h := hero()
	toughen(h); toughen(u)
	check(String(s.world.ai.mots(u).fight) == "standard" and s.world.is_enemy(u, h), "the %s is a hostile Aggression unit" % who)
	var p := s.world.nav.nearest_walkable(u.pos + Vector2.from_angle(u.facing) * 3.0)
	h.pos = p; h._sync_transform(0); s.world.nav.track_unit(h)
	h.facing = (u.pos - h.pos).angle()
	u.take_damage(1.0, h)
	var n := 0
	while n < 120 and not attacking(u, h):
		await ticks(1); n += 1
	check(attacking(u, h), "the %s fights back (%d ticks)" % [who, n])
	# The hero runs off, away from it; it gives chase.
	var away := Vector2.INF
	var back := (h.pos - u.pos).angle()
	for a in 16:
		var c := s.world.nav.nearest_walkable(h.pos + Vector2.from_angle(back + a * PI / 8.0 * (1 if a % 2 else -1)) * 40.0)
		if c.distance_to(h.pos) > 30.0:
			away = c; break
	h.move_to(away, true)
	var ranged: bool = u.stats.get("ranged", false)
	var k := 0
	# Save mid-pursuit: a swordsman on the run after the hero, an archer while
	# its shot clip runs.
	while k < 300 and not (attacking(u, h) and u.pos.distance_to(h.pos) > u.melee_reach(h) + 1.0 \
			and (u._anim_lock > 0.5 if ranged else k >= 30 and u.action in ["run", "walk"])):
		await ticks(1); k += 1
	var gap := u.pos.distance_to(h.pos)
	var lock := u._anim_lock
	print("CHASE_BEFORE ", who, " ", u.pos, " hero ", h.pos, " gap ", gap, " order ", current(u).get("type", ""), " lock ", lock, " alert ", u.alert)
	check(k < 300 and attacking(u, h) and u.alert, "the %s chases the fleeing hero (%.1f m, clip %.2f s)" % [who, gap, lock])
	var saved_hero_pos := h.pos
	var alarm := [u.has_meta("alerted"), int(u.get_meta("alarm_left", -1)), u.get_meta("ai_post", [])]
	await reload("npc-chase-" + who)
	u = s.world.units[uid]
	h = hero()
	toughen(h)
	print("CHASE_AFTER ", who, " ", u.pos, " hero ", h.pos, " order ", current(u).get("type", ""), " lock ", u._anim_lock, " alert ", u.alert)
	check(h.pos.distance_to(saved_hero_pos) < 0.01, "the hero is where it was saved")
	check(attacking(u, h), "the %s's attack on the restored hero survives the load" % who)
	check(u.alert, "the %s keeps its combat stance" % who)
	check([u.has_meta("alerted"), int(u.get_meta("alarm_left", -1)), u.get_meta("ai_post", [])] == alarm,
		"the %s keeps its alarm alert, countdown and guard segment %s" % [who, alarm])
	# Through the rest of a saved clip and after it: no pause in the pursuit.
	var hold := maxi(10, ceili(u._anim_lock / GameUnit.TICK) + 5)
	var kept := true
	for i in hold:
		await ticks(1)
		kept = kept and attacking(u, h) and u.alert
	check(kept, "the %s keeps attacking in its combat stance for %d ticks after the load" % [who, hold])
	var start := u.pos.distance_to(h.pos)
	await ticks(40)
	var later := u.pos.distance_to(h.pos)
	print("CHASE_LATER ", who, " ", u.pos, " hero ", h.pos, " gap ", later, " order ", current(u).get("type", ""))
	check(attacking(u, h) and (ranged or later < start or later <= u.melee_reach(h) + 0.5),
		"the %s goes on with the pursuit (%.1f -> %.1f m)" % [who, start, later])
	if who == "swordsman":
		_revisit(u, h)
	# Out of the next case's way.
	s.world.remove_unit(u)


## A zone stored on leaving and restored on a revisit (not a game load) keeps
## the guard segment and alarm state for its absence catch-up but no fight
## with the party that walked out: its units decide afresh.
func _revisit(u: GameUnit, h: GameUnit) -> void:
	check(attacking(u, h), "the swordsman still attacks before the zone is stored")
	var post: Variant = u.get_meta("ai_post", [])
	s.state.store_zone("gz3g", s.world)
	var row: Dictionary = s.state.zones["gz3g"].get("ai", {}).get(u.uid, {})
	check(row.has("attack") and row.get("alert", false), "the stored zone records the swordsman's attack and stance")
	u.order = {}; u.orders.clear(); u.alert = false
	s.state.restore_zone("gz3g", s.world)
	s.state.replay_restored(s.world)
	check(not attacking(u, h) and not u.alert and u.get_meta("ai_post", []) == post,
		"a zone revisit keeps the segment but resumes no fight with the departed party")
