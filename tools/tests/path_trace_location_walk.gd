extends "res://tools/tests/path_trace_first_person_live.gd"
## Additional authored locations with live inline simulation and normal move
## orders. No animation seeking or per-frame actor placement. Camera input is
## scripted; the separate-process campaign route is a different fixture.
var s: Session
var g: Game
var h: GameUnit
var rt: Node
var zone := "gz4g"
var dlss := false
var storm := false
var direct_input := false
var peaceful := false
var route_legs := 8
var total_distance := 0.0
var previous_position := Vector2.ZERO
var visited: Array[Vector2] = []
var stages := []
var observations := []
var inactive_frames := 0
var nrd_inactive_frames := 0
var shifted_frames := 0
var transform_mismatches := 0
var maximum_transform_error := 0.0
var mismatch_examples := []
var in_flight_reads := 0
var world_start := 0.0
var pose_timing := false
var early_pose := {}
var pose_stage := ""
var pose_index := 0
var scenery_placements := {}
var camera_driver: Node
var drive_goal := Vector2.INF
var drive_enabled := false
var drive_heading := 0.0
var drive_tilt := -0.12


class CameraDriver extends Node:
	var callback: Callable
	func _process(dt: float) -> void:
		callback.call(dt)


func drive_camera(dt: float) -> void:
	if not drive_enabled: return
	g.direct.heading=drive_heading; g.direct.tilt=drive_tilt
	if direct_input:
		var aim := {"t":"direct_look","units":[h.uid],"heading":g.direct.heading}
		aim.merge(g.direct.aim_view(h))
		s.submit(aim)
		s.submit({"t":"direct_move","units":[h.uid],"direction":(drive_goal-h.pos).normalized() if drive_goal.is_finite() else Vector2.ZERO,"run":false})
	g.direct.apply_camera(minf(dt,0.1))
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _process(_dt: float) -> void:
	if not pose_timing or not is_instance_valid(h) or not is_instance_valid(rt) or rt._scene==null: return
	early_pose.clear()
	for entry: Dictionary in rt._scene.instances:
		var mesh: Node3D=entry.node.get_ref()
		if is_instance_valid(mesh) and mesh is MeshInstance3D and mesh.layers==EIUnitModel.CLOSE_VIEW_LAYER and (entry.mask&1)!=0:
			early_pose[mesh.get_instance_id()]={"frame":Engine.get_process_frames(),"traced":str(entry.transform.origin),"presented":str(h.model.presented_mesh_transform(mesh).origin),"shift":str(h.model._view_shift)}

func inventory() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var locations := []
	for id: String in ["gz4g","gz5g","bz7g","gz9g","gz11k","gz18h","bz8k"]:
		var z := campaign.zone(id)
		var mob := EIMob.load_bytes(GameData.read_file("maps/"+String(z.get("mob",""))+".mob"))
		var row := {"zone":z,"objects":mob.objects}
		if id=="gz11k":
			GameData.options.gfx_waterfalls=1
			var terrain := EITerrain.load_map(String(z.mpr))
			if terrain and terrain._waterfalls: row["waterfalls"]=terrain._waterfalls.field.falls
			if terrain: terrain.free()
		locations.append(row)
	FileAccess.open(out.path_join("location-inventory.json"),FileAccess.WRITE).store_string(JSON.stringify(locations,"\t"))
	get_tree().quit()

