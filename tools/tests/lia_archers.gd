extends "third_person_kbm.gd"
## LiA's natural-bow prototypes and town guard. Exercise complete AI ticks,
## including patrol interruption, cooldown pursuit and fear/kiting.
var rows:=[]
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_LOW),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0));s.state.world_time=13.0
	await s.enter_zone("gz21k",1,false);await prepare()
	var records:=[];var seen:={}
	for u:GameUnit in s.world.unit_rows():
		var weapons:Array=u.info.get("weapons",[])
		var bow:bool=not weapons.is_empty() and Items.info(String(weapons[0])).get("row",{}).get("type_id",-1) in [5,6]
		if bow and not seen.has(u.proto.name):records.append(u.info.duplicate(true));seen[u.proto.name]=true
		if u!=hero:s.world.remove_unit(u)
	for proto:String in ["bz21k Human Archer1 F","zone22 Human Archer1 F","zone23 Human Archer1 F","zone23 Human Archer2 F","zone25 Human Hunter F"]:
		records.append({"prototype":proto,"need_import":0,"player":1})
	var start:=hero.pos;var axis:=Vector2.RIGHT;var found:=false
	for ring in 60:
		for angle in 16:
			var at:=start+Vector2.from_angle(angle*TAU/16)*ring
			for direction in 8:
				axis=Vector2.from_angle(direction*TAU/8);hero.pos=at;s.world.nav.track_unit(hero)
				var end:=at+axis*24.0
				if s.world.nav.direct_line(hero,end) and s.world.terrain_ray(at,s.world.ground_at(at.x,at.y)+1.5,end,s.world.ground_at(end.x,end.y)+1.5)>.99:
					start=at;found=true;break
			if found:break
		if found:break
	check(found,"Ingos terrain has a clear bow lane")
	if not found:get_tree().quit(1);return
	for record:Dictionary in records:
		record.nid=0;record.position=Vector3(start.x,start.y,0)
		var archer:=s.world.spawn_unit(record)
		archer.set_process(false);archer.set_physics_process(false)
		archer.faction=1;hero.faction=0
		archer.mode="aggression";archer.set_meta("um",{"fight":"aggression","susp":true,"corpse":true,"fear":0})
		for phase:String in ["standing","moving","patrol_interrupt","natural_notice","outside","close"]:
			seed(151031)
			mode=String(archer.proto.name)+" "+phase
			var reach:=float(archer.stats.reach)
			var distance:=reach+4.0 if phase=="outside" else 4.0 if phase=="close" else reach-1.0
			archer.pos=start;hero.pos=start+axis*distance;archer.facing=axis.angle();hero.facing=axis.orthogonal().angle()
			archer.order={};archer.orders.clear();archer.path=PackedVector2Array();archer._goal=Vector2.INF;archer._motion=null
			archer._pending_hit={};archer._anim_lock=0;archer._attack_cd=0;archer.action="idle";archer.alert=true
			archer.ai_next=0;archer._perceive_next=INF;archer.set_meta("noticed",{} if phase=="natural_notice" else {hero.get_instance_id():hero})
			for key:String in ["fear_on","fear","calm","ai_rechoose","ignore"]:archer.remove_meta(key)
			archer._pose_snap=true;archer._update_pose();archer._anim_lock=0
			for u:GameUnit in [hero,archer]:s.world.nav.track_unit(u);u._sync_transform(0)
			if phase in ["patrol_interrupt","natural_notice"]:
				archer.command({"type":"move","to":hero.pos,"run":false,"calm":true})
				archer.set_meta("calm",{"busy":true,"until":s.world.time+20.0})
			var min_distance:=distance;var fired:=false;var shots:=0;var ticks:=0
			var target_start:=hero.pos
			var noticed_distance:=-1.0
			var approach_after_notice:=0.0
			for tick in 420:
				hero._moving=phase=="moving"
				if hero._moving:hero.pos=target_start+axis.orthogonal()*sin(tick*.09)*.6;s.world.nav.track_unit(hero)
				s.world.time+=GameUnit.TICK;archer.tick(GameUnit.TICK);archer._sync_transform(0)
				min_distance=minf(min_distance,archer.pos.distance_to(hero.pos));ticks+=1
				if not archer.get_meta("noticed",{}).is_empty():
					if noticed_distance<0:noticed_distance=archer.pos.distance_to(hero.pos)
					approach_after_notice=maxf(approach_after_notice,noticed_distance-archer.pos.distance_to(hero.pos))
				for child in s.world.get_children():
					if child is Projectile and child.source==archer:shots+=1;child.free()
				if shots>=2:fired=true;break
			check(fired,"full AI releases repeated arrows")
			if phase in ["standing","moving","patrol_interrupt"]:
				check(min_distance>=distance-.5,"in-range AI does not approach before firing")
			if phase=="natural_notice":
				check(noticed_distance>5.0 and approach_after_notice<.5,"natural perception interrupts the approach as soon as retreat wins")
			if phase=="outside":check(min_distance>=reach-.5,"out-of-range approach stops at firing range")
			if phase=="close":check(archer.pos.distance_to(hero.pos)>distance,"close attacker makes archer retreat before shooting")
			rows.append({"prototype":archer.proto.name,"phase":phase,"reach":reach,"initial_distance":distance,"noticed_distance":noticed_distance,"approach_after_notice":approach_after_notice,"minimum_distance":min_distance,"shots":shots,"ticks":ticks})
		s.world.remove_unit(archer)
	g.queue_free();s.queue_free();await frames(5)
	print("LIA_ARCHERS ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows}))
	get_tree().quit(0 if failures.is_empty() else 1)
