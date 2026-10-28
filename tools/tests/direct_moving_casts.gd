extends "direct_moving_attacks.gd"
## Real direct input, authority ticks and the original human figure. Reuses
## the attack fixture's loaded scene and body/camera measurements.
var spell_ready := false
var next_cast := 1.0
var live_start := 0.0
var cast_case := 0
var held_case := false
var held_moving_frames := 0
var direction_frames := [0,0,0,0]
var logic_rows := []
var pose_samples := []
var previous_chest := Quaternion.IDENTITY
var previous_position := Vector3.ZERO
var maximum_cast_body_step := 0.0
var maximum_cast_body_speed := 0.0
var maximum_recovery_step := 0.0
var finished_clip_frames := 0
var captured_images: Array[Image] = []
var last_capture_time := -1.0
var collar_failures := []

func _check_body_alignment() -> void:
	if not spell_ready or elapsed < 0.2: return
	var before := maximum_collar_error
	super._check_body_alignment()
	if maximum_collar_error>maxf(before,0.001):
		collar_failures.append({"time":elapsed,"action":hero.action,"error":maximum_collar_error,"shift":str(hero.model._view_shift),"right":str(hero.model._view_right),"camera_right":str(g.rig.camera.global_basis.x),"eye_delta":str(hero.model._view_eye-g.rig.camera.global_position),"pose_pending":hero.model._pose_pending,"timeline_pending":hero.model._timeline_pending,"base_saved":hero._direct_pose._base_keys.size()})

func check(ok: bool, label: String) -> void:
	if not ok and is_instance_valid(g):
		print("CAST_INPUT_STATE ",JSON.stringify({"active":g.direct.active(),"leader":g.direct.leader()!=null,"focus":g.rig._window_focused,"held":g.rig.held,"transitioning":g.direct.transitioning(),"movie":s.movie_active(),"hud_blocked":g.hud.blocks_camera(),"cursor":g.direct.field().cursor_mode,"wheel":g.direct.field().wheel.visible,"paused":get_tree().paused}))
	super.check(ok,label)

func _ready() -> void:
	await super._ready()
	set_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	GameData.options.free_run = 0
	held_case = "--held" in OS.get_cmdline_user_args()
	var h: Dictionary = hero.get_meta("hero")
	h.spells = ["healing{}","arrow{}","fireworks{}"]
	h.skills = {"astral":100,"elemental":100,"sense":100}
	h.int = 25.0; h.dex = 25.0
	Combat.hero_stats(hero,h)
	# Isolate the spell effect from the unrelated 15-tick health regeneration.
	hero.race=hero.race.duplicate(true); hero.race.health_regen=0.0
	await authority_cases()
	clean()
	# Remove effects from the separate authority cases before recording.
	for child in s.world.get_children():
		if child is ParticleFx or child is SpellFx: child.queue_free()
	await frames(2)
	if "--isolate-body" in OS.get_cmdline_user_args():
		for node in s.world.map.object_nodes: node.visible=false
		dummy.visible=false
	# A slow caster exercises the original cast:<hold> action as well.
	if held_case: hero.stats.actions = 12.0
	var plan := hero._cast_plan(Spells.parse("healing{}"),hero._cast_clip())
	print("CAST_PLAN ",JSON.stringify(plan))
	if held_case: check(plan.hold > 0,"slow caster uses an authored held cast")
	hero.gait_run = run_case
	g.direct.heading = 0.8; hero.facing = 0.8
	g.direct.tilt = -1.0 if fp and "--isolate-body" in OS.get_cmdline_user_args() else -0.55 if fp else -0.2
	hero._sync_transform(0); hero.reset_physics_interpolation()
	last_position = hero.pos; live_start = s.world.draw_time()
	spell_ready = true
	if fp and DisplayServer.get_name()!="headless":
		g.direct.apply_camera()
		RenderingServer.frame_pre_draw.disconnect(_check_body_alignment)
		RenderingServer.frame_pre_draw.connect(_check_body_alignment)
	s.world.set_process(true); s.world.set_physics_process(true); set_process(true)

func clean() -> void:
	reset(); hero.stop_steering(); g.direct.stop_move()
	hero.restore_gait(2); hero.action="idle"; hero._hold_left=0; hero._pre_left=0
	hero.pos=anchor; hero.facing=0.8; hero.gait_run=false
	hero._pose_snap=true; hero._update_pose(); hero._anim_lock=0
	hero.mana=hero.max_mana; hero.hp=hero.max_hp*0.2
	hero._regen_t=0
	hero._perceive_next=INF; hero.ai_next=INF
	s.world.nav.track_unit(hero)
	var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers: timers.pending.clear()
	g.direct._world=s.world; g.direct._neutral=false; g.direct.heading=hero.facing

