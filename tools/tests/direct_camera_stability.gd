extends "third_person_kbm.gd"
var measurements:=[]
func frames(n:=4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g) and is_instance_valid(g.rig):g.rig._window_focused=true

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="first-person camera";await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	hero.pos=Vector2(69.82051,128);hero.facing=0;hero._sync_transform(0);hero.reset_physics_interpolation();hero._anim_lock=0
	g.direct.heading=0;g.direct.tilt=-0.1;hero.action="idle"
	for gait: int in [2,1,0]:
		hero.restore_gait(gait);hero._anim_lock=0;hero.action="idle"
		for i in 90:g.direct.apply_camera(1.0/60.0)
		for act: String in (["idle","walk","attack"] if gait==2 else ["idle","walk"]):
			hero.action=act;hero.model.act(act,1,0);var anim:=hero.model.player.get_animation(hero.model.player.current_animation)
			var lo:=Vector3(INF,INF,INF);var hi:=-lo;var head_lo:=lo;var head_hi:=hi
			for i in 61:
				hero.model.player.seek(anim.length*float(i)/60,true);hero.model.flush_pending_pose()
				var before:=hero.model.eye_position();g.direct.apply_camera(1.0/60)
				check(hero.model.eye_position().is_equal_approx(before),"camera leaves skeleton intact") if i==0 else null
				var at:=g.rig.camera.global_position-hero.global_position;lo=lo.min(at);hi=hi.max(at)
				var head:=hero.model.eye_position()-hero.global_position;head_lo=head_lo.min(head);head_hi=head_hi.max(head)
			measurements.append({"gait":gait,"action":act,"camera_range":hi-lo,"head_range":head_hi-head_lo})
			check((hi-lo).length()<0.002,"stable view through %s at gait %d"%[act,gait])
	check(hero.model._head_hidden,"head stays hidden in player-controlled first person")
	hero.action="idle";hero.restore_gait(2);hero._anim_lock=0
	var previous:=g.rig.camera.global_position;var max_step:=0.0
	for i in 90:
		g.direct.apply_camera(1.0/60);var at:=g.rig.camera.global_position;max_step=maxf(max_step,at.distance_to(previous));previous=at
	check(max_step<=2.5/60+0.001,"posture height changes ease without a one-frame jump")
	var before:=g.rig.camera.global_position;var root_before:=hero.global_position;hero.pos+=Vector2(5,0);hero._sync_transform(0);g.direct.apply_camera(1.0/60)
	check((g.rig.camera.global_position-before).distance_to(hero.global_position-root_before)<0.002,"camera follows actor translation immediately")
	var direction:=Vector3(0,0,-1);g.direct.heading=PI/2;g.direct.tilt=0;g.direct.apply_camera(0)
	check((-g.rig.camera.global_basis.z).distance_to(direction)<0.001,"mouse look remains immediate")
	hero.action="anim:uspecial25";hero.model.play("uspecial25",0,true);hero.model.player.seek(0,true);hero.model.flush_pending_pose();g.direct.apply_camera(1.0/60)
	check(not hero.model._head_hidden and is_equal_approx(g.rig.camera.fov,65.0),"opening lie-down uses an external view")
	check(g.rig.camera.global_position.distance_to(hero.model.eye_position())>0.7,"opening camera stays clear of the lying body")
	check(hero.model._current=="uspecial25","camera does not replace the opening animation")
	hero.action="idle";hero.model.act("idle",1,0);g.direct.apply_camera(1.0/60)
	check(hero.model._head_hidden and is_equal_approx(g.rig.camera.fov,75.0),"first-person view resumes after scripted pose")
	GameData.options.control_mode=2;g.direct.heading=0;g.direct.tilt=-0.1;g.direct.apply_camera(1.0/60)
	var old_fraction:=g.direct._shoulder_fraction;g.direct._shoulder_fraction=old_fraction*0.3
	g.direct.apply_camera(1.0/60)
	check(g.direct._shoulder_fraction>old_fraction*0.3 and g.direct._shoulder_fraction<old_fraction,"shoulder view eases out after obstruction clears")
	g.rig.held=true;var held:=g.rig.camera.global_transform;g.direct.apply_camera(1.0/60)
	check(g.rig.camera.global_transform==held,"scripted camera retains ownership")
	var report={"checks":checks,"failures":failures,"measurements":measurements,"max_posture_step":max_step,"assertions":evidence.assertions}
	FileAccess.open("user://direct-camera-stability.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMERA_CHECKS ",checks," checks ",failures.size()," failures ",measurements)
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
