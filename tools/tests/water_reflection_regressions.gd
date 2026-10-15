extends Node
## Rendered regression checks on the first Ingos lake (gz11k).
## Run with Forward+, the normal separate render thread, and optionally --hd.
## HD needs community.hd-lands-textures@1.5.0 installed in the test user directory.
## Negative controls restore the two old behaviours so an insensitive fixture
## cannot pass. Fog also has an independent reference: the original FOG path.
const FOG_CORRECTION := "if ((CAMERA_VISIBLE_LAYERS & 1048576u) != 0u) { ei_g = 0.0; }"
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)


func frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func difference(first: Image, second: Image, opaque := false, start_y := 0, end_y := 180) -> Dictionary:
	var a: Image = first.duplicate()
	var b: Image = second.duplicate()
	a.resize(320, 180, Image.INTERPOLATE_NEAREST)
	b.resize(320, 180, Image.INTERPOLATE_NEAREST)
	var changed := 0
	var samples := 0
	var error := 0.0
	for y in range(start_y, end_y):
		for x in 320:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if opaque and (ca.a < 0.95 or cb.a < 0.95): continue
			var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			samples += 1
			error += delta
			if delta > 0.025: changed += 1
	return {"changed": changed, "samples": samples, "mean_error": error / maxi(1, samples)}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--hd" in OS.get_cmdline_user_args():
		var error := ModStore.create_profile("Reflection validation", false, ["community.hd-lands-textures@1.5.0"])
		if error.is_empty(): error = GameData.open(GameData.root)
		check(error.is_empty(), "HD Lands profile opens: " + error)
		if not error.is_empty():
			get_tree().quit(1)
			return
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"display_mode": 0, "auto_graphics": 0,
		"gfx_water": 1, "gfx_water_reflections": 2, "gfx_sky": 1,
		"gfx_terrain": 2, "gfx_materials": 1, "gfx_volumetric": 1, "gfx_far_view": 0,
		"q_aa": 0, "q_shadows": 0, "vsync": 0, "confine_mouse": 0, "autosave": 0,
		"show_tutorial": 0, "unit_fog": 0, "net_upnp": 0, "net_lan": 0, "net_directory": 0}, true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280, 720))
	Engine.max_fps = 60
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var session := Session.new()
	add_child(session)
	session.state.ensure_hero(0, "Human Hero")
	var game := Game.new()
	game.session = session
	session.game = game
	add_child(game)
	await session.enter_zone("gz11k", 1, false)
	session.set_physics_process(false)
	session.world.set_process(false)
	session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	game.rig.set_process(false)
	game.direct.set_process(false)
	game.hud.hide()
	game.hud.process_mode = Node.PROCESS_MODE_DISABLED
	for unit: GameUnit in session.world.units.values():
		unit.hide()
		unit.set_process(false)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.near = 0.05
	camera.far = 100
	camera.fov = 75
	camera.current = true
	await frames(30)
	game.set_process(false)
	var terrain := session.world.terrain
	terrain.set_process(false)
	var reflector := terrain._reflection
	check(is_instance_valid(reflector), "Forward+ Mirror creates a reflection owner")
	if not is_instance_valid(reflector):
		TexUpscale.shutdown()
		get_tree().quit(1)
		return
	Engine.time_scale = 0.0
	await _fog_checks(session, game, terrain, camera, reflector)
	await _motion_checks(session, game, terrain, camera, reflector)
	var report := {"map": "gz11k", "hd": "--hd" in OS.get_cmdline_user_args(),
		"checks": checks, "failures": failures, "rows": rows}
	FileAccess.open("user://water-reflection-regressions.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WATER_REFLECTION_REGRESSIONS ", JSON.stringify(report))
	game.queue_free()
	session.queue_free()
	await frames(10)
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)


