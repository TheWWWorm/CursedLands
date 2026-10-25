extends "path_trace_zone_traversal.gd"
## Fixed first-person city route: adaptive exploration can choose another
## branch after a sub-metre position difference, invalidating FPS comparisons.
## --dar-benchmark removes the inspection cap; schedule that run as GPU heavy.
const ROUTE := [Vector2(167.8734,285.402),Vector2(182.8603,275.6479),
	Vector2(188.9388,292.5357),Vector2(182.8603,275.6479)]
func choose_goal(leg: int,_avoid: Array=[]) -> Vector2:
	return ROUTE[leg%ROUTE.size()]
func phase(label: String,seconds: float,goal:=Vector2.INF,pan:=false) -> void:
	Engine.max_fps=0 if OS.get_cmdline_user_args().has("--dar-benchmark") else 30
	# Live actors can briefly obstruct this crowded route. Keep the same
	# waypoint/arrival requirement, allowing time for the obstruction to clear.
	await super.phase(label,maxf(seconds,20.0) if goal.is_finite() else seconds,goal,pan)
	if goal.is_finite():check(hero.pos.distance_to(goal)<1.0,label+" reaches its fixed comparison waypoint")
