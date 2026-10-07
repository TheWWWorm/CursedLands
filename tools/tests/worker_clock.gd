extends Node
## Clock conservation and bounded delivery after real elapsed stalls. This
## changes only the separate worker's backlog policy, never tick duration.
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
	check(w._logic_step == 5,"long stall delivers at most five ticks")
	check(is_equal_approx(total(w),3.0),"elapsed time retained after stall")
	check(w.logic_fraction() >= 0.0 and w.logic_fraction() < 1.0,"backlog never extrapolates a spline")
	for i in range(1,21):
		var before := w._logic_step
		w._sample_frame(2500+i*10,2.0)
		check(w._logic_step-before <= 5,"bounded repayment")
		check(absf(total(w)-(3.0+i*0.02)) < 1e-8,"conserved elapsed time")
	check(w._logic_debt == 0.0 and absf(w.time-3.4) < GameWorld.TICK,"worker catches up")
	# No queued tick executes during a movie; its wall duration is excluded.
	var s := Session.new()
	w.session = s
	w.stop_at = w._logic_step+2
	var before := total(w)
	w._sample_frame(3000,2.0)
	check(s.movie_active(),"movie interrupts the batch")
	check(absf(total(w)-before-0.6) < 1e-8,"interrupted batch retains undelivered time")
	check(w.logic_fraction() < 1.0,"interrupted fraction is bounded")
	var steps := w._logic_step
	before = total(w)
	w._sample_frame(13000,2.0)
	check(w._logic_step == steps and total(w) == before,"movie duration never enters backlog")
	s._movie_ev = {}
	w.stop_at = -1
	w._sample_frame(13010,2.0)
	check(w._logic_step-steps <= 5 and absf(total(w)-before-0.02) < 1e-8,"movie resumes bounded pending work")
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
	w.session = null
	w.free(); s.free()
	print("WORKER_CLOCK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
