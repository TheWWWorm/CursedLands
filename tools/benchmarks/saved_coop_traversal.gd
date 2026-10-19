extends "coop_traversal_session.gd"
## Two rendered ENet peers and the normal separate authority. Both heroes
## come from supplied saves via the ordinary host-load / bring-hero paths.
## Commands travel through Game; attributes, damage, stamina, enemies and
## effects are never overridden. Input files are copied into isolated data.
class SpellObservation extends RefCounted:
	var game: Game
	var world: GameWorld:
		get: return game.world
	var session: Session:
		get: return game.session
	var travel_event := {}
	var delivered := {}
	var started := {}
	var completed := {}
	var pending_manual := {}
	var clouds := []
	var peak_clouds := 0
	func on_event(e: Dictionary) -> void:
		if e.get("t") == "travel": travel_event = e.duplicate(true)
		elif e.get("t") in ["travel_close", "load_begin"]: travel_event.clear()
		if e.get("t")=="castfx" and world:
			var caster:GameUnit=world.units.get(int(e.get("uid",-1)))
			if caster and caster.controller==session.my_index:
				var code:=String(Spells.parse(String(e.spell)).code)
				started[code]=int(started.get(code,0))+1
				pending_manual[code]=true
				print("SAVED_COOP_CAST_STARTED ",JSON.stringify({"code":code,"world_time":world.time,"peer":session.my_index,"seconds_to_effect":e.get("secs",0)}))
		if e.get("t")=="spellfx" and world:
			var caster: GameUnit=world.units.get(int(e.get("a",-1)))
			if caster and caster.controller==session.my_index:
				var code:=String(e.get("code",""));delivered[code]=int(delivered.get(code,0))+1
				if pending_manual.erase(code):completed[code]=int(completed.get(code,0))+1
				if code=="acid_fog":
					clouds=clouds.filter(func(c):return float(c.until)>world.time)
					clouds.append({"at":Vector2(float(e.x),float(e.y)),"until":world.time+float(Spells.parse(String(e.spell)).duration)*GameUnit.TICK})
					peak_clouds=maxi(peak_clouds,clouds.size())
				print("SAVED_COOP_SPELL_DELIVERED ",JSON.stringify({"code":code,"world_time":world.time,"peer":session.my_index,"completed":completed.get(code,0),"point":[e.get("x"),e.get("y")],"live_clouds":clouds.filter(func(c):return float(c.until)>world.time).size()}))

class ShopPlan extends ArenaRun:
	var intent:={}
	func buy(index:int)->String:intent={"action":"buy","args":[index]};return ""
	func sell(uid:int)->String:intent={"action":"sell","args":[uid]};return ""
	func train()->String:intent={"action":"train","args":[]};return ""
	func refresh()->String:intent={"action":"refresh","args":[]};return ""

var observed := SpellObservation.new()
var retention_rows:=[]
var old_worlds:Array[WeakRef]=[]
var tournament: ArenaOnlineSession
var tournament_screen: ArenaOnlineScreen


var host_source:=""
var guest_source:=""
var group_file:=""
var spell_times:={}
var weakened:={}
var weapon_serials:={}
var last_seen_pos:=Vector2.ZERO
var last_progress:=0.0
var routes_done:=0
var saved_camera:={}
var guest_gpu:=-1
var guest_display:=""
var guest_xauthority:=""
var owner_size:=Vector2i(1920,1080)
var guest_size:=Vector2i(1920,1080)
var camera_cycle:=false
var camera_phase:=-1
var casting_code:=""
var casting_count:=0
var casting_since:=0.0
var cast_timeouts:={}
var casting_started_count:=0
var casting_target:=-1
var casting_point:=false
var cast_sequence:=0
var cloud_capture_at:=-100.0
var checkpoint:=false
var settle_here:=false
var stopped:=false
var measured_zone:=""
var zone_began:=0.0
var zone_visits:={}
var changing_location:=false
var exit_requested_at:=-100.0
var prior_deaths:=0
var measured_world:WeakRef
var match_poses:=""

func write_group(value: Dictionary) -> void:
	# Two clients share this observer file. Publish a complete snapshot so a
	# guest never reads the interval between truncating and writing the file.
	var temporary := group_file + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(temporary, group_file)

