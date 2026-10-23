extends Node
## Real arena SubViewport preparation and cancellation. Use an isolated muted
## profile and --audit-out. Inline authority keeps this shader test local; the
## ordinary ArenaPveField and its animation/picking/bell gates are unchanged.

class InlineArena extends ArenaPveScreen:
	func _create_boards() -> ArenaTournamentBattles:
		return ArenaTournamentBattles.new()

class DrawProbe extends CompositorEffect:
	var mutex := Mutex.new()
	var draws := 0
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int, _data: RenderData) -> void:
		mutex.lock()
		draws += 1
		mutex.unlock()
	func count() -> int:
		mutex.lock()
		var result := draws
		mutex.unlock()
		return result

var out := "user://shader-compilation-arena"
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var screen: InlineArena
var probe: DrawProbe
var latest := {}
var watching := false
var case_name := "normal"
var first_capture := false
var middle_capture := false
var final_capture := false
var ready_under_cover := 0
var original_warmup := true
var previous_observer := Callable()
var ordering_violations: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		# The qualification runner stops on FAIL. Preserve the actual counters
		# before printing so an ordering regression retains its evidence.
		save_report()
	print("PASS " if ok else "FAIL ", label)


func save_report() -> void:
	var report := {"checks":checks,"failures":failures,"progress":rows,"captures":captures,
		"ready_under_cover":ready_under_cover,"scene_draws":probe.count() if probe else 0,
		"ordering_violations":ordering_violations,
		"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name()}
	FileAccess.open(out.path_join("shader-compilation-arena.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")


func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _progress(value: Dictionary) -> void:
	if not watching or probe == null: return
	latest = value.duplicate(true)
	latest["case"] = case_name
	latest["scene_draws"] = probe.count()
	latest["warming"] = is_instance_valid(screen) and screen.field._warming
	latest["screen_active"] = ShaderCompilationScreen.active()
	latest["viewport_mode"] = int(screen.field.view.render_target_update_mode) if is_instance_valid(screen) else -1
	rows.append(latest.duplicate(true))


func capture(label: String) -> void:
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), label+": rendered image is readable")
	if image == null or image.is_empty(): return
	check(image.save_png(out.path_join(label+".png")) == OK, label+": screenshot saved")
	var error := 0.0
	for point: Vector2 in [Vector2(0.03,0.03),Vector2(0.97,0.03),Vector2(0.03,0.97),Vector2(0.97,0.97)]:
		var color := image.get_pixel(int(point.x*image.get_width()),int(point.y*image.get_height()))
		var backdrop := ShaderCompilationScreen.BACKGROUND
		error = maxf(error,maxf(absf(color.r-backdrop.r),maxf(absf(color.g-backdrop.g),absf(color.b-backdrop.b))))
	var ink := 0
	for y in range(image.get_height()/4,image.get_height()*3/4,4):
		for x in range(image.get_width()/4,image.get_width()*3/4,4):
			var color := image.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) > 0.25: ink += 1
	check(error < 0.04 and ink > 25, label+": actual preparation message is opaque and legible")
	captures.append({"file":label+".png","background_max_error":error,"text_bar_samples":ink,
		"scene_draws":probe.count(),"progress":latest.duplicate(true)})


func _posted() -> void:
	if not watching or not is_instance_valid(screen) or probe == null or not ShaderCompilationScreen.displayed(): return
	if not screen.field._warming: ready_under_cover += 1
	if case_name != "normal" or latest.is_empty(): return
	if not first_capture:
		first_capture = true
		check(int(latest.get("elapsed_ms",0)) >= ShaderCompilationScreen.SHOW_DELAY_MS,
			"long preparation shows progress only after the shared quiet window")
		capture("arena-before-first-draw")
	elif not middle_capture and int(latest.get("completed",0)) > 0 \
			and int(latest.get("completed",0)) < int(latest.get("total",0)):
		middle_capture = true
		capture("arena-materials-in-progress")
	elif not final_capture and int(latest.get("total",0)) > 0 \
			and int(latest.get("completed",0)) == int(latest.get("total",0)):
		final_capture = true
		capture("arena-materials-completed")


func wait_ready(deadline_ms := 180_000) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < deadline_ms:
		await frames()
		if not is_instance_valid(screen): return false
		if not screen.field._warming and not ShaderCompilationScreen.active(): return true
	return false