func steer_authority(v: Vector2) -> void:
	s.apply_command({"t":"direct_move","units":[hero.uid],"direction":v},0)

func tick_authority() -> void:
	s.world.time += GameUnit.TICK; s.world._logic_step += 1
	hero.tick(GameUnit.TICK)
	var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers: timers._tick(GameUnit.TICK,true)

func authority_cases() -> void:
	clean()
	g.direct.step(Vector2.UP,0.1)
	check(not hero.direct_steering.is_empty(),"direct movement starts before spell selection")
	g.begin_cast(0); g.direct.cast_self()
	check(not hero.direct_steering.is_empty() and hero.orders.size()==1,"self-cast preserves held movement and queues one spell")
	var mana := hero.mana
	var hp := hero.hp
	var heading := hero.facing
	tick_authority()
	check(hero.action.begins_with("cast"),"moving self-cast starts on authority")
	check(absf(wrapf(hero.facing-heading,-PI,PI))<0.0001,"self-cast retains facing away from world east")
	check(is_equal_approx(mana-hero.mana,hero._spell_cost(Spells.parse("healing{}"))),"moving spell pays exactly one native spell cost")
	var timers := s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers == null or timers.pending.is_empty():
		check(false,"self-cast fixture has its scheduled effect")
		get_tree().quit(1)
		await get_tree().process_frame
		return
	check(timers.pending.size()==1,"moving spell schedules one effect")
	var effect_ticks := roundi(float(timers.pending[0].left)/GameUnit.TICK)
	var cast_from := hero.pos
	var maximum_speed_error := 0.0
	for i in effect_ticks:
		steer_authority(Vector2.RIGHT)
		tick_authority()
		maximum_speed_error=maxf(maximum_speed_error,absf(hero._move_speed-hero.speed()*0.65))
		if i<effect_ticks-1: check(hero.hp==hp,"movement does not release healing early")
	check(hero.hp>hp and timers.pending.is_empty(),"healing releases once on the original effect tick")
	check(hero.pos.distance_to(cast_from)>0.1,"caster travels during the committed animation")
	check(maximum_speed_error<0.02,"casting uses the moving-attack speed reduction")
	check(is_equal_approx(mana-hero.mana,hero._spell_cost(Spells.parse("healing{}"))),"steering does not charge the spell again")
	logic_rows.append({"effect_ticks":effect_ticks,"travel":hero.pos.distance_to(cast_from),"speed_error":maximum_speed_error})
	steer_authority(Vector2.ZERO); var stopped := hero.pos; tick_authority()
	check(hero.pos==stopped and hero.direct_steering.is_empty(),"release stops movement during cast recovery")
	# Press/release/repress while a spell is buffered behind recovery.
	clean(); hero.action="attack"; hero._anim_lock=0.4
	g.begin_cast(0); g.direct.cast_self()
	steer_authority(Vector2.RIGHT); steer_authority(Vector2.ZERO); steer_authority(Vector2.LEFT)
	check(hero.orders.size()==1 and hero.orders[0].get("type")=="cast","starting and restarting movement preserves a buffered cast")
	for i in 15:
		steer_authority(Vector2.RIGHT); tick_authority()
		if hero.action.begins_with("cast"): break
	check(hero.action.begins_with("cast"),"buffered cast executes after recovery without another click")
	# A targeted cast must finish turning even when camera heading differs.
	clean(); dummy.pos=anchor+Vector2(-2,2); dummy._sync_transform(0); s.world.nav.track_unit(dummy)
	# A party order on a unit goes on only while the party has noticed it
	# (54dd70); the player targets the dummy it sees.
	var known: Dictionary = hero.get_meta("noticed", {}); known[dummy.get_instance_id()] = dummy; hero.set_meta("noticed", known)
	steer_authority(Vector2.RIGHT); g.pending_spell="arrow{}"; g.cast_on(dummy)
	check(hero.orders.size()==1,"learned targeted spell is accepted by authority")
	for i in 40:
		steer_authority(Vector2.RIGHT); tick_authority()
		if hero.action.begins_with("cast"): break
	check(hero.action.begins_with("cast"),"moving targeted cast turns and commits without chasing")
	check(hero.path.is_empty(),"targeted direct cast retains independent steering")
	# Exercise the primary fire handler, including its range-rejection branch.
	clean(); PadInput.active="pad"; g.direct.field().target={"unit":dummy}
	g.direct.step(Vector2.UP,0.1); g.pending_spell="arrow{}"; g.direct.attack()
	check(not hero.direct_steering.is_empty() and hero.orders.size()==1,"aimed fire handler keeps movement during a spell")
	clean(); dummy.pos=anchor+Vector2(100,0); g.direct.field().target={"unit":dummy}
	g.direct.step(Vector2.UP,0.1); g.pending_spell="arrow{}"; g.direct.attack()
	check(hero.orders.is_empty() and not hero.direct_steering.is_empty(),"out-of-range spell neither queues nor stops held movement")
	PadInput.active="kbm"; g.direct.field().target={}
	clean(); steer_authority(Vector2.RIGHT); g.pending_spell="fireworks{}"
	var ground_target := anchor+Vector2(4,0)
	g.cast_on(null,null,ground_target)
	check(hero.orders.size()==1 and hero.orders[0].point==ground_target and not hero.direct_steering.is_empty(),"ground spell retains its chosen point and held movement")
	for i in 30:
		steer_authority(Vector2.RIGHT); tick_authority()
		if hero.action.begins_with("cast"): break
	check(hero.action.begins_with("cast") and hero.path.is_empty(),"moving ground cast executes without an approach route")
	# Native non-combat locks and tactical cast orders retain their behavior.
	clean(); steer_authority(Vector2.RIGHT); hero.action="anim:fixture"; hero._anim_lock=1
	var locked := hero.pos; tick_authority()
	check(hero.pos==locked,"scripted animation still locks movement")
	clean(); steer_authority(Vector2.RIGHT)
	s.apply_command({"t":"cast","unit":hero.uid,"spell":"healing{}","target":hero.uid},0)
	check(hero.direct_steering.is_empty(),"tactical cast still replaces direct steering")
	clean(); hero.restore_gait(0); hero._anim_lock=0
	g.begin_cast(0); g.direct.cast_self()
	for i in 80:
		steer_authority(Vector2.RIGHT); tick_authority()
		if hero.action.begins_with("cast"): break
	check(hero.action.begins_with("cast") and hero.stance==GameUnit.STANCE_NONE,"direct cast stands up before composing the moving body")
	await frames(3)

