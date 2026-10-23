extends "res://tools/tests/water_raytrace_artifact.gd"
## Actual campaign water preparation. Run in a disposable muted profile with
## --audit-out. Render counters observe real Mirror draws and RT submissions;
## the one injected snapshot failure is reported separately from GPU success.

const Reflection = preload("res://src/game/fx/water_reflection.gd")
const RayDevice = preload("res://src/game/fx/water_raytrace_device.gd")

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
		var value := draws
		mutex.unlock()
		return value

var manual := false
var watching := false
var case_name := "setup"
var scene_probe: DrawProbe
var mirror_probe: DrawProbe
var probe_camera := 0
var connected_device := 0
var progress: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var acknowledgements: Array[Dictionary] = []
var screenshots: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var previously_held := false
var previous_observer := Callable()
var original_warmup := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func reflector() -> Reflection:
	return t._reflection if is_instance_valid(t) and is_instance_valid(t._reflection) else null


func held() -> bool:
	var reflection := reflector()
	return reflection != null and ShaderCompilationScreen.active() \
		and ShaderCompilationScreen._current._owners.has(reflection._preparation_owner)


func _step() -> void:
	var reflection := reflector()
	if reflection == null: return
	reflection.set_process(false)
	reflection._process(1.0/60.0)
	if reflection.camera != null and reflection.camera.get_instance_id() != probe_camera:
		probe_camera = reflection.camera.get_instance_id()
		mirror_probe = DrawProbe.new()
		var compositor := Compositor.new()
		compositor.compositor_effects = [mirror_probe]
		reflection.camera.compositor = compositor
	if reflection._rt != null and reflection._rt.get_instance_id() != connected_device:
		connected_device = reflection._rt.get_instance_id()
		reflection._rt.rendered.connect(_acknowledged.bind(connected_device))


func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		if manual: _step()
		await RenderingServer.frame_post_draw


func snapshot() -> Dictionary:
	var reflection := reflector()
	return {"case":case_name, "time_ms":Time.get_ticks_msec(), "screen_active":ShaderCompilationScreen.active(),
		"water_owner":held(), "scene_draws":scene_probe.count() if scene_probe else 0,
		"reflection_draws":mirror_probe.count() if mirror_probe else 0,
		"serial":reflection._preparation_serial if reflection else -1,
		"device_id":reflection._rt.get_instance_id() if reflection and reflection._rt else 0,
		"completed_renders":reflection._rt.completed_renders if reflection and reflection._rt else 0,
		"stats":reflection.rt_stats.duplicate(true) if reflection else {}}


func _progress(value: Dictionary) -> void:
	if not watching: return
	var row := snapshot()
	row.merge(value, true)
	progress.append(row)
	if previously_held and not bool(row.water_owner): releases.append(row.duplicate(true))
	previously_held = bool(row.water_owner)


func _acknowledged(serial: int, ok: bool, device_id: int) -> void:
	var row := snapshot()
	row.merge({"ack_serial":serial, "ok":ok, "ack_device_id":device_id}, true)
	acknowledgements.append(row)


func begin_case(label: String) -> Dictionary:
	case_name = label
	previously_held = held()
	var start := snapshot()
	cases.append({"case":label,"start":start})
	return start


func cover_capture(label: String, draws_before: int) -> void:
	check(ShaderCompilationScreen.active(), label+": preparation cover is active before 3D work")
	check(scene_probe.count() == draws_before, label+": presenting the cover did not draw the campaign")
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), label+": completed canvas draw is readable")
	if image == null or image.is_empty(): return
	check(image.save_png(out.path_join(label+".png")) == OK, label+": screenshot saved")
	var error := 0.0
	for point: Vector2 in [Vector2(0.03,0.03),Vector2(0.97,0.03),Vector2(0.03,0.97),Vector2(0.97,0.97)]:
		var color := image.get_pixel(int(point.x*image.get_width()),int(point.y*image.get_height()))
		var background := ShaderCompilationScreen.BACKGROUND
		error = maxf(error,maxf(absf(color.r-background.r),maxf(absf(color.g-background.g),absf(color.b-background.b))))
	var ink := 0
	for y in range(image.get_height()/4,image.get_height()*3/4,4):
		for x in range(image.get_width()/4,image.get_width()*3/4,4):
			var color := image.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) > 0.25: ink += 1
	check(error < 0.04 and ink > 25, label+": actual message is opaque and legible")
	screenshots.append({"file":label+".png","background_max_error":error,"text_bar_samples":ink,"state":snapshot()})


func wait_finished(require_rt := false, deadline_ms := 180_000) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < deadline_ms:
		await frames()
		var reflection := reflector()
		if require_rt and (reflection == null or reflection._rt_failed): return false
		var ready: bool = not require_rt or (reflection._rt_ready and reflection.rt_stats.get("active",false) \
			and reflection._rt != null and reflection._rt.completed_renders > 0)
		if ready and not held() and not ShaderCompilationScreen.active(): return true
	return false


