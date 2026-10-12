extends "third_person_kbm.gd"
## Loaded original map; normal world ticks, model callbacks and camera.
## Tests the shipping pose pipeline rather than a fixture-side animator.
var elapsed:=0.0
var anchor:=Vector2.ZERO
var weapon:="sword"
var fp:=false
var run_case:=false
var observer:=false
var dummy:GameUnit
var last_position:=Vector2.ZERO
var moving_frames:=0
var moving_distance:=0.0
var starts:=[]
var seen_serial:=-1
var maximum_joint_error:=0.0
var maximum_joint_angle:=0.0
var maximum_torso_error:=0.0
var maximum_camera_motion:=0.0
var camera_offset:=Vector3.INF
var leg_changes:=0
var last_leg:=Quaternion.IDENTITY
var capture_dir:=""
var capture_frame:=0
var sampled_frames:=0
var aligned_frames:=0
var maximum_collar_error:=0.0

func frames(n:=4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g):g.rig._window_focused=true

func _ready() -> void:
	set_process(false);process_priority=20
	for arg in OS.get_cmdline_user_args():
		if arg=="--bow":weapon="bow"
		if arg=="--first-person":fp=true
		if arg=="--run":run_case=true
		if arg=="--observer":observer=true
		if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3 if fp else 2,"pad_enabled":0,"blood":0,"character_light":1,"volume_stream":0,"volume_sfx":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="moving "+weapon;await s.enter_zone("gz1g",1,false);await prepare()
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.restore_gait(2);hero._anim_lock=0
	var origin:=hero.pos;var found:=false
	for ring in 50:
		for i in 24:
			hero.pos=origin+Vector2.from_angle(i*TAU/24)*ring;s.world.nav.track_unit(hero)
			if [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(-1,-1)].all(func(d):return s.world.nav.direct_line(hero,hero.pos+d*2.5)):
				found=true;break
		if found:break
	check(found,"open original terrain for movement")
	anchor=hero.pos;last_position=anchor
	var item:=""
	for row:Dictionary in GameData.db.table("weapons"):
		if String(row.type).to_lower()!=weapon:continue
		for material:Dictionary in GameData.db.table("materials"):
			if String(material.type).to_lower()==String(row.material_type).to_lower():item=String(row.name)+"."+String(material.name);break
		if not item.is_empty():break
	check(not item.is_empty(),"weapon comes from original database")
	var h:Dictionary=hero.get_meta("hero");h.weapons=[item];h.dex=25.0;h.str=25.0;h.skills={"melee":100,"archery":100}
	Combat.hero_stats(hero,h);hero.set_equipment(PackedStringArray(h.get("armors",[])),PackedStringArray([item]))
	hero.stop_steering();hero.order={};hero.orders.clear();hero._pending_hit={};hero._attack_cd=0;hero._anim_lock=0
	hero.action="idle";hero.alert=true;hero._pose_snap=true;hero._update_pose();hero._anim_lock=0
	hero._perceive_next=INF;hero.ai_next=INF;hero.facing=0;hero.gait_run=run_case
	hero._sync_transform(0);hero.reset_physics_interpolation()
	dummy=body(anchor+Vector2(2 if weapon=="sword" else 5,0),0,false);dummy.max_hp=10000;dummy.hp=10000;dummy.faction=1
	dummy._perceive_next=INF;dummy.ai_next=INF;dummy.facing=PI;dummy.blocked=true;s.world.nav.track_unit(dummy)
	hero.set_meta("hate",{"w":s.world.get_instance_id(),"f":[1]})
	g.direct._neutral=false;g.direct.heading=0;g.direct.tilt=-0.1;g.direct._world=s.world
	g.rig._window_focused=true;g.rig.release();g.rig.set_process(true)
	s.apply_command({"t":"direct_control","leader":hero.uid},0)
	s.world.set_process(true);s.world.set_physics_process(true)
	g.hud.visible=false;g.hud._safe_root.visible=false;g.direct._overlay.visible=not observer
	g.direct.set_process_input(false);g.set_process_unhandled_input(false)
	if not capture_dir.is_empty():DirAccess.make_dir_recursive_absolute(capture_dir)
	GameData.options.display_mode=0;GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1152,720)
	get_viewport().scaling_3d_scale=1.0
	get_tree().paused=false;set_process(true)
	if fp and DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_check_body_alignment)

func _check_body_alignment() -> void:
	if not is_processing() or not is_instance_valid(hero) or hero.model == null: return
	var model:=hero.model
	if not model._view_active or model._view_chest == null: return
	var collar:=model._view_chest.to_global(model._view_collar)+model._view_shift
	maximum_collar_error=maxf(maximum_collar_error,absf((collar-g.rig.camera.global_position).dot(g.rig.camera.global_basis.x)))
	aligned_frames+=1