func run()->void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		print("SAVED_COOP_PARSE_OK");get_tree().quit();return
	guest=OS.get_cmdline_user_args().has("--guest")
	default_render_thread=OS.get_cmdline_user_args().has("--default-render-thread")
	checkpoint=OS.get_cmdline_user_args().has("--checkpoint")
	stationary=OS.get_cmdline_user_args().has("--stationary")
	settle_here=OS.get_cmdline_user_args().has("--settle-here")
	camera_cycle=OS.get_cmdline_user_args().has("--camera-cycle")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--host-save="):host_source=arg.trim_prefix("--host-save=")
		if arg.begins_with("--guest-save="):guest_source=arg.trim_prefix("--guest-save=")
		if arg.begins_with("--duration="):duration=float(arg.trim_prefix("--duration="))
		if arg.begins_with("--label="):run_label=arg.trim_prefix("--label=").validate_filename()+"-"
		if arg.begins_with("--guest-gpu="):guest_gpu=int(arg.trim_prefix("--guest-gpu="))
		if arg.begins_with("--guest-display="):guest_display=arg.trim_prefix("--guest-display=")
		if arg.begins_with("--guest-xauthority="):guest_xauthority=arg.trim_prefix("--guest-xauthority=")
		if arg.begins_with("--owner-size="):owner_size=parse_size(arg.trim_prefix("--owner-size="))
		if arg.begins_with("--guest-size="):guest_size=parse_size(arg.trim_prefix("--guest-size="))
		if arg.begins_with("--match-poses="):match_poses=arg.trim_prefix("--match-poses=")
	if host_source.is_empty() or guest_source.is_empty():push_error("Both save paths are required");get_tree().quit(2);return
	var original:=CampaignState.load_from(host_source)
	if original==null:push_error("Host save cannot load");get_tree().quit(2);return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"net_websocket":0,"control_mode":1,"display_mode":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"pad_enabled":0,"camera_style":1,"cam_follow":1},true)
	var rules:Dictionary=original.mod_config.get("rules",{}).duplicate()
	for key:String in rules.keys():
		if key.begins_with("sandbox_"):
			if int(rules[key])!=0:push_error("Performance run requires ordinary health and stamina");get_tree().quit(2);return
			rules.erase(key)
	var problem:=ModStore.apply_rules(rules)
	if not problem.is_empty():push_error(problem);get_tree().quit(2);return
	Engine.max_fps=0
	await frames_wait(15);apply_window_size()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	group_file=ProjectSettings.globalize_path("user://saved-coop-group.json")
	if not guest:
		DirAccess.copy_absolute(host_source,SaveInfo.path("supplied-host"))
		DirAccess.copy_absolute(guest_source,SaveInfo.path("supplied-guest"))
		write_group({})
		if OS.get_cmdline_user_args().has("--trials-first"):
			for cycle in 3:await trial(cycle)
	await before_campaign()
	await open_campaign()
	if not await until(func():return s.world!=null and not s.loading_game and not s._remote_loading and hero()!=null,90):push_error("Saved hero did not deploy");await finish();return
	await frames_wait(45)
	FileAccess.open("user://saved-coop-ready-"+("guest" if guest else "owner"),FileAccess.WRITE).store_string("ready")
	if not await until(func():return FileAccess.file_exists("user://saved-coop-ready-guest") and FileAccess.file_exists("user://saved-coop-ready-owner"),90):
		push_error("Both views did not become ready");await finish();return
	apply_window_size();Gfx.apply_quality(get_viewport())
	var h:=hero();g.selected.assign([h]);g.rig.focus(h.position);g.rig.follow(h);g.hud.text_window.open=false
	start_pos=h.pos;last_pos=h.pos;last_seen_pos=h.pos;progress_pos=h.pos
	saved_camera=g.rig.pose()
	if not guest:g.set_speed(2)
	await until(func():return s.clock_speed==1,10)
	g.issue({"t":"gait","units":[h.uid],"gait":2});g.issue({"t":"aggression","units":[h.uid],"on":false})
	if not match_poses.is_empty():
		var positions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(match_poses))
		var pose:Dictionary=positions["guest" if guest else "owner"]
		var destination:=Vector2(float(pose.position[0]),float(pose.position[1]))
		g.issue({"t":"move","units":[h.uid],"x":destination.x,"y":destination.y,"run":false})
		if not await until(func():return h.pos.distance_to(destination)<.12 and h.action=="idle",60):
			push_error("Restart pose could not be reached through ordinary movement");await finish();return
		g.rig.set_pose(pose.camera_pose)
		start_pos=h.pos;last_pos=h.pos;last_seen_pos=h.pos;progress_pos=h.pos
		await frames_wait(120)
	# The saved Necromancers' Desert has surviving groups in the western
	# valley and far northern ridge. Walk the routes; never reposition actors.
	route.assign([Vector2(238,342),Vector2(181,352),Vector2(168,365),Vector2(128,303),Vector2(113,348),Vector2(155,280),Vector2(163,210),Vector2(162,143),Vector2(210,151),Vector2(278,145),Vector2(304,150),Vector2(286,235),start_pos])
	initial_dead=s.world.unit_rows().filter(func(u):return u.dead).size()
	initial_world_time=s.world.time
	var record:Dictionary=h.get_meta("hero")
	print("SAVED_COOP_START ",JSON.stringify({"peer":"guest" if guest else "owner","index":s.my_index,"zone":s.zone_id,"hero":h.uid,"pos":str(h.pos),"hp":h.hp,"max_hp":h.max_hp,"mana":h.mana,"max_mana":h.max_mana,"skills":record.get("skills"),"perks":record.get("perks"),"spells":record.get("spells"),"weapons":record.get("weapons"),"armors":record.get("armors"),"stats":h.stats,"options":GameData.options,"size":str(get_viewport().get_visible_rect().size),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"pid":OS.get_process_id(),"worker":s.local_host.process_id}))
	frame_usec=Time.get_ticks_usec();began=Time.get_ticks_msec();next_decision=INF if stationary else 20.0;stage="settled" if stationary else "baseline";_running=true