func assert_mirror_release(label: String, initial_draws: int) -> void:
	var matched := false
	for row: Dictionary in releases:
		if row["case"] == label:
			matched = int(row.reflection_draws) > initial_draws
			break
	check(matched, label+": water owner ends only after a real reflected 3D draw")


func assert_rt_release(label: String, initial_renders: int) -> void:
	var matched := false
	for row: Dictionary in acknowledgements:
		if row["case"] == label and bool(row.ok):
			matched = int(row.ack_serial) == int(row.serial) and int(row.ack_device_id) == int(row.device_id) \
				and int(row.completed_renders) > initial_renders and not bool(row.water_owner)
			break
	check(matched, label+": matching device and request acknowledge newly rendered RT output")


func image_has_geometry(texture: Texture2D) -> bool:
	var image := texture.get_image()
	if image == null or image.is_empty(): return false
	var hits := 0
	for y in range(0,image.get_height(),8):
		for x in range(0,image.get_width(),8):
			if image.get_pixel(x,y).a > 0.1: hits += 1
	return hits > 50


func apply_mode(mode: int) -> void:
	GameData.options.gfx_water_reflections = mode
	t.apply_gfx()
	if reflector(): reflector().set_process(false)


func choose_recenter(initial: Transform3D) -> bool:
	var target := initial.origin-initial.basis.z*18.0
	for i in 16:
		camera.global_position = initial.origin+Vector3(cos(i*TAU/16),0,sin(i*TAU/16))*18.0
		camera.look_at(target)
		var level: float = reflector()._select_plane(camera)
		if is_finite(level) and camera.global_position.y > level+0.15: return true
	camera.global_transform = initial
	return false


