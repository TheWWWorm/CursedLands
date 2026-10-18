extends Node
## Distant work stays spread after a stall and never caches a later pose.
class CountingUnit extends GameUnit:
	var presentations := 0
	var elapsed := 0.0
	func _present_frame(dt: float) -> void:
		presentations += 1
		elapsed += dt

class CountingFx extends ParticleFx:
	var target: GameUnit
	var samples := 0
	var points := []
	func _sample_unit_point(u: GameUnit, sel: int) -> Vector3:
		samples += 1
		return Vector3(u.uid,sel,u.pos.x)
	func _advance_effects(_dt: float) -> void:
		points = [unit_point(target,0),unit_point(target,0),unit_point(target,1)]

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	var world := GameWorld.new()
	world.authority = false
	world.arena_overview = true
	world._client_placement = RefCounted.new()
	for speed in [1.0,2.0]:
		Engine.time_scale = speed
		var crowd: Array[CountingUnit] = []
		for i in 162:
			var unit := CountingUnit.new(); unit.world = world
			unit._overview_present_due = ArenaTournamentBattles.overview_pose_phase(i) * speed
			crowd.append(unit)
		var previous_count := 0; var peak := 0
		for frame in 60:
			for unit in crowd: unit._process(speed/60.0)
			var count: int = crowd.reduce(func(total,unit):return total+unit.presentations,0)
			peak = maxi(peak,count-previous_count); previous_count = count
		check(peak <= 30,"162 distant actors spread across frames at either speed")
		check(crowd.all(func(unit):return unit.presentations == 10),"staggering retains every actor's full pose cadence")
		for unit in crowd: unit.free()
		var actors: Array[CountingUnit] = []
		for phase in [0.003,0.02,0.05,0.08]:
			var actor := CountingUnit.new()
			actor.world = world
			actor._overview_present_due = phase * speed
			actors.append(actor)
		for frame in 120:
			for actor in actors: actor._process(speed / 120.0)
		check(actors.all(func(u):return u.presentations >= 9 and u.presentations <= 11),"distant cadence is independent of combat speed")
		for actor in actors: actor._process(0.35 * speed)
		var phases := {}
		for actor in actors: phases[roundi(actor._overview_present_due / speed * 1000000.0)] = true
		check(phases.size() == actors.size(),"one long frame does not synchronize different actors")
		check(actors.all(func(u):return u._overview_present_due > 0.0),"overdue actors schedule a future pose")
		world.arena_overview = false
		for actor in actors:
			var before := actor.presentations
			actor._process(speed / 120.0)
			check(actor.presentations == before + 1,"focused presentation resumes immediately")
			check(absf(actor.elapsed - speed * (1.35 + 1.0/120.0)) < 0.00001,"all elapsed animation time survives throttling")
			actor.free()
		world.arena_overview = true
	Engine.time_scale = 1.0
	var actor := GameUnit.new(); actor.world = world; actor.uid = 77; actor.pos = Vector2(4,0)
	var fx := CountingFx.new(); fx.world = world; fx.target = actor
	fx._process(0.1)
	check(fx.samples == 2 and fx.points == [Vector3(77,0,4),Vector3(77,0,4),Vector3(77,1,4)],"one synchronous overview update reuses identical endpoints")
	check(fx._point_cache.is_empty() and not fx._point_cache_active,"effect updates release every cached endpoint")
	actor.pos.x = 9
	fx._process(0.1)
	check(fx.samples == 4 and fx.points[0] == Vector3(77,0,9),"the next effect update samples the new pose")
	world.arena_overview = false
	fx._process(0.1)
	check(fx.samples == 7,"focused effects keep their direct sampling path")
	fx.unit_point(actor,0); actor.pos.x = 11
	check(fx.unit_point(actor,0).z == 11 and fx.samples == 9,"queries outside an effect update cannot see stale cache data")
	fx.free(); actor.free(); world.free()
	print("ARENA_OVERVIEW_CADENCE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
