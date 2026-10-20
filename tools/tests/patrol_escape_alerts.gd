extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func actor(w:GameWorld,id:int,faction:int,p:Vector2)->GameUnit:
	var u:=GameUnit.new();u.world=w;u.uid=id;u.pos=p;u.faction=faction
	u.proto={"senses":[8.5,100.0,0.0],"detection":[1.0,1.0,1.0],"peripheral_skills":0.0,"vision_arc":180.0}
	u.stats={"sight":8.5};u.info={"logic":[{"logic_model":1,"aggression":0,"help_radius":7.0}]}
	w.set_unit(id,u);return u
func _ready()->void:
	var w:=GameWorld.new();w.zone={"type":"game"};w.time=1
	var guard:=actor(w,1,1,Vector2.ZERO);var ally:=actor(w,2,1,Vector2(-4,0));var hero:=actor(w,3,0,Vector2(5,0))
	hero.controller=0;ally.facing=PI;w.set_relation(1,0,2);w.set_relation(1,1,0)
	check(w.ai.player_perceive(guard,true).has(hero.get_instance_id()),"guard spots approaching player")
	check(w.ai._help.any(func(e):return e[0]==ally),"spotting player alerts a nearby ally before a hit")
	check(not w.ai.player_perceive(ally,true).has(hero.get_instance_id()),"ally initially faces away from player")
	for i in 27:w.time+=GameUnit.TICK;w.ai.tick()
	check(ally.has_meta("suspect"),"ally investigates the warning after its sound delay")
	guard.order={"type":"attack","target":hero,"ai":true};guard.target=hero
	hero.pos=Vector2(40,0);w.time+=GameUnit.TICK
	check(w.ai.enemies(guard).has(hero),"original NPC rule retains an already noticed distant hostile")
	check(not guard.has_meta("suspect"),"distance alone does not replace combat with investigation")
	w.ai.rechoose(guard)
	check(guard.target==hero and guard.order.get("type")=="attack","distant attacker remains the active combat target")
	guard.orders.clear();guard.order={};hero.pos=Vector2(5,0);w.time+=GameUnit.TICK
	check(not w.ai.enemies(guard).is_empty(),"guard can detect the player again")
	guard.set_meta("um",UnitAI.MOT_AGGRESSION);hero.pos=Vector2(40,0);w.time+=GameUnit.TICK
	check(not w.ai.enemies(guard).is_empty(),"authored Aggression keeps scripted pursuit")
	guard.remove_meta("um");w.zone.type="arena";w.time+=GameUnit.TICK
	check(not w.ai.enemies(guard).is_empty(),"arena combat remains persistent")
	w.zone.type="game";w.time+=GameUnit.TICK;w.set_relation(1,0,1)
	guard.remove_meta("noticed");ally.remove_meta("noticed");hero.pos=Vector2(5,0);ally.pos=Vector2(-2,0);ally.facing=0
	check(not w.is_enemy(ally,hero),"neutral friend starts peaceful")
	w.ai.on_attacked(guard,hero)
	check(w.is_enemy(ally,hero) and not guard.dead,"witness becomes hostile before its friend dies")
	ally.remove_meta("hate");ally.remove_meta("noticed");ally.facing=PI;w.time+=GameUnit.TICK
	w.ai.on_attacked(guard,hero)
	check(not w.is_enemy(ally,hero),"friend who cannot see the assault remains neutral")
	ally.facing=0;ally.pos=Vector2(-50,0);w.time+=GameUnit.TICK
	w.ai.on_attacked(guard,hero)
	check(not w.is_enemy(ally,hero),"distant friend receives no global hostility")
	for u:GameUnit in [guard,ally,hero]:u.free()
	w.free();print("PATROL_ESCAPE_ALERTS ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