func _process(dt: float) -> void:
	if not spell_ready: return
	elapsed=s.world.draw_time()-live_start; sampled_frames+=1; g.rig._window_focused=true
	var casting := hero.action.begins_with("cast") and hero._anim_lock>0
	var direction := clampi(int((elapsed-1.0)/3.0),0,3)
	if casting and hero.pos.distance_to(last_position)>0.00001:
		moving_frames+=1; moving_distance+=hero.pos.distance_to(last_position); moving_seconds+=dt
		direction_frames[direction]+=1
		if hero.action.contains(":"): held_moving_frames+=1
	last_position=hero.pos
	if casting and seen_serial!=hero._action_serial:
		seen_serial=hero._action_serial
		starts.append({"time":s.world.time,"remaining":hero._anim_lock,"clip":hero.model._current,"action":hero.action})
	if hero._direct_pose:
		var pose:=hero._direct_pose
		maximum_torso_error=maxf(maximum_torso_error,pose.torso_error)
		var leg:=hero.model.get_node("hp/ll1") as EIAnimPart
		if casting and hero._moving and leg.animation_key.angle_to(last_leg)>0.001: leg_changes+=1
		last_leg=leg.animation_key
		var chest := hero.model.get_node("hp/bd") as EIAnimPart
		var chest_position := hero.model.to_local(chest.global_position)
		var chest_rotation := chest._world_key.normalized()
		if not pose_samples.is_empty() and elapsed>1.5 and elapsed-pose_samples[-1].time<0.033 and hero._moving \
				and (casting or String(pose_samples[-1].action).begins_with("cast")):
			var step := previous_position.distance_to(chest_position)
			maximum_cast_body_step=maxf(maximum_cast_body_step,step)
			maximum_cast_body_speed=maxf(maximum_cast_body_speed,step/maxf(elapsed-pose_samples[-1].time,0.001))
			if not casting: maximum_recovery_step=maxf(maximum_recovery_step,step)
		if casting and hero._moving and hero.model.player.current_animation.is_empty(): finished_clip_frames+=1
		pose_samples.append({"time":elapsed,"action":hero.action,"clip":hero.model._current,"phase":hero.model.player.current_animation_position,
			"chest_angle_step":previous_chest.angle_to(chest_rotation),"chest_position_step":previous_position.distance_to(chest_position),
			"pose_weight":pose.weight,"gait_phase":pose.phase,"lower_clip":pose.lower_clip,"hip_position":str(hero.model.get_node("hp").position),"chest_position":str(chest.position)})
		previous_chest=chest_rotation; previous_position=chest_position
		var skel:=hero.model.get_node_or_null("Skeleton") as Skeleton3D
		if skel:
			for part: EIAnimPart in pose.parts:
				var expected:=skel.global_transform.affine_inverse()*part.global_transform
				var actual:=skel.get_bone_global_pose(part.bone_idx)
				maximum_joint_error=maxf(maximum_joint_error,expected.origin.distance_to(actual.origin))
				maximum_joint_angle=maxf(maximum_joint_angle,expected.basis.get_rotation_quaternion().angle_to(actual.basis.get_rotation_quaternion()))
	if fp and elapsed>0.5:
		var offset:=g.rig.camera.global_position-hero.global_position
		if camera_offset!=Vector3.INF: maximum_camera_motion=maxf(maximum_camera_motion,offset.distance_to(camera_offset))
		camera_offset=offset
	var move:=Vector2.ZERO
	if elapsed>=0.5 and elapsed<13.0: move=[Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT][direction]
	g.direct._move_refresh=0; g.direct._neutral=false; g.direct._fire=false
	g.direct.step(move,dt)
	if elapsed>=next_cast and elapsed<12.0 and hero._anim_lock<=0 and hero.orders.is_empty():
		hero.mana=hero.max_mana
		g.begin_cast(0); g.direct.cast_self(); cast_case+=1; next_cast=elapsed+4.0
	if observer: _observer_camera()
	if not capture_dir.is_empty() and sampled_frames%4==0: _capture_frame()
	if elapsed>18.0 and hero._anim_lock<=0 and hero.orders.is_empty() and hero.order.is_empty():
		set_process(false); _finish.call_deferred()