func _process(dt:float) -> void:
	elapsed=s.world.draw_time();sampled_frames+=1;g.rig._window_focused=true
	if hero.action=="attack" and hero._anim_lock>0 and hero.pos.distance_to(last_position)>0.00001:
		moving_frames+=1;moving_distance+=hero.pos.distance_to(last_position)
	last_position=hero.pos
	if hero.action=="attack" and seen_serial!=hero._action_serial:
		seen_serial=hero._action_serial;starts.append({"time":s.world.time,"remaining":hero._attack_cd,"clip":hero.model._current})
	if hero._direct_pose:
		var pose:=hero._direct_pose
		maximum_torso_error=maxf(maximum_torso_error,pose.torso_error)
		var leg:=hero.model.get_node("hp/ll1") as EIAnimPart
		if hero.action=="attack" and hero._moving and leg.animation_key.angle_to(last_leg)>0.001:leg_changes+=1
		last_leg=leg.animation_key
		var skel:=hero.model.get_node_or_null("Skeleton") as Skeleton3D
		if skel:
			for part:EIAnimPart in pose.parts:
				var expected:=skel.global_transform.affine_inverse()*part.global_transform
				var actual:=skel.get_bone_global_pose(part.bone_idx)
				maximum_joint_error=maxf(maximum_joint_error,expected.origin.distance_to(actual.origin))
				maximum_joint_angle=maxf(maximum_joint_angle,expected.basis.get_rotation_quaternion().angle_to(actual.basis.get_rotation_quaternion()))
	if fp and elapsed>0.5:
		var offset:=g.rig.camera.global_position-hero.global_position
		if camera_offset!=Vector3.INF:maximum_camera_motion=maxf(maximum_camera_motion,offset.distance_to(camera_offset))
		camera_offset=offset
	if observer:
		hero.model.set_head_hidden(false)
		var pivot:=hero.global_position+Vector3.UP
		g.rig.camera.global_position=pivot+Vector3(-2.2,1.0,3.2);g.rig.camera.look_at(pivot,Vector3.UP)
	var move:=Vector2.ZERO
	if elapsed>=1 and elapsed<3.4:move=Vector2.UP
	elif elapsed>=3.4 and elapsed<5.8:move=Vector2.RIGHT
	elif elapsed>=5.8 and elapsed<8.2:move=Vector2.DOWN
	elif elapsed>=8.2 and elapsed<10.6:move=Vector2.LEFT
	g.direct._move_refresh=0;g.direct._neutral=false;g.direct._fire=elapsed>=0.6 and elapsed<11.7
	g.direct.step(move,dt);g.direct._update_feedback(dt);g.direct._overlay.queue_redraw()
	if not capture_dir.is_empty() and sampled_frames%4==0:
		_capture_frame()
	if elapsed>16.0 and hero._pending_hit.is_empty() and hero.orders.is_empty() and hero.order.is_empty():
		set_process(false);_finish.call_deferred()

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join("frame-%04d.png"%capture_frame));capture_frame+=1

func _finish() -> void:
	s.world.set_process(false);s.world.set_physics_process(false)
	check(starts.size()>=3,"repeated native attacks start")
	check(moving_frames>20 and moving_distance>1,"authority moves during committed swings")
	check(leg_changes>15,"legs animate throughout moving attacks")
	check(maximum_torso_error<0.005,"blend preserves authored upper-body orientation")
	check(maximum_joint_error<0.001 and maximum_joint_angle<0.005,"weighted body and hair/weapon attachments share the final pose")
	for i in range(1,starts.size()):check(starts[i].time-starts[i-1].time>=starts[i-1].remaining-GameUnit.TICK*1.1,"movement does not shorten attack cooldown")
	if fp:check(maximum_camera_motion<0.01,"first-person eye remains steady during moving attacks")
	if fp and DisplayServer.get_name() != "headless":
		check(aligned_frames>60 and maximum_collar_error<0.001,"body remains centred after the live movement/attack pose is drawn")
	check(hero.direct_steering.is_empty(),"releasing movement clears independent input")
	var report:={"checks":checks,"failures":failures,"weapon":weapon,"first_person":fp,"run":run_case,"attack_starts":starts,"moving_frames":moving_frames,"distance":moving_distance,"leg_changes":leg_changes,"joint_position_error":maximum_joint_error,"joint_angle_error":maximum_joint_angle,"torso_error":maximum_torso_error,"camera_motion":maximum_camera_motion,"aligned_frames":aligned_frames,"collar_error":maximum_collar_error}
	FileAccess.open("user://direct-moving-attacks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOVING_ATTACKS ",JSON.stringify(report))
	if not capture_dir.is_empty() and not observer and DisplayServer.get_name() != "headless":
		g.direct.set_process(true)
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang
			await frames(3);await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_dir.path_join("hud-compact-"+lang+".png"))
		RemakeText.lang="en";g.direct.pointer=true
		await frames(3);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("hud-cursor.png"))
		g.direct.pointer=false;g.direct.switch_view(true)
		await frames(3);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("hud-tactical.png"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