func run() -> void:
	seed(7321)
	process_priority=102
	var start := Vector2.INF
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--pt-zone="): zone=arg.trim_prefix("--pt-zone=")
		if arg.begins_with("--pt-start="):
			var xy := arg.trim_prefix("--pt-start=").split(",")
			if xy.size()==2: start=Vector2(float(xy[0]),float(xy[1]))
		if arg=="--pt-dlss": dlss=true
		if arg=="--pt-storm": storm=true
		if arg=="--pt-direct-input": direct_input=true
		if arg=="--pt-peaceful": peaceful=true
		if arg=="--pt-pose-timing": pose_timing=true
		if arg=="--pt-no-sequence": capture_sequence=false
		if arg.begins_with("--pt-legs="): route_legs=maxi(1,int(arg.trim_prefix("--pt-legs=")))
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_cmdline_user_args().has("--pt-walk-inventory"):
		inventory(); return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":2,
		"gfx_terrain":1,"gfx_ground_contact":0,"gfx_depth_of_field":0,"gfx_water_reflections":2,
		"rt_shadows":0,"rt_gi":0,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,"render_scale":0,
		"rtx_upscaling":4 if dlss else 0,"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"character_light":0,"autosave":0,"show_tutorial":0,"scroll_border":0,
		"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="2560x1440"
	GameData.options.fps_limit=GameData.FPS_LIMITS.find(30)
	Engine.max_fps=30; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	s=Session.new(); add_child(s)
	g=Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0)); s.state.world_time=12
	s.state.god_modes[0]=1 # NPC combat and effects stay live without ending the test.
	await s.enter_zone(zone,1,false)
	check(s.zone_id==zone and s.world!=null,"authored live location loads: "+zone)
	if s.world==null: await finish(); return
	check(not s.party_heroes().is_empty(),"location supplies a playable hero")
	if s.party_heroes().is_empty(): await finish(); return
	h=s.party_heroes()[0]; t=s.world.terrain; camera=g.rig.camera
	if peaceful:
		# Optional exploration-only profile: keep actors, patrols and animation
		# live, but avoid an invulnerable novice being permanently surrounded.
		# Combat/effect routes deliberately omit this flag.
		for faction in 32:
			s.world.set_relation(h.faction,faction,0)
			s.world.set_relation(faction,h.faction,0)
	if start.is_finite():
		var requested := start
		start=Vector2.INF
		for radius in 13:
			for angle in 24:
				var at := requested+Vector2.from_angle(float(angle)*TAU/24)*float(radius)*0.5
				if not s.world.nav.cell_open(at,h._classes[2]): continue
				h.pos=at
				for direction in 16:
					if s.world.nav.direct_line(h,at+Vector2.from_angle(float(direction)*TAU/16)*3.0): start=at; break
				if start.is_finite(): break
			if start.is_finite(): break
		check(start.is_finite(),"requested starting site has open navigation within six metres")
		if not start.is_finite(): await finish(); return
		print("LOCATION_START requested=",requested," open=",start)
		h.pos=start; h.resync_drawn() # Initial site only; all route motion uses move_to.
	g.selected.assign([h]); g.rig.set_process(false); g.direct.set_process(false); g.rig.release()
	g.direct._set_view_mode(3); g.direct.heading=h.facing; g.direct.tilt=-0.12; g.direct.apply_camera()
	# Feed camera/commands before normal pose and PT callbacks. A coroutine
	# resuming from a render-thread readback can otherwise change the camera
	# after PT has already submitted that frame.
	camera_driver=CameraDriver.new()
	camera_driver.process_priority=-6
	camera_driver.callback=drive_camera
	add_child(camera_driver)
	g.set_speed(1)
	GameData.options.resolution=maxi(0,GameData.resolutions().find(Vector2i(2560,1440)))
	GameData._apply_window()
	GameData._window_gen+=1 # Cancel startup's deferred native-size placement.
	get_window().mode=Window.MODE_WINDOWED
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=resolution
	get_window().borderless=true; get_window().size=Vector2i(2560,1440)
	Gfx.apply_quality(get_viewport())
	get_viewport().scaling_3d_scale=0.5
	if dlss: RtxGraphics.apply_upscaling(get_viewport())
	rt=g.get_node("SceneRaytrace")
	check(await ready_scene(rt),"live location prepares PT")
	print("LOCATION_INITIAL ",JSON.stringify(rt.stats))
	check(rt.stats.get("display_size",[])==[3840,2160] and rt.stats.get("size",[])==[960,540],"4K display and Low/Performance trace sizes")
	check(h.model._view_active,"production first-person body is active")
	verify_scenery_placement()
	if dlss: check(RtxGraphics.sr_active(),"DLSS Performance SDK is active")
	if not failures.is_empty(): await finish(); return
	if OS.get_cmdline_user_args().has("--pt-location-benchmark"):
		var benchmark: Node=load("res://tools/tests/path_trace_location_benchmark.gd").new()
		add_child(benchmark);await benchmark.measure(self);await finish();return
	if OS.get_cmdline_user_args().has("--pt-grass-audit"):
		await load("res://tools/tests/path_trace_grass_live.gd").new().run(self)
		await finish(); return
	world_start=s.world.time
	if direct_input: s.submit({"t":"direct_control","leader":h.uid})
	previous_position=h.pos; visited.append(h.pos)
	await stage("arrival-held",90)
	for leg in route_legs:
		var goal := choose_goal(leg)
		check(goal.is_finite(),"live navigation supplies leg "+str(leg))
		if not goal.is_finite(): break
		if storm and leg==route_legs/2:
			g.sound.weather.on_event({"w":1,"fade":3.0},g.sound._ticks)
			g._update_daylight(false)
		var origin := h.pos
		if not direct_input: h.move_to(goal,false)
		g.direct.heading=(goal-origin).angle()
		await stage("walk-%02d"%leg,420,goal,leg)
		check(h.pos.distance_to(origin)>1.0,"normal hero movement advances leg "+str(leg))
		# Live actors and body sweeps may stop an exploration leg short of its
		# planned endpoint. Record that separately from renderer stability; the
		# next leg starts from the actual position and still has to advance.
		stages.back()["reached_goal"]=h.pos.distance_to(goal)<0.7
		if not stages.back().reached_goal: print("LOCATION_BLOCKED_GOAL ",leg," remaining=",h.pos.distance_to(goal))
		visited.append(h.pos)
		await stage("look-%02d"%leg,60,Vector2.INF,leg)
		if leg==route_legs/2:
			g.direct._set_view_mode(2); await stage("third-person-held",90)
			g.direct._set_view_mode(3); await stage("first-person-restored",60)
			if direct_input:
				for gait in [1,0,2]:
					s.submit({"t":"gait","units":[h.uid],"gait":gait})
					await stage("posture-"+str(gait),60)
	await stage("final-held",90)
	check(total_distance>float(route_legs)*3.0,"route contains substantial actual player movement")
	check(s.world.time>world_start+10.0,"world simulation and NPCs advance throughout the route")
	check(inactive_frames==0,"PT stays active through all sampled completed frames")
	check(nrd_inactive_frames==0,"NRD stays active through all sampled completed frames")
	check(shifted_frames>0,"first-person look-down exercises body clearance")
	check(transform_mismatches==0,"PT body transforms match the displayed first-person body")
	check(not h.dead,"live hero survives the route")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"development cursor stays free")
	if dlss:
		var status: Dictionary=RtxGraphics.bridge().call("get_status")
		check(int(status.get("last_error",-1))==0 and int(status.get("dlss_evaluations",0))>100,"DLSS completes location traversal without SDK errors")
	await finish()

