extends "res://tools/tests/path_trace_walk_performance.gd"
## Recording-derived route through the ordinary single-player host process.
## Never substitute camera travel or inline simulation for player movement.
var s: Session
var g: Game
var h: GameUnit
var rt: Node
var route_results:=[]
var track:=[]
var route_distance:=0.0
var last_pos:=Vector2.ZERO
var look_goal:=Vector2(64,138)
var view_mode:=3
var inactive_frames:=0
var inactive_nrd_frames:=0
var began:=0
var dlss_fg:=false

func create_session() -> Session:
	return Session.new()

func create_game() -> Game:
	return Game.new()

func run() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var dlss:=OS.get_cmdline_user_args().has("--route-dlss")
	dlss_fg=OS.get_cmdline_user_args().has("--route-dlss-fg")
	var inventory:=OS.get_cmdline_user_args().has("--route-inventory")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":2,
		"gfx_terrain":1,"gfx_ground_contact":0,"gfx_depth_of_field":0,"gfx_water_reflections":2,
		"pt_mode":0 if inventory else 1,"pt_accumulation":0,"q_rt_lighting":0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.options.rtx_upscaling=2 if dlss else 0
	GameData.options.rtx_frame_generation=1 if dlss_fg else 0
	if dlss:check(RtxGraphics.facts().sr,"DLSS SDK available before traversal")
	if dlss_fg:check(dlss and RtxGraphics.facts().fg and RtxGraphics.facts().reflex,"native NVIDIA frame generation available before traversal")
	if not failures.is_empty():await finish();return
	s=create_session();get_parent().add_child(s)
	g=create_game();g.session=s;s.game=g;get_parent().add_child(g)
	if DisplayServer.get_name()=="headless":
		check(await s.local_host.start(0,1,true)==OK,"inventory starts the production single-player worker")
	await s.new_campaign(false)
	for i in 1800:
		if s.world!=null and not s.loading_game and not s._remote_loading:break
		await frames(1)
	check(s.local_host.frontend and s.local_host.single_player and s.world!=null and not s.world.authority,
		"ordinary campaign uses the separate simulation process")
	if not failures.is_empty():await finish();return
	h=s.party_heroes()[0];t=s.world.terrain;camera=g.rig.camera
	g.rig.set_process(false);g.direct.set_process(false);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	g.set_speed(1)
	var units:=[]
	for u: GameUnit in s.world.units.values():
		units.append({"uid":u.uid,"proto":u.proto.get("name",""),"pos":[u.pos.x,u.pos.y],"height":u.global_position.y,"dead":u.dead,"hp":u.hp})
	FileAccess.open(out.path_join("route-inventory.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"units":units,"hero":h.uid,"size":[t.sectors_x*32,t.sectors_y*32],"zone":s.world.zone},"\t"))
	var map:=GameData.load_image(String(s.world.zone.get("minimap","")))
	if map:map.flip_y();map.save_png(out.path_join("map.png"))
	if inventory:await finish();return
	GameData.resolution_size="3840x2160"
	get_window().borderless=true;get_window().size=resolution
	Gfx.apply_quality(get_viewport())
	g.direct._set_view_mode(3);g.direct.heading=0;g.direct.tilt=-0.12;g.direct.apply_camera()
	rt=g.get_node("SceneRaytrace")
	check(await ready_scene(rt),"recording route prepares PT")
	check(s.local_host._process_alive(),"simulation process survives cold shader loading")
	if dlss:
		check(RtxGraphics.sr_active(),"DLSS survives campaign loading and forced redraws")
	if not failures.is_empty():await finish();return
	get_window().size=resolution;await frames(20)
	check(rt.stats.get("display_size",[])==[3840,2160],"route renders at recorded 4K resolution")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	last_pos=h.pos;began=Time.get_ticks_msec()
	await stage("ruins-held",10)
	await walk("east-opening",Vector2(60,139),25)
	await walk("downhill-path",Vector2(66,125),25)
	g.set_speed(2)
	await encounter(1804,"wolf",true)
	g.sound.weather.on_event({"w":1,"fade":0.0},g.sound._ticks);g._update_daylight(false)
	await walk("slope-to-boar",Vector2(57.5,106),25)
	await encounter(1890,"slope-boar",true)
	await stage("slope-after-combat",25)
	await milestone("slope")
	view_mode=1;g.direct._set_view_mode(1);g.direct._update_view_model(null)
	await walk("down-to-beach",Vector2(48,82),35)
	await encounter(1915,"beach-boar",true)
	await stage("beach-after-combat",25)
	await milestone("beach")
	await encounter(1921,"shore-toad",true)
	await encounter(1922,"south-toad",true)
	await stage("shore-after-five-kills",20)
	get_tree().paused=true
	await stage("shore-paused",8)
	get_tree().paused=false
	GameData.options.pt_accumulation=1
	await stage("shore-still-scene-filter",15)
	view_mode=3;g.direct._set_view_mode(3);look_goal=Vector2(60,135)
	await stage("look-back-uphill",15)
	await milestone("final")
	check(inactive_frames==0,"PT stays active along the recording-derived route")
	check(inactive_nrd_frames==0,"NRD stays active during responsive accumulation")
	check(route_distance>80 and h.pos.y<70,"actual player reaches the southern beach from the ruins")
	FileAccess.open(out.path_join("recording-route.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),
		"runs":route_results,"track":track,"distance":route_distance,"inactive_frames":inactive_frames,
		"inactive_nrd_frames":inactive_nrd_frames,"dlss":RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {},"host_process":s.local_host.frontend,"authority":s.world.authority,"stats":rt.stats},"\t"))
	await finish()

func update_view() -> void:
	if view_mode==3:
		if h.pos.distance_to(look_goal)>1.0:g.direct.heading=(look_goal-h.pos).angle()
		g.direct.apply_camera(1.0/60.0)
	else:
		var at:=h.global_position
		camera.global_position=at+Vector3(-12,24,24)
		camera.look_at(at+Vector3(0,1,0))
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func stage(label: String,seconds: float,predicate:=Callable()) -> void:
	var wall:=[];var cpu:=[];var generations:=[]
	var rtx_before:Dictionary=RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {}
	var fg_active_frames:=0
	var dlss_before:=int(RtxGraphics.bridge().call("get_status").get("dlss_evaluations",0)) if RtxGraphics.bridge()!=null else 0
	gpu_samples.clear();sampling=true
	var start:=Time.get_ticks_msec();var previous:=Time.get_ticks_usec();var last_track:=start-1000
	while Time.get_ticks_msec()-start<seconds*1000:
		update_view();await frames(1)
		var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
		if dlss_fg and RtxGraphics.bridge().call("get_status").get("frame_generation_active",false):fg_active_frames+=1
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		route_distance+=h.pos.distance_to(last_pos);last_pos=h.pos
		if not rt.stats.get("active",false):inactive_frames+=1
		if GameData.options.pt_accumulation==0 and (rt.device==null or not rt.device.get("nrd_active")):
			inactive_nrd_frames+=1
		if Time.get_ticks_msec()-last_track>=1000:
			last_track=Time.get_ticks_msec()
			track.append({"ms":last_track-began,"phase":label,"pos":[h.pos.x,h.pos.y],
				"hp":h.hp,"world_time":s.world.time,"units":s.world.units.size(),"view":view_mode,
				"fps":Engine.get_frames_per_second(),"generation":rt.stats.get("snapshot_generation",0),
				"wound_layers":UnitWounds._wound_layers.size(),"wound_jobs":UnitWounds._jobs.size()})
		if predicate.is_valid() and predicate.call():break
		if h.dead:check(false,"hero survives "+label);break
	sampling=false
	var row:={"dlss":RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {},"phase":label,"seconds":(Time.get_ticks_msec()-start)/1000.0,"frame_ms":summary(wall),
		"process_ms":summary(cpu),"rt_gpu_ms":summary(gpu_samples.duplicate()),"hp":h.hp,"pos":[h.pos.x,h.pos.y],
		"world_time":s.world.time,"generation":rt.stats.get("snapshot_generation",0),"distance":route_distance,
		"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"wound_layers":UnitWounds._wound_layers.size(),
		"wound_jobs":UnitWounds._jobs.size(),"nrd":rt.device.get("nrd_active") if rt.device!=null else false}
	row["sampled_frames"]=wall.size()
	row["dlss_evaluations"]=int(row.dlss.get("dlss_evaluations",0))-dlss_before
	row["game_presents"]=int(row.dlss.get("game_presents",0))-int(rtx_before.get("game_presents",0))
	row["presented_frames"]=int(row.dlss.get("presented_frames",0))-int(rtx_before.get("presented_frames",0))
	row["fg_active_frames"]=fg_active_frames
	if dlss_fg:
		if get_tree().paused:
			check(not row.dlss.get("frame_generation_active",true),"NVIDIA frame generation suspends while paused")
		else:
			check(fg_active_frames>=wall.size()-20,"NVIDIA frame generation stays active: "+label)
			check(row.presented_frames>=wall.size()*1.8 and row.presented_frames<=wall.size()*2.2,"NVIDIA presents approximately two frames per render: "+label)
		check(int(FsrGraphics.bridge().call("get_status").get("frame_generation_dispatches",0))==0,"FSR frame generation unused: "+label)
	if OS.get_cmdline_user_args().has("--route-dlss"):
		check(row.dlss.get("sr_supported",false) and int(row.dlss.get("last_error",-1))==0,"DLSS remains available: "+label)
		check(row.dlss_evaluations>=wall.size()-2,"DLSS evaluates rendered frames: "+label)
	var marks: GroundMarks=s.world.ground_marks
	if marks:row["marks"]={"blood":marks.blood_marks.size(),"feet":marks.foot_marks.size(),"fire":marks.fire_marks.size()}
	route_results.append(row);print("RECORDING_STAGE ",JSON.stringify(row))

func walk(label: String,goal: Vector2,seconds: float) -> void:
	look_goal=goal
	s.submit({"t":"move","units":[h.uid],"x":goal.x,"y":goal.y,"run":false})
	await stage(label,seconds,func():return h.pos.distance_to(goal)<0.6)
	check(h.pos.distance_to(goal)<0.6,"player walks to "+label)

func encounter(uid: int,label: String,loot: bool) -> void:
	var enemy: GameUnit=s.world.units.get(uid)
	check(is_instance_valid(enemy),"authored encounter exists: "+label)
	if not is_instance_valid(enemy):return
	look_goal=enemy.pos
	s.submit({"t":"attack","units":[h.uid],"target":uid,"run":false})
	await stage("fight-"+label,40,func():
		var target: GameUnit=s.world.units.get(uid)
		return target==null or target.dead)
	check(is_instance_valid(enemy) and enemy.dead,"normal combat defeats "+label)
	if loot and is_instance_valid(enemy) and enemy.dead:
		s.submit({"t":"loot","units":[h.uid],"target":uid,"run":false})
		await stage("loot-"+label,15,func():return not s.world.units.has(uid))
		check(not s.world.units.has(uid),"normal looting removes "+label)
	# The recording heals between fights. Keep ordinary damage and wound
	# effects active; use the known self-heal instead of invulnerability.
	if not h.dead and h.hp<h.max_hp*.9:
		s.submit({"t":"cast","unit":h.uid,"target":h.uid,"spell":"healing{}"})
		await stage("heal-"+label,20,func():return h.hp>=h.max_hp*.95)

func milestone(label: String) -> void:
	# Readback can stall. Exclude it and the following frames from timing.
	await shot("route-"+label);await frames(30)

func finish() -> void:
	get_tree().paused=false
	await s.local_host.stop()
	g.queue_free();s.queue_free();await frames(16);TexUpscale.shutdown()
	print("RECORDING_ROUTE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
