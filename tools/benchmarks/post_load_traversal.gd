extends Node
## Measure delivered frame intervals from the first uncovered frame. No hidden
## settling interval, disabled simulation, renderer timing queries or readbacks
## in the measured phases. Use the same save/settings/GPU for both builds.
var session: Session
var game: Game
var hero: GameUnit
var config := {"save":"", "pt":1, "width":1920, "height":1080, "leg_seconds":12.0, "pan_seconds":20.0}
var out := "user://post-load-traversal"
var phase := ""
var rows: Array[Dictionary] = []
var loads: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var recording := false
var previous := 0
var revealed := false
var reveal_us := 0
var pressed_key := 0
var initial_pos := Vector2.ZERO
var route := Vector2.INF
var failure := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	run.call_deferred()

func covered() -> bool:
	return session.loading_game or session._remote_loading or is_instance_valid(LoadingScreen._current) or ShaderCompilationScreen.active()

func pipelines() -> Array:
	return [Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)]

func state() -> Dictionary:
	var rt := game.get_node("SceneRaytrace")
	var cache := game.world.terrain.color_cache
	return {"pipelines":pipelines(), "terrain_pages_built":cache.built if is_instance_valid(cache) else 0,
		"terrain_jobs":cache._jobs.size() if is_instance_valid(cache) else 0,
		"pt_active":rt.stats.get("active",false), "pt_rebuilding":rt.stats.get("rebuilding",false),
		"pt_pending_stage":rt._pending_stage, "camera":str(game.rig.camera.global_position),
		"hero":str(hero.pos) if is_instance_valid(hero) else "", "paused":get_tree().paused,
		"hero_hp":hero.hp if is_instance_valid(hero) else -1, "hero_dead":hero.dead if is_instance_valid(hero) else false}

func _process(_dt: float) -> void:
	if is_instance_valid(game) and game.rig: game.rig._window_focused = true
	if not recording or not is_instance_valid(game.world): return
	var now := Time.get_ticks_usec()
	var mask := covered()
	if not revealed:
		if mask: return
		revealed = true; reveal_us = now; previous = now
		loads.back()["at_reveal"] = state()
		return
	var ms := (now-previous)/1000.0; previous = now
	var row := {"phase":phase, "at_s":(now-reveal_us)/1000000.0, "ms":ms, "covered":mask,
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0}
	if ms > 50.0 or mask: row["state"] = state()
	samples.append(row)

func key(action: String) -> void:
	var code := 0
	EIKeymap._tables()
	for scan: int in EIKeymap._active_map():
		if EIKeymap._active_map()[scan] == action: code = int(EIKeymap._code_of.get(scan,0)); break
	if code == pressed_key: return
	for pair in [[pressed_key,false],[code,true]]:
		if not pair[0]: continue
		var event := InputEventKey.new()
		event.keycode = pair[0]; event.physical_keycode = pair[0]; event.pressed = pair[1]
		Input.parse_input_event(event)
	pressed_key = code

func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"frames":0}
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0; var over50 := 0; var over100 := 0
	for v: float in values:
		total += v; over50 += int(v > 50.0); over100 += int(v > 100.0)
	return {"frames":values.size(), "mean_ms":total/values.size(), "p95_ms":sorted[int(sorted.size()*.95)],
		"p99_ms":sorted[int(sorted.size()*.99)], "max_ms":sorted.back(), "over_50ms":over50, "over_100ms":over100}

func move(destination: Vector2) -> void:
	game.issue({"t":"move", "units":[hero.uid], "x":destination.x, "y":destination.y, "run":true})

func choose_route() -> void:
	initial_pos = hero.pos; route = Vector2.INF
	for distance: float in [45.0,30.0,20.0,12.0]:
		for angle in 24:
			var point := initial_pos + Vector2.from_angle(float(angle)*TAU/24.0)*distance
			if session.world.nav.direct_line(hero,point): route = point; return