func observe_game()->void:
	observed.game=g
	g.event_presented.connect(observed.on_event)

func open_campaign()->void:
	GameData.player_name="Save test caster" if guest else "Save test fighter"
	s=Session.new();get_parent().add_child(s)
	g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	observe_game()
	s.message.connect(func(message:String):print("SAVED_COOP_MESSAGE ",message))
	if guest:
		# A restart comparison reclaims the already imported saved hero.
		CoopProgress.bring_slot="" if checkpoint else "supplied-guest"
		if OS.get_cmdline_user_args().has("--full-trials-first"):
			if not await until(func():return FileAccess.file_exists("user://campaign-authority-ready"),90):get_tree().quit(2);return
		if s.join("127.0.0.1",29917)!=OK:get_tree().quit(2);return
	else:
		if await s.local_host.start(29917,2,false)!=OK:get_tree().quit(2);return
		if not await s.load_game_shown("supplied-host"):push_error("Host load failed");get_tree().quit(2);return
		FileAccess.open("user://campaign-authority-ready",FileAccess.WRITE).store_string("ready")
		if child<0:child=launch_guest(guest_arguments())
		if not await until(func():return s.players.size()==2,90):push_error("Saved guest did not join");await finish();return

func before_campaign()->void:
	if not OS.get_cmdline_user_args().has("--full-trials-first"):return
	if not guest:child=launch_guest(guest_arguments())
	for cycle in 3:
		await full_tournament(cycle)

func guest_arguments()->PackedStringArray:
	var args:=PackedStringArray(["--rendering-method","forward_plus"])
	if not OS.get_cmdline_user_args().has("--real-audio"):args.append_array(["--audio-driver","Dummy"])
	if not default_render_thread:args.append_array(["--render-thread","safe"])
	if guest_gpu>=0:args.append_array(["--gpu-index",str(guest_gpu)])
	if OS.has_feature("editor"):args.append_array(["--path",ProjectSettings.globalize_path("res://")])
	args.append_array(["--","--ei-path="+GameData.root,"--tool="+get_script().resource_path,"--guest","--host-save="+host_source,"--guest-save="+guest_source,"--duration="+str(duration),"--label="+run_label.trim_suffix("-")])
	for flag:String in ["--default-render-thread","--checkpoint","--stationary","--settle-here","--camera-cycle","--full-trials-first","--change-locations","--real-audio"]:
		if OS.get_cmdline_user_args().has(flag):args.append(flag)
	args.append_array(["--owner-size=%dx%d"%[owner_size.x,owner_size.y],"--guest-size=%dx%d"%[guest_size.x,guest_size.y]])
	if not match_poses.is_empty():args.append("--match-poses="+match_poses)
	return args

