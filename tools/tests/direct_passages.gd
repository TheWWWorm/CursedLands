extends "third_person_kbm.gd"
var routes:=[]

func simulate(from: Vector2, to: Vector2, camera_mode: int) -> Vector2:
	reset();g.direct.stop_move();hero.pos=from;hero.restore_gait(2);hero._anim_lock=0;hero.facing=(to-from).angle()
	hero._perceive_next=INF;hero.ai_next=INF;s.world.nav.track_unit(hero);hero._sync_transform(0)
	GameData.options.control_mode=camera_mode
	s.apply_command({"t":"direct_control","leader":-1 if camera_mode==1 else hero.uid},0)
	if camera_mode==1:s.apply_command({"t":"move","units":[hero.uid],"x":to.x,"y":to.y},0)
	var ticks:=0
	for i in 120:
		if camera_mode!=1:s.apply_command({"t":"direct_move","units":[hero.uid],"direction":(to-hero.pos).normalized()},0)
		s.world.time+=GameUnit.TICK;hero.tick(GameUnit.TICK);ticks+=1
		if hero.pos.distance_to(to)<0.25:break
	var result:=hero.pos
	routes.append({"from":[from.x,from.y],"to":[to.x,to.y],"mode":camera_mode,"end":[result.x,result.y],"ticks":ticks})
	return result

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="starting ruins passage";await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false)
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	for pair: Array in [[Vector2(52.5,138),Vector2(52.5,134),true,true], [Vector2(56.3,138.9),Vector2(59.0,139.5),true,true], [Vector2(57.5,140),Vector2(57.5,138),false,false], [Vector2(58,140),Vector2(58,138),false,true]]:
		var a:Vector2=pair[0];var b:Vector2=pair[1]
		for camera_mode:int in [1,2,3]:
			check((simulate(a,b,camera_mode).distance_to(b)<0.3)==pair[2],"outward ruin passage/wall agrees with ordinary walking "+str(a)+", mode "+str(camera_mode))
			check((simulate(b,a,camera_mode).distance_to(a)<0.3)==pair[3],"inward ruin passage/wall agrees with ordinary walking "+str(a)+", mode "+str(camera_mode))
	await steering_interruptions()
	var report={"checks":checks,"failures":failures,"assertions":evidence.assertions,"routes":routes}
	FileAccess.open("user://direct_passages.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PASSAGE_CHECKS ",checks," checks ",failures.size()," failures ",routes)
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

func move_tick(direction: Vector2) -> void:
	s.apply_command({"t":"direct_move","units":[hero.uid],"direction":direction},0)
	s.world.time+=GameUnit.TICK;hero.tick(GameUnit.TICK)

func begin_corner(ticks: int) -> Vector2:
	reset();hero.stop_steering();hero.pos=Vector2(56.3,138.9);hero.restore_gait(2);hero._anim_lock=0
	hero.facing=0;hero._perceive_next=INF;hero.ai_next=INF;s.world.nav.track_unit(hero)
	s.apply_command({"t":"direct_control","leader":hero.uid},0)
	var direction:=Vector2(2.7,0.6).normalized()
	for i in ticks:move_tick(direction)
	return direction

func steering_interruptions() -> void:
	mode="steering inside the ruin corner"
	for camera_mode: int in [2,3]:
		GameData.options.control_mode=camera_mode
		begin_corner(0)
		for i in 45:move_tick(Vector2.RIGHT)
		check(hero.pos.x>59.0,"constant forward input crosses the eastern opening, mode "+str(camera_mode))
		for ticks: int in [3,6,9,12]:
			var direction:=begin_corner(ticks)
			var at:=hero.pos
			move_tick(Vector2.ZERO)
			for i in 5:hero.tick(GameUnit.TICK)
			check(hero.pos==at and hero._direct_terrain.is_empty(),"release stops during the corner, mode %d tick %d"%[camera_mode,ticks])
			direction=begin_corner(ticks);at=hero.pos
			for i in 4:move_tick(-direction)
			check((hero.pos-at).dot(direction)<-0.02,"reverse leaves the corner promptly, mode %d tick %d"%[camera_mode,ticks])
		var direction:=begin_corner(6)
		check(not hero._direct_terrain.is_empty(),"fixture reaches active corner assistance")
		var at:=hero.pos
		hero.direct_steering.until=Time.get_ticks_msec()-1
		for i in 5:hero.tick(GameUnit.TICK)
		check(hero.pos==at and hero._direct_terrain.is_empty(),"expired input cancels the corner assistance")
		direction=begin_corner(6);at=hero.pos
		s.apply_command({"t":"direct_control","leader":-1},0)
		for i in 5:hero.tick(GameUnit.TICK)
		check(hero.pos==at and hero._direct_terrain.is_empty(),"leaving direct mode cancels the corner assistance")
		direction=begin_corner(6);at=hero.pos
		var actor:=body(at+direction*0.7,0,false);s.world.nav.track_unit(actor)
		for i in 5:move_tick(direction)
		check(hero.pos.distance_to(actor.pos)>=at.distance_to(actor.pos)-0.001,"corner assistance cannot enter an overlapping character")
		s.world.remove_unit(actor)
		direction=begin_corner(6);at=hero.pos
		hero.direct_steering.village_limit=Vector3(at.x,at.y,0.1)
		for i in 5:hero.tick(GameUnit.TICK)
		check(hero.pos.distance_to(at)<=0.105,"corner assistance respects the scripted village boundary")