func _fog_checks(session: Session, game: Game, terrain: EITerrain, camera: Camera3D, reflector: Node) -> void:
	for hour in [12.0, 0.0]:
		session.state.world_time = hour
		game._update_daylight(false)
		# Keep the depth-fog compensation active without temporal mist noise.
		game._env.volumetric_fog_density = 0.0
		for pose in 2:
			var anchor: Vector2 = [Vector2(173, 267), Vector2(165, 240)][pose]
			var target: Vector2 = [Vector2(260, 186), Vector2(255, 184)][pose]
			camera.global_position = Vector3(anchor.x, maxf(terrain.height_at(anchor.x, anchor.y), 6.4) + 2.5, -anchor.y)
			camera.look_at(Vector3(target.x, terrain.height_at(target.x, target.y) + 1.0, -target.y))
			reflector.request_refresh()
			var tag := "fog-%s-%d" % ["day" if hour == 12.0 else "night", pose]
			var captures := {}
			var scenes := {}
			for variant in ["fixed", "control", "reference"]:
				# The reflection environment has no automatic fog. Its correct
				# compensated material must match the independent original FOG output.
				Gfx._set_vol_fog(variant != "reference")
				if variant == "control":
					for entry: Array in Gfx._made:
						var shader: Shader = entry[0].get_ref()
						if shader: shader.code = shader.code.replace(FOG_CORRECTION, "")
				await frames(8)
				check(reflector.viewport != null, "%s %s has a reflected image" % [tag, variant])
				if reflector.viewport == null: return
				var image: Image = reflector.viewport.get_texture().get_image()
				captures[variant] = image
				image.save_png("user://%s-%s-reflection.png" % [tag, variant])
				var scene := get_viewport().get_texture().get_image()
				scenes[variant] = scene
				scene.save_png("user://%s-%s.png" % [tag, variant])
			var fixed := difference(captures.fixed, captures.reference, true)
			var control := difference(captures.control, captures.reference, true)
			var main := difference(scenes.fixed, scenes.control, false, 0, 70)
			rows.append({"case": tag, "fixed": fixed, "control": control, "main_view": main})
			check(fixed.samples > 1000, tag + " compares visible reflected geometry")
			check(fixed.mean_error < 0.005 and fixed.changed < 50, tag + " matches original fog colours")
			check(control.changed > 100 and control.mean_error > fixed.mean_error * 5.0, tag + " detects the previous colour corruption")
			check(main.changed < 20, tag + " leaves main-view shading unchanged")
	Gfx._set_vol_fog(true)


func _motion_checks(session: Session, game: Game, terrain: EITerrain, camera: Camera3D, reflector: Node) -> void:
	GameData.options.gfx_volumetric = 0
	Gfx._set_vol_fog(false)
	session.state.world_time = 12.0
	game._update_daylight(false)
	var anchor := Vector2(122.5, 88.5)
	camera.global_position = Vector3(anchor.x, terrain.height_at(anchor.x, anchor.y) + 1.6, -anchor.y)
	camera.look_at(camera.global_position + Vector3(1, -0.1, 0))
	reflector.request_refresh()
	await frames(8)
	check(reflector.viewport.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"reflection viewport uses the current render-frame camera pose")
	for variant in ["fixed", "control"]:
		if variant == "control":
			reflector.viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		await frames(8)
		var bad := 0
		var worst := 0
		var first_submissions: Array[int] = []
		for i in 24:
			var pitch: float = [-0.7, 0.2, 0.0, -0.15][i % 4]
			# A separate render thread delivers post-draw through the deferred
			# queue, sometimes after the next frame's reflection _process.
			# Change the camera at process start, as the real camera rig does,
			# so both views receive the pose before that frame is submitted.
			await get_tree().process_frame
			var drawn := Engine.get_frames_drawn()
			camera.look_at(camera.global_position + Vector3(cos(pitch), sin(pitch), 0))
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
			first_submissions.append(Engine.get_frames_drawn()-drawn)
			var first := get_viewport().get_texture().get_image()
			await frames(5)
			var settled := get_viewport().get_texture().get_image()
			var delta := difference(first, settled, false, 60, 180)
			worst = maxi(worst, delta.changed)
			if delta.changed > 50:
				bad += 1
				if bad <= 2:
					first.save_png("user://motion-%s-%d-first.png" % [variant, i])
					settled.save_png("user://motion-%s-%d-settled.png" % [variant, i])
		rows.append({"case": "motion", "variant": variant, "transitions": 24,
			"bad_frames": bad, "worst_changed_pixels": worst,"first_submissions":first_submissions})
		check(first_submissions.all(func(n:int)->bool:return n==1),variant+" captures the first submitted camera frame")
		check(bad == 0 if variant == "fixed" else bad > 0,
			"rapid pitch has no transient gap" if variant == "fixed" else "motion control detects interpolation lag")
	reflector.viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
