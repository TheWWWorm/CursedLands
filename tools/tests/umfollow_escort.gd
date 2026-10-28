extends Node
## A UMFollow escort moves as the original's Follow state does: the Follow
## motivation (5d1e10) enters it and its tick (5d6f90) keeps FollowMinDist 2 /
## FollowMaxDist 4 round a standing target (no new walk while the target is
## within 4 m of the escort's goal) and leads a walking target by its
## position 5 ticks ahead. Real field zone, hero, AI and paths.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

## A walkable spot `r` from `from` that `u` can reach (the path's end within 1 m).
func reachable(w: GameWorld, u: GameUnit, from: Vector2, r: float) -> Vector2:
	for a in range(16):
		var c := w.nav.nearest_walkable(from + Vector2.from_angle(a * PI / 8.0) * r)
		if absf(c.distance_to(from) - r) > 0.3: continue
		var route := w.nav.find_path(u.pos, c, [u], [], 0.0, u.move_class(), true, NAN, 1e6, 0.0, false)
		if not route.is_empty() and route[-1].distance_to(c) < 1.0:
			return c
	return Vector2.INF

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	var at := reachable(w, hero, hero.pos, 3.2)
	check(at.is_finite(), "a reachable spot 3.2 m from the hero")
	var f := w.spawn_unit({"nid":991201, "prototype":"GoblinTutor", "player":1, "position":Vector3(at.x, at.y, 0)})
	f.faction = hero.faction
	f.mode = "follow"; f.mode_data = {"target": hero}
	var start := f.pos
	for i in 60: w._tick(GameUnit.TICK)
	print("UMFOLLOW_NEAR order ", f.order.get("type", ""), " moved ", f.pos.distance_to(start), " d ", f.dist3(hero))
	check(f.order.get("type", "") == "follow" and f.order.get("target") == hero, "the escort is in the Follow state on the hero")
	check(f.pos.distance_to(start) < 0.1, "3.2 m from a standing target it stays (within FollowMaxDist)")
	# Far from a standing target it walks up and stops within FollowMinDist.
	var far := reachable(w, hero, hero.pos, 7.0)
	check(far.is_finite(), "a reachable spot 7 m from the hero")
	w.dialog_place(f, far, 0.0)
	var n := 0
	while n < 300 and (f.dist3(hero) >= 2.0 or f.order.has("walk")):
		w._tick(GameUnit.TICK); n += 1
	check(f.dist3(hero) < 2.0 and not f.order.has("walk"), "7 m away it walks up and stops within 2 m (%d ticks, %.2f m)" % [n, f.dist3(hero)])
	# A walking target is led: the escort's goal lies ahead of it.
	var dest := reachable(w, hero, hero.pos, 14.0)
	check(dest.is_finite(), "a reachable spot 14 m ahead of the hero")
	hero.command({"type": "move", "to": dest, "run": false})
	var led := false
	var walks := 0
	for i in 200:
		var before: Vector2 = f.order.get("walk", Vector2.INF)
		w._tick(GameUnit.TICK)
		var goal: Vector2 = f.order.get("walk", Vector2.INF)
		if goal.is_finite() and goal != before and hero.follow_walking():
			walks += 1
			var heading := hero.future_pos(5) - hero.pos
			if heading.length() > 0.01 and (goal - hero.pos).dot(heading) > 0.0:
				led = true
		if hero.order.is_empty() and not hero.follow_walking():
			break
	check(walks > 0 and led, "behind a walking target it heads for the target's position 5 ticks ahead (%d walks)" % walks)
	for i in 200: w._tick(GameUnit.TICK)
	check(f.dist3(hero) <= 4.0, "it catches up once the target stops (%.2f m)" % f.dist3(hero))
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("UMFOLLOW_ESCORT ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
