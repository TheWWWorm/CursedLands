extends "res://tools/tests/water_raytrace_performance.gd"
## The same interleaved measurement with one real moving, animated character.
var hero: GameUnit
var start_position := Vector2.ZERO
var started := 0

func setup() -> Array:
	var context := await super.setup()
	for unit: GameUnit in context[0].world.units.values():
		if unit.has_meta("hero") and unit.model != null: hero = unit; break
	assert(hero != null)
	var view: Camera3D = t._reflection.camera
	var pixel := view.get_viewport().get_visible_rect().size*0.5
	var location := view.project_ray_origin(pixel)+view.project_ray_normal(pixel)*13.0
	hero.pos = Vector2(location.x,-location.z); start_position=hero.pos
	hero.placement_z = maxf(0.05,t._reflection.plane+1.0-context[0].world.ground_at(hero.pos.x,hero.pos.y))
	hero.show(); hero.resync_drawn(); hero.set_process(false); hero.set_physics_process(false)
	hero.model.act("walk",1,0.0); hero.model.player.pause(); started=Time.get_ticks_usec()
	return context

func begin_gpu() -> void:
	if hero != null:
		var time := (Time.get_ticks_usec()-started)/1000000.0
		hero.pos=start_position+Vector2(sin(time)*0.5,0); hero.resync_drawn()
		var clip := hero.model.player.get_animation("ei/"+hero.model._current)
		hero.model.player.seek(fmod(time,clip.length),true); hero.model.flush_pending_pose()
	super.begin_gpu()

func benchmark_orders() -> Array:
	return [["mirror_full","rt_half"],["rt_half","mirror_full"],["mirror_full","rt_half"]]

func benchmark_note() -> String:
	return "Frozen camera, one original character walking and moving every frame. Same motion in both modes; RT rebuilds live TLAS. Three interleaved rounds; not a crowded combat benchmark. RT uses quarter the pixels and approximate materials."
