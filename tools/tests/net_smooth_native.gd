extends Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ", label)

func _ready() -> void:
	check(ClassDB.class_exists("NetSmoothKernel"), "native interpolation available")
	if failures:
		get_tree().quit(1); return
	var scalar := NetSmooth.new()
	var native: Object = ClassDB.instantiate("NetSmoothKernel")
	var rng := RandomNumberGenerator.new(); rng.seed = 661214
	var target := Vector2.ZERO
	var facing := 0.0
	var now := 0
	for i in 4096:
		if i % 11 == 0:
			target = Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		else:
			target += Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
		facing = rng.randf_range(-20, 20) if i % 7 else INF
		now += rng.randi_range(1, 700) if i % 17 else -200
		if i % 31 == 0:
			scalar.view = Vector2.INF; native.view = Vector2.INF
		if i % 23 == 0:
			scalar.yaw = INF; native.yaw = INF
		var quiet := i % 19 == 0
		scalar.got_at(target, now, quiet, facing)
		native.got_at(target, now, quiet, facing)
		check(scalar.view == native.view and scalar.yaw == native.yaw, "received position and yaw")
		check(scalar._speed == native._speed and scalar._yaw_speed == native._yaw_speed, "received rates")
		check(scalar._interval == native._interval and scalar._last_ms == native._last_ms, "interval clamp and smoothing")
		for dt in [-0.1, 0.0, 0.003, 0.02, 0.06, 0.2]:
			check(scalar.step(target, dt) == native.step(target, dt), "interpolated position")
			# Missing-facing snapshots preserve the old heading; the unit's
			# actual facing supplied to the draw pass is always finite.
			var angle := facing if is_finite(facing) else 0.0
			check(scalar.step_yaw(angle, dt) == native.step_yaw(angle, dt), "interpolated yaw")
	print("NET_SMOOTH_NATIVE checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
