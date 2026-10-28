extends "third_person_kbm.gd"
## Real authored peasant, map navigation, motion predictor, command handler and
## order-path particles. Prepared positions isolate preview from perception.
var notices: Array[Dictionary] = []
var target_unit: GameUnit
var anchor := Vector2.ZERO
var direction := Vector2.RIGHT
class WatchedSession extends Session:
	var paths:Array[Dictionary]=[]
	func broadcast(e:Dictionary) -> void:
		if e.get("t")=="order_path":paths.append(e.duplicate(true))
		super.broadcast(e)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":0,"show_path":1,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	s=WatchedSession.new();notices=(s as WatchedSession).paths;add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false)
	while ShaderCompilationScreen.active():await frames(1)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.get_node("UnitFog").set_process(false);g.rig.set_process(false);g.direct.set_process(false)
	hero=s.party_units(0)[0]
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.erase_unit(u.uid)
	var record:Dictionary={}
	for o:Dictionary in EIMob.load_bytes(GameData.read_file("maps/zone18.mob")).objects:
		if "peasants" in String(o.get("prototype","")).to_lower() and not o.get("logic",[]).is_empty() and o.logic[0].aggression==3:
			record=o.duplicate(true);break
	check(not record.is_empty(),"authored fearful батрак record")
	if record.is_empty():get_tree().quit(1);return
	var found:=false
	for y in range(16,int(s.world.terrain.size_ei().y)-25,8):
		for x in range(16,int(s.world.terrain.size_ei().x)-25,8):
			hero.pos=Vector2(x,y)
			for d:Vector2 in [Vector2.RIGHT,Vector2.DOWN]:
				if not s.world.nav.direct_line(hero,hero.pos+d*24):continue
				var dry:=true
				for n in 25:
					if s.world.nav.cell_wet(hero.pos+d*n):dry=false;break
				if dry:anchor=hero.pos;direction=d;found=true;break
			if found:break
		if found:break
	check(found,"authored terrain has a clear running corridor")
	if not found:get_tree().quit(1);return
	record.nid=900017;record.position=Vector3(anchor.x+direction.x*8,anchor.y+direction.y*8,0)
	target_unit=s.world.spawn_unit(record)
	for u:GameUnit in [hero,target_unit]:
		u.set_process(false);u.set_physics_process(false);u.ai_next=INF;u._perceive_next=INF;u.blocked=false;u.hidden=false;u.fogged=false;u.visible=true
		u.resync_drawn()
	# A party order on a unit goes on only while the party has noticed it
	# (54dd70); perception is off here, so the hero is given that entry.
	var known:Dictionary=hero.get_meta("noticed",{});known[target_unit.get_instance_id()]=target_unit;hero.set_meta("noticed",known)
	target_unit.faction=1;hero.faction=0;s.world.set_relation(0,1,2)
	for scenario in ["fleeing","approaching","stationary","paused","queued","revealed"]:
		await run_case(scenario)
	# The same owner event is consumed by a replica; no client-side prediction.
	var last:Dictionary=notices.back() if not notices.is_empty() else {}
	if not last.is_empty():
		var expected:=g.marks._ghost_ticks(last)
		var replica:=OrderMarks.new();replica.game=g;add_child(replica)
		check(replica._ghost_ticks(last)==expected,"replica reconstructs the authority's current-target path")
		replica.queue_free()
	g.queue_free();s.queue_free();await frames(8)
	print("ATTACK_PATH_CURRENT_TARGET ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if failures else 0)

func run_case(scenario:String) -> void:
	mode=scenario;reset();notices.clear()
	hero.pos=anchor;hero.ai_next=INF;hero._perceive_next=INF;hero.restore_gait(2);hero._pose_snap=true;hero.resync_drawn();s.world.nav.track_unit(hero)
	target_unit.order={};target_unit.orders.clear();target_unit.path=PackedVector2Array();target_unit._anim_lock=0;target_unit._moving=false
	target_unit.pos=anchor+direction*8;target_unit.facing=direction.angle();target_unit.resync_drawn();s.world.nav.track_unit(target_unit)
	if scenario!="stationary":
		var to:=anchor+direction*(1 if scenario=="approaching" else 24)
		target_unit.move_to(to,true,false)
		for i in 12:target_unit._tick(GameUnit.TICK)
		check(target_unit._moving and target_unit.future_pos(32).distance_to(target_unit.pos)>0.5,"target uses a live running prediction")
	if scenario=="revealed":
		target_unit.visible=false
		# A placement ends the old draw-clock route; isolate the visibility
		# restoration fix from interpolation along the prior running path.
		target_unit._draw_motion_active=false;target_unit._draw_line_goal=Vector2.INF
		target_unit.pos+=direction*0.8
		target_unit.visible=true
		check(Vector2(target_unit.global_position.x,-target_unit.global_position.z).distance_to(target_unit.pos)<0.001,"earlier hidden-creature position fix survives visibility restoration")
	var at:=target_unit.pos;var hp:=target_unit.hp
	var command:={"t":"attack","units":[hero.uid],"target":target_unit.uid}
	if scenario=="queued":
		hero.command({"type":"wait","t":0.11});command.queue=true
	get_tree().paused=scenario=="paused"
	s.apply_command(command,0)
	if scenario=="paused":
		check(not notices.is_empty(),"paused command draws before any actor tick")
	else:
		for i in 12:
			hero._tick(GameUnit.TICK)
			if not notices.is_empty():break
	check(notices.size()==1,"one attack preview emitted")
	if not notices.is_empty():
		var e:=notices[0]
		var goal:=Vector2(e.target[0],e.target[1]);var end:=Vector2(e.end[0],e.end[1])
		check(goal.distance_to(at)<0.001,"destination ring is on current target")
		check(end.distance_to(at)<0.5,"ghost navigation route ends on current target")
		var dots:=g.marks._ghost_ticks(e)
		check(not dots.is_empty() and Vector2(dots[-1].x,dots[-1].y).distance_to(at)<=hero.melee_reach(target_unit)+0.6,"trail stops at reach of current target")
		if scenario=="fleeing":check(hero._goal.distance_to(at)>0.5,"actual pursuit still intercepts the running target")
		print("ATTACK_PATH_SAMPLE ",JSON.stringify({"case":scenario,"prototype":target_unit.proto.get("name",""),"current":[at.x,at.y],"predicted":str(target_unit.future_pos(64)),"preview":e,"pursuit":str(hero._goal)}))
		if scenario=="fleeing" and DisplayServer.get_name()!="headless":
			hero.resync_drawn();target_unit.resync_drawn();g.selected.assign([hero])
			var centre:=hero.pos.lerp(at,0.5);var focus:=EISpace.pos(centre.x,centre.y,s.world.ground_at(centre.x,centre.y))
			g.rig.camera.global_position=focus+Vector3(0,24,5);g.rig.camera.look_at(focus)
			g.rig.camera.reset_physics_interpolation();g.hud._tutorial.close()
			# Refresh the same received event after positioning the camera; no
			# simulation tick is needed for the native order-mark particles.
			get_tree().paused=true
			g.marks.on_path(e)
			var fx:=ParticleFx.for_order_marks(s.world)
			fx.set_process(false) # Hold the 0.6-second marker during GPU capture.
			await frames(8)
			check(fx.effects.any(func(effect):return effect.e.type==0x2039 and effect.mmi!=null and effect.mmi.multimesh.visible_instance_count>0),"current-target preview reaches the rendered particle buffer")
			get_viewport().get_texture().get_image().save_png("user://running-peasant-path.png")
			fx.set_process(true)
	check(target_unit.pos==at and target_unit.hp==hp,"preview leaves target motion and health unchanged")
	get_tree().paused=false
