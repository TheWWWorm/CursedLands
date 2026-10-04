class_name NetSmooth
extends RefCounted
## Remake co-op (clients): the host sends unit positions about 10 times a
## second (Session.SNAP_RATE), late and unevenly over the internet. Drawn at
## those positions a walking unit would jump every few frames; instead it is
## drawn gliding from where it is drawn to the newest position, timed to
## arrive when the next snapshot is due (the measured snapshot interval).
## Jumps over TELEPORT metres (and `quiet` updates) are shown at once.
## The facing likewise: a turning unit's snapshot facing steps by up to
## TURN_SPEED x the interval (0.9 rad) each time; drawn as it came it turned in
## jerks, so the drawn yaw turns towards the newest facing over the interval too.

const TELEPORT := 6.0

var view := Vector2.INF
var yaw := INF
var _speed := 0.0
var _yaw_speed := 0.0
var _last_ms := 0
var _interval := 0.1


func got(target: Vector2, quiet := false, facing := INF) -> void:
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		_interval = clampf(lerpf(_interval, (now - _last_ms) / 1000.0, 0.25), 0.05, 0.4)
	_last_ms = now
	if quiet or view == Vector2.INF or view.distance_to(target) > TELEPORT:
		view = target
		_speed = 0.0
		if facing != INF:
			yaw = facing
		_yaw_speed = 0.0
		return
	_speed = view.distance_to(target) / _interval
	if facing != INF and yaw != INF:
		_yaw_speed = absf(angle_difference(yaw, facing)) / _interval


func step(target: Vector2, dt: float) -> Vector2:
	if view == Vector2.INF or view.distance_to(target) > TELEPORT:
		view = target
		yaw = INF   # placed anew: facing as it is (step_yaw)
	else:
		view = view.move_toward(target, maxf(_speed, 0.5) * maxf(dt, 0.0))
	return view


## The yaw to draw (after step): turning towards `facing` at the pace the
## snapshots showed (at least 2 rad/s, for a facing set between snapshots).
func step_yaw(facing: float, dt: float) -> float:
	if yaw == INF:
		yaw = facing
	else:
		yaw = rotate_toward(yaw, facing, maxf(_yaw_speed, 2.0) * maxf(dt, 0.0))
	return yaw


# ---------------------------------------------------------------- host: interest

## Beyond this distance from every player-controlled unit a unit's snapshot
## goes out at a fifth of the rate (Session._physics_process).
const FAR := 90.0


static func near_points(world: GameWorld) -> PackedVector2Array:
	var out := PackedVector2Array()
	for u: GameUnit in world.units.values():
		if u.controller >= 0 and not u.dead:
			out.append(u.pos)
	return out


static func far(p: Vector2, near: PackedVector2Array) -> bool:
	for q in near:
		if p.distance_squared_to(q) < FAR * FAR:
			return false
	return not near.is_empty()