func verify_scenery_placement() -> void:
	var tested := 0
	var missing := []
	for root: Node3D in s.world.objects.values():
		for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or mesh.mesh==null or mesh.global_position.distance_to(camera.global_position)>80: continue
			var bounds := (mesh.global_transform*mesh.get_aabb()).grow(0.02)
			var hits := RenderingServer.instances_cull_aabb(bounds,mesh.get_world_3d().scenario)
			tested+=1
			if not hits.has(mesh.get_instance_id()): missing.append(str(mesh.get_path()))
	scenery_placements={"tested":tested,"missing":missing}
	print("SCENERY_PLACEMENT ",JSON.stringify(scenery_placements))
	check(tested>0 and missing.is_empty(),"nearby scenery is present at its authored renderer bounds")

func choose_goal(leg: int) -> Vector2:
	var best := Vector2.INF
	var score := -INF
	var preferred := (t.size_ei()*0.5-h.pos).angle() if leg==0 else g.direct.heading+0.55
	var directions := PackedFloat32Array()
	for i in 24: directions.append(preferred+float(i)*TAU/24)
	for i in 32: directions.append(float(i)*TAU/32)
	for distance: float in [12.0,8.0,5.0,3.0]:
		for angle: float in directions:
			var point := h.pos+Vector2.from_angle(angle)*distance
			# Direct steering's body sweeps handle NPC overlap/escape. A nearby
			# attacker's grid stamp must not make every direction look closed.
			if not s.world.nav.direct_line(h,point,not direct_input): continue
			var nearest := 100.0
			for earlier: Vector2 in visited: nearest=minf(nearest,point.distance_to(earlier))
			var value := distance+minf(nearest,8.0)+cos(angle-preferred)*2.0
			if value>score: score=value; best=point
	return best

