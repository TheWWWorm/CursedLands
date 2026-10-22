extends "third_person_kbm.gd"
## Authored Ingos actors and terrain, actual command/animation/mark paths.
var hd := false
var measurements := []

func _ready() -> void:
	hd = OS.get_cmdline_user_args().has("--hd")
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":3,"pad_enabled":0,"confine_mouse":0,"gfx_soft_ground":1,"footprints":1},true)
	if hd:
		check(ModStore.create_profile("Ingos HD",false,["community.hd-lands-textures@1.4.0"]).is_empty(),"activate installed HD Lands")
		check(GameData.open(GameData.root).is_empty(),"mount native campaign with HD textures")
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="Ingos talk and snow";await s.enter_zone("bz8k",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false)
	await talks()
	await snow()
	var minimap:Minimap=g.hud.minimap
	var colours:=minimap._mark_col
	check(colours.size()==4,"four minimap marker classes")
	if colours.size()==4:
		check(colours[0].g>colours[0].r*2 and colours[0].g>colours[0].b*2,"selected marker is green")
		check(colours[1].r>0.5 and colours[1].g>0.5 and colours[1].b<0.3,"neutral/exit marker is yellow")
		check(colours[2].r>colours[2].g*2 and colours[2].r>colours[2].b*2,"hostile marker is red")
		check(colours[3].r>0.5 and colours[3].b>0.3 and colours[3].g<0.3,"quest marker is pink")
	measurements.append({"minimap_colours":str(colours),"atlas":minimap._atlas.get_size()})
	mode="Fireworks direct cast";await s.enter_zone("gz11k",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false)
	await casts()
	g.queue_free();s.queue_free();await frames(10)
	print("INGOS_DIRECT_FEEDBACK ",JSON.stringify({"checks":checks,"failures":failures,"hd":hd,"measurements":measurements}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

func talks() -> void:
	var worker:GameUnit=s.world.units[136667]
	var trapper:GameUnit=s.world.units[1001621802]
	s.state.set_var(0,"b.Trapper.T42",1)
	for camera_mode:int in [2,3]:
		GameData.options.control_mode=camera_mode
		for u:GameUnit in [worker,trapper]:
			hero.pos=u.pos+Vector2(1.7,0);hero._sync_transform(0);hero.reset_physics_interpolation()
			u.order={};u.orders.clear();u._anim_lock=0;u._talk_command=0;u._talk_posted=9
			u.hidden=false;u.fogged=false;u.visible=true
			g.direct.apply_camera();await aim(u)
			check(g.pick_unit(get_viewport().get_visible_rect().size*.5,hero)==u,"crosshair actually picks "+str(u.info.name))
			var hint:=g.direct.interaction_hint()
			check(hint.is_empty() if u==worker else hint.get("verb")==RemakeText.t("Talk"),"only NPC with a current topic gets Talk in view "+str(camera_mode))
			reset();await aim(u);g.direct.interact()
			# Villages open the topic list at once (no approach); fields approach first.
			var talking:bool=hero.has_meta("interact") or s.world.vm.briefings._original_village_topics.has(s.my_index)
			check(not talking if u==worker else talking,"E uses the same topic eligibility (view %d, %s)"%[camera_mode,u.info.name])
			s.world.vm.briefings.clear_original_topics(s.my_index)
			g.hud._dialog._topics={};g.hud._dialog.visible=false   # Goodbye
		reset();trapper._talk_command=1
		check(not g.can_talk_to(trapper),"busy NPC has no talk action")
		trapper._talk_command=0
	reset()

func snow() -> void:
	var soft:=s.world.terrain.details.soft_ground
	var marks:=s.world.ground_marks
	var anchor:=Vector2.INF
	for y in range(35,95):
		for x in range(35,95):
			var p:=Vector2(x+.5,y+.5)
			if soft.step_allowed(p) and soft.step_allowed(p+Vector2(3,0)) and s.world.nav.cell_open(p,hero._classes[2]):
				anchor=p;break
		if anchor!=Vector2.INF:break
	check(anchor!=Vector2.INF,"authored Ingos has a walkable snow witness")
	if anchor==Vector2.INF:return
	for smooth:bool in [false,true]:
		hero.info.smooth_joints=smooth;hero.refresh_figure(true)
		hero.restore_gait(2);hero._anim_lock=0;hero.action="walk";hero.model.act("walk",1,0)
		var contacts:=0
		var before:=marks.foot_marks.size()
		soft.clear()
		for i in 60:
			hero.pos=anchor+Vector2(float(i)*.04,0);hero._sync_transform(0)
			hero.model.player.advance(.04);hero.model.flush_pending_pose()
			for part:String in ["ll3","rl3"]:
				if not marks._sole_contact(marks._part(hero,part)).is_empty():contacts+=1
			marks.queue_unit(hero);marks._drain_units()
		check(contacts>10,"native soles survive joint mode "+str(smooth))
		check(marks.foot_marks.size()>before,"real footfall frames emit prints with joint mode "+str(smooth))
		check(not soft.sectors.is_empty(),"actual snow pressure is recorded with joint mode "+str(smooth))
		measurements.append({"smooth":smooth,"contacts":contacts,"new_marks":marks.foot_marks.size()-before,"snow_sectors":soft.sectors.size()})
	# Rebuild into crouched combat, then return to standing movement. The
	# original saved foot nodes must not outlive a redress/model rebuild.
	hero.restore_gait(1);hero._anim_lock=0;hero.action="attack";hero.model.act("attack",1,0)
	hero.refresh_figure(true);marks.queue_unit(hero);marks._drain_units()
	hero.restore_gait(2);hero._anim_lock=0;hero.action="walk";hero.model.act("walk",1,0)
	var before:=marks.foot_marks.size()
	for i in 50:
		hero.pos=anchor+Vector2(0,float(i)*.035);hero._sync_transform(0)
		hero.model.player.advance(.04);marks.queue_unit(hero);marks._drain_units()
	check(marks.foot_marks.size()>before,"prints resume after crouched attack and figure replacement")
	check(marks._units[hero.get_instance_id()].foot_model==hero.model.get_instance_id(),"contact cache follows current figure")
	# DirectPose owns the walking phase during strafing attacks.
	hero.direct_controlled=true;hero.direct_motion=Vector2(.05,0);hero._move_speed=1.5
	var pose:=DirectPose.new(hero);hero.add_child(pose);hero._direct_pose=pose
	hero.action="attack";hero.model.act("attack",1,0)
	for i in 20:
		pose.restore_pose();hero.model.player.advance(.02);pose.apply_pose(.02)
		marks.queue_unit(hero);marks._drain_units()
	check(not pose.lower_clip.is_empty() and marks._units[hero.get_instance_id()].clip==pose.lower_clip,"moving attack footprints follow the composed foot cycle")
	pose.restore_pose();hero._direct_pose=null;pose.free();hero.direct_motion=Vector2.ZERO;hero._move_speed=0

func casts() -> void:
	var h:Dictionary=hero.get_meta("hero");h.spells=["fireworks{}"];h.skills={"sense":100};h.int=25.0
	Combat.hero_stats(hero,h)
	var range_m:float=Spells.parse("fireworks{}").range
	check(is_equal_approx(range_m,30),"native Fireworks has 30 metre base range")
	for camera_mode:int in [2,3]:
		GameData.options.control_mode=camera_mode
		for distance:float in [10.0,28.0,31.0,45.0]:
			reset();hero.stop_steering();hero.mana=hero.max_mana
			g.pending_spell="fireworks{}"
			var at:=hero.pos+Vector2(distance,0)
			var target:=g.pending_target(null,at)
			check(not target.is_empty() and g.pending_in_range(target)==(distance<=range_m),"Fireworks range feedback at "+str(distance)+" in view "+str(camera_mode))
			# Bypass UI feedback to check the host, including delayed requests.
			s.submit({"t":"direct_cast","unit":hero.uid,"spell":"fireworks{}","x":at.x,"y":at.y})
			var start:=hero.pos;var mana:=hero.mana
			for tick in 60:
				hero._tick(GameUnit.TICK)
				if hero.action.begins_with("cast") or (hero.order.is_empty() and hero.orders.is_empty()):break
			check(hero.pos==start and hero.path.is_empty(),"direct cast never starts an approach at "+str(distance))
			check(hero.mana<mana if distance<=range_m else hero.mana==mana,"only an in-range direct cast spends stamina")
	# Tactical commands preserve the native walk-into-range behavior.
	reset();GameData.options.control_mode=1;hero.mana=hero.max_mana
	var at:=hero.pos+Vector2(35,0)
	s.submit({"t":"cast","unit":hero.uid,"spell":"fireworks{}","x":at.x,"y":at.y})
	check(hero.orders.size()==1 and not hero.orders[0].get("in_place",false),"tactical cast retains approach permission")
