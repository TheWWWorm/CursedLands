extends "third_person_kbm.gd"
## Actual bow animation, authoritative moving release and both camera modes.
## Local command dispatch; network latency/packet delivery is outside scope.
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false);await prepare()
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	var start:=hero.pos;var found:=false
	for ring in 40:
		for angle in 16:
			hero.pos=start+Vector2.from_angle(angle*TAU/16)*ring;s.world.nav.track_unit(hero)
			if [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN].all(func(d):return s.world.nav.direct_line(hero,hero.pos+d*4)):
				found=true;break
		if found:break
	check(found,"original terrain supports movement in four directions");start=hero.pos
	var bow:=""
	for row:Dictionary in GameData.db.table("weapons"):
		if String(row.type).to_lower()!="bow":continue
		for mat:Dictionary in GameData.db.table("materials"):
			if String(mat.type).to_lower()==String(row.material_type).to_lower():bow=String(row.name)+"."+String(mat.name);break
		if not bow.is_empty():break
	var h:Dictionary=hero.get_meta("hero");h.weapons=[bow];h.skills={"archery":100};h.dex=25.0;h.str=25.0
	Combat.hero_stats(hero,h);hero.set_equipment(PackedStringArray(h.get("armors",[])),PackedStringArray([bow]))
	check(hero.stats.ranged,"real authored bow selected")
	for camera_mode in [2,3]:
		GameData.options.control_mode=camera_mode
		for movement:Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			mode="camera %d, move %s"%[camera_mode,movement]
			reset();hero.stop_steering();hero.pos=start;hero.direct_controlled=true;hero.restore_gait(2)
			hero.action="idle";hero.alert=true;hero._pose_snap=true;hero._update_pose();hero._anim_lock=0;hero._sync_transform(0)
			g.direct._world=s.world;g.rig._window_focused=true;g.direct.heading=0;g.direct.tilt=-.12;g.direct.apply_camera()
			g.direct.attack()
			for i in 40:
				hero._tick(GameUnit.TICK)
				if not hero._pending_hit.is_empty():break
			check(hero._pending_hit.has("view_offset"),"normal attack commits a camera ray through authority")
			if hero._pending_hit.is_empty():continue
			var old:Vector3=hero._pending_hit.direction
			var launched:Projectile
			var latest:Dictionary
			for i in 80:
				# Turn during the authored windup while the actor keeps walking.
				g.direct.heading=.65;g.direct.tilt=-.22;hero._sync_transform(0);g.direct.apply_camera()
				g.direct._look_refresh=0;g.direct._move_refresh=0;g.direct.step(movement,GameUnit.TICK)
				latest=g.direct.aim_view(hero)
				hero._tick(GameUnit.TICK)
				for child in s.world.get_children():
					if child is Projectile:launched=child;launched.set_physics_process(false);break
				if launched:break
			check(launched!=null,"bow releases one projectile")
			if not launched:continue
			var muzzle:=DirectCombat.origin(hero)
			var eye:Vector3=muzzle+latest.view_offset
			var end:Vector3=eye+latest.view_direction*60.0
			var hit:=DirectCombat.ray_body(s.world,hero,eye,end,DirectCombat.scene_fraction(s.world,eye,end))
			var expected:Vector3=(eye.lerp(end,hit.fraction)-muzzle).normalized()
			check(launched._direction.distance_to(expected)<.00001,"release follows the latest reticle ray from the moved pose")
			check(launched._direction.distance_to(old)>.05,"release does not reuse the button-down aim")
			check(launched.global_position.distance_to(muzzle)<.00001 and hero.pos.distance_to(start)>.001,"launch origin moves with the actor")
			var fixed:=launched._direction;g.direct.heading=-1;g.direct.apply_camera();g.direct.step(Vector2.ZERO,.1)
			check(launched._direction==fixed,"flight direction remains fixed after release")
			launched.free()
	mode="validation"
	for value in [{},{"view_offset":Vector3(NAN,0,0),"view_direction":Vector3.RIGHT},{"view_offset":Vector3(13,0,0),"view_direction":Vector3.RIGHT},{"view_offset":Vector3.ZERO,"view_direction":Vector3(INF,0,0)},{"view_offset":Vector3.ZERO,"view_direction":Vector3.ZERO}]:
		check(DirectCombat.view_input(value).is_empty(),"invalid view input ignored")
	var saved:=hero.direct_view.duplicate(true)
	s.apply_command({"t":"direct_look","units":[hero.uid],"heading":1.0,"view_offset":Vector3.ZERO,"view_direction":Vector3.LEFT},1)
	check(hero.direct_view==saved,"another player cannot change the release ray")
	g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown()
	print("DIRECT_RELEASE_AIM ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
