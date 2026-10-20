extends Node
## Original models, delayed snapshots and the same draw-step/animation path
## used by both the local simulation worker and remote co-op clients.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	GameData.options.merge({"auto_graphics":0,"volume_sfx":0,"volume_stream":0},true)
	var host:=GameWorld.new();add_child(host);host.set_process(false);host.set_physics_process(false)
	var view:=GameWorld.new();add_child(view);view.authority=false;view.set_process(false);view.set_physics_process(false)
	var a:=host.spawn_unit({"nid":1,"prototype":"GoblinA1","position":Vector3(5,5,0)})
	var b:=view.spawn_unit(a.info)
	for u:GameUnit in [a,b]:u.set_process(false);u.set_physics_process(false)
	for clip:String in ["uattack01","uattack03","uattack04"]:
		a._anim_acc=.4
		a.model.play(clip,0,true);a.action="attack"
		check(a._anim_acc==0.0,"new strike discards old clip's unflushed time")
		b.apply_snapshot(a.snapshot())
		check(b.model._current==clip,"replica plays the authority's selected "+clip)
		var phase:=b.model.player.current_animation_position
		b.apply_snapshot(a.snapshot())
		check(b.model.player.current_animation_position==phase,"duplicate paused snapshot cannot restart or advance a strike")
		# A snapshot arriving after five logic ticks must show that part of
		# the strike, not begin its windup after the damage event arrives.
		host.time+=5*GameUnit.TICK;view.time=host.time
		var late:=view.spawn_unit(a.info.merged({"nid":2}))
		late.set_process(false);late.set_physics_process(false)
		late.apply_snapshot(a.snapshot())
		check(late.model.player.current_animation_position>=4*GameUnit.TICK,"late snapshot catches up strike pose")
		view.remove_unit(late)
	var frog:=host.spawn_unit({"nid":3,"prototype":"ToadM1","position":Vector3(5,7,0)})
	frog.set_process(false);frog.set_physics_process(false)
	frog._anim_acc=.4;frog._cast_anim(frog._cast_clip(),0);frog.action="cast"
	check(frog._anim_acc==0.0,"frog spit starts at its first frame despite deferred idle time")
	for prototype:String in ["Human Hero","succubgreym13"]:
		var caster:=host.spawn_unit({"nid":5,"prototype":prototype,"position":Vector3(8,5,0)})
		check(caster!=null,"held-cast model exists: "+prototype)
		if caster==null:continue
		caster.set_process(false);caster.set_physics_process(false)
		var clip:=caster._cast_clip()
		caster._cast_anim(clip,12);caster.action="cast:12"
		var began:=host.time
		for step in 30:
			host.time=began+(step+1)*GameUnit.TICK
			caster.model.player.advance(caster._held(caster._pre_cast(GameUnit.TICK)))
			if step not in [4,15,29]:continue
			var late:=view.spawn_unit(caster.info.merged({"nid":6}))
			late.set_process(false);late.set_physics_process(false)
			view.time=host.time+10 # another packet may already have moved this clock
			late.apply_snapshot(caster.snapshot(),false,PackedFloat64Array(),host.time)
			check(late.model._current==caster.model._current,"late held cast uses exact clip: "+prototype)
			check(absf(late.model.player.current_animation_position-caster.model.player.current_animation_position)<.001,"late held cast preserves windup/hold/recovery phase: "+prototype)
			view.remove_unit(late)
		host.remove_unit(caster)
	var runner:=view.spawn_unit({"nid":4,"prototype":"Human Hero","position":Vector3(5,9,0)})
	runner.set_process(false);runner.set_physics_process(false)
	runner.action="run";runner._pose_snap=true;runner._update_pose();runner.model.act("run")
	runner.net_view.got_at(runner.pos,1000,true,0);runner._sync_transform(0);runner._speed_from=runner.pos
	var row:=runner.snapshot();row[1]+=.15;row[4]="idle";row[13]=0.0
	runner.apply_snapshot(row)
	runner._draw_step(1.0/60)
	check(runner.model._current.to_lower().contains("run"),"stop retains stride while interpolated body is still moving")
	check(runner._anim_rate()>0.0,"settling stride has a movement rate")
	for i in 30:runner._draw_step(1.0/60)
	check(runner._drawn.distance_to(runner.pos)<.001 and runner.model._current.to_lower().contains("idle"),"idle begins once the drawn body reaches destination")
	# At accelerated speed, drawn displacement is measured per simulation
	# second; packet intervals are still wall time.
	Engine.time_scale=55.0/27.0
	runner.action="run";runner.model.act("run");runner._settle_action=""
	runner.net_view.got_at(runner.pos,2000,true,0);runner._sync_transform(0);runner._speed_from=runner.pos
	row=runner.snapshot();row[1]+=.3;row[4]="idle";row[13]=0.0
	runner.apply_snapshot(row);runner._draw_step(Engine.time_scale/60.0)
	check(runner.model._current.to_lower().contains("run") and runner._draw_move_speed>0.0,"2x stop keeps moving legs through its final interpolated step")
	for i in 40:runner._draw_step(Engine.time_scale/60.0)
	check(runner._drawn.distance_to(runner.pos)<.001 and runner.model._current.to_lower().contains("idle"),"2x stop reaches idle at its destination")
	Engine.time_scale=1
	runner.action="run";runner.model.act("run");runner._settle_action=""
	runner.net_view.got(runner.pos,true,0);runner.net_view._speed=4.0
	runner._sync_transform(0);runner._speed_from=runner.pos
	row=runner.snapshot();row[1]+=.05;row[4]="idle";row[13]=0.0
	runner.apply_snapshot(row);runner._draw_step(1.0/60)
	check(runner._drawn.distance_to(runner.pos)<.001 and runner.model._current.to_lower().contains("idle"),"final partial stride keeps approach speed instead of a slow-motion tail")
	host.queue_free();view.queue_free()
	for i in 5:await get_tree().process_frame
	print("UNIT_PRESENTATION_TIMING ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