func stage(label: String,ticks: int,goal:=Vector2.INF,leg:=-1) -> void:
	Engine.max_fps=30
	var began := Time.get_ticks_msec()
	var from := h.pos
	var start_heading := g.direct.heading
	var stage_frames := 0
	var resets := 0
	pose_stage=label
	RenderingServer.frame_pre_draw.connect(sample_body_pose)
	drive_goal=goal
	drive_heading=start_heading
	drive_enabled=true
	for i in ticks:
		pose_index=i
		if label.begins_with("look-"):
			drive_heading=start_heading+TAU*float(i)/float(ticks)
			drive_tilt=-1.1 if leg%2==0 else -0.12
		else:
			drive_tilt=-0.7 if leg%3==0 else -0.12
		await frames(1); await RenderingServer.frame_post_draw
		stage_frames+=1
		total_distance+=h.pos.distance_to(previous_position); previous_position=h.pos
		var active: bool=rt.stats.get("active",false) and rt.device!=null
		if not active: inactive_frames+=1
		elif not rt.device.nrd_active:
			var observed: RefCounted=rt.device
			RenderingServer.call_on_render_thread(inspect_device.bind(observed))
			var state: Dictionary=await inspected_device
			if state.closed and observed!=rt.device:
				RenderingServer.call_on_render_thread(inspect_device.bind(rt.device))
				state=await inspected_device
			if state.nrd and not state.closed: in_flight_reads+=1
			else: nrd_inactive_frames+=1
		if not rt.stats.get("history_reused",false): resets+=1
		if i%30==0:
			observations.append({"stage":label,"i":i,"pos":[h.pos.x,h.pos.y],"eye":str(camera.global_transform),
				"generation":rt.stats.get("snapshot_generation",0),"active":active,"hp":h.hp,"world_time":s.world.time})
		if capture_sequence and label in ["arrival-held","walk-00","look-00","walk-04","look-04","third-person-held","final-held"] and i>=40 and i<52:
			var frame := get_viewport().get_texture().get_image()
			frame.resize(1920,1080,Image.INTERPOLATE_LANCZOS)
			frame.save_png(out.path_join("sequence-%s-%02d.png"%[label,i-40]))
		if goal.is_finite() and h.pos.distance_to(goal)<0.6: break
	RenderingServer.frame_pre_draw.disconnect(sample_body_pose)
	drive_enabled=false
	if direct_input: s.submit({"t":"direct_move","units":[h.uid],"direction":Vector2.ZERO})
	stages.append({"phase":label,"frames":stage_frames,"seconds":(Time.get_ticks_msec()-began)/1000.0,
		"from":[from.x,from.y],"to":[h.pos.x,h.pos.y],"goal":str(goal),"distance":total_distance,"history_resets":resets,
		"stats":rt.stats.duplicate(true),"world_time":s.world.time})
	await shot(label)
	persist()
	print("LOCATION_STAGE ",zone," ",label," frames=",stage_frames," distance=",total_distance," inactive=",inactive_frames," nrd_inactive=",nrd_inactive_frames)

func sample_body_pose() -> void:
	# The separate render thread may deliver frame_post_draw after the next
	# CPU tick starts. Compare the presentation and submitted RT transforms at
	# frame_pre_draw, after the model's final alignment callback, without an
	# asynchronous readback crossing into a different process frame.
	if h.model._view_active and rt._scene!=null:
		if h.model._view_shift.length()>0.001: shifted_frames+=1
		for entry: Dictionary in rt._scene.instances:
			var mesh: Node3D=entry.node.get_ref()
			if is_instance_valid(mesh) and mesh is MeshInstance3D and mesh.layers==EIUnitModel.CLOSE_VIEW_LAYER and (entry.mask&1)!=0:
				var presented: Vector3=h.model.presented_mesh_transform(mesh).origin
				var error: float=entry.transform.origin.distance_to(presented)
				maximum_transform_error=maxf(maximum_transform_error,error)
				if error>0.0001:
					transform_mismatches+=1
					if mismatch_examples.size()<12:
						mismatch_examples.append({"stage":pose_stage,"i":pose_index,"frame":Engine.get_process_frames(),"node":str(mesh.get_path()),"traced":str(entry.transform.origin),"presented":str(presented),"shift":str(h.model._view_shift),"error":error,"early":early_pose.get(mesh.get_instance_id(),{}),"rebuilding":rt.stats.get("rebuilding",false),"generation":rt.stats.get("snapshot_generation",0)})

func persist() -> void:
	var status: Dictionary=RtxGraphics.bridge().call("get_status") if dlss else {}
	FileAccess.open(out.path_join("location-walk.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"zone":zone,"stages":stages,"observations":observations,
		"final_stats":rt.stats if is_instance_valid(rt) else {},
		"distance":total_distance,"inactive_frames":inactive_frames,"nrd_inactive_frames":nrd_inactive_frames,
		"shifted_frames":shifted_frames,"transform_mismatches":transform_mismatches,"max_transform_error":maximum_transform_error,
		"mismatch_examples":mismatch_examples,
		"scenery_placements":scenery_placements,
		"in_flight_reads":in_flight_reads,"dlss":status,"weather_transition":storm,"world_start":world_start,"direct_input":direct_input,"peaceful":peaceful,
		"note":"Live inline authority; real hero move orders and normal animations, scripted camera turns. God mode prevents NPC combat ending the fixture. Initial site may be explicitly positioned; no route teleportation. Capture readbacks and a 30 FPS cap make this unsuitable for performance comparison."
	},"\t"))

func finish() -> void:
	persist()
	if is_instance_valid(g): g.queue_free()
	if is_instance_valid(s): s.queue_free()
	await frames(16); TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
