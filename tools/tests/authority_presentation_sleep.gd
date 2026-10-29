extends Node
## The solo campaign's simulation worker is a headless authority: it draws
## nothing, yet placed and animated every actor every frame, about as much
## CPU as the simulation itself at normal speed. Actors the world has not
## ticked for two logic steps (asleep outside the original's active set) now
## keep their figures on the invisible replicas' coarse presentation clock.
## A tick, a placement, a turn or an observer wakes them at once; their
## animation time still arrives; a drawing authority and the opt-out keep
## presenting every frame.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func sleeping(units: Array) -> int:
	var n := 0
	for u: GameUnit in units:
		if u._presentation_sleeping: n += 1
	return n

## Two logic steps without ticking these actors, then two frames.
func rest(w: GameWorld) -> void:
	w._logic_step += 2
	await frames(2)

func _ready() -> void:
	check(GameUnit._headless, "runs headless, as the worker does")
	var w := GameWorld.new(); w.zone = {"type":"game"}; w.presentation = false; add_child(w)
	# A real-time authority ticks from its frame clock (_process); with that
	# off and physics processing on, the test advances its logic steps itself
	# while the world still reports drawing frames, as the worker's does.
	w.set_process(false); w.set_physics_process(true)
	check(w.authority and w.draw_frame_enabled(), "authority world draws frames")
	var units: Array = []
	for i in 6:
		var u: GameUnit = w.spawn_unit({"prototype":"Human Hero", "position":Vector3(5.0 + 3.0 * i, 5.0, 0.0)})
		u.ai_next = INF; u._perceive_next = INF
		units.append(u)
	check(units.all(func(u: GameUnit) -> bool: return u.model != null and u.model.player != null), "actors carry figures")
	await frames(2)
	check(sleeping(units) == 0, "actors present every frame while recently ticked")
	await rest(w)
	check(sleeping(units) == units.size(), "actors the world stopped ticking sleep their presentation")
	check(units.all(func(u: GameUnit) -> bool: return not u.is_processing() and not u.model.is_processing()), "a sleeping actor and its figure take no frame callbacks")
	# Animation time still arrives on the coarse clock.
	var a: GameUnit = units[0]
	var clock_before: float = a._anim_clock
	w.time += 0.6
	for i in 2 * GameWorld.HIDDEN_PRESENTATION_BUCKETS:
		w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(a._presentation_sleeping and a._anim_clock > clock_before and is_equal_approx(a._anim_clock, w.draw_time()),
		"a sleeping actor's animation clock follows the world's draw time: %.3f -> %.3f" % [clock_before, a._anim_clock])
	# A tick wakes the actor before its logic runs, and it stays awake while ticked.
	a.tick(GameUnit.TICK)
	check(not a._presentation_sleeping and a.is_processing() and a.model.is_processing(), "a tick wakes the actor's presentation")
	w._logic_step += 1
	await frames(2)
	check(not a._presentation_sleeping, "one logic step without a tick keeps it awake")
	await rest(w)
	check(a._presentation_sleeping, "two logic steps without a tick put it back to sleep")
	# A placement or a turn outside a tick wakes it and places it at once.
	var b: GameUnit = units[1]
	b.pos = b.pos + Vector2(1.0, 0.0)
	check(not b._presentation_sleeping and b._xf_pos == b.pos, "a placement wakes the actor and places its figure")
	await rest(w)
	var c: GameUnit = units[2]
	c.facing = c.facing + 1.0
	check(not c._presentation_sleeping and c._xf_facing == c.facing, "a turn wakes the actor and turns its figure")
	await rest(w)
	# An observed figure (the unit panel) never sleeps.
	var d: GameUnit = units[3]
	d.anim_watched = true
	check(not d._presentation_sleeping, "observing the figure wakes it")
	await rest(w)
	check(not d._presentation_sleeping and sleeping(units) == units.size() - 1, "an observed figure keeps presenting every frame")
	d.anim_watched = false
	await rest(w)
	check(sleeping(units) == units.size(), "all actors sleep again once unobserved")
	# A drawing authority (the co-op host, the arena) is unchanged.
	w.presentation = true
	for u: GameUnit in units: u.wake_presentation()
	await rest(w)
	check(sleeping(units) == 0, "a drawing authority presents every actor every frame")
	w.presentation = false
	await rest(w)
	check(sleeping(units) == units.size(), "the headless authority sleeps them again")
	# The opt-out keeps the earlier behaviour.
	GameUnit.sleep_idle_authority = false
	for u: GameUnit in units: u.wake_presentation()
	await rest(w)
	check(sleeping(units) == 0, "--ei-eager-authority presents every actor every frame")
	GameUnit.sleep_idle_authority = true
	await rest(w)
	check(sleeping(units) == units.size(), "sleeping resumes with the default")
	# A world tick wakes exactly the actors it ticks.
	for u: GameUnit in units: u.wake_presentation()
	w.active_set.wake_unit(units[4])
	await rest(w)
	w._tick(GameUnit.TICK)
	await frames(1)
	check(not units[4]._presentation_sleeping and sleeping(units) == units.size() - 1, "the world tick wakes the actors it ticks and no other")
	w.queue_free()
	await frames(4)
	print("AUTHORITY_PRESENTATION_SLEEP ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
