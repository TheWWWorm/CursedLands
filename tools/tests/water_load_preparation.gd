extends "water_raytrace_artifact.gd"
## A loading camera away from the river must not leave the first Mirror draw
## waiting for a gameplay-time preparation owner. Uses real campaign geometry.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
class DrawProbe extends CompositorEffect:
	var mutex := Mutex.new()
	var draws := 0
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int, _data: RenderData) -> void:
		mutex.lock(); draws += 1; mutex.unlock()
	func count() -> int:
		mutex.lock(); var value := draws; mutex.unlock(); return value

func run() -> void:
	var original_warmup := ShaderWarmup.enabled
	ShaderWarmup.enabled = false
	var context := await setup()
	var game: Game = context[1]
	Engine.max_fps = 30
	for i in 16:
		if not ShaderCompilationScreen.active(): break
		await frames()
	check(not ShaderCompilationScreen.active(), "setup preparation has finished")
	var river_view := camera.global_transform
	var loading_camera := game.rig.camera
	var original_camera := loading_camera.global_transform
	loading_camera.global_position = Vector3(-1000, 20, 1000)
	loading_camera.current = true
	GameData.options.gfx_water_reflections = 0; t.apply_gfx()
	GameData.options.gfx_water_reflections = 2; t.apply_gfx()
	var reflection: Reflection = t._reflection
	reflection.set_process(false)
	reflection._process(0.016)
	check(not is_finite(reflection.plane) and reflection._needs_preparation,
		"off-river loading camera leaves first Mirror work pending")
	check(not reflection._preparing, "unseen water does not acquire a gameplay cover")
	# Install a real render-thread observer before production loading warmup.
	reflection._create_view()
	reflection.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var probe := DrawProbe.new()
	var compositor := Compositor.new(); compositor.compositor_effects = [probe]
	reflection.camera.compositor = compositor
	var before_pose := loading_camera.global_transform
	var before_time: float = game.world.time
	var before_wave := t._waves.time_ticks()
	LoadingScreen.begin(get_tree(), game.world.zone)
	ShaderWarmup.enabled = true
	var started := Time.get_ticks_usec()
	ShaderWarmup.run(game)
	var elapsed := Time.get_ticks_usec() - started
	check(probe.count() >= 4, "loading completes actual reflected scene draws")
	check(not reflection._needs_preparation and not reflection._preparing,
		"first Mirror preparation completes under the loading screen")
	check(loading_camera.global_transform == before_pose and game.world.time == before_time
		and t._waves.time_ticks() == before_wave, "preparation preserves player camera and simulation clocks")
	check(reflection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and not t._water_mat.get_shader_parameter("planar_enabled"), "representative view is disabled before play")
	var loaded := reflection.viewport.get_texture().get_image()
	var loaded_hits := 0
	for y in range(0, loaded.get_height(), 8):
		for x in range(0, loaded.get_width(), 8):
			if loaded.get_pixel(x, y).a > 0.1: loaded_hits += 1
	check(loaded_hits > 50, "completed loading image contains real reflected geometry")
	loaded.save_png(out.path_join("loading-mirror.png"))
	var prepared_draws := probe.count()
	ShaderWarmup.run(game)
	check(probe.count() == prepared_draws and not reflection._needs_preparation,
		"repeated loading warmup reuses its completed reflection")
	var serial := reflection._preparation_serial
	LoadingScreen.end()
	for i in 16:
		if not ShaderCompilationScreen.active(): break
		await frames()
	check(not ShaderCompilationScreen.active(), "loading preparation owners and settling finish")
	camera.global_transform = river_view; camera.current = true
	reflection.request_refresh(); reflection._process(0.016)
	check(is_finite(reflection.plane), "first gameplay camera sees authored river water")
	check(not reflection._preparing and reflection._preparation_serial == serial
		and not ShaderCompilationScreen.active(), "first visible water keeps gameplay controllable")
	check(reflection.camera.global_transform.is_equal_approx(Reflection.reflected_transform(camera.get_camera_transform(), reflection.plane)),
		"first visible water uses the real camera transform")
	check(reflection.camera.cull_mask == Reflection.reflection_mask(camera.cull_mask)
		and reflection.camera.far == camera.far, "normal reflection masks and draw distance survive preparation")
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := reflection.viewport.get_texture().get_image()
	var hits := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			if image.get_pixel(x, y).a > 0.1: hits += 1
	check(hits > 50, "prepared Mirror renders actual river-bank geometry")
	image.save_png(out.path_join("prepared-mirror.png"))
	get_viewport().get_texture().get_image().save_png(out.path_join("prepared-river.png"))
	rows.append({"loading_warmup_us":elapsed,"completed_mirror_draws":prepared_draws,"preparation_serial":serial,"geometry_samples":hits,"loading_geometry_samples":loaded_hits})
	if reflection.has_method("prepare_loading"):
		loading_camera.current = true
		reflection._disable()
		var before_guard := probe.count()
		check(not reflection.prepare_loading(loading_camera), "gameplay cannot force a loading draw")
		LoadingScreen.begin(get_tree(), game.world.zone)
		GameData.graphics_revision += 1
		LoadingScreen.force_deferred = true
		check(not reflection.prepare_loading(loading_camera), "deferred loading does not force a draw")
		LoadingScreen.force_deferred = false
		GameData.options.gfx_water_reflections = 3
		check(not reflection.prepare_loading(loading_camera), "hardware RT keeps its existing preparation path")
		GameData.options.gfx_water_reflections = 2
		reflection.viewport.disable_3d = true
		check(not reflection.prepare_loading(loading_camera) and reflection._needs_preparation,
			"canvas-only reflection cannot acknowledge unfinished 3D work")
		reflection.viewport.disable_3d = false
		var water := t.water.duplicate()
		t.water.fill(-INF)
		check(not reflection.prepare_loading(loading_camera) and reflection._needs_preparation,
			"absent water preserves pending preparation")
		t.water = water
		var ground := t.liquid_ground.duplicate()
		t.liquid_ground.fill(EITerrain.LAVA)
		check(not reflection.prepare_loading(loading_camera) and reflection._needs_preparation,
			"live lava cells are excluded even when the water index was already built")
		t.liquid_ground = ground
		check(probe.count() == before_guard, "declined preparation performs no reflected draws")
		check(reflection.prepare_loading(loading_camera) and not reflection._needs_preparation,
			"a graphics revision prepares current water under the loading cover")
		check(probe.count() >= before_guard + 4, "graphics refresh completes new scene draws")
		LoadingScreen.end()
	loading_camera.global_transform = original_camera
	ShaderWarmup.enabled = original_warmup
	FileAccess.open(out.path_join("water-load-preparation.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows}, "\t"))
	game.queue_free(); context[0].queue_free(); await frames(8)
	TexUpscale.shutdown(); UnitWounds.shutdown()
	print("WATER_LOAD_PREPARATION checks=",checks," failures=",failures.size())
	get_tree().quit(int(not failures.is_empty()))
