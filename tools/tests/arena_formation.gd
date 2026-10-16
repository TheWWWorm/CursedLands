extends Node
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready()->void:
	var run:=ArenaRun.new();run.auto_save=false;run.begin(8341);run.training=126;run.wave=30
	for family in [0,1,2,3,4,6,7,9,11]:run._recruit(family,1,5)
	run.arrange()
	var battle:=ArenaPveMatch.new();battle.run=run;battle.rendered=false
	add_child(battle);battle.set_process(false);battle._world_parent=self;battle.prepare()
	var motion:=ArenaFormationMotion.new()
	var targets:={}
	for unit:GameUnit in battle.world.unit_rows():
		targets[unit]=unit.pos
		motion.enter(unit,unit.pos)
		if not motion.movers.has(unit):print("NO_ENTRANCE ",unit.info.prototype," ",unit.pos," radius=",unit.body_radius())
	check(motion.movers.size()==targets.size(),"all fifteen late-game creatures run into formation")
	for frame in 600:
		motion.advance(1.0/60.0,battle.world)
		if motion.movers.is_empty():break
	check(motion.movers.is_empty(),"dense mixed formation settles within ten seconds")
	for unit:GameUnit in targets:check(unit.pos.distance_to(targets[unit])<0.05,"native arrival preserves exact formation")
	var unit:GameUnit=battle.world.unit_rows()[0]
	var before:=unit.pos
	motion.move(unit,Vector2(29,39))
	for frame in 12:motion.advance(1.0/60.0,battle.world)
	check(unit.pos!=before and unit.pos.distance_to(Vector2(29,39))>0.1,"retargeted movement is continuous")
	var redirected:=Vector2(29,25)
	motion.move(unit,redirected)
	for frame in 600:
		motion.advance(1.0/60.0,battle.world)
		if motion.movers.is_empty():break
	check(motion.movers.is_empty() and unit.pos.distance_to(redirected)<0.05,"second move replaces the first destination")
	check(battle.world.time==0 and battle.damage==[0.0,0.0],"movement leaves combat state untouched")
	print("ARENA_FORMATION ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
