extends Node
## Native Fear(1) records from both campaigns: a nearby allied NPC hears a
## 26-tick delayed warning, then investigates even without seeing the enemy.
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready()->void:
	var expansion:=GameData.campaign_id==CampaignProfile.ASTRAL
	var mob:=EIMob.load_bytes(GameData.read_file("maps/zone1.mob" if expansion else "maps/zone18.mob"))
	var record:Dictionary={}
	for o:Dictionary in mob.objects:
		if "peasants" in String(o.get("prototype","")).to_lower() and not o.get("logic",[]).is_empty() and o.logic[0].aggression==3:
			record=o.duplicate(true);break
	check(not record.is_empty(),"authored fearful peasant exists")
	if record.is_empty():get_tree().quit(1);return
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false);w.zone={"type":"game"}
	record.nid=1;record.position=Vector3(20,20,0)
	var peon:=w.spawn_unit(record)
	var guard_rec:=record.duplicate(true);guard_rec.nid=2;guard_rec.position=Vector3(24,20,0);guard_rec.logic[0].aggression=0
	var guard:=w.spawn_unit(guard_rec)
	guard_rec.nid=3;guard_rec.position=Vector3(45,20,0)
	var far_guard:=w.spawn_unit(guard_rec)
	var enemy:=w.spawn_unit({"nid":4,"prototype":"Human Hero","position":Vector3(18,20,0),"player":0})
	for u:GameUnit in [peon,guard,far_guard,enemy]:u.set_process(false);u.set_physics_process(false);u._perceive_next=INF;u.ai_next=INF
	enemy.controller=0;w.set_relation(peon.faction,enemy.faction,2)
	peon.set_meta("noticed",{enemy.get_instance_id():enemy});peon.set_meta("perceived",w.time)
	check(w.ai.mots(peon).fear==1 and w.ai.logic(peon).help_radius==10.0,"authored Fear(1) and help radius retained")
	w.ai._fear_tick(peon,1)
	check(w.ai._help.any(func(e):return e[0]==guard) and not w.ai._help.any(func(e):return e[0]==far_guard),"seeing danger calls nearby allies only")
	for tick in 26:
		w.time+=GameUnit.TICK;w.ai.tick()
		# Repeated calls must not keep postponing an older warning.
		w.ai.call_for_help(peon,enemy.pos)
	check(not guard.has_meta("suspect"),"warning waits the original 26 ticks")
	w.time+=GameUnit.TICK;w.ai.tick()
	check(guard.has_meta("suspect") and guard.get_meta("suspect").pos==enemy.pos,"oldest repeated warning reaches an ally at the danger point")
	check(not far_guard.has_meta("suspect"),"distant ally remains unaware")
	check(not w.ai.activity._eligible_script(guard),"warning remains visible to activity scheduling")
	w.ai._help.clear();guard.remove_meta("suspect");w.ai.hit_hook(peon,enemy)
	check(w.ai._help.any(func(e):return e[0]==guard),"being hit calls for help too")
	w.free();get_tree().quit(1 if failures else 0)
