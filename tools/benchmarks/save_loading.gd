extends Node
## Load-time diagnostic: fresh application entry, first authority-worker load,
## and two subsequent loads. Run through GPU Lab as a heavy benchmark.
## Pass --bench-pt=0|1, --bench-zone=ZONE and --audit-out=/absolute/new/results.
## --bench-fps=N sets the frame cap while loading (default 30, 0 uncapped).
## --bench-standby boots the simulation worker in advance, as the menus do.
## --bench-first-save=/absolute/save.sav measures the real first load from an
## empty game, starting its authority process, instead of an inline zone entry.
var session: Session
var game: Game
var rows := []
var events := []
var started := 0
var phase := ""
var mode := 0
var out := "user://save-loading"
var watching := false
var sample := ""
var last_stage := ""
var first_save := ""
var zone := "gz3g"
var reloads := 3
var fps := 30
var standby := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func progress(row: Dictionary) -> void:
	var key := str(row.get("phase"))+":"+str(row.get("completed"))+":"+str(row.get("total"))
	if watching and key != phase:
		phase=key
		events.append({"case":sample,"ms":Time.get_ticks_msec()-started,"phase":key})

func _process(_dt: float) -> void:
	if not watching or not is_instance_valid(game): return
	var rt := game.get_node_or_null("SceneRaytrace")
	if rt == null: return
	var stage := "gather" if rt._gather!=null else "prepare-%s"%rt._pending_stage if rt._pending_stage>=0 else "gpu" if rt._pending_device!=null else "active" if rt._ready_gpu else "idle"
	if stage != last_stage:
		last_stage=stage
		events.append({"case":sample,"ms":Time.get_ticks_msec()-started,"rt_stage":stage})

func settle() -> bool:
	var deadline := Time.get_ticks_msec()+240000
	var stable := 0
	while Time.get_ticks_msec()<deadline and stable<5:
		Engine.max_fps=fps
		await get_tree().process_frame
		var rt := game.get_node("SceneRaytrace")
		var done := not session.loading_game and not session._remote_loading and not is_instance_valid(LoadingScreen._current) and not ShaderCompilationScreen.active()
		done = done and (mode==0 or (rt.stats.get("active",false) and not rt.stats.get("rebuilding",false)))
		stable = stable+1 if done else 0
	return stable>=5

func begin(label: String) -> void:
	sample=label;phase="";last_stage="";watching=true;started=Time.get_ticks_msec()

func finish(sync_ms: int,ok: bool) -> void:
	var rt := game.get_node("SceneRaytrace")
	var row := {"window":str(get_window().size),"terrain_pages_built":game.world.terrain.color_cache.built if is_instance_valid(game.world.terrain.color_cache) else 0,"case":sample,"mode":mode,"fps_cap":fps,"standby":standby,"total_ms":Time.get_ticks_msec()-started,"request_ms":sync_ms,"ok":ok,"map_stats":game.world.map.stats.duplicate(true),"warmup_ms":ShaderWarmup.last_ms,"materials":ShaderWarmup.last_count,"stats":rt.stats.duplicate(true)}
	if game.world.terrain._cliffs != null:
		row["cliff_reused"] = game.world.terrain._cliffs.get("reused") == true
		row["cliff_build_us"] = game.world.terrain._cliffs.build_us
	watching=false;rows.append(row)
	FileAccess.open(out.path_join("measurements.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"events":events,"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	print("LOAD_MEASUREMENT ",JSON.stringify(row))

func run() -> void:
	seed(20261026)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-pt="):mode=int(arg.trim_prefix("--bench-pt="))
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--bench-first-save="):first_save=arg.trim_prefix("--bench-first-save=")
		if arg.begins_with("--bench-zone="):zone=arg.trim_prefix("--bench-zone=")
		if arg=="--bench-standby":standby=true
		if arg.begins_with("--bench-fps="):fps=maxi(0,int(arg.trim_prefix("--bench-fps=")))
		if arg.begins_with("--bench-reloads="):reloads=clampi(int(arg.trim_prefix("--bench-reloads=")),0,20)
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"pt_mode":mode,"pt_accumulation":0,"q_rt_lighting":0,"pt_sharc":0,"pt_restir":0,"pt_refraction":0,"pt_ray_reconstruction":0,"rt_shadows":0,"rt_gi":0,"gfx_water_reflections":2,"autosave":0,"auto_graphics":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"display_mode":0,"vsync":0,"fps_limit":0,"rtx_upscaling":0,"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,"scroll_border":0,"pad_enabled":0},true)
	GameData._apply_window();Gfx.apply_quality(get_viewport());Engine.max_fps=fps
	get_window().size=Vector2i(1280,720)
	for i in 3:await get_tree().process_frame
	TutorialPanel.auto_show=false
	if standby:LocalHost.prepare_standby(get_tree())
	LoadingScreen.on_frame=func(frame:int):
		if watching:events.append({"case":sample,"ms":Time.get_ticks_msec()-started,"loading_frame":frame})
	ShaderCompilationScreen.on_progress=progress
	session=Session.new();get_parent().add_child(session)
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	var ok := true
	if first_save.is_empty():
		begin("initial-zone")
		session._enter_zone(zone,1,false)
	else:
		DirAccess.make_dir_recursive_absolute(SaveInfo.path("loading-probe").get_base_dir())
		ok=DirAccess.copy_absolute(first_save,SaveInfo.path("loading-probe"))==OK
		var info:=first_save.get_basename()+".info.sav"
		if FileAccess.file_exists(info):DirAccess.copy_absolute(info,SaveInfo.path("loading-probe").get_basename()+".info.sav")
		begin("first-save")
		ok=await session.load_game_shown("loading-probe") and ok
	var sync_ms := Time.get_ticks_msec()-started
	ok=await settle() and ok
	finish(sync_ms,ok)
	if not ok:get_tree().quit(2);return
	var save_result := session.save_game("loading-probe")
	print("LOAD_SAVE_RESULT ",save_result)
	for i in reloads:
		await get_tree().create_timer(0.3,true,false,true).timeout
		begin("reload-%d"%i)
		ok=await session.load_game_shown("loading-probe")
		sync_ms=Time.get_ticks_msec()-started
		ok=await settle() and ok
		finish(sync_ms,ok)
		if not ok:break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("loaded.png"))
	# Measure the loaded PT image above; drain the optional renderer before
	# engine shutdown, as in the registered save-load lifetime regression.
	GameData.options.pt_mode=0
	for i in 12:await get_tree().process_frame
	ShaderCompilationScreen.on_progress=Callable()
	LoadingScreen.on_frame=Callable()
	var worker_log := session.local_host._config + ".log"
	if FileAccess.file_exists(worker_log):
		FileAccess.open(out.path_join("worker.log"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(worker_log))
	await session.local_host.stop()
	game.queue_free();session.queue_free()
	for i in 8:await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit(0 if ok else 1)
