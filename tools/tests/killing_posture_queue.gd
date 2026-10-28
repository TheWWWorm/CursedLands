extends Node
## #113: request crawl/kneel at several points in a real lethal melee swing.
## The shown cross must reach that posture on authority and replica.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr('FAIL ',label)
func step(w:GameWorld,u:GameUnit)->void:
	w.time+=GameUnit.TICK
	u._tick(GameUnit.TICK);u._draw_step(GameUnit.TICK);u.anim_flush()
	u.model.player.advance(GameUnit.TICK);u.model._process(0)
func _ready()->void:
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false);w.zone={'type':'game'}
	var rw:=GameWorld.new();add_child(rw);rw.authority=false;rw.set_process(false);rw.set_physics_process(false)
	for gait:int in [0,1]:
		for offset:int in [0,1,4,9,15]:
			var a:=w.spawn_unit({'prototype':'Human Hero','position':Vector3(5,5,0)})
			var b:=w.spawn_unit({'prototype':'Human Hero','position':Vector3(6,5,0)})
			for u:GameUnit in [a,b]:u.set_process(false);u.set_physics_process(false);u.ai_next=INF;u._perceive_next=INF
			a.controller=0;a.set_meta('hero',{});a.faction=0;b.faction=1;w.set_relation(0,1,2)
			# A party order on a unit goes on only while the party has noticed it
			# (54dd70); perception is off here, so the attacker is given that entry.
			a.set_meta('noticed',{b.get_instance_id():b})
			a.facing=0;b.facing=0
			a.stats.dmg_min=10000.0;a.stats.dmg_max=10000.0;a.stats.to_hit=10000.0;a.stats.dmg_types=PackedFloat32Array([0,0,1,0,0,0,0])
			a.restore_gait(2);a._anim_lock=0;a.action='idle';a._update_pose()
			a.command({'type':'attack','target':b,'aim':1})
			for i in 120:
				step(w,a)
				if a.action=='attack' and not a._pending_hit.is_empty():break
			check(a.action=='attack','starts killing attack')
			var replica:=rw.spawn_unit({'prototype':'Human Hero','position':Vector3(5,5,0)})
			replica.set_process(false);replica.set_physics_process(false);replica.apply_snapshot(a.snapshot(),true)
			for i in offset:step(w,a)
			a.set_gait(gait)
			var host_cross:=false;var replica_cross:=false
			for i in 150:
				step(w,a)
				replica.apply_snapshot(a.snapshot());replica._draw_step(GameUnit.TICK);replica.anim_flush()
				replica.model.player.advance(GameUnit.TICK);replica.model._process(0)
				host_cross=host_cross or (a.model._current.begins_with('ucross') and a.model.pose_state==(EIUnitModel.ST_LIE if gait==0 else EIUnitModel.ST_WARRY))
				replica_cross=replica_cross or (replica.model._current.begins_with('ucross') and replica.model.pose_state==(EIUnitModel.ST_LIE if gait==0 else EIUnitModel.ST_WARRY))
			print('KILL_CASE ',gait,' offset ',offset,' dead ',b.dead,' host ',host_cross,' replica ',replica_cross,' stance ',a.gait(),' clip ',a.model._current)
			check(b.dead,'blow kills target')
			check(a.gait()==gait and replica.gait()==gait,'killing blow preserves requested gait')
			check(host_cross,'authority crosses after kill');check(replica_cross,'replica crosses after kill')
			a.queue_free();b.queue_free();replica.queue_free()
	w.queue_free();rw.queue_free()
	for i in 6:await get_tree().process_frame
	print('KILLING_POSTURE_QUEUE ',checks,' checks ',failures,' failures')
	get_tree().quit(1 if failures else 0)
