extends "local_host_campaign.gd"
## Authored campaign geometry, real solo authority, keyboard steering and the
## production first-person camera. Captures are visual evidence, not benchmarks.
signal inspected(value: Dictionary)
var route_resolution := Vector2i(1920,1080)
var out := ""
var zone := "gz4g"
var fixture := ""
var use_fg := false
var standard_rendering := false
var peaceful := false
var leg_count := 4
var s: Session
var g: Game
var hero: GameUnit
var rt: Node
var drive := false
var heading := 0.0
var tilt := -0.12
var rows := []
var visited: Array[Vector2] = []
var distance := 0.0
var previous_position := Vector2.ZERO
var recording_start := 0

func _process(_dt: float) -> void:
	if g and g.rig:
		g.rig._window_focused = true
		if drive:
			g.direct.heading = heading
			g.direct.tilt = tilt

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down
	Input.parse_input_event(event)

func status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}

func write_file(name: String, value: String) -> void:
	var file:=FileAccess.open(out.path_join(name),FileAccess.WRITE)
	file.store_string(value)
	file.close()

func inspect_device(device: RefCounted) -> void:
	inspected.emit.call_deferred({"nrd":device.nrd_active,"closed":device._closed})

func rendering_ready() -> bool:
	if standard_rendering:return not rt.stats.get("active",false)
	return rt.stats.get("active",false) and rt.device!=null and rt.device.nrd_active

func reaches_exit(target: Vector2) -> bool:
	for exit: Dictionary in s.world.zone.get("exits",{}).values():
		if not exit.has("remove"):continue
		var area: Rect2=(exit.remove as Rect2).grow(1.5)
		var outside:=not area.has_point(hero.pos)
		for sample in 40:
			var inside:=area.has_point(hero.pos.lerp(target,float(sample+1)/40.0))
			if inside and outside:return true
			if not inside:outside=true
	return false

func choose_goal(leg: int, avoid: Array = []) -> Vector2:
	var best := Vector2.INF
	var score := -INF
	var preferred := (s.world.terrain.size_ei()*0.5-hero.pos).angle() if leg==0 else heading+0.8
	for length: float in [18.0,12.0,8.0,5.0,3.0]:
		for angle in 32:
			var direction := preferred+float(angle)*TAU/32
			var refused:=false
			for blocked_direction:float in avoid:
				if cos(direction-blocked_direction)>0.8:refused=true;break
			if refused:continue
			var target := hero.pos+Vector2.from_angle(direction)*length
			# Match continuous keyboard steering: terrain and body sweeps are
			# separate. A coarse actor stamp can cover our start while a real
			# escape remains open, and moving bodies may have no standing stamp.
			if not s.world.nav.direct_line(hero,target,false) or reaches_exit(target): continue
			if s.world.nav.steering_blocker(hero,target)!=null: continue
			var nearest := 20.0
			for earlier: Vector2 in visited: nearest=minf(nearest,target.distance_to(earlier))
			var value := length+minf(nearest,8.0)+cos(direction-preferred)*3.0
			if value>score: score=value;best=target
	return best