func choose_other_plane(previous: float) -> bool:
	var initial := camera.global_transform
	var width := t.sectors_x*EITerrain.SECTOR
	var candidates := []
	for y in range(0,t.sectors_y*EITerrain.SECTOR,8):
		for x in range(0,width,8):
			var level := t.water[y*width+x]
			if not is_finite(level) or absf(level-previous) <= 0.5 or t.liquid_ground[y*width+x] in [EITerrain.LAVA,255]: continue
			if t.height_at(x,y) >= level-0.3: continue
			var position := Vector3(x+0.5,level+2.0,-y-0.5)
			candidates.append({"position":position,"distance":position.distance_squared_to(initial.origin)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance < b.distance)
	for candidate: Dictionary in candidates.slice(0,64):
		camera.global_position = candidate.position
		camera.look_at(camera.global_position+Vector3(0,-2,-6))
		var level: float = reflector()._select_plane(camera)
		if is_finite(level) and absf(level-previous) > 0.25: return true
	camera.global_transform = initial
	return false


func run() -> void:
	original_warmup = ShaderWarmup.enabled
	ShaderWarmup.enabled = false
	GameData.options.merge({"fsr_upscaling":0,"fsr_frame_generation":0,"q_water_rt_quality":0},true)
	var context := await setup()
	manual = true
	scene_probe = DrawProbe.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [scene_probe]
	camera.compositor = compositor
	apply_mode(0)
	check(await wait_finished(), "setup preparation drains before isolated water cases")
	previous_observer = ShaderCompilationScreen.on_progress
	ShaderCompilationScreen.on_progress = _progress
	watching = true
	var initial := camera.global_transform
	begin_case("initial-mirror")
	var before := scene_probe.count()
	apply_mode(2)
	_step()
	cover_capture("initial-mirror", before)
	check(held() and reflector()._preparation_submitted, "initial Mirror retains its owner while waiting for a reflected draw")
	check(await wait_finished(), "initial Mirror preparation and settling finish")
	assert_mirror_release("initial-mirror",0)
	check(image_has_geometry(reflector().viewport.get_texture()), "Mirror acknowledgement corresponds to actual reflected geometry")
	var start := begin_case("mirror-explicit-settings")
	before = scene_probe.count()
	var old_revision: int = GameData.graphics_revision
	GameData.set_options({"q_aniso":0 if GameData.option("q_aniso") != 0 else 1})
	cover_capture("mirror-explicit-settings",before)
	_step()
	check(GameData.graphics_revision > old_revision and held(), "general explicit graphics changes acquire a water preparation owner")
	check(await wait_finished(), "Mirror settings preparation finishes")
	assert_mirror_release("mirror-explicit-settings",int(start.reflection_draws))
	apply_mode(0)
	await frames(4)
	begin_case("initial-rt")
	before = scene_probe.count()
	apply_mode(3)
	_step()
	cover_capture("initial-rt",before)
	check(held(), "initial hardware RT retains the cover while gathering its real scene")
	var rt_ready := await wait_finished(true)
	check(rt_ready, "campaign hardware RT completes actual preparation")
	if rt_ready:
		assert_rt_release("initial-rt",0)
		check(image_has_geometry(reflector()._rt.output), "RT acknowledgement corresponds to real traced scenery")
		start = begin_case("rt-quality-settings")
		before = scene_probe.count()
		GameData.set_options({"q_water_rt_quality":1})
		cover_capture("rt-quality-settings",before)
		_step()
		check(held() and reflector()._preparation_submitted, "quality change waits for its own render despite existing valid output")
		check(await wait_finished(true), "RT quality preparation finishes")
		assert_rt_release("rt-quality-settings",int(start.completed_renders))
		check(reflector()._rt.output.get_size() == Vector2(960,540), "quality request renders the requested larger reflection")
		start = begin_case("ordinary-recenter")
		var recentered := choose_recenter(initial)
		check(recentered, "a real camera move over 16 metres retains visible water")
		if recentered:
			reflector().request_refresh()
			_step()
			check(not held() and not ShaderCompilationScreen.active(), "ordinary recenter starts rebuilding without a modal cover")
			check(await wait_finished(true), "ordinary recenter finishes hardware RT in the background")
			check(int(snapshot().device_id) != int(start.device_id), "recenter actually replaced the hardware scene")
			var modal := false
			for row: Dictionary in progress:
				if row["case"] == "ordinary-recenter" and bool(row.water_owner): modal = true
			check(not modal, "no water preparation owner appears during ordinary camera travel")
		start = begin_case("ordinary-plane-change")
		var previous_plane: float = reflector().plane
		var changed_plane := choose_other_plane(previous_plane)
		check(changed_plane, "original map supplies a second visible water level")
		if changed_plane:
			reflector().request_refresh()
			_step()
			check(absf(reflector().plane-previous_plane) > 0.25 and not held() and not ShaderCompilationScreen.active(),
				"an actual authored water-plane change rebuilds without a modal cover")
			check(await wait_finished(true), "ordinary water-plane replacement completes hardware RT")
			check(int(snapshot().device_id) != int(start.device_id), "the new water plane actually replaces the hardware scene")
			var modal := false
			for row: Dictionary in progress:
				if row["case"] == "ordinary-plane-change" and bool(row.water_owner): modal = true
			check(not modal, "no preparation owner appears during the pool transition")
	# These are real lifecycle paths. The snapshot error is deliberately
	# injected after a real gather begins; it is not counted as rendered work.
	apply_mode(0)
	await frames(4)
	camera.global_transform = initial
	begin_case("snapshot-fallback-injected")
	apply_mode(3)
	_step()
	var gathering := reflector()._rt_scene != null
	check(gathering and held(), "fallback injection starts with genuine unfinished scene preparation")
	if gathering:
		reflector()._rt_scene.failed = true
		_step()
		check(reflector()._rt_failed and not held(), "failed snapshot releases its preparation owner")
		check(await wait_finished(), "snapshot fallback removes the cover")
		check(t._water_mat.get_shader_parameter("planar_texture") == reflector().viewport.get_texture(), "snapshot failure retains the planar fallback")
	apply_mode(0)
	await frames(4)
	begin_case("no-water")
	camera.global_position = Vector3(-1000,10,1000)
	apply_mode(3)
	_step()
	check(not held() and not ShaderCompilationScreen.active(), "no visible water does not create a waiting cover")
	camera.global_transform = initial
	reflector().request_refresh()
	_step()
	check(held(), "deferred initial preparation begins when water becomes visible")
	camera.global_position = Vector3(-1000,10,1000)
	reflector().request_refresh()
	_step()
	check(not held(), "leaving visible water cancels an unfinished preparation owner")
	check(await wait_finished(), "no-water cancellation settles and removes the cover")
	apply_mode(0)
	camera.global_transform = initial
	begin_case("off-before-first-draw")
	apply_mode(2)
	_step()
	check(held(), "Mirror cancellation starts before its first reflected draw")
	apply_mode(0)
	check(reflector() == null, "Off removes the reflection controller")
	check(await wait_finished(), "Off releases both preparation and queued draw acknowledgement")
	begin_case("scene-exit")
	apply_mode(3)
	_step()
	check(held(), "scene exit interrupts real pending water preparation")
	context[1].queue_free()
	context[0].queue_free()
	manual = false
	check(await wait_finished(), "scene exit releases its water preparation owner")
	await frames(8)
	watching = false
	ShaderCompilationScreen.on_progress = previous_observer
	ShaderWarmup.enabled = original_warmup
	check(GameData.option("confine_mouse") == 0 and GameData.option("show_fps") == 1 \
		and GameData.option("volume_sfx") == 0 and GameData.option("volume_stream") == 0 and GameData.option("volume_voice") == 0,
		"fixture preserves all mandated development profile preferences")
	var report := {"checks":checks,"failures":failures,"cases":cases,"progress":progress,"owner_releases":releases,
		"render_acknowledgements":acknowledgements,"screenshots":screenshots,"raytracing_supported":RayDevice.supported(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name(),
		"profile":OS.get_user_data_dir(),"injected_failure":"snapshot failed after real gather began"}
	FileAccess.open(out.path_join("shader-compilation-water.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	print("SHADER_COMPILATION_WATER ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