static func parse_size(value:String)->Vector2i:
	var parts:=value.split("x")
	assert(parts.size()==2 and int(parts[0])>=640 and int(parts[1])>=480)
	return Vector2i(int(parts[0]),int(parts[1]))

func apply_window_size()->void:
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=guest_size if guest else owner_size
	get_window().position=Vector2i.ZERO

func launch_guest(args:PackedStringArray)->int:
	# Only the spawned peer inherits the temporary X11 display. Restore the
	# owner's environment before any further authority/renderer work.
	var previous:={}
	for key:String in ["DISPLAY","XAUTHORITY"]:
		previous[key]={"present":OS.has_environment(key),"value":OS.get_environment(key)}
	if not guest_display.is_empty():OS.set_environment("DISPLAY",guest_display)
	if not guest_xauthority.is_empty():OS.set_environment("XAUTHORITY",guest_xauthority)
	var pid:=OS.create_process(OS.get_executable_path(),args)
	for key:String in previous:
		if previous[key].present:OS.set_environment(key,previous[key].value)
		else:OS.unset_environment(key)
	return pid

func _process(dt:float)->void:
	if _running:
		if s.world==null or s.loading_game or s._remote_loading or hero()==null:
			frame_usec=Time.get_ticks_usec();frames.clear();return
		if measured_zone!=s.zone_id:
			adopt_zone((Time.get_ticks_msec()-began)/1000.0)
	if _running and camera_cycle and not stationary:
		var t:=(Time.get_ticks_msec()-began)/1000.0
		var phase:=int(t/120.0)%3
		if settle_here and t>=duration-90:phase=0
		if phase!=camera_phase:
			camera_phase=phase
			g.direct._set_view_mode([1,2,3][phase])
			print("SAVED_COOP_CAMERA ",JSON.stringify({"seconds":t,"mode":GameData.option("control_mode"),"peer":"guest" if guest else "owner"}))
		if t>=20 and not (settle_here and t>=duration-90):
			var real_dt:=dt/maxf(Engine.time_scale,0.001)
			if phase==0:g.rig.yaw+=real_dt*.12
			else:
				# Keep the ordinary direct camera active while orders follow the
				# route. Look around during travel and aim at live combat targets.
				var target:GameUnit=s.world.units.get(target_id)
				var h:=hero()
				if target and h:g.direct.heading=(target.pos-h.pos).angle()
				elif h:g.direct.heading=h.facing+sin(t*.1)*.7
				g.direct.tilt=-.12+sin(t*.05)*.1
	super._process(dt)
	if _running and guest:
		var t:=(Time.get_ticks_msec()-began)/1000.0
		var clouds_now:=observed.clouds.filter(func(c):return float(c.until)>s.world.time).size()
		if clouds_now>=2 and t-cloud_capture_at>120:
			cloud_capture_at=t;capture.call_deferred(int(t))

func saved_cast(code:String,target:GameUnit,t:float)->bool:
	var h:=hero();var spells:Array=h.get_meta("hero").get("spells",[])
	for slot in spells.size():
		var sp:=Spells.parse(String(spells[slot]))
		if sp.code!=code or h.mana<g.spell_ui_cost(h,sp):continue
		# Direct views intentionally do not walk into spell range. Approach
		# through ordinary movement first, with a margin for moving enemies.
		if target!=h and h.pos.distance_to(target.pos)>float(sp.range)*.8:
			stage="approaching for "+code
			move_to(h,target.pos+(h.pos-target.pos).normalized()*float(sp.range)*.6)
			return true
		g.begin_cast(slot)
		var info:=g.pending_target(target,target.pos)
		if info.is_empty() or not g.pending_in_range(info):g.cancel_touch_target();return false
		if h.action in ["walk","run"]:g.issue({"t":"stop","units":[h.uid]})
		casting_started_count=int(observed.started.get(code,0))
		casting_target=target.uid;casting_point=bool(sp.point)
		g.cast_on(target,null,target.pos);g.cancel_touch_target();last_spell=t;spell_times[code]=t
		casting_code=code;casting_count=int(observed.completed.get(code,0));casting_since=t
		attempts[code]=int(attempts.get(code,0))+1;attack_target=-1;move_goal=Vector2.INF
		return true
	return false