func setup() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	original_warmup = ShaderWarmup.enabled
	ShaderWarmup.enabled = true
	ShaderWarmup._warmed.clear()
	GameData.arena_mode = 0
	GameData.arena_speed = 1
	GameData.options.merge(GfxPresets.values(GfxPresets.ORIGINAL),true)
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"q_aa":0,"q_shadows":0,
		"render_scale":4,"vsync":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,
		"volume_stream":0,"volume_voice":0,"autosave":0,"show_tutorial":0,
		"net_lan":0,"net_upnp":0,"net_directory":0,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	GameData._apply_audio()
	GameData._apply_window()
	get_tree().root.borderless = true
	get_tree().root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(3)
	previous_observer = ShaderCompilationScreen.on_progress
	ShaderCompilationScreen.on_progress = _progress
	RenderingServer.frame_post_draw.connect(_posted)
	screen = InlineArena.new()
	add_child(screen)
	screen.run.auto_save = false
	probe = DrawProbe.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [probe]
	screen.field.camera.compositor = compositor
	watching = true


func run() -> void:
	await setup()
	check(ShaderWarmup.active(), "real arena shader warmup is enabled")
	check(not screen.field.prepare_battle_presentation(), "the ordinary battle gate waits for initial shader preparation")
	check(await wait_ready(), "arena preparation and final settling finish")
	check(first_capture and middle_capture and final_capture, "actual initial, intermediate and completed progress frames are captured")
	var count := 0
	var previous_draws := 0
	var completed := 0
	var total := 0
	var ordered := true
	var viewport_live := true
	var gated := true
	for row: Dictionary in rows:
		if row["case"] != "normal" or row.phase != ShaderCompilationScreen.MATERIALS or int(row.completed) <= completed: continue
		count += 1
		if int(row.scene_draws) <= previous_draws or (completed > 0 and int(row.completed) != completed+1) \
				or int(row.viewport_mode) != SubViewport.UPDATE_ALWAYS:
			ordering_violations.append({"previous_draws":previous_draws,"previous_completed":completed,"progress":row})
		ordered = ordered and int(row.scene_draws) > previous_draws and (completed == 0 or int(row.completed) == completed+1)
		viewport_live = viewport_live and int(row.viewport_mode) == SubViewport.UPDATE_ALWAYS
		gated = gated and bool(row.warming) and bool(row.screen_active)
		previous_draws = int(row.scene_draws)
		completed = int(row.completed)
		total = int(row.total)
	check(count > 1 and completed == total, "all actual arena materials reach the completed denominator")
	check(ordered and viewport_live, "every material completion follows a real SubViewport draw beneath the cover")
	check(gated and ready_under_cover == 0, "the shared battle gate remains closed through progress and final settling")
	check(screen.field.view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the original arena viewport update mode is restored")
	check(is_zero_approx(screen.battle.world.time), "shader preparation does not start combat")
	check(screen.field.prepare_battle_presentation() == ArenaAnimationWarmup.picking_ready(),
		"shader completion preserves the original animation picking readiness gate")
	case_name = "cached"
	var before := rows.size()
	screen.field._warm_round = ""
	check(not screen.field.prepare_battle_presentation(), "next fight checks readiness through the ordinary gate")
	check(await wait_ready(), "cached fight becomes ready")
	check(rows.size() == before and not ShaderCompilationScreen.displayed(), "cached Start Fight never shows shader progress with FSR off")
	# Cancel real work after a completed batch, then remove the actual arena.
	# The exit signal must release its unique hold even if its waiter retires.
	case_name = "cancel"
	ShaderWarmup._warmed.clear()
	screen.field._warm_round = ""
	check(not screen.field.prepare_battle_presentation(), "a fresh arena preparation starts through the normal gate")
	var started := Time.get_ticks_msec()
	var partial := false
	while Time.get_ticks_msec()-started < 60_000:
		await frames()
		var progress := ShaderCompilationScreen._current
		partial = is_instance_valid(progress) and progress._completed > 0 and progress._completed < progress._total
		if partial: break
	check(partial and ShaderCompilationScreen.active(), "cancellation interrupts genuine unfinished material preparation")
	screen.queue_free()
	await frames(16)
	check(not is_instance_valid(screen), "the cancelled arena leaves the scene tree")
	check(not ShaderCompilationScreen.active(), "arena exit releases the preparation owner and cover")
	watching = false
	ShaderCompilationScreen.on_progress = previous_observer
	RenderingServer.frame_post_draw.disconnect(_posted)
	ShaderWarmup.enabled = original_warmup
	save_report()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	print("SHADER_COMPILATION_ARENA ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
