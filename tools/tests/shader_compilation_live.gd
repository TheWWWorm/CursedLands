extends Node
## Real campaign/material/temporal preparation. Run in a disposable profile;
## --audit-out selects reports/screenshots. This fixture never fabricates work
## or calls the screen's begin/update/end APIs to simulate compilation.

class DrawProbe extends CompositorEffect:
	var mutex := Mutex.new()
	var draws := 0
	var render_thread := 0
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int, _data: RenderData) -> void:
		mutex.lock()
		draws += 1
		render_thread = OS.get_thread_caller_id()
		mutex.unlock()
	func snapshot() -> Dictionary:
		mutex.lock()
		var result := {"draws":draws, "render_thread":render_thread}
		mutex.unlock()
		return result

class WorldClockProbe extends Node:
	var observer: Node
	var ticks := 0
	func _process(_dt: float) -> void:
		ticks += 1
	func _notification(what: int) -> void:
		if is_instance_valid(observer) and what in [NOTIFICATION_PAUSED, NOTIFICATION_UNPAUSED]:
			observer.call("_pause_changed", what == NOTIFICATION_PAUSED)

var out := "user://shader-compilation-live"
var checks := 0
var failures: Array[String] = []
var progress_rows: Array[Dictionary] = []
var pause_rows: Array[Dictionary] = []
var sdk_rows: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var session: Session
var game: Game
var probe: DrawProbe
var world_probe: WorldClockProbe
var watch := false
var case_name := "setup"
var latest_phase := ""
var posted := 0
var first_draws := {}
var watch_first_draw := false
var material_capture := false
var material_previous_completed := 0
var previous_observer := Callable()
var original_warmup := true
var original_deferred := false
var sdk_tested := false
var fg_tested := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func sdk_status() -> Dictionary:
	var bridge := FsrGraphics.bridge()
	return bridge.call("get_status") if bridge != null else {}


