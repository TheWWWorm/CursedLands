extends Node
## Overlap escape, swaps, long detours, fast arrival and paused presentation.
var checks := 0
var failures: Array[String] = []
var battle: ArenaPveMatch
var motion := ArenaFormationMotion.new()
var next_id := 500000

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func actor(id: String, point: Vector2, side := 1) -> GameUnit:
	next_id += 1
	var unit := battle.world.spawn_unit({"prototype":id,"nid":next_id,"player":side,"position":Vector3(point.x,point.y,0)})
	ArenaPveMatch._fit_figure(unit)
	unit.pos=point; unit.resync_drawn(); battle.world.nav.track_unit(unit)
	return unit

func reset() -> void:
	motion.clear()
	if battle: battle.free()
	var run := ArenaRun.new(); run.auto_save=false; run.begin(8341); run.army.clear()
	battle=ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self; battle.prepare()
	for unit: GameUnit in battle.world.unit_rows(): battle.world.remove_unit(unit)

func finish(seconds := 8.0) -> bool:
	for frame in ceili(seconds*60):
		motion.advance(1.0/60.0,battle.world)
		if motion.movers.is_empty(): return true
	return false

func _ready() -> void:
	reset()
	var one := actor("cyclopsa20",Vector2(24,32))
	var two := actor("cyclopsa20",Vector2(24,32),2)
	motion.move(one,Vector2(22,26)); motion.move(two,Vector2(27,38))
	check(finish(), "initially overlapping large creatures separate and arrive")
	check(one.pos.distance_to(Vector2(22,26))<0.05 and two.pos.distance_to(Vector2(27,38))<0.05, "overlap escape keeps both exact destinations")
	reset()
	one=actor("cyclopsa20",Vector2(22,30)); two=actor("cyclopsa20",Vector2(30,30),2)
	motion.move(one,Vector2(30,30)); motion.move(two,Vector2(22,30))
	check(finish(), "head-on destination swap routes around other body")
	check(one.pos.distance_to(Vector2(30,30))<0.05 and two.pos.distance_to(Vector2(22,30))<0.05, "swap reaches both final positions")
	reset()
	one=actor("boarredf3",Vector2(22,32)); two=actor("cyclopsa20",Vector2(32,32),2)
	motion.move(one,Vector2(32,32))
	for frame in 120: motion.advance(1.0/60.0,battle.world)
	check(motion.movers.has(one) and one.pos.distance_to(Vector2(32,32))>0.5,"occupied destination keeps arrival pending")
	check(one.pos.distance_to(two.pos)>one.body_radius()+two.body_radius()-0.2,"stalled arrival keeps clear of the occupying body")
	motion.move(two,Vector2(36,39))
	check(finish() and one.pos.distance_to(Vector2(32,32))<0.05,"stalled creature recovers when the destination clears")
	reset()
	for index in 12: actor("cyclopsa20",Vector2(27,18.0+index*2.5))
	one=actor("boarredf3",Vector2(22,32))
	var target := Vector2(33,32)
	motion.move(one,target)
	var outside := false
	var distance := 0.0
	var before := one.pos
	for frame in 900:
		motion.advance(1.0/60.0,battle.world)
		distance += one.pos.distance_to(before); before=one.pos
		outside = outside or not ArenaTerrain.PLAY_AREA.has_point(one.pos)
		if motion.movers.is_empty(): break
	check(motion.movers.is_empty() and one.pos.distance_to(target)<0.05, "wide wall detour reaches destination")
	check(outside and distance>18.0, "long route can cross the field boundary while travelling")
	# Opposing giant formations cross, rotate and unpack from overlapping rows.
	for pattern in 6:
		reset()
		var actors: Array[GameUnit] = []
		var points: Array[Vector2] = []
		for index in 12:
			var point := Vector2(22.0+(index%3)*7,22.0+(index/3)*6)
			points.append(point)
			var initial := point if pattern < 3 else Vector2(25.0+(index%3),28.0+(index/3))
			actors.append(actor("cyclopsa20" if index%2==0 else "dragonbrownm16",initial,1+index%2))
		for index in 12:
			var destination := points[11-index] if pattern%3==0 else points[(index+(3 if pattern%3==1 else 5))%12]
			motion.move(actors[index],destination)
		check(finish(15.0),"twelve mixed giants finish crossing pattern %d" % pattern)
		for index in 12:
			var destination := points[11-index] if pattern%3==0 else points[(index+(3 if pattern%3==1 else 5))%12]
			check(actors[index].pos.distance_to(destination)<0.05,"giant keeps destination %d:%d" % [pattern,index])
	reset()
	one=actor("trollblackslowf16",Vector2(22,32))
	motion.move(one,Vector2(34,32))
	check(finish(3.0), "slow native creature reaches twelve-metre move promptly")
	motion.move(one,Vector2(22,24)); motion.advance(0.1,battle.world)
	before=one.pos; motion.paused=true; motion.advance(1.0,battle.world)
	check(one.pos==before, "pause freezes deployment movement")
	motion.paused=false; motion.move(one,Vector2(28,39))
	check(finish(), "replacement destination supersedes an active detour")
	check(battle.world.time==0.0 and battle.damage==[0.0,0.0], "detours and speed boosts never advance combat")
	motion.clear(); battle.queue_free(); await get_tree().process_frame
	print("ARENA_DEPLOYMENT_MOTION ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
