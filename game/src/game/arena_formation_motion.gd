class_name ArenaFormationMotion
extends RefCounted
## Preparation uses the native movement command and path/footstep animation,
## without advancing perception, attacks, spell timers or the combat clock.
const PACE := 2.2
var movers := {}
var paused := false


func enter(unit: GameUnit, target: Vector2, origin := Vector2.INF) -> void:
	if origin == Vector2.INF:
		var direction := -1.0 if unit.faction == 1 else 1.0
		var candidates: Array[Vector2] = []
		# Prefer a run-in from the rear; packed giant formations may only
		# leave a short clear approach immediately ahead of the destination.
		for distance in [5.0, 3.5, 2.0, 1.0, 0.5, -0.5, -1.0]:
			for side in [0.0, -2.0, 2.0, -4.0, 4.0]:
				candidates.append(Vector2(clampf(target.x + direction * distance, 18.8, 45.2), clampf(target.y + side, 19, 45)))
		for candidate in candidates:
			var clear := true
			for other: GameUnit in unit.world.unit_rows():
				if other != unit and candidate.distance_to(other.pos) < unit.body_radius() + other.body_radius() + 0.2:
					clear = false; break
			if not clear: continue
			var path := unit.world.nav.find_path(candidate, target, [unit], [], 0.0, unit.move_class())
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


func advance(dt: float, world: GameWorld) -> void:
	if paused: return
	for unit in movers.keys():
		if not is_instance_valid(unit) or unit.world != world or unit.is_queued_for_deletion():
			movers.erase(unit); continue
		var target: Vector2 = movers[unit]
		unit._moving = false
		unit._move_speed = 0.0
		unit._draw_motion_active = false
		unit._draw_line_goal = Vector2.INF
		if unit.pos.distance_to(target) > 0.03:
			if unit.order.is_empty():
				unit.move_to(target, true)
				unit.order = unit.orders.pop_front()
			unit._do_move(dt * PACE)
			unit._move_speed *= PACE
			# Positions already sample the native spline at presentation time.
			# Do not extrapolate them with the frozen combat clock's remainder.
			unit._draw_motion_active = false
			unit._draw_line_goal = Vector2.INF
		else:
			unit.order = {}; unit.orders.clear(); unit.path.clear()
			unit._set_action("idle")
			if unit._turn_to(0.0 if unit.faction == 1 else PI, dt * PACE): movers.erase(unit)
		# Online preparation owns only this presentation pose; combat remains
		# host-authoritative. Do not smooth back to the last idle snapshot.
		if not world.authority: unit.net_view.got(unit.pos, true, unit.facing)
		unit._sync_transform(0.0)
		world.nav.track_unit(unit)


func clear() -> void:
	for unit in movers:
		if not is_instance_valid(unit): continue
		unit.order = {}; unit.orders.clear(); unit.path.clear()
		unit._moving = false; unit._move_speed = 0.0
		unit._draw_motion_active = false; unit._draw_line_goal = Vector2.INF
		unit._set_action("idle")
	movers.clear()


## A ready formation must never hold combat behind a blocked walk-in.
func settle(world: GameWorld) -> void:
	for unit in movers:
		if not is_instance_valid(unit) or unit.world != world: continue
		unit.pos = movers[unit]
		unit.resync_drawn()
		world.nav.track_unit(unit)
	clear()
