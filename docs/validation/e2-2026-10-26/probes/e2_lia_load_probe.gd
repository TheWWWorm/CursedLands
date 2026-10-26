extends "local_host_campaign.gd"
## LiA's bz5h contains unindexed procedural geometry. Load through the same
## frontend/worker route as the menu, then let weather cover rasterization run.
## Optional --save-fixture copies a reporter save into the disposable profile.
var traced := false
var framegen := false
var probe_g: Game
var probe_rows := []
var probe_start := 0
var probe_shots := 0
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="):fixture=arg.trim_prefix("--save-fixture=")
		if arg=="--lia-pt":traced=true
		if arg=="--lia-fg":framegen=true
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,
		"volume_voice":0,"auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,
		"q_aa":0,"gfx_soft_ground":0,"gfx_ground_contact":0,"gfx_depth_of_field":0,
		"gfx_weather_surfaces":1,"gfx_water_reflections":3 if traced else 2,
		"control_mode":3,"pt_mode":1 if traced else 0,"q_rt_lighting":0,"pt_accumulation":0,
		"rtx_upscaling":1 if framegen else 0,"rtx_frame_generation":1 if framegen else 0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="1920x1080"
	GameData.options.resolution=maxi(0,GameData.resolutions().find(Vector2i(1920,1080)))
	GameData._window_state.clear();GameData._apply_window()
	await get_tree().create_timer(0.5,true,false,true).timeout
	GameData._window_gen+=1
	get_window().wrap_controls=false;get_window().min_size=Vector2i.ONE
	get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true
	get_window().size=Vector2i(1920,1080);get_window().position=Vector2i.ZERO
	var s:=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	probe_g=g;probe_start=Time.get_ticks_msec()
	RenderingServer.frame_post_draw.connect(probe_draw)
	check(GameData.campaign_id==CampaignProfile.ASTRAL,"test uses LiA data")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	if fixture.is_empty():
		s.state.ensure_hero(0,s._hero_proto(0));s.state.current_zone="gz2h"
		s.state.camera={"at":[160.32,11.863,-233.213],"yaw":-0.8,"pitch":-0.2,"distance":20.0,"style":1,"free":true}
		check(s.state.save(SaveInfo.path("weather-load"))==OK,"seed saved in isolated profile")
	else:
		check(DirAccess.copy_absolute(fixture,SaveInfo.path("weather-load"))==OK,"supplied save copied without modification")
	var expected:=CampaignState.load_from(SaveInfo.path("weather-load"))
	check(expected!=null,"saved campaign is readable")
	if expected==null:get_tree().quit(1);return
	var rt:Node=g.get_node("SceneRaytrace")
	for cycle in 1:
		check(await s.load_game_shown("weather-load"),"save load completes, cycle %d"%cycle)
		check(s.local_host.frontend and s.zone_id==expected.current_zone,"worker presents saved zone")
		check(await until(func():return LoadingScreen._current==null and ShaderCompilationScreen._current==null,90),"load presentation completes")
		if traced:
			check(await until(func():return rt.stats.get("active",false) and rt.device!=null and rt.device.nrd_active,45),"NRD presents actual PT output")
		var start:=s.world.time
		g.set_speed(1)
		check(await until(func():return s.world.time>start+0.5,15),"simulation continues after first visible frames")
		await get_tree().create_timer(3.0,true,false,true).timeout
		check(s.local_host._process_alive() and not g.my_units().is_empty(),"authority and party survive weather processing")
		if traced:check(rt.stats.get("active",false) and rt.device.output_ready(),"PT remains available after load")
		if framegen:
			check(await until(func():return RtxGraphics.bridge()!=null and RtxGraphics.bridge().call("get_status").get("frame_generation_active",false),15),"NVIDIA FG activates after save load")
			var before:Dictionary=RtxGraphics.bridge().call("get_status")
			for frame in 60:await RenderingServer.frame_post_draw
			var after:Dictionary=RtxGraphics.bridge().call("get_status")
			check(int(after.get("presented_frames",0))-int(before.get("presented_frames",0))>=110,"SDK confirms generated frames in loaded LiA")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://lia-weather-load-%d.png"%cycle)
	FileAccess.open("user://lia-load-frames.json",FileAccess.WRITE).store_string(JSON.stringify(probe_rows))
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 12:await get_tree().process_frame
	print("LIA_WEATHER_SAVE_LOAD ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func probe_draw() -> void:
	if not is_instance_valid(probe_g): return
	var rt:=probe_g.get_node("SceneRaytrace")
	var row:={"stats":rt.stats.duplicate(),"nrd":rt.device.nrd_active if rt.device else false,"ms":Time.get_ticks_msec()-probe_start,"loading":LoadingScreen._current!=null,"shader":ShaderCompilationScreen.active(),"pt":bool(rt.stats.get("active",false)),"owner":rt._preparation_owner,"camera":str(get_viewport().get_camera_3d()),"world":is_instance_valid(probe_g.world)}
	probe_rows.append(row)
	if row.world and not row.loading and not row.shader and probe_shots<3:
		if probe_shots==0 or row.pt:
			get_viewport().get_texture().get_image().save_png("user://lia-first-%d.png"%probe_shots);probe_shots+=1
