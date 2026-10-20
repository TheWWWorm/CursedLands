extends "third_person_kbm.gd"
## Run ordinary use orders through their authored clips and hit callbacks.
func _ready() -> void:
	check(GameData.option("direct_first_person_actions") == 1, "new profiles keep first-person actions by default")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"blood":0,"confine_mouse":0,"display_mode":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="first-person actions";await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	hero._story_clip="";hero._story_pose_ticks=0
	for enabled: int in [1,0]:
		GameData.options.direct_first_person_actions=enabled
		for sub: String in ["loot","science"]:
			for gait: int in [2,1,0]:
				reset();hero.restore_gait(gait);hero._anim_lock=0;hero.action="idle"
				var calls := [0]
				hero.command({"type":"use","sub":sub,"at":hero.pos,"done":func(): calls[0]+=1})
				var clips := {};var wrong_frames := 0;var ended := false
				for tick in 400:
					hero._tick(GameUnit.TICK);g.direct.apply_camera(GameUnit.TICK)
					if hero.action.begins_with("anim:"):
						clips[hero.action]=true
						if hero.model._head_hidden != bool(enabled) or not is_equal_approx(g.rig.camera.fov,75.0 if enabled else 65.0): wrong_frames+=1
					if hero.order.is_empty() and hero.orders.is_empty() and hero._anim_lock<=0:
						ended=true;break
				var label := "%s gait %d setting %d" % [sub,gait,enabled]
				check(not clips.is_empty(),label+" plays native action animations")
				check(wrong_frames==0,label+" keeps the selected action perspective throughout")
				check(ended and calls[0]==1,label+" completes and invokes its interaction once")
				check(hero.model._head_hidden and is_equal_approx(g.rig.camera.fov,75.0),label+" returns to ordinary first person")
				for tick in 10: hero._tick(GameUnit.TICK)
				check(calls[0]==1,label+" does not repeat its effect after completion")
				evidence.cases.append({"sub":sub,"gait":gait,"enabled":enabled,"clips":clips.keys(),"wrong_camera_frames":wrong_frames,"callbacks":calls[0]})
	GameData.options.direct_first_person_actions=1;hero.action="anim:uspecial25"
	GameData.options.control_mode=2;g.direct.apply_camera()
	check(not hero.model._head_hidden and is_equal_approx(g.rig.camera.fov,65.0),"third-person mode stays third person with action preference enabled")
	GameData.options.control_mode=3;g.rig.held=true
	var held := g.rig.camera.global_transform;g.direct.apply_camera()
	check(g.rig.camera.global_transform==held,"scripted camera framing retains ownership")
	FileAccess.open("user://first-person-actions.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":evidence.cases,"assertions":evidence.assertions},"\t"))
	print("FIRST_PERSON_ACTIONS ", JSON.stringify({"checks":checks,"failures":failures}))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