func measure(label: String, seconds: float, pan := false) -> void:
	phase = label
	var before := state(); var origin := hero.pos; var world_time := game.world.time
	var low := game.rig.camera.global_position; var high := low
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec()-start < int(seconds*1000000.0):
		if pan:
			var t := (Time.get_ticks_usec()-start)/1000000.0
			var actions := ["camera_right","camera_up","camera_left","camera_down"]
			key(actions[mini(int(t/(seconds/4.0)),3)])
		await get_tree().process_frame
		low = low.min(game.rig.camera.global_position); high = high.max(game.rig.camera.global_position)
	key("")
	rows.append({"load":loads.size()-1, "phase":label, "before":before, "after":state(),
		"hero_distance":hero.pos.distance_to(origin), "camera_extent":str(high-low), "simulation_seconds":game.world.time-world_time})
	if hero.dead or game.world.time-world_time < seconds*0.6: failure = "gameplay interrupted during "+label
	if pan and high.distance_to(low) < 15.0: failure = "camera did not traverse during "+label

func save_report() -> void:
	for row: Dictionary in rows:
		var values := samples.filter(func(s): return s.phase == row.phase).map(func(s): return s.ms)
		row["frame_times"] = distribution(values)
	FileAccess.open(out.path_join("traversal.json"),FileAccess.WRITE).store_string(JSON.stringify({"config":config,
		"loads":loads, "rows":rows, "samples":samples, "failure":failure, "options":GameData.options,
		"adapter":RenderingServer.get_video_adapter_name(), "window":str(get_window().size),
		"render_scale":get_viewport().scaling_3d_scale, "frame_limit":Engine.max_fps},"\t")+"\n")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--traversal-config="): config.merge(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--traversal-config="))),true)
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	seed(20261027)
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"pt_mode":int(config.pt),"pt_accumulation":0,"q_rt_lighting":0,"pt_sharc":0,"pt_restir":0,
		"pt_refraction":0,"pt_ray_reconstruction":0,"rt_shadows":0,"rt_gi":0,"gfx_water_reflections":2,
		"autosave":0,"auto_graphics":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"display_mode":0,"vsync":0,"fps_limit":0,"rtx_upscaling":0,"rtx_frame_generation":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"scroll_border":0,"pad_enabled":0,"control_mode":0},true)
	GameData._apply_window(); GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(config.width,config.height)
	Gfx.apply_quality(get_viewport()); Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	TutorialPanel.auto_show = false
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	DirAccess.copy_absolute(config.save,SaveInfo.path("post-load-traversal"))
	session = Session.new(); get_parent().add_child(session)
	game = Game.new(); game.session = session; session.game = game; get_parent().add_child(game)
	for cycle in 2:
		recording = true; revealed = false; phase = "%d-release" % cycle
		var started := Time.get_ticks_usec()
		loads.append({"cycle":cycle, "started":started})
		if not await session.load_game_shown("post-load-traversal"):
			failure = "save load failed"; break
		while not revealed and Time.get_ticks_usec()-started < 180000000: await get_tree().process_frame
		if not revealed: failure = "loading cover failed to close"; break
		loads.back()["load_ms"] = (reveal_us-started)/1000.0
		var party := session.party_units(0)
		if party.is_empty(): failure = "no party"; break
		hero = party[0]; game.selected.assign([hero]); game.rig.held = false
		game.rig.follow(hero); game.rig._window_focused = true
		choose_route()
		if route == Vector2.INF: failure = "no traversable route"; break
		loads.back()["route"] = [str(initial_pos),str(route)]
		game.issue({"t":"aggression", "units":[hero.uid], "on":false})
		move(route)
		await measure("%d-first-traversal" % cycle, float(config.leg_seconds))
		move(initial_pos)
		await measure("%d-return-traversal" % cycle, float(config.leg_seconds))
		game.issue({"t":"stop", "units":[hero.uid]})
		game.rig._free = true
		await measure("%d-first-pan" % cycle, float(config.pan_seconds), true)
		if cycle == 0: await measure("%d-repeat-pan" % cycle, float(config.pan_seconds), true)
		recording = false
		save_report()
		print("POST_LOAD_TRAVERSAL ",cycle," ",JSON.stringify(loads.back()))
	key(""); recording = false; save_report()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("traversed.png"))
	GameData.options.pt_mode = 0
	for i in 12: await get_tree().process_frame
	await session.local_host.stop()
	game.queue_free(); session.queue_free()
	for i in 8: await get_tree().process_frame
	TexUpscale.shutdown(); print("POST_LOAD_TRAVERSAL_DONE ",failure); get_tree().quit(int(not failure.is_empty()))
