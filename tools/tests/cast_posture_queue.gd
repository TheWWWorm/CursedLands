extends Node
## #109: changing gait during a one-shot must cross from the displayed
## casting posture after the spell finishes, on authority and replica.
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)

func step(w: GameWorld, u: GameUnit) -> void:
	w.time+=GameUnit.TICK
	u._tick(GameUnit.TICK); u._draw_step(GameUnit.TICK); u.anim_flush()
	u.model.player.advance(GameUnit.TICK); u.model._process(0)

func _ready() -> void:
	var w:=GameWorld.new(); add_child(w); w.set_process(false); w.set_physics_process(false); w.zone={"type":"game"}
	var rw:=GameWorld.new(); add_child(rw); rw.authority=false; rw.set_process(false); rw.set_physics_process(false)
	for pair: Array in [[2,0],[2,1],[1,2]]:
		var u:=w.spawn_unit({"prototype":"Human Hero","position":Vector3(5,5,0)})
		u.set_process(false); u.set_physics_process(false); u.controller=0; u._perceive_next=INF; u.ai_next=INF
		u.restore_gait(pair[0]); u._anim_lock=0; u.action="idle"; u._update_pose()
		u.max_mana=10000; u.mana=10000; u.stats.int=25.0
		u.command({"type":"cast","spell":"healing{}","target":u})
		for i in 120:
			step(w,u)
			if u.action.begins_with("cast"): break
		check(u.action.begins_with("cast"), "spell begins from gait %d" % pair[0])
		var from:=u.model.pose_state
		var replica:=rw.spawn_unit({"prototype":"Human Hero","position":Vector3(5,5,0)})
		replica.set_process(false); replica.set_physics_process(false); replica.apply_snapshot(u.snapshot(),true)
		u.set_gait(pair[1]); u._draw_step(0)
		replica.apply_snapshot(u.snapshot()); replica._draw_step(0)
		check(u.model.pose_state==from and replica.model.pose_state==from, "gait %d request keeps the displayed casting posture" % pair[1])
		var host_cross:=false; var replica_cross:=false
		for i in 160:
			step(w,u)
			replica.apply_snapshot(u.snapshot()); replica._draw_step(GameUnit.TICK); replica.anim_flush()
			replica.model.player.advance(GameUnit.TICK); replica.model._process(0)
			host_cross = host_cross or u.model._current.begins_with("ucross")
			replica_cross = replica_cross or replica.model._current.begins_with("ucross")
		check(host_cross,"authority plays the queued posture transition %d -> %d" % [pair[0],pair[1]])
		check(replica_cross,"replica plays the queued posture transition %d -> %d" % [pair[0],pair[1]])
		u.queue_free(); replica.queue_free()
	w.queue_free(); rw.queue_free()
	for i in 6: await get_tree().process_frame
	print("CAST_POSTURE_QUEUE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