func safe_to_idle() -> bool:
	var party := s.world.party_units().filter(func(u):return u.controller>=0)
	if party.is_empty() or party.any(func(u):return u.dead or u.hp<u.max_hp*.9):return false
	for unit:GameUnit in s.world.unit_rows():
		if unit.dead or unit.controller>=0 or not s.world.is_enemy(hero(),unit):continue
		if party.any(func(u):return u.pos.distance_to(unit.pos)<35):return false
	return true

func decide(t:float)->void:
	next_decision=t+.35
	var h:=hero()
	if h==null:return
	# Optional live steering is limited to ordinary player commands. It lets
	# the operator navigate around authored terrain without moving actors.
	var control_path:="user://saved-coop-control.json"
	if FileAccess.file_exists(control_path):
		var control=JSON.parse_string(FileAccess.get_file_as_string(control_path))
		if control is Dictionary:current_control=control
	if current_control.get("finish",false):_running=false;finish.call_deferred();return
	if h.dead:stage="awaiting revival";return
	if settle_here and t>=duration-90 and safe_to_idle():
		if not stopped:g.issue({"t":"stop","units":[h.uid]});stopped=true
		stage="settled";return
	stopped=false
	if h.action=="attack":weapon_serials[h._remote_action_serial]=true
	g.selected.assign([h])
	if not casting_code.is_empty():
		if int(observed.completed.get(casting_code,0))>casting_count:
			if casting_code=="weak":weakened[casting_target]=true
			if guest and casting_code in ["acid_fog","lightning","weak"]:cast_sequence+=1
			casting_code=""
		elif t-casting_since<2.5 or (int(observed.started.get(casting_code,0))>casting_started_count and t-casting_since<25):
			var waiting_target:GameUnit=s.world.units.get(casting_target)
			if not casting_point and (waiting_target==null or waiting_target.dead):
				casting_code="";return
			stage="casting "+casting_code;return
		else:
			cast_timeouts[casting_code]=int(cast_timeouts.get(casting_code,0))+1
			g.issue({"t":"stop","units":[h.uid]});casting_code="";attack_target=-1
	if h.action.begins_with("cast") or t-last_spell<1.2:return
	var ally:GameUnit=null
	for u:GameUnit in s.world.party_units():
		if u!=h and u.controller>=0 and not u.dead:ally=u;break
	if h.hp<h.max_hp*0.8 and saved_cast("healing",h,t):stage="healing";return
	if ally and ally.hp<ally.max_hp*.55 and h.pos.distance_to(ally.pos)<15 and saved_cast("healing",ally,t):stage="healing ally";return
	if OS.get_cmdline_user_args().has("--change-locations") and not guest \
			and t<duration-180 and (changing_location or t-zone_began>360):
		if leave_for_next_zone(h,t):return
	if current_control.get("move_only",false):
		var point:=Vector2(current_control.point[0],current_control.point[1])
		stage="steered travel";move_to(h,point);return
	var group:Dictionary={}
	if guest and FileAccess.file_exists(group_file):
		var value=JSON.parse_string(FileAccess.get_file_as_string(group_file))
		if value is Dictionary:group=value
	var target:GameUnit=s.world.units.get(int(group.get("target",target_id)))
	if target==null or target.dead or h.pos.distance_to(target.pos)>35 or visited.has(target.uid):target=choose_target(h)
	if target and target.uid!=target_id:
		target_id=target.uid;target_since=t;progress_at=t;progress_hp=target.hp;attack_target=-1
		print("TRAVERSE_TARGET ","guest" if guest else "owner"," time=",int(t)," ",target.display_name," ",target.pos)
	if target and (target.hp<progress_hp-1 or h.pos.distance_to(last_seen_pos)>2):progress_at=t;progress_hp=target.hp;last_seen_pos=h.pos
	if target and t-progress_at>45:
		visited[target.uid]=true;print("TRAVERSE_SKIP_STALLED ",target.uid);target=null;target_id=-1
	if not guest:
		write_group({"target":target.uid if target else -1,"point":[h.pos.x,h.pos.y]})
	if target:
		stage="combat";move_goal=Vector2.INF
		if guest:
			# Repeated clouds are intentional: the supplied caster commonly
			# stacks them, interleaving lightning and weakening during fights.
			var sequence:=["acid_fog","acid_fog","acid_fog","weak","lightning","acid_fog","lightning"]
			var code:String=sequence[cast_sequence%sequence.size()]
			if code=="weak" and weakened.has(target.uid):cast_sequence+=1;code=sequence[cast_sequence%sequence.size()]
			if saved_cast(code,target,t):return
			if saved_cast("lightning",target,t):return
		else:
			if not weakened.has(target.uid) and saved_cast("weak",target,t):return
			if t-float(spell_times.get("lightning",-100.0))>10 and saved_cast("lightning",target,t):return
		if attack_target!=target.uid or h.action=="idle":g.forced_on("attack",target,null);attempts.attack+=1;attack_target=target.uid
		return
	target_id=-1
	if guest:
		if ally and h.pos.distance_to(ally.pos)>3:stage="travel";move_to(h,ally.pos)
		else:stage="regroup"
		return
	if ally and h.pos.distance_to(ally.pos)>20:stage="regroup";g.issue({"t":"stop","units":[h.uid]});return
	var point:Vector2=route[route_index%route.size()]
	if h.pos.distance_to(point)<5:
		route_index+=1;point=route[route_index%route.size()];last_progress=t;last_seen_pos=h.pos
		print("TRAVERSE_WAYPOINT ",route_index," at ",h.pos)
	if h.pos.distance_to(last_seen_pos)>2:last_progress=t;last_seen_pos=h.pos
	if t-last_progress>35:
		print("TRAVERSE_ROUTE_BLOCKED ",route_index," at ",h.pos);route_index+=1;last_progress=t;move_goal=Vector2.INF
		point=route[route_index%route.size()]
	stage="travel";move_to(h,point)

