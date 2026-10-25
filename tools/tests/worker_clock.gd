extends Node
## Bounded real elapsed frames and conservation of admitted simulation work.
## Overload wall time is dropped; supplied/interrupted ticks remain ordered.
class ClockWorld extends GameWorld:
	var stop_at := -1
	var intervals: Array[float] = []
	func _tick_body(dt: float) -> void:
		time += dt
		intervals.append(dt)
		if _logic_step == stop_at and session:
			session._movie_ev = {"serial":1}

var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func total(w: ClockWorld) -> float:
	return w.time + w._logic_accumulator + w._logic_debt

func _ready() -> void:
	var legacy := ClockWorld.new()
	legacy._advance(3.0)
	check(legacy._logic_step == 5 and legacy._logic_debt == 0.0,"inline five-tick cap preserved")
	legacy.free()
	var w := ClockWorld.new()
	w.retain_logic_debt = true
	w._sample_frame(1000,2.0)
	w._sample_frame(2500,2.0)
	check(w._logic_step == 10,"fast-mode stall delivers at most ten ticks")
	check(is_equal_approx(total(w),0.55),"long stall admits only five wall ticks at the selected rate")
	check(w.logic_fraction() >= 0.0 and w.logic_fraction() < 1.0,"backlog never extrapolates a spline")
	for i in range(1,21):
		var before := w._logic_step
		w._sample_frame(2500+i*10,2.0)
		check(w._logic_step-before <= 10,"bounded repayment at selected rate")
		check(absf(total(w)-(0.55+i*0.02)) < 1e-8,"conserved admitted time")
	check(w._logic_debt == 0.0 and absf(w.time-0.95) < GameWorld.TICK,"worker resumes without replaying the stall")
	# No queued tick executes during a movie; its wall duration is excluded.
	var s := Session.new()
	w.session = s
	w.stop_at = w._logic_step+2
	var before := total(w)
	w._sample_frame(3000,2.0)
	check(s.movie_active(),"movie interrupts the batch")
	check(absf(total(w)-before-0.55) < 1e-8,"interrupted batch retains admitted undelivered time")
	check(w.logic_fraction() < 1.0,"interrupted fraction is bounded")
	var steps := w._logic_step
	before = total(w)
	w._sample_frame(13000,2.0)
	check(w._logic_step == steps and total(w) == before,"movie duration never enters backlog")
	s._movie_ev = {}
	w.stop_at = -1
	w._sample_frame(13010,2.0)
	check(w._logic_step-steps <= 10 and absf(total(w)-before-0.02) < 1e-8,"movie resumes bounded pending work")
	# Notifications reset raw timestamp, preserving only time already owed.
	before = total(w)
	w._notification(Node.NOTIFICATION_PAUSED)
	w._notification(Node.NOTIFICATION_UNPAUSED)
	w._sample_frame(33000,2.0)
	check(total(w) == before,"pause excludes the full paused wall interval")
	w._sample_frame(33010,2.0)
	check(absf(total(w)-before-0.02) < 1e-8,"resume accrues current time only")
	for notice in [Node.NOTIFICATION_EXIT_TREE,Node.NOTIFICATION_ENTER_TREE,
			Node.NOTIFICATION_DISABLED,Node.NOTIFICATION_ENABLED,
			Node.NOTIFICATION_APPLICATION_PAUSED,Node.NOTIFICATION_APPLICATION_RESUMED]:
		before = total(w)
		w._notification(notice)
		w._sample_frame(50000+notice,1.0)
		check(total(w) == before,"lifecycle timestamp reset %d" % notice)
	# Mixed frame sizes and rate changes conserve game time exactly, without
	# reading Engine's clamped frame delta or changing the native 55ms step.
	var expected := total(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 941352
	for i in 4096:
		var dt := rng.randf_range(0.0,0.03) if i%17 else rng.randf_range(0.2,1.2)
		steps = w._logic_step
		w._advance(dt)
		expected += dt
		check(w._logic_step-steps <= 5 and absf(total(w)-expected) < 1e-7,"mixed stalls %d" % i)
		check(w.logic_fraction() >= 0.0 and w.logic_fraction() < 1.0,"mixed fraction %d" % i)
	for dt in [NAN,INF,-INF,-1.0]:
		before = total(w)
		w._advance(dt)
		check(absf(total(w)-before) < 1e-8,"invalid elapsed never adds time")
	check(w.intervals.all(func(dt): return dt == GameWorld.TICK),"all ticks retain55ms")
	# Reporter #98: sustained slow callbacks used to saturate both speeds at
	# the identical five-tick cap. Exercise the real timestamp path in both
	# worker and inline worlds, not just a faster front-end animation clock.
	for worker in [false, true]:
		for frame_ms in [125, 200, 250, 500]:
			var rates := []
			for rate in [1.0, 55.0 / 27.0]:
				var slow := ClockWorld.new()
				slow.retain_logic_debt = worker
				slow._sample_frame(1000, rate)
				for frame in 40: slow._sample_frame(1000 + (frame + 1) * frame_ms, rate)
				rates.append(slow.time)
				check(slow.intervals.all(func(dt): return dt == GameWorld.TICK), "slow callbacks preserve tick duration")
				slow.free()
			check(rates[1] / rates[0] > 1.95, "fast stays faster with %dms callbacks, worker=%s" % [frame_ms, worker])
			print("SLOW_CLOCK frame_ms=", frame_ms, " worker=", worker, " fast/normal=", rates[1]/rates[0])
	w.session = null
	w.free(); s.free()
	print("WORKER_CLOCK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