func _capture_frame() -> void:
	# Buffer the short real-time sequence so PNG compression cannot stall
	# animation playback or hide a single-frame transition.
	if elapsed>5.0 or elapsed-last_capture_time<1.0/20.0: return
	last_capture_time=elapsed
	await RenderingServer.frame_post_draw
	capture_samples.append({"frame":captured_images.size(),"time":elapsed,"action":hero.action,"moving":hero._moving,
		"direction":str(hero.direct_motion),"clip":hero.model._current,"phase":hero.model.player.current_animation_position})
	captured_images.append(get_viewport().get_texture().get_image())

func _finish() -> void:
	s.world.set_process(false); s.world.set_physics_process(false)
	check(starts.size()>=3,"repeated moving native casts start")
	check(moving_frames>5 and moving_seconds>0.5 and moving_distance>1,"authority moves throughout committed casts")
	check(direction_frames.all(func(n): return n>0),"forward, backward and both strafe directions move during casts")
	check(leg_changes>15,"legs continue animating beneath the native casting pose")
	check(maximum_torso_error<0.005,"moving cast preserves authored upper-body orientation")
	check(maximum_joint_error<0.001 and maximum_joint_angle<0.005,"body and attachments share the final casting pose")
	# A finished clip can coincide exactly with a logic tick, especially
	# held casts. Report coverage across runs instead of requiring this
	# scheduling window to exist in every recording.
	# Normal hip sway can cover centimetres during a slow captured frame.
	# A planted-pose reset instead jumps 10 cm in a few milliseconds.
	check(maximum_cast_body_speed<3.0,"casting and recovery have no abrupt body position reset")
	for i in range(1,starts.size()): check(starts[i].time-starts[i-1].time>=starts[i-1].remaining-GameUnit.TICK*1.1,"movement does not shorten casting recovery")
	if held_case: check(held_moving_frames>5,"legs move while the casting clip holds its release pose")
	if fp: check(maximum_camera_motion<0.01,"first-person eye remains steady during moving casts")
	if fp and DisplayServer.get_name()!="headless": check(aligned_frames>60 and maximum_collar_error<0.001,"first-person body stays centred after the moving cast is drawn")
	check(hero.direct_steering.is_empty(),"releasing movement clears independent input")
	var report:={"checks":checks,"failures":failures,"first_person":fp,"run":run_case,"held":held_case,"observer":observer,
		"cast_starts":starts,"moving_frames":moving_frames,"moving_seconds":moving_seconds,"distance":moving_distance,
		"direction_frames":direction_frames,"held_moving_frames":held_moving_frames,"leg_changes":leg_changes,
		"joint_position_error":maximum_joint_error,"joint_angle_error":maximum_joint_angle,"torso_error":maximum_torso_error,
		"camera_motion":maximum_camera_motion,"aligned_frames":aligned_frames,"collar_error":maximum_collar_error,"logic":logic_rows}
	report.maximum_cast_body_step=maximum_cast_body_step; report.finished_clip_frames=finished_clip_frames
	report.maximum_cast_body_speed=maximum_cast_body_speed; report.maximum_recovery_step=maximum_recovery_step
	report.collar_failures=collar_failures
	FileAccess.open("user://direct-moving-casts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open("user://cast-pose-samples.json",FileAccess.WRITE).store_string(JSON.stringify(pose_samples,"\t"))
	if not capture_dir.is_empty():
		FileAccess.open(capture_dir.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(capture_samples,"\t"))
		for i in captured_images.size(): captured_images[i].save_png(capture_dir.path_join("frame-%04d.png"%i))
	print("MOVING_CASTS ",JSON.stringify(report))
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