func sample(t:float)->void:
	super.sample(t)
	var row:Dictionary=samples.back()
	if OS.get_cmdline_user_args().has("--full-trials-first"):census("campaign-%d"%int(t))
	row.spell_events=observed.delivered.duplicate()
	row.manual_casts_started=observed.started.duplicate()
	row.manual_casts_completed=observed.completed.duplicate()
	row.live_acid_clouds=observed.clouds.filter(func(c):return float(c.until)>s.world.time).size()
	row.peak_acid_clouds=observed.peak_clouds
	row.observed_weapon_swings=weapon_serials.size()
	row.cast_timeouts=cast_timeouts.duplicate()
	row.render_size=str(get_viewport().get_visible_rect().size)
	row.camera_mode=GameData.option("control_mode")
	row.camera_pose=g.rig.pose()
	row.adapter=RenderingServer.get_video_adapter_name()
	row.zone=s.zone_id
	row.zone_visits=zone_visits.duplicate()
	row.deaths+=prior_deaths
	row.display=OS.get_environment("DISPLAY")
	row.surviving_foes=s.world.unit_rows().filter(func(u):return not u.dead and u.controller<0 and s.world.is_enemy(hero(),u)).size()
	FileAccess.open("user://traversal-"+run_label+("guest" if guest else "owner")+".json",FileAccess.WRITE).store_string(JSON.stringify(samples,"\t"))
	print("SAVED_COOP_COUNTS ","guest" if guest else "owner"," ",JSON.stringify({"seconds":t,"spells":row.spell_events,"swings":row.observed_weapon_swings,"foes":row.surviving_foes}))

func finish()->void:
	if guest:
		# Leave both imported heroes present in the authority's checkpoint.
		await until(func():return not s.online or s.multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED,30)
	elif s and s.world and not stationary:
		var answer:=await s.local_host.request("save",{"slot":"checkpoint-end","name":"","camera":s.local_host.view(),"image":PackedByteArray()})
		print("SAVED_COOP_CHECKPOINT ",JSON.stringify(answer))
	await super.finish()

