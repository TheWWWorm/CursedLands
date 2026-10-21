class_name ArenaFormationMotion
extends RefCounted
## Preparation uses the native movement command and path/footstep animation,
## without advancing perception, attacks, spell timers or the combat clock.
const PACE := 3.5
const MIN_SPEED := 7.0
const MAX_SPEED := 14.0
const RETRY_SECONDS := 0.25
var movers := {}
var paused := false
var _stalled := {}
var _retries := {}


func enter(unit: GameUnit, target: Vector2, origin := Vector2.INF) -> void:
	if origin == Vector2.INF:
		var direction := -1.0 if unit.faction == 1 else 1.0
		var candidates: Array[Vector2] = []
		# Prefer a run-in from the rear; packed giant formations may only
		# leave a short clear approach immediately ahead of the destination.
		var approach := ArenaTerrain.PLAY_AREA.grow(5.0)
		for distance in [8.0, 6.0, 4.0, 2.0, 1.0, -1.0, -2.0, -4.0, -6.0, -8.0]:
			for side in [0.0, -2.0, 2.0, -4.0, 4.0]:
				candidates.append(Vector2(clampf(target.x + direction * distance, approach.position.x, approach.end.x), clampf(target.y + side, approach.position.y, approach.end.y)))
		for candidate in candidates:
			if not unit.world.nav.cell_open(candidate,unit.move_class()): continue
			var clear := true
			for other: GameUnit in unit.world.unit_rows():
				if other != unit and candidate.distance_to(other.pos) < unit.body_radius() + other.body_radius() + 0.2:
					clear = false; break
			if not clear: continue
			var path := _route(unit, candidate, target)
			if not path.is_empty() and path[-1].distance_to(target) < 0.3:
				origin = candidate; break
	if origin != Vector2.INF:
		unit.pos = origin
		unit.facing = (target - origin).angle()
		unit.resync_drawn()
		unit.world.nav.track_unit(unit)
	move(unit, target)


func move(unit: GameUnit, target: Vector2) -> void:
	if unit.pos.distance_to(target) < 0.03: return
	unit.move_to(target, true)
	unit.order = unit.orders.pop_front()
	movers[unit] = target
	_stalled[unit] = 0.0
	_retries[unit] = 0
	_detour(unit, target)


func advance(dt: float, world: GameWorld) -> void:
	if paused: return
	# A slow rendered frame must not skip an entire blocking body.
	var remaining := minf(dt, 0.25)
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 30.0)
		_advance(step, world)
		remaining -= step


func _advance(dt: float, world: GameWorld) -> void:
	for unit in movers.keys():
		if not is_instance_valid(unit) or unit.world != world or unit.is_queued_for_deletion():
			forget(unit); continue
		var target: Vector2 = movers[unit]
		unit._moving = false
		unit._move_speed = 0.0
		unit._draw_motion_active = false
		unit._draw_line_goal = Vector2.INF
		if unit.pos.distance_to(target) > 0.03:
			if unit.order.is_empty():
				unit.move_to(target, true)
				unit.order = unit.orders.pop_front()
				_detour(unit, target)
			unit.running = true
			var speed := maxf(0.05, unit.speed())
			var pace := clampf(speed * PACE, MIN_SPEED, MAX_SPEED) / speed
			var before: Vector2 = unit.pos
			unit._do_move(dt * pace)
			unit._move_speed *= pace
			_stalled[unit] = float(_stalled.get(unit,0.0)) + dt if unit.pos.distance_squared_to(before) < 0.000001 else 0.0
			if float(_stalled[unit]) >= RETRY_SECONDS:
				_detour(unit, target)
				_stalled[unit] = 0.0
			# Positions already sample the native spline at presentation time.
			# Do not extrapolate them with the frozen combat clock's remainder.
			unit._draw_motion_active = false
			unit._draw_line_goal = Vector2.INF
		else:
			unit.order = {}; unit.orders.clear(); unit.path.clear()
			unit._set_action("idle")
			if unit._turn_to(0.0 if unit.faction == 1 else PI, dt * PACE): forget(unit)
		# Online preparation owns only this presentation pose; combat remains
		# host-authoritative. Do not smooth back to the last idle snapshot.
		if not world.authority: unit.net_view.got(unit.pos, true, unit.facing)
		unit._sync_transform(0.0)
		world.nav.track_unit(unit)


## Preparation has no combat clock to expire ordinary AI waits. Search around
## every current body, including other movers, and retry using presentation time.
## The complete courtyard navigation is available, including outside the field.
static func _route(unit: GameUnit, from: Vector2, target: Vector2, extra := 0.2) -> PackedVector2Array:
	var nav := unit.world.nav
	var avoid: Array = []
	for other: GameUnit in unit.world.unit_rows():
		if other != unit and not other.dead and not other.is_queued_for_deletion(): avoid.append(other)
	var exact := nav.exact_search
	nav.exact_search = false
	var route := nav.find_path(from,target,[unit],avoid,extra,unit.move_class(),true)
	nav.exact_search = exact
	return route


func _detour(unit: GameUnit, target: Vector2) -> void:
	var attempts := int(_retries.get(unit, 0))
	var padding := 0.0 if unit.pos.distance_to(target) < 2.0 else 0.2 + minf(attempts * 0.1,0.4)
	var route := _route(unit,unit.pos,target,padding)
	if route.is_empty() and padding > 0.0: route = _route(unit,unit.pos,target,0.0)
	_retries[unit] = attempts + 1
	if route.is_empty(): return
	# A partial route can finish while its destination is still occupied.
	# Restore the command before a stalled retry installs the next path.
	if not unit.order.has("to"):
		unit.move_to(target, true)
		unit.order = unit.orders.pop_front()
	unit.path = route
	unit._planned_motion = unit.world.nav.motion_record(unit.pos,route,unit.move_class(),unit.has_meta("flying"))
	unit._planned_motion.path = route
	unit._planned_motion.from = unit.pos
	unit._motion = null
	unit._avoid = null; unit._avoid_at = Vector2.INF; unit._wait_on = null
	unit.order.cost_started = true


func forget(unit) -> void:
	movers.erase(unit); _stalled.erase(unit); _retries.erase(unit)


func clear() -> void:
	for unit in movers:
		if not is_instance_valid(unit): continue
		unit.order = {}; unit.orders.clear(); unit.path.clear()
		unit._moving = false; unit._move_speed = 0.0
		unit._draw_motion_active = false; unit._draw_line_goal = Vector2.INF
		unit._set_action("idle")
	movers.clear()
	_stalled.clear(); _retries.clear()


## A ready formation must never hold combat behind a blocked walk-in.
func settle(world: GameWorld) -> void:
	for unit in movers:
		if not is_instance_valid(unit) or unit.world != world: continue
		unit.pos = movers[unit]
		unit.resync_drawn()
		world.nav.track_unit(unit)
	clear()
