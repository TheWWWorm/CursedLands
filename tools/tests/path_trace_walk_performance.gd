extends "res://tools/tests/path_trace_spatial_performance.gd"
## Full-effects 4K live simulation with repeated walking/recentering, then
## an optional four-minute animated-player soak. Use a heavy GPU Lab job.
var walk_legs := 9
var walk_ticks := 180
var soak := false
var storm_fast := false
func summary(values: Array) -> Dictionary:
	values.sort()
	return {} if values.is_empty() else {"n":values.size(),"median":values[values.size()/2],
		"p95":values[int(values.size()*0.95)],"p99":values[int(values.size()*0.99)],"max":values[-1]}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--pt-hd":resolution=Vector2i(1920,1080)
		if arg=="--pt-soak":soak=true;walk_legs=30;walk_ticks=240
		if arg=="--pt-storm-fast":storm_fast=true
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":2,
		"gfx_terrain":1,"gfx_ground_contact":0,"gfx_depth_of_field":0,"gfx_water_reflections":2,
		"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="%dx%d"%[resolution.x,resolution.y]
	get_window().borderless=true;get_window().size=resolution
	Gfx.apply_quality(get_viewport())
	var session:=Session.new();add_child(session)
	var game:=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=12
	await session.enter_zone("gz1g",1,false)
	var hero: GameUnit=session.party_heroes()[0] if soak else null
	if soak:session.state.god_modes[0]=1 # Keep NPC combat active without ending the fixture.
	if storm_fast:
		game.speed=1;session.field_speed=1;Engine.time_scale=55.0/27.0
		game.sound.weather.on_event({"w":1,"fade":0.0},game.sound._ticks)
		game._update_daylight(false)
	t=game.world.terrain
	camera=Camera3D.new();game.add_child(camera);camera.fov=65;camera.near=0.08
	var start:=hero.global_position if soak else game.rig.camera.global_position
	camera.position=start;camera.current=true
	game.rig.set_process(false);game.direct.set_process(false)
	game.hud.hide();game.hud.set_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"live full-effects scene prepares PT")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	get_window().borderless=true;get_window().size=resolution
	await frames(20)
	check(rt.stats.display_size==[resolution.x,resolution.y],"walking benchmark uses the requested full resolution")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=30 if soak else 0
	var route: Array[Vector2]=[Vector2(start.x,-start.z),Vector2(start.x+24,-start.z),
		Vector2(start.x+24,-start.z+24),Vector2(start.x,-start.z+24),Vector2(start.x,-start.z)]
	var results:=[];var inactive:=0;var nrd_inactive:=0;var distance:=0.0
	var began:=Time.get_ticks_msec()
	var last_hero:=hero.pos if soak else Vector2.ZERO
	for leg in walk_legs:
		var a: Vector2=route[leg%4];var b: Vector2=route[leg%4+1]
		if soak:hero.move_to(b)
		var wall:=[];var cpu:=[];var process:=[];var poses:=[];var phases:={}
		gpu_samples.clear();sampling=true
		var previous:=Time.get_ticks_usec()
		for tick in walk_ticks:
			var p:=a.lerp(b,float(tick)/(walk_ticks-1))
			if soak:
				distance+=hero.pos.distance_to(last_hero);last_hero=hero.pos;p=hero.pos
			camera.position=Vector3(p.x,t.height_at(p.x,p.y)+1.7,-p.y)
			var forward:=Vector3(b.x-a.x,0.0,a.y-b.y).normalized()
			camera.look_at(camera.position+forward+Vector3(0,-0.12,0))
			await frames(1)
			var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			cpu.append(rt.stats.get("cpu_update_ms",0));process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			poses.append(rt.stats.get("updated_poses",0))
			for key: String in ["cpu_topology_ms","cpu_snapshot_ms","cpu_gather_ms","cpu_total_ms"]:
				if not phases.has(key):phases[key]=[]
				phases[key].append(rt.stats.get(key,0))
			if not rt.stats.get("active",false):inactive+=1
			if soak and (rt.device==null or not rt.device.get("nrd_active")):nrd_inactive+=1
		sampling=false
		var row:={"leg":leg,"frame_ms":summary(wall),"rt_gpu_ms":summary(gpu_samples.duplicate()),
			"scene_cpu_ms":summary(cpu),"process_ms":summary(process),"poses":summary(poses),
			"generation":rt.stats.get("snapshot_generation",0),"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"nrd":rt.device.get("nrd_active") if rt.device!=null else false,"position":str(camera.position),
			"hero_distance":distance,"elapsed_ms":Time.get_ticks_msec()-began}
		for key: String in phases:row[key]=summary(phases[key])
		results.append(row);print("WALK_PERFORMANCE ",JSON.stringify(row))
	# Keep GPU readback out of the route; it can stall rendering for seconds
	# and contaminate the next segment's engine performance monitor.
	await shot("walk-final")
	check(inactive==0,"PT remains active throughout the full walking route")
	if soak:
		check(nrd_inactive==0,"NRD remains active throughout the player movement soak")
		check(distance>100.0,"animated player traverses over 100 metres with live simulation")
		check(Time.get_ticks_msec()-began>=230000,"movement soak covers at least 230 seconds")
	FileAccess.open(out.path_join("walk-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"runs":results,
		"resolution":[resolution.x,resolution.y],"stats":rt.stats,"soak":soak,"storm_fast":storm_fast,
		"time_scale":Engine.time_scale,"sun_linear":Gfx.sun.srgb_to_linear().r,
		"inactive_frames":inactive,"nrd_inactive_frames":nrd_inactive},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