func adopt_zone(t:float)->void:
	var h:=hero()
	if not measured_zone.is_empty():
		if not samples.is_empty():prior_deaths=int(samples[-1].deaths)
		if measured_world:old_worlds.append(measured_world)
		start_pos=h.pos;last_pos=h.pos;last_seen_pos=h.pos;progress_pos=h.pos
		initial_dead=s.world.unit_rows().filter(func(u):return u.dead).size()
		initial_world_time=s.world.time;route_index=0;last_progress=t
		visited.clear();weakened.clear();target_id=-1;attack_target=-1;move_goal=Vector2.INF
		casting_code="";observed.clouds.clear();observed.pending_manual.clear()
		g.selected.assign([h]);g.rig.focus(h.position);g.rig.follow(h)
		g.issue({"t":"gait","units":[h.uid],"gait":2});g.issue({"t":"aggression","units":[h.uid],"on":false})
		if not guest:g.set_speed(2)
		if s.zone_id=="gz17h":
			route.assign([Vector2(345,110),Vector2(345,170),Vector2(350,230),Vector2(300,280),Vector2(230,280),Vector2(200,220),Vector2(200,160),Vector2(280,160),Vector2(340,120),start_pos])
		elif s.zone_id!="gz18h":
			var size:=Vector2(s.world.nav.size)*NavGrid.CELL
			route.clear()
			for fraction:Vector2 in [Vector2(.3,.3),Vector2(.3,.7),Vector2(.7,.7),Vector2(.7,.3),Vector2(.5,.5)]:
				route.append(s.world.nav.nearest_walkable(size*fraction))
			route.append(start_pos)
		if not guest: write_group({})
	measured_zone=s.zone_id;measured_world=weakref(s.world);zone_began=t;changing_location=false
	zone_visits[s.zone_id]=int(zone_visits.get(s.zone_id,0))+1
	print("SAVED_COOP_LOCATION ",JSON.stringify({"seconds":t,"zone":s.zone_id,"position":str(h.pos),"peer":"guest" if guest else "owner","exits":s.world.zone.get("exits",{})}))

func leave_for_next_zone(h:GameUnit,t:float)->bool:
	var travel:Dictionary=observed.travel_event
	if not travel.is_empty():
		var options:Array=travel.get("options",[]).filter(func(o):return String(o.zone)!=s.zone_id and s.campaign.zone(String(o.zone)).get("type","")=="game")
		options.sort_custom(func(a,b):
			var av:=int(zone_visits.get(a.zone,0));var bv:=int(zone_visits.get(b.zone,0))
			if av!=bv:return av<bv
			if String(a.zone)=="gz17h":return true
			if String(b.zone)=="gz17h":return false
			return String(a.zone)<String(b.zone))
		if not options.is_empty() and t-exit_requested_at>3:
			var option:Dictionary=options[0]
			g.issue({"t":"travel","zone":option.zone,"entrance":option.entrance})
			exit_requested_at=t;stage="changing location";return true
	var choices:=[]
	for number in s.world.zone.get("exits",{}):
		var ex:Dictionary=s.world.zone.exits[number]
		if ex.has("remove") and s.campaign.zone(String(ex.get("to","none"))).get("type","")=="edge" and s._exit_is_open(int(number),s.my_index):
			choices.append({"number":int(number),"rect":ex.remove,"point":(ex.remove as Rect2).get_center()})
	if choices.is_empty():return false
	choices.sort_custom(func(a,b):return h.pos.distance_squared_to(a.point)<h.pos.distance_squared_to(b.point))
	var choice:Dictionary=choices[0]
	changing_location=true;stage="walking to map exit"
	write_group({"target":-1,"point":[h.pos.x,h.pos.y]})
	if (choice.rect as Rect2).has_point(h.pos):
		if t-exit_requested_at>3:
			g.issue({"t":"leave_exit","exit":choice.number});exit_requested_at=t
	else:move_to(h,choice.point)
	return true

func census(label:String,fps:=0.0)->void:
	var row:={"label":label,"ticks":Time.get_ticks_msec(),"pid":OS.get_process_id(),
		"peer":"guest" if guest else "owner","fps":fps,"adapter":RenderingServer.get_video_adapter_name(),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"old_worlds_alive":old_worlds.filter(func(w):return w.get_ref()!=null).size(),
		"frame_listeners":get_tree().get_signal_connection_list("process_frame").size(),
		"figure_models":EIFigure._models.size(),"figure_meshes":EIFigure._meshes.size(),
		"unit_textures":EIUnitModel._textures.size(),"fade_materials":CameraFade._derived.size(),
		"wound_composites":UnitWounds._composites.size(),"wound_layers":UnitWounds._wound_layers.size(),
		"wound_jobs":UnitWounds._jobs.size(),"warmed_materials":ShaderWarmup._keep.size()}
	retention_rows.append(row)
	FileAccess.open("user://retention-"+run_label+("guest" if guest else "owner")+".json",FileAccess.WRITE).store_string(JSON.stringify(retention_rows,"\t"))
	print("RETENTION ",JSON.stringify(row))