func phase(label: String, seconds: float, goal := Vector2.INF, pan := false) -> void:
	var start := Time.get_ticks_usec()
	var before := hero.pos
	var first_heading := heading
	var sdk_before := status()
	var frames := 0; var active := 0; var nrd := 0; var body := 0; var fg := 0;var usable:=0
	var times := []; var observations := [];var blocked:=[]
	var previous := start
	var checkpoint:=hero.pos;var checkpoint_time:=0.0;var reroutes:=[];var avoid:=[]
	if goal.is_finite(): key(KEY_W,true)
	print("ZONE_PHASE_START ",label," ",(start-recording_start)/1000000.0)
	while Time.get_ticks_usec()-start<int(seconds*1000000):
		var elapsed := (Time.get_ticks_usec()-start)/1000000.0
		if goal.is_finite() and elapsed-checkpoint_time>1.5:
			if hero.pos.distance_to(checkpoint)<0.3:
				avoid.append(heading)
				var alternate:=choose_goal(1,avoid)
				if alternate.is_finite():
					var nearby:=[]
					for unit: GameUnit in s.world.units.values():
						if unit!=hero and unit.pos.distance_to(hero.pos)<3.0:
							nearby.append({"id":unit.uid,"position":str(unit.pos)})
					goal=alternate;reroutes.append({"at":elapsed,"goal":str(goal),"position":str(hero.pos),"nearby_units":nearby})
			checkpoint=hero.pos;checkpoint_time=elapsed
		if goal.is_finite(): heading=(goal-hero.pos).angle()
		elif pan: heading=first_heading+sin(elapsed*0.65)*0.9
		await RenderingServer.frame_post_draw
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		frames+=1
		var now := Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		distance+=hero.pos.distance_to(previous_position);previous_position=hero.pos
		if rt.stats.get("active",false) and rt.device!=null:
			active+=1
			if rt.device.nrd_active: nrd+=1
			else:
				var observed: RefCounted=rt.device
				RenderingServer.call_on_render_thread(inspect_device.bind(observed))
				var state: Dictionary=await inspected
				if state.closed and observed!=rt.device:
					RenderingServer.call_on_render_thread(inspect_device.bind(rt.device));state=await inspected
				if state.nrd and not state.closed:nrd+=1
		if hero.model and hero.model._view_active: body+=1
		if g.direct.usable():usable+=1
		elif blocked.size()<12:blocked.append({"at":elapsed,"shader":ShaderCompilationScreen.active(),"transition":g.direct.transitioning(),"map":s.map_open,"holding":s._zone_holding,"remote_loading":s._remote_loading,"world_mode":s.world.process_mode,"focus":g.rig._window_focused,"held":g.rig.held,"hud":g.hud.blocks_camera()})
		if status().get("frame_generation_active",false): fg+=1
		if frames%30==0:observations.append({"pos":[hero.pos.x,hero.pos.y],"eye":str(g.rig.camera.global_transform),"world_time":s.world.time,"pending_inputs":s._input_out.pending.size(),"rebuilding":rt.stats.get("rebuilding",false)})
		if goal.is_finite() and hero.pos.distance_to(goal)<0.8:break
	key(KEY_W,false)
	var sdk_after := status()
	var enabled := GameData.option("rtx_frame_generation")!=0
	var presents := int(sdk_after.get("presented_frames",0))-int(sdk_before.get("presented_frames",0))
	var game_presents := int(sdk_after.get("game_presents",0))-int(sdk_before.get("game_presents",0))
	if standard_rendering:
		check(active==0 and nrd==0,label+" stays in standard rendering")
	else:
		check(active==frames and nrd==frames,label+" keeps PT/native NRD active")
	check(body==frames,label+" uses the production first-person body")
	check(usable==frames,label+" stays in controllable gameplay")
	if goal.is_finite():check(hero.pos.distance_to(before)>1.0,label+" keyboard input moves the authority-controlled hero")
	if use_fg:
		check(fg>=frames*0.95 if enabled else fg==0,label+" actual FG state matches request")
		check(presents>=game_presents*1.8 if enabled else presents==0,label+" SDK presentation confirms FG")
	times.sort()
	rows.append({"phase":label,"start_s":(start-recording_start)/1000000.0,"seconds":(Time.get_ticks_usec()-start)/1000000.0,
		"frames":frames,"pt_frames":active,"nrd_frames":nrd,"first_person_frames":body,"controllable_frames":usable,"fg_frames":fg,"sdk_presents":presents,"game_presents":game_presents,"reroutes":reroutes,
		"from":[before.x,before.y],"to":[hero.pos.x,hero.pos.y],"travelled":hero.pos.distance_to(before),"goal":str(goal),
		"frame_ms":{"median":times[times.size()/2],"p95":times[int(times.size()*0.95)],"max":times.back()},"observations":observations,"blocked":blocked})
	# Full-frame readback and PNG encoding create artificial pauses in a live
	# video. Ordinary diagnostic/benchmark runs retain the still captures.
	if not OS.get_cmdline_user_args().has("--zone-route-recording"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(label+".png"))
	persist()
	print("ZONE_PHASE ",label," distance=",rows.back().travelled," PT=",active,"/",frames," NRD=",nrd," FG=",fg)

