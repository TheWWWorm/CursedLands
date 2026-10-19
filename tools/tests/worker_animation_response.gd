extends Node
## Separate production authority process, original loaded models and actual
## commands. This measures input/pose timing, not sustained gameplay FPS.
var checks:=0
var failures:=0
var s:Session
var g:Game
var hero:GameUnit
var preview_samples:=0
var shadow_samples:=0
var moving_samples:=0
var max_preview_error:=0.0
var max_shadow_error:=0.0
var leg_changes:=0
var last_leg:=Quaternion.IDENTITY
var rows:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func wait_real(seconds:float)->void:
	await get_tree().create_timer(seconds,true,false,true).timeout
func until(predicate:Callable,seconds:=10.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await get_tree().process_frame
	return bool(predicate.call())
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0,"control_mode":1,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"pad_enabled":0,"vsync":0},true)
	s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false)
	hero=s.party_units(0)[0]
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	s.world.vm.instances.clear()
	var h:Dictionary=hero.get_meta("hero");h.spells=["healing{}"];h.skills={"astral":100};h.int=80.0
	Combat.hero_stats(hero,h);hero.mana=hero.max_mana;hero.hp=hero.max_hp*.5
	check(s.save_game("animation_worker_fixture")==OK,"prepared original hero saves")
	check(await s.local_host.start(0,1,true)==OK,"separate authority starts")
	check(await s.load_game_shown("animation_worker_fixture"),"prepared scene loads through worker")
	if s.world==null:await s.local_host.stop();get_tree().quit(1);return
	hero=g.my_units()[0];g.selected.assign([hero]);g.rig.release()
	check(not s.world.authority,"visible world uses production snapshots")
	for speed in [1,2]:
		g.set_speed(0);s.local_host._sync_single_clock()
		await s.local_host.request("measure_save");await wait_real(.3)
		var origin:=hero.pos
		s.submit({"t":"move","units":[hero.uid],"x":origin.x+2.0,"y":origin.y,"run":true})
		await s.local_host.request("measure_save")
		var began:=Time.get_ticks_msec();g.set_speed(speed)
		check(await until(func():return hero.pos.distance_to(origin)>.03),"paused move resumes at speed "+str(speed))
		var latency:=Time.get_ticks_msec()-began
		rows.append({"speed":speed,"move_response_ms":latency})
		check(latency<250,"move responds within 250ms including worker/network/display")
		check(await until(func():return hero.action=="idle" and hero.pos.distance_to(origin)>1.0),"walk reaches requested destination")
		await wait_real(.2)
	GameData.options.control_mode=3
	g.direct._process(.016);await wait_real(.4);g.direct.set_process(false);g.rig.set_process(false)
	g.direct._neutral=false;g.direct.heading=hero.facing;g.direct.tilt=-.6
	g.hud.unit_panel.visible=true;g.hud.unit_panel._doll.follow_pose=true
	if DisplayServer.get_name()!="headless":RenderingServer.frame_pre_draw.connect(observe)
	for camera_mode in [3,2]:
		GameData.options.control_mode=camera_mode;g.direct._process(.016);g.direct._neutral=false
		for direction:Vector2 in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
			g.direct.step(direction,.016);await wait_real(.15)
			g.pending_spell="healing{}";g.direct.cast_self()
			var end:=Time.get_ticks_msec()+1600
			while Time.get_ticks_msec()<end:
				g.direct.step(direction,1.0/60);g.direct.apply_camera()
				if hero.direct_motion!=Vector2.ZERO and hero.action.begins_with("cast"):moving_samples+=1
				await get_tree().process_frame
			g.direct.step(Vector2.ZERO,.016);await wait_real(.25)
	check(moving_samples>30,"worker sends moving casts in both direct camera modes")
	if DisplayServer.get_name()!="headless":
		RenderingServer.frame_pre_draw.disconnect(observe)
		check(preview_samples>20 and leg_changes>15 and max_preview_error<.005,"preview copies the final moving legs")
		check(shadow_samples>20 and max_shadow_error<.005,"first-person shadows copy the final moving legs")
	GameData.options.control_mode=1;g.direct._process(.016);await wait_real(.1)
	await s.local_host.stop();get_tree().paused=false;Engine.time_scale=1
	s.online=false;s.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	print("WORKER_ANIMATION_RESPONSE ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"moving_samples":moving_samples,"preview_samples":preview_samples,"leg_changes":leg_changes,"shadow_samples":shadow_samples,"preview_error":max_preview_error,"shadow_error":max_shadow_error}))
	g.queue_free();s.queue_free();await wait_real(.1);TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
func observe()->void:
	if not is_instance_valid(hero) or not hero.action.begins_with("cast") or hero.direct_motion==Vector2.ZERO:return
	var doll:Paperdoll=g.hud.unit_panel._doll
	if doll._model==null:return
	var source:Node3D=hero.model.get_node("hp/ll1")
	var preview:Node3D=doll._model.get_node_or_null("hp/ll1")
	if preview:
		var source_pose:Transform3D=hero.model.global_transform.affine_inverse()*source.global_transform
		var preview_pose:Transform3D=doll._model.global_transform.affine_inverse()*preview.global_transform
		max_preview_error=maxf(max_preview_error,source_pose.origin.distance_to(preview_pose.origin))
		max_preview_error=maxf(max_preview_error,source_pose.basis.get_rotation_quaternion().angle_to(preview_pose.basis.get_rotation_quaternion()))
		var q:=preview_pose.basis.get_rotation_quaternion()
		if q.angle_to(last_leg)>.001:leg_changes+=1
		last_leg=q;preview_samples+=1
	for row:Dictionary in hero.model._view_shadows:
		if not row.shadow.visible or not "ll" in String(hero.model.get_path_to(row.source)):continue
		shadow_samples+=1
		max_shadow_error=maxf(max_shadow_error,row.shadow.global_position.distance_to(row.source.global_position))
		max_shadow_error=maxf(max_shadow_error,row.shadow.global_basis.get_rotation_quaternion().angle_to(row.source.global_basis.get_rotation_quaternion()))
