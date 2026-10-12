extends "third_person_kbm.gd"
## Actual authority steering and native/DirectPose animation, rendered at
## every sampled frame. No placeholder animation or isolated idle pose.
var measurements := []
var armor := PackedStringArray()

func _ready() -> void:
	mode="running straight down"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":3,"pad_enabled":0,"confine_mouse":0,"display_mode":0,"blood":0},true)
	RenderingServer.set_render_loop_enabled(true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("bz8k",1,false);await prepare()
	for u: GameUnit in s.world.units.values():
		if u.info.get("name","")=="AGuard1": armor=PackedStringArray(u.info.get("armors",u.proto.get("wears",[])))
	check(not armor.is_empty(),"use native Ingos guard armor for the clothed running case")
	await s.enter_zone("gz11k",1,false);await prepare()
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	hero.direct_controlled=true;hero._present_frame(1.0/60)
	var start:=hero.pos;var found:=false
	for ring in 32:
		for angle in 16:
			hero.pos=start+Vector2.from_angle(float(angle)*TAU/16)*ring
			s.world.nav.track_unit(hero)
			if [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN].all(func(d):return s.world.nav.direct_line(hero,hero.pos+d*6.0)):
				found=true;break
		if found:break
	check(found,"loaded Ingos snow terrain has room for sustained steering")
	start=hero.pos
	var weapons:=PackedStringArray(hero.info.get("weapons",[]))
	var shirt:=PackedStringArray(hero.info.get("armors",[]))
	for armored: bool in [false,true]:
		hero.set_equipment(armor if armored else shirt,weapons)
		await frames(3)
		for fov: int in [5,0,12]: # default 75, minimum 50, maximum 110 degrees
			GameData.options.direct_fov_first=fov
			reset();hero.stop_steering();hero.pos=start;hero.mana=hero.max_mana
			hero.restore_gait(2);hero._anim_lock=0;hero._sync_transform(0);hero.reset_physics_interpolation()
			g.direct.heading=0;g.direct.tilt=0;g.direct.look(Vector2(0,100))
			check(is_equal_approx(g.direct.tilt,-1.45),"mouse reaches maximum downward pitch")
			var sprint:=InputEventKey.new();sprint.keycode=KEY_SHIFT;sprint.physical_keycode=KEY_SHIFT;sprint.pressed=true
			Input.parse_input_event(sprint)
			var acc:=0.0;var distance:=0.0;var running:=0;var rim:=0;var duplicate:=0;var poses:Dictionary={}
			for frame in 360:
				var dt:=1.0/60.0
				g.direct.heading+=dt*1.3
				g.direct.step(Vector2.UP if frame<180 else Vector2.RIGHT,dt)
				acc+=dt
				while acc>=GameUnit.TICK:
					acc-=GameUnit.TICK;s.world.time+=GameUnit.TICK
					var from:=hero.pos;hero.tick(GameUnit.TICK);distance+=hero.pos.distance_to(from)
				hero._physics_process(dt);hero._process(dt)
				g.direct.apply_camera(dt)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				if hero.running and hero.action=="run": running+=1
				poses[snappedf(hero.model.player.current_animation_position,.05)]=true
				for vertex:Vector3 in hero.model._view_rim:
					if g.rig.camera.is_position_in_frustum(hero.model._view_chest.to_global(vertex)+hero.model._view_shift):rim+=1
				for row:Dictionary in hero.model._view_shadows:
					if row.shadow.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:duplicate+=1
				if frame in [100,230]:
					get_viewport().get_texture().get_image().save_png("user://running-down-armor%s-fov%d-frame%d.png" % [armored,fov,frame])
			sprint=InputEventKey.new();sprint.keycode=KEY_SHIFT;sprint.physical_keycode=KEY_SHIFT;Input.parse_input_event(sprint)
			g.direct.stop_move()
			var label:="armor=%s fov=%d" % [armored,50+fov*5]
			check(running>200 and distance>5.0 and poses.size()>8,"sustained real running and animation: "+label)
			check(rim==0,"neck rim stays outside every running/turning/strafe frame: "+label)
			check(duplicate==0,"one visible body and weapon in every frame: "+label)
			measurements.append({"case":label,"seconds":6,"frames":360,"run_frames":running,"distance":distance,"pose_samples":poses.size(),"rim_vertices_visible":rim,"duplicate_frames":duplicate})
	g.queue_free();s.queue_free();await frames(8)
	print("FIRST_PERSON_RUNNING_DOWN ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
