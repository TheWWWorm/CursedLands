extends Node
## Independent builders: native owned records versus the original GDScript
## constructor. Cover route edges and seek boundaries, not merely metadata.
var checks := 0
var failures := 0
const DIRS := [Vector2i(0,-1),Vector2i(-1,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1),Vector2i(1,0),Vector2i(1,-1)]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ",label)

func compare(native: NavSpline, scalar: NavSpline, at: float) -> void:
	var a := native.sample(at)
	var b := scalar.sample_script(at)
	check(a == b, "sample %s: %s / %s" % [at,a,b])

func _ready() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 775229
	var native := NavSpline.new()
	var scalar := NavSpline.new(); scalar._kernel = null
	check(native._kernel != null and native._kernel.has_method("build"), "native route builder available")
	var build_native := 0
	var build_script := 0
	for trial in 768:
		var cells: Array[Vector2i] = []
		var values := PackedInt32Array()
		var p := Vector2i(rng.randi_range(-400,400),rng.randi_range(-400,400))
		for i in (trial % 65):
			cells.append(p)
			if trial % 5: values.append(rng.randi_range(0,1024))
			p += DIRS[rng.randi_range(0,7)] if trial % 11 else Vector2i.ZERO
		var from := Vector2(cells[0] if not cells.is_empty() else p)*0.5+Vector2(.1,.2)
		var to := Vector2(cells[-1] if not cells.is_empty() else p)*0.5+Vector2(.3,.4)
		if trial % 13 == 0: to = from
		var base := rng.randf_range(.01,1.0) if trial % 7 else 0.0
		var turn := rng.randf_range(.01,.8) if trial % 9 else 0.0
		if trial % 17 == 0: turn = 1e10
		var heading := rng.randf_range(-PI,PI)
		var before := Time.get_ticks_usec()
		native.build(from,to,cells,values,base,turn,heading)
		build_native += Time.get_ticks_usec()-before
		check(native._native_records, "normal route uses native construction")
		before = Time.get_ticks_usec()
		scalar.build_script(from,to,cells,values,base,turn,heading)
		build_script += Time.get_ticks_usec()-before
		check(native.start == scalar.start and native.heading == scalar.heading and native.initial_turn == scalar.initial_turn and native.turn_rate == scalar.turn_rate and native.duration == scalar.duration, "route timing " + str(trial))
		check(native.controls == scalar.controls, "controls " + str(trial))
		check(native.nodes == scalar.nodes, "nodes " + str(trial))
		check(native._lengths == scalar._lengths and native._intervals == scalar._intervals and native._x_coefficients == scalar._x_coefficients and native._y_coefficients == scalar._y_coefficients, "coefficients " + str(trial))
		for at in [-1.0,0.0,.000001,1.0,20.0,1000.0]: compare(native,scalar,at)
		var boundary := absf(scalar.initial_turn)/turn if turn > 0.0 else 0.0
		if turn > 0.0:
			for interval in scalar._intervals:
				if not is_finite(boundary): break
				for offset in [-.00000001,0.0,.00000001]: compare(native,scalar,boundary+offset)
				boundary += interval
		if is_finite(scalar.duration):
			for at in [scalar.duration,scalar.duration+.001,scalar.duration*.5]: compare(native,scalar,at)
			for i in 16: compare(native,scalar,rng.randf_range(0,scalar.duration+.1))
		# Input edits and later rebuilds cannot alter a retained route.
		var snapshot := native.sample(2.0)
		cells.clear(); values.fill(0)
		check(native.sample(2.0) == snapshot,"owned construction input")
	# Old script construction switch is independent of sampling fallback.
	native._native_build = false
	native.build(Vector2(.1,.2),Vector2(1.2,1.3),[Vector2i.ZERO,Vector2i.ONE],PackedInt32Array([512,384]),.2,1,.4)
	check(not native._native_records,"diagnostic switch retains original builder")
	compare(native,native,1.0)
	var bad: PackedFloat64Array = native._kernel.build(Vector2.ZERO,Vector2.ONE,[Vector2i(2147483647,0)],PackedInt32Array(),.2,1,.4)
	check(bad.is_empty(),"unrepresentable cell deltas rejected")
	print("MOTION_BUILD checks=",checks," failures=",failures," native_us=",build_native," script_us=",build_script)
	get_tree().quit(1 if failures else 0)