func full_tournament(cycle:int)->void:
	census("before-tournament-%d"%cycle)
	tournament=ArenaOnlineSession.new();tournament.player_name="Save test caster" if guest else "Save test fighter"
	get_parent().add_child(tournament)
	var ready_file:="user://trials-lobby-%d"%cycle
	if guest:
		if not await until(func():return FileAccess.file_exists(ready_file),90):get_tree().quit(2);return
		if tournament.join("127.0.0.1:29918")!=OK:get_tree().quit(2);return
		if not await until(func():return tournament._connected and tournament.members.size()==2,90):get_tree().quit(2);return
		tournament.request("ready")
	else:
		if await tournament.host_shown(29918)!=OK:get_tree().quit(2);return
		FileAccess.open(ready_file,FileAccess.WRITE).store_string("ready")
		if not await until(func():return tournament.members.size()==2 and tournament.members.values().all(func(m):return m.ready),90):get_tree().quit(2);return
		var problem:=tournament.start_game(7319+cycle)
		if not problem.is_empty():push_error(problem);get_tree().quit(2);return
	if not await until(func():return tournament.started and tournament.view.seats.size()==9,90):get_tree().quit(2);return
	tournament_screen=ArenaOnlineScreen.new();tournament_screen.connection=tournament
	get_parent().add_child(tournament_screen);await frames_wait(15);apply_window_size()
	if not guest:tournament.request("speed",[2])
	var round_number:=-1;var plan:={};var ready_sent:=false
	var next_action:=0;var next_watch:=0;var next_measure:=0
	var frame_count:=0;var measured_at:=Time.get_ticks_msec();var start:=measured_at
	while tournament.view.global_stage!="won":
		var now:=Time.get_ticks_msec();var view:=tournament.view
		if now-start>3600000:push_error("Full tournament exceeded one hour");get_tree().quit(2);return
		if view.wave!=round_number:
			round_number=view.wave;plan={"done":false,"actions":0,"rerolls":0};ready_sent=false
		if now>=next_action and view.global_stage=="prepare" and not view.preparing_battle and view.lives>0:
			next_action=now+650
			if not plan.done:
				var copy:=ShopPlan.new();copy.auto_save=false
				var snap:=view.snapshot()
				for key:String in ["gold","army","shop","lives","training","stage","wave","history","free_refresh","next_uid","boons"]:
					copy.set(key,snap[key])
				ArenaBotPlanner.step(copy,2 if guest else 3,view.wave,view.lives,plan)
				if not copy.intent.is_empty():
					var args:Array=copy.intent.args
					if copy.intent.action=="sell":args.append(view.sale_value(view.unit(int(args[0]))))
					tournament.request(copy.intent.action,args)
					tournament.request("arrange")
			elif not ready_sent:
				if not view.ready_seats.has(tournament.my_seat):tournament.request("ready")
				ready_sent=true
		if now>=next_watch:
			next_watch=now+7000
			var selected:=int((now-start)/7000)%10-1
			if selected<0:tournament_screen._show_boards()
			else:tournament_screen._show_player(selected)
		if now>=next_measure:
			next_measure=now+30000
			census("tournament-%d-round-%d-%s"%[cycle,view.wave,view.global_stage],float(frame_count)*1000/maxi(1,now-measured_at))
			print("RETENTION_MATCH ",JSON.stringify({"cycle":cycle,"round":view.wave,"stage":view.global_stage,"health":view.lives,"alive":view.alive_players().size(),"seconds":(now-start)/1000.0,"peer":"guest" if guest else "owner"}))
			frame_count=0;measured_at=now
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://tournament-%d-%s-%04d.png"%[cycle,"guest" if guest else "owner",int((now-start)/1000)])
		frame_count+=1
		await get_tree().process_frame
	census("tournament-%d-completed-round-%d-place-%d"%[cycle,tournament.view.wave,tournament.view.placements[0]])
	var finished_file:="user://trials-finished-%d-"%cycle
	FileAccess.open(finished_file+("guest" if guest else "owner"),FileAccess.WRITE).store_string("finished")
	if not guest:await until(func():return FileAccess.file_exists(finished_file+"guest"),60)
	old_worlds.append(weakref(tournament_screen.battle.world))
	for board:ArenaPveMatch in tournament_screen._tournament_battles.boards.values():old_worlds.append(weakref(board.world))
	tournament_screen.queue_free();await frames_wait(4)
	await tournament.close_shown();tournament.queue_free();await frames_wait(120)
	census("tournament-%d-freed"%cycle)