func save_report() -> void:
	var report := {"checks":checks, "failures":failures, "cases":cases,
		"progress":progress_rows, "pause_events":pause_rows, "sdk_phases":sdk_rows,
		"captures":captures, "sdk_tested":sdk_tested, "frame_generation_tested":fg_tested,
		"facts":FsrGraphics.facts(), "final_sdk_status":sdk_status(),
		"main_thread":OS.get_thread_caller_id(), "draw_probe":probe.snapshot() if probe else {},
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"device":RenderingServer.get_video_adapter_name(), "profile":OS.get_user_data_dir(),
		"warmup_cache_note":"The material admission cache is cleared; driver/disk caches are not deleted."}
	var file := FileAccess.open(out.path_join("shader-compilation-live.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")


func capture(label: String, require_cover := false) -> Dictionary:
	# Synchronous GPU readback is intentional. During a forced material batch
	# it captures the last completed draw, not merely queued CanvasItem text.
	var image := get_viewport().get_texture().get_image()
	var row := {"case":case_name, "file":label+".png", "phase":latest_phase,
		"screen_active":ShaderCompilationScreen.active(), "posted":posted,
		"scene_draws":int(probe.snapshot().draws) if probe else 0}
	var valid: bool = image != null and not image.is_empty()
	check(valid, label+": readable rendered image")
	if not valid:
		captures.append(row)
		return row
	row["size"] = [image.get_width(), image.get_height()]
	check(image.save_png(out.path_join(label+".png")) == OK, label+": screenshot saved")
	var edge_error := 0.0
	for p: Vector2 in [Vector2(0.03,0.03), Vector2(0.97,0.03), Vector2(0.03,0.97), Vector2(0.97,0.97)]:
		var c := image.get_pixel(int(p.x*image.get_width()), int(p.y*image.get_height()))
		var b := ShaderCompilationScreen.BACKGROUND
		edge_error = maxf(edge_error, maxf(absf(c.r-b.r), maxf(absf(c.g-b.g), absf(c.b-b.b))))
	var visible_ink := 0
	for y in range(image.get_height()/4, image.get_height()*3/4, 4):
		for x in range(image.get_width()/4, image.get_width()*3/4, 4):
			var c := image.get_pixel(x,y)
			if maxf(c.r, maxf(c.g,c.b)) > 0.25: visible_ink += 1
	row["background_max_error"] = edge_error
	row["visible_text_bar_samples"] = visible_ink
	if require_cover:
		check(edge_error < 0.04 and visible_ink > 25, label+": actual opaque message covers the campaign")
	captures.append(row)
	return row


func on_progress(value: Dictionary) -> void:
	if not watch: return
	var row := value.duplicate(true)
	row["case"] = case_name
	row["scene_draws"] = int(probe.snapshot().draws)
	row["posted_callbacks"] = posted
	row["screen_active"] = ShaderCompilationScreen.active()
	row["paused"] = get_tree().paused
	row["owns_pause"] = ShaderCompilationScreen.owns_pause(get_tree())
	row["saved_pause"] = bool(session.saved_play_clock().paused)
	progress_rows.append(row)
	latest_phase = String(value.phase)
	if case_name == "materials" and latest_phase == ShaderCompilationScreen.MATERIALS:
		var completed := int(value.completed)
		if completed > material_previous_completed and material_previous_completed > 0 \
				and material_previous_completed < int(value.total) and not material_capture:
			material_capture = true
			# Read the preceding batch's presented progress. The first advance
			# has not presented its number yet, regardless of its batch size;
			# a second advance may complete the list while the image is mid-way.
			capture("materials-in-progress", true)
		material_previous_completed = maxi(material_previous_completed, completed)


func _posted() -> void:
	posted += 1


func _pre_draw() -> void:
	if watch and watch_first_draw and not get_tree().root.disable_3d:
		first_draws[case_name] = {"screen_active":ShaderCompilationScreen.active(),
			"scene_draws_before":int(probe.snapshot().draws), "posted":posted}
		watch_first_draw = false


func _pause_changed(paused: bool) -> void:
	if not watch or not is_instance_valid(session): return
	pause_rows.append({"case":case_name, "paused":paused,
		"owns_pause":ShaderCompilationScreen.owns_pause(get_tree()),
		"saved_pause":bool(session.saved_play_clock().paused),
		"world_ticks":world_probe.ticks if world_probe else 0})


func wait_clear(label: String, limit_ms := 30_000, sdk_before: Dictionary = {}, require_fg := false) -> Dictionary:
	var started := Time.get_ticks_msec()
	var first_posted := posted
	var owned_frames := 0
	var clock_stable := true
	var saved_clock_valid := true
	var pause_started := false
	var held_ticks := 0
	var held_time := 0.0
	var covered_frames := 0
	var early_clear := false
	var last_sdk_phase := ""
	var initializations := 0
	var last_status: Dictionary = sdk_status()
	while ShaderCompilationScreen.active() and Time.get_ticks_msec()-started < limit_ms:
		await frames()
		if ShaderCompilationScreen.owns_pause(get_tree()):
			owned_frames += 1
			if not pause_started:
				pause_started = true
				held_ticks = world_probe.ticks
				held_time = session.state.world_time
			clock_stable = clock_stable and world_probe.ticks == held_ticks and is_equal_approx(session.state.world_time, held_time)
			saved_clock_valid = saved_clock_valid and get_tree().paused and not game.world.can_process() \
				and not bool(session.saved_play_clock().paused)
		if ShaderCompilationScreen.active(): covered_frames += 1
		if not sdk_before.is_empty():
			last_status = sdk_status()
			var initializing: bool = last_status.get("temporal_shaders_initializing",false) \
				or last_status.get("upscaler_initializing",false) or last_status.get("frame_generation_initializing",false)
			if initializing: initializations += 1
			var phase := "%s/%s/%s/%s/%s" % [last_status.get("temporal_shaders_initializing",false),
				last_status.get("upscaler_initializing",false), last_status.get("frame_generation_initializing",false),
				last_status.get("upscaler_provider",""), last_status.get("frame_generation_provider","")]
			if phase != last_sdk_phase:
				last_sdk_phase = phase
				sdk_rows.append({"case":label,"elapsed_ms":Time.get_ticks_msec()-started,
					"screen_active":ShaderCompilationScreen.active(),"posted":posted,"status":last_status.duplicate(true)})
				if ShaderCompilationScreen.active(): capture(label+"-phase-%02d"%sdk_rows.size(), true)
				print("SHADER_COMPILATION_SDK_PHASE ", JSON.stringify(sdk_rows.back()))
				if sdk_rows.size()%2 == 1: save_report()
			if not ShaderCompilationScreen.active():
				early_clear = int(last_status.get("upscale_evaluations",0)) <= int(sdk_before.get("upscale_evaluations",0)) \
					or (require_fg and int(last_status.get("frame_generation_dispatches",0)) <= int(sdk_before.get("frame_generation_dispatches",0)))
	var row := {"case":label,"wait_ms":Time.get_ticks_msec()-started,
		"cleared":not ShaderCompilationScreen.active(),"posted_frames":posted-first_posted,
		"owned_pause_frames":owned_frames,"covered_frames":covered_frames,
		"world_clock_stable":clock_stable,"saved_clock_valid":saved_clock_valid,
		"initializing_frames":initializations,"premature_clear":early_clear,
		"sdk_before":sdk_before,"sdk_after":last_status}
	cases.append(row)
	check(bool(row.cleared), label+": preparation cover removes within the deadline")
	check(clock_stable and saved_clock_valid, label+": owned pause freezes world updates without changing saved gameplay pause")
	if not sdk_before.is_empty():
		var minimum_presentations := 2147483647
		var maximum_presentations := 0
		for event: Dictionary in progress_rows:
			if event["case"] != label: continue
			minimum_presentations = mini(minimum_presentations, int(event.presentations))
			maximum_presentations = maxi(maximum_presentations, int(event.presentations))
		row["screen_presentation_span"] = maxi(0,maximum_presentations-minimum_presentations)
		check(not early_clear and int(last_status.get("upscale_evaluations",0)) > int(sdk_before.get("upscale_evaluations",0)),
			label+": cover remains until genuine SDK upscaling evaluations advance")
		check(int(last_status.get("last_error",-1)) == 0 and String(last_status.get("upscaler_provider","")).begins_with("3.1."),
			label+": actual FSR 3.1 provider succeeds")
		check(covered_frames >= 2 and posted-first_posted >= 3 and int(row.screen_presentation_span) >= 2,
			label+": actual screen presentations advance through SDK preparation")
		if require_fg:
			check(int(last_status.get("frame_generation_dispatches",0)) > int(sdk_before.get("frame_generation_dispatches",0)),
				label+": ordinary campaign gate permits actual frame-generation dispatches under the owned pause")
	save_report()
	return row


func setup() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	original_warmup = ShaderWarmup.enabled
	original_deferred = LoadingScreen.force_deferred
	ShaderWarmup.enabled = false
	LoadingScreen.force_deferred = false
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":0,
		"render_scale":4,"vsync":0,"fps_limit":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"autosave":0,"show_tutorial":0,
		"net_upnp":0,"net_lan":0,"net_directory":0,"unit_fog":0,"control_mode":0,
		"pad_enabled":0,"scroll_border":0,"gfx_water":1,"gfx_sky":1,"gfx_water_reflections":0,
		"rt_gi":0,"rt_shadows":0,"pt_mode":0,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = maxi(0,GameData.resolutions().find(Vector2i(1280,720)))
	GameData._apply_audio()
	GameData._apply_window()
	get_tree().root.borderless = true
	get_tree().root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PadInput.active = "kbm"
	TouchInput.enabled = false
	session = Session.new()
	add_child(session)
	game = Game.new()
	game.session = session
	session.game = game
	add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	var zone: Dictionary = session.campaign.zone_by_map("zone3obr")
	session._enter_zone(zone.id,1,false)
	session.state.world_time = 12.0
	session.world.vm.instances.clear()
	game.hud._dialog.hide()
	game.rig.release()
	game.rig.set_process(false)
	game.direct.set_process(false)
	game.rig.camera.make_current()
	probe = DrawProbe.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [probe]
	game.rig.camera.compositor = compositor
	world_probe = WorldClockProbe.new()
	world_probe.observer = self
	world_probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.world.add_child(world_probe)
	await frames(12)
	get_tree().root.grab_focus()
	check(game.world != null and game.hud != null and int(probe.snapshot().draws) > 0, "real campaign renders through the production camera")
	check(not get_tree().paused and game.world.can_process() and world_probe.ticks > 0, "campaign simulation is initially unpaused")
	check(LoadingScreen._current == null and not ShaderCompilationScreen.active(), "initial campaign loading completes before measurement")
	previous_observer = ShaderCompilationScreen.on_progress
	ShaderCompilationScreen.on_progress = on_progress
	RenderingServer.frame_post_draw.connect(_posted)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	watch = true


func run_materials() -> void:
	case_name = "materials"
	material_previous_completed = 0
	var before_draws := int(probe.snapshot().draws)
	ShaderWarmup.enabled = true
	ShaderWarmup._warmed.clear()
	check(ShaderWarmup.active(), "real material warmup is enabled, including command-line admission")
	LoadingScreen.begin(get_tree(), session.campaign.zone(session.zone_id))
	ShaderWarmup.run(game)
	check(ShaderCompilationScreen.active(), "material cover survives the synchronous preparation call")
	capture("materials-completed", true)
	var advances := 0
	var previous_count := 0
	var previous_draws := before_draws
	var total := 0
	var ordered := true
	var covered := true
	var batch := ShaderWarmup.FORWARD_BATCH if RenderingServer.get_current_rendering_method() == "forward_plus" else ShaderWarmup.BATCH
	for row: Dictionary in progress_rows:
		if row["case"] != case_name or row.phase != ShaderCompilationScreen.MATERIALS: continue
		var completed := int(row.completed)
		if completed <= previous_count: continue
		advances += 1
		ordered = ordered and int(row.scene_draws) > previous_draws and completed-previous_count <= batch
		covered = covered and bool(row.screen_active)
		previous_count = completed
		previous_draws = int(row.scene_draws)
		total = int(row.total)
	check(advances > 1 and total > batch and material_capture, "multiple real material batches produce intermediate progress")
	check(ordered and covered, "each completed-material advance follows a completed scene draw under the cover")
	check(total > 0 and previous_count == total and ShaderWarmup.last_count == total, "material progress completes the actual warmup list")
	LoadingScreen.end()
	await wait_clear("materials")
	await frames(3)
	check(not get_tree().paused and not bool(session.saved_play_clock().paused), "material completion restores gameplay and saved clock")


func run_sdk() -> void:
	var facts := FsrGraphics.facts()
	if not facts.api or not facts.sr3:
		cases.append({"case":"fsr31","skipped":"Actual Windows SDK FSR 3.1 is unavailable on this backend."})
		return
	sdk_tested = true
	case_name = "fsr31"
	var before := sdk_status()
	GameData.set_options({"q_aa":0,"fsr_upscaling":1,"fsr_quality":3,"fsr_frame_generation":0})
	capture("fsr31-pre-presented", true)
	var row := await wait_clear(case_name, 180_000, before)
	check(int(row.owned_pause_frames) > 0, "SDK preparation owns an actual single-player pause")
	await frames(3)
	check(not get_tree().paused and not bool(session.saved_play_clock().paused), "SDK preparation restores gameplay and saved clock")
	var gate := FsrGraphics.campaign_gate(get_tree(), game.rig.camera)
	if not facts.fg3 or not bool(gate.allowed) or not get_tree().root.has_focus():
		cases.append({"case":"fsr31-fg","skipped":"Normal campaign/focus/SDK gate does not allow frame generation.","gate":gate})
		return
	fg_tested = true
	case_name = "fsr31-fg"
	before = sdk_status()
	GameData.set_options({"fsr_frame_generation":1})
	capture("fsr31-fg-pre-presented", true)
	await wait_clear(case_name, 180_000, before, true)
	await frames(3)
	check(not get_tree().paused and not bool(session.saved_play_clock().paused), "frame-generation preparation restores the prior clock")


func run_native_temporal() -> void:
	case_name = "fsr2"
	var before := int(probe.snapshot().draws)
	watch_first_draw = true
	GameData.set_options({"q_aa":5,"fsr_upscaling":0,"fsr_frame_generation":0})
	check(int(probe.snapshot().draws) == before, "q_aa=5 applies only after a canvas-only presentation, before the next 3D draw")
	check(ShaderCompilationScreen.active(), "q_aa=5 retains the preparation cover after applying settings")
	capture("fsr2-pre-presented", true)
	await wait_clear(case_name, 180_000)
	check(first_draws.has(case_name) and bool(first_draws[case_name].screen_active), "the first q_aa=5 3D draw begins under the opaque cover")
	check(int(probe.snapshot().draws) > before and get_tree().root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2,
		"real campaign frames use native FSR2 after preparation")
	await frames(3)
	check(not get_tree().paused and not bool(session.saved_play_clock().paused), "native temporal preparation restores gameplay and saved clock")
	capture("fsr2-ready")
	# Actual graphics change while already paused must preserve the player's
	# clock rather than turning a preexisting pause into a screen-owned pause.
	case_name = "player-paused"
	get_tree().paused = true
	GameData.set_options({"q_aa":0})
	await wait_clear(case_name)
	check(get_tree().paused and bool(session.saved_play_clock().paused), "actual graphics preparation preserves preexisting player pause")
	get_tree().paused = false
	await frames(3)


func run_terrain() -> void:
	case_name = "terrain-settings"
	GameData.set_options({"gfx_terrain":1,"gfx_grass":1,"gfx_biome_cover":1})
	check(ShaderCompilationScreen.active() and ShaderCompilationScreen.terrain_pending(game.world.terrain),
		"explicit terrain and vegetation settings retain a preparation owner")
	capture("terrain-pre-presented", true)
	await wait_clear(case_name)
	var details := game.world.terrain.details
	check(is_instance_valid(details) and not details._wanted_chunks.is_empty() and details._queue.is_empty() \
		and details._grass_jobs.is_empty() and details._wanted_chunks.keys().all(func(key): return details._chunks.has(key)),
		"requested visible vegetation jobs are installed before the cover retires")
	check(progress_rows.any(func(row: Dictionary) -> bool: return row["case"]==case_name and row.phase==ShaderCompilationScreen.TERRAIN),
		"actual terrain work reports its localized preparation phase")
	check(not ShaderCompilationScreen.terrain_pending(game.world.terrain), "completed terrain request releases its bounded work")
	await frames(3)


func run() -> void:
	await setup()
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		check(false, "live compilation qualification requires an actual Forward+ renderer")
	else:
		await run_materials()
		# Keep SDK first: native FSR2 would otherwise warm the shared advanced
		# shader group before the SDK's cold initialization is observed.
		await run_sdk()
		await run_native_temporal()
		await run_terrain()
	check(pause_rows.any(func(row: Dictionary) -> bool: return row.paused and row.owns_pause and not row.saved_pause),
		"real screen-owned pause notifications preserve the saved gameplay clock")
	watch = false
	ShaderCompilationScreen.on_progress = previous_observer
	if RenderingServer.frame_post_draw.is_connected(_posted): RenderingServer.frame_post_draw.disconnect(_posted)
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw): RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	ShaderWarmup.enabled = original_warmup
	LoadingScreen.force_deferred = original_deferred
	GameData.options.fsr_upscaling = 0
	GameData.options.fsr_frame_generation = 0
	GameData.options.q_aa = 0
	GameData._apply_window()
	get_tree().paused = false
	save_report()
	game.rig.camera.compositor = null
	game.queue_free()
	session.queue_free()
	await frames(16)
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	print("SHADER_COMPILATION_LIVE ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