func persist() -> void:
	write_file("zone-traversal.json",JSON.stringify({
		"checks":checks,"failures":failures,"campaign":GameData.campaign_id,"zone":s.zone_id,"title":s.zone_title(s.zone_id),
		"rows":rows,"distance":distance,"window":str(DisplayServer.window_get_size()),"status":status(),"neutral_exploration":peaceful,
		"frame_limit":Engine.max_fps,"actor_count":s.world.units.size(),"options":GameData.options.duplicate(),
		"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"note":"Real solo worker, normal keyboard steering, live AI and authored geometry; camera turns are scripted. God mode prevents death. Neutral exploration, when flagged, changes the fixture's initial diplomacy. Initial save may be supplied; no route teleportation. frame_limit=0 identifies an uncapped benchmark."},"\t"))

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;process_priority=-6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--zone-route-zone="):zone=arg.trim_prefix("--zone-route-zone=")
		if arg.begins_with("--zone-route-save="):fixture=arg.trim_prefix("--zone-route-save=")
		if arg=="--zone-route-fg":use_fg=true
		if arg=="--zone-route-standard":standard_rendering=true
		if arg=="--zone-route-4k":route_resolution=Vector2i(3840,2160)
		if arg=="--zone-route-peaceful":peaceful=true
		if arg.begins_with("--zone-route-legs="):leg_count=int(arg.trim_prefix("--zone-route-legs="))
	if out.is_empty():out=ProjectSettings.globalize_path("user://zone-traversal")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_HIGH if standard_rendering else GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":2,"gfx_terrain":1,
		"gfx_soft_ground":0,"gfx_ground_contact":0,"gfx_depth_of_field":0,"gfx_water_reflections":3,
		"pt_mode":1,"q_rt_lighting":0,"pt_accumulation":0,"rtx_upscaling":1 if use_fg else 0,"rtx_frame_generation":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"autosave":0,"show_tutorial":0,"control_mode":3,
		"pad_enabled":0,"scroll_border":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	if standard_rendering:
		GameData.options.merge({"gfx_soft_ground":1,"gfx_water_reflections":2,"pt_mode":0,"rt_shadows":0,"rt_gi":0},true)
	GameData.resolution_size="%dx%d"%[route_resolution.x,route_resolution.y]
	GameData.options.resolution=maxi(0,GameData.resolutions().find(route_resolution))
	GameData._window_state.clear();GameData._apply_window()
	s=Session.new();get_parent().add_child(s)
	g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	if fixture.is_empty():
		s.state.ensure_hero(0,s._hero_proto(0));s.state.current_zone=zone;s.state.god_modes[0]=1;s.state.world_time=12
		if peaceful:
			# Supplemental visual coverage when live enemies surround the novice
			# fixture. Preserve map actors, patrols, geometry and collisions.
			var neutral:=PackedInt32Array();neutral.resize(1024);neutral.fill(0)
			s.state.zones[zone]={"dead":[],"units":{},"levers":{},"diplomacy":neutral}
		check(s.state.save(SaveInfo.path("zone-route"))==OK,"create isolated authored-zone save")
	else:check(DirAccess.copy_absolute(fixture,SaveInfo.path("zone-route"))==OK,"copy supplied save without changing it")
	check(await s.load_game_shown("zone-route"),"worker loads the authored zone")
	check(await until(func():return s.world!=null and not s._remote_loading and LoadingScreen._current==null and ShaderCompilationScreen._current==null,120),"world and preparation barriers complete")
	if s.world==null or s.party_heroes().is_empty():get_tree().quit(1);return
	hero=s.party_heroes()[0];g.selected.assign([hero]);g.rig.release();g.rig._window_focused=true
	s.submit({"t":"console","line":"god on","request":1})
	g.set_speed(1);heading=hero.facing;drive=true;tilt=-0.12
	GameData._window_gen+=1
	get_window().wrap_controls=false;get_window().min_size=Vector2i.ONE
	var oversized:=route_resolution.x>DisplayServer.screen_get_size().x or route_resolution.y>DisplayServer.screen_get_size().y
	if oversized:get_window().borderless=false
	get_window().mode=Window.MODE_WINDOWED
	if not oversized:get_window().borderless=true
	# Avoid starting an oversized capture from a screen-covering window.
	# Some Wine presentation paths still clamp it; verify the actual size below.
	if oversized:
		get_window().size=Vector2i(1920,1080);get_window().position=Vector2i(32,32)
	for i in 8:await get_tree().process_frame
	get_window().borderless=true
	get_window().position=Vector2i(32,32) if oversized else Vector2i.ZERO
	get_window().size=route_resolution
	Engine.max_fps=30
	rt=g.get_node("SceneRaytrace")
	check(await until(func():return rendering_ready() and g.direct.usable(),120),"renderer and first-person controls are ready")
	check(s.local_host.frontend and s.local_host._process_alive(),"real separate-process solo authority")
	# Wine/X11 acknowledges an oversized borderless capture window on the
	# following frames; PT can already be ready before that resize lands.
	check(await until(func():return DisplayServer.window_get_size()==route_resolution,3),"full-size capture window")
	print("ZONE_WINDOW ",{"requested":str(route_resolution),"actual":str(DisplayServer.window_get_size()),"mode":get_window().mode,"position":str(get_window().position)})
	if use_fg:check(RtxGraphics.facts().fg,"qualified NVIDIA FG runtime")
	if failures>0:await s.local_host.stop();get_tree().quit(1);return
	var settled:=0
	var settle_until:=Time.get_ticks_msec()+30000
	while settled<90 and Time.get_ticks_msec()<settle_until:
		await RenderingServer.frame_post_draw
		var renderer_active: bool=not rt.stats.get("active",false) if standard_rendering else rt.stats.get("active",false)
		settled=settled+1 if g.direct.usable() and renderer_active and not rt.stats.get("rebuilding",false) else 0
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(settled==90,"preparation settles before recording")
	previous_position=hero.pos;visited.append(hero.pos)
	var world_start := s.world.time
	recording_start=Time.get_ticks_usec()
	write_file("record-ready","%dx%d"%[route_resolution.x,route_resolution.y])
	await get_tree().create_timer(2.0,true,false,true).timeout
	await phase("held-fg-off",6)
	for leg in leg_count:
		if use_fg and leg==leg_count/2:
			GameData.options.rtx_frame_generation=1
			check(await until(func():return status().get("frame_generation_active",false),20),"FG activates for remaining movement")
		var goal := choose_goal(leg)
		check(goal.is_finite(),"authored navigation supplies route leg "+str(leg))
		if not goal.is_finite():break
		tilt=-0.65 if leg%2 else -0.12
		await phase("walk-%d"%leg,12,goal)
		visited.append(hero.pos)
		await phase("pan-%d"%leg,4,Vector2.INF,true)
	await phase("final-held",6)
	check(distance>8.0,"route includes substantial actual player movement")
	check(s.world.time>world_start+10,"world simulation advances throughout traversal")
	key(KEY_W,false);drive=false;g.direct.stop_move();g.direct.set_process(false)
	check(await until(func():return s._input_out.pending.is_empty(),5),"final commands are acknowledged")
	check(not hero.dead and s.local_host._process_alive(),"party and authority survive traversal")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test cursor remains free")
	persist()
	write_file("record-done","done")
	key(KEY_W,false);drive=false;g.direct.stop_move();await s.local_host.stop()
	g.queue_free();s.queue_free()
	for i in 12:await get_tree().process_frame
	print("STANDARD_ZONE_TRAVERSAL " if standard_rendering else "PT_ZONE_TRAVERSAL ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
