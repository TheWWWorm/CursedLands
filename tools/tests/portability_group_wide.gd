extends Node
## Portability.group runs a load-time group (`wide`) on its own threads, one
## per processor, instead of the four-thread pool: every job runs exactly
## once, on more threads than the pool when the machine has them, uneven
## jobs balance across the lanes, a pool group inside a wide job completes,
## and small or constrained groups keep the pool.
var checks := 0
var failures: Array[String] = []

class Record extends RefCounted:
	var lock := Mutex.new()
	var runs := {}      # index -> count
	var threads := {}   # thread id -> jobs
	var out := []
	func note(i: int, value: int) -> void:
		lock.lock()
		runs[i] = int(runs.get(i, 0)) + 1
		var id := OS.get_thread_caller_id()
		threads[id] = int(threads.get(id, 0)) + 1
		out[i] = value
		lock.unlock()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

static func work(i: int, spins: int) -> int:
	var acc := i
	for k in spins:
		acc = (acc * 1103515245 + 12345) & 0x7fffffff
	return acc

func complete(r: Record, n: int, label: String) -> void:
	var once := r.runs.size() == n
	for i in n:
		once = once and int(r.runs.get(i, 0)) == 1 and r.out[i] == work(i, 2000)
	check(once, "%s: every job ran once with its own result (%d of %d)" % [label, r.runs.size(), n])

func _ready() -> void:
	var processors := OS.get_processor_count()
	var pool := Portability.POOL_THREADS
	var main := OS.get_main_thread_id()
	# 1. A wide group with plenty of jobs.
	var n := 512
	var r := Record.new()
	r.out.resize(n)
	var t0 := Time.get_ticks_usec()
	Portability.group(func(i: int) -> void: r.note(i, work(i, 2000)), n, true)
	var wide_us := Time.get_ticks_usec() - t0
	complete(r, n, "wide")
	var lanes := Portability.wide_lanes(n)
	check(lanes == mini(mini(processors, Portability.WIDE_LANES), n / 2) or Portability.constrained(), "wide lanes are one per processor up to the limit (%d for %d processors)" % [lanes, processors])
	if lanes > pool:
		check(r.threads.size() > pool, "a wide group runs on more threads than the pool (%d > %d)" % [r.threads.size(), pool])
		check(r.threads.size() <= lanes, "no more lanes than asked (%d <= %d)" % [r.threads.size(), lanes])
		check(not r.threads.has(main), "the caller's thread runs no wide job")
		var busiest := 0
		for id: int in r.threads:
			busiest = maxi(busiest, r.threads[id])
		check(busiest < n / 2, "the jobs spread over the lanes (busiest ran %d of %d)" % [busiest, n])
	else:
		check(r.threads.size() >= 1, "a small machine keeps the pool (%d threads)" % r.threads.size())
	# 2. Uneven jobs: the lanes take the next job each, so one long job does
	# not hold the others' lanes idle (the group ends soon after that job).
	var u := Record.new()
	u.out.resize(64)
	var spans := PackedInt64Array()
	spans.resize(64)
	t0 = Time.get_ticks_usec()
	Portability.group(func(i: int) -> void:
		var started := Time.get_ticks_usec()
		var v := work(i, 200000 if i == 0 else 2000)
		u.note(i, v)
		spans[i] = Time.get_ticks_usec() - started, 64, true)
	var uneven_us := Time.get_ticks_usec() - t0
	var long_us := spans[0]
	var others_us := 0
	for i in range(1, 64):
		others_us += spans[i]
	check(u.runs.size() == 64 and int(u.runs.get(0, 0)) == 1 and long_us > 0, "uneven group: every job ran once")
	if lanes > pool:
		check(uneven_us < long_us + others_us / 2, "the long job does not serialize the rest (%d us; long %d us, others %d us)" % [uneven_us, long_us, others_us])
	# 3. A pool group inside a wide job completes (no deadlock between the
	# dedicated lanes and the pool).
	var inner := Record.new()
	inner.out.resize(16 * 8)
	Portability.group(func(i: int) -> void:
		Portability.group(func(k: int) -> void: inner.note(i * 8 + k, work(i * 8 + k, 2000)), 8), 16, true)
	complete(inner, 16 * 8, "pool groups inside a wide group")
	# 4. The pool path is unchanged: every job once, on the caller's thread or
	# the pool's.
	var p := Record.new()
	p.out.resize(n)
	Portability.group(func(i: int) -> void: p.note(i, work(i, 2000)), n)
	complete(p, n, "pool")
	check(p.threads.size() <= pool + 1, "a pool group stays within the pool (%d threads)" % p.threads.size())
	# 5. Small and empty groups.
	var s := Record.new()
	s.out.resize(3)
	Portability.group(func(i: int) -> void: s.note(i, work(i, 2000)), 3, true)
	complete(s, 3, "three wide jobs")
	check(Portability.wide_lanes(3) <= 1 and Portability.wide_lanes(0) == 0, "too few jobs for lanes (%d, %d)" % [Portability.wide_lanes(3), Portability.wide_lanes(0)])
	var ran := [0]
	Portability.group(func(_i: int) -> void: ran[0] += 1, 0, true)
	check(ran[0] == 0, "an empty group runs nothing")
	# 6. A wide group may be run again at once (the lanes are joined).
	var again := Record.new()
	again.out.resize(n)
	Portability.group(func(i: int) -> void: again.note(i, work(i, 2000)), n, true)
	complete(again, n, "wide, again")
	print("PORTABILITY_GROUP_TIMING processors=%d lanes=%d wide_us=%d uneven_us=%d long_us=%d others_us=%d threads=%d" % [
		processors, lanes, wide_us, uneven_us, long_us, others_us, r.threads.size()])
	print("PORTABILITY_GROUP_WIDE ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
