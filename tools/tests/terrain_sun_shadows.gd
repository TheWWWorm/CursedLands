extends Node
## Render original terrain alone so every changed shadow pixel comes from
## a hill, with the previous caster exclusion as the negative control.
var checks := 0
var failures: Array[String] = []
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func frames(count := 8) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func capture(view: SubViewport, label: String) -> Image:
	await frames()
	var pixels := view.get_texture().get_image()
	check(pixels.save_png("user://terrain-sun-" + label + ".png") == OK, "save " + label)
	return pixels

func site(terrain: EITerrain) -> Vector2:
	var size := terrain.size_ei()
	var best := -INF
	var at := size * 0.5
	for y in range(16, int(size.y)-16, 4):
		for x in range(16, int(size.x)-48, 4):
			var h := terrain.height_at(x, y)
			var slope := absf(terrain.height_at(x+1, y)-h) + absf(terrain.height_at(x, y+1)-h)
			if slope > 0.3: continue
			for distance in range(8, 40, 4):
				var rise := terrain.height_at(x+distance, y)-h-distance*0.45
				var score := rise - slope*4.0 - distance*0.03
				if score > best:
					best = score
					at = Vector2(x, y)
	return at

func run_case(map_name: String) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1024, 768)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	Gfx.apply_quality(view)
	var zone: Dictionary = CampaignMap.load_from(GameData.texts).zones[map_name]
	var terrain := EITerrain.load_map(zone.mpr)
	check(terrain != null, map_name + " original terrain loads")
	if terrain == null: view.free(); return
	view.add_child(terrain)
	terrain.set_process(false)
	var at := site(terrain)
	var focus := Vector3(at.x, terrain.height_at(at.x, at.y), -at.y)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position = focus + Vector3(-8, 8, 13)
	camera.look_at(focus + Vector3(5, 2, 0))
	camera.current = true
	camera.far = 120
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.3, 0.4)
	view.add_child(env)
	var sun := DirectionalLight3D.new()
	view.add_child(sun)
	sun.look_at(-Vector3(1, 0.45, 0), Vector3.UP)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 2.0 if Portability.compatibility() else 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	Gfx.fit_shadows(sun, terrain.size_ei())
	Gfx.set_light(Color(0.65, 0.65, 0.65), Color(0.75, 0.75, 0.75))
	Gfx.sync_sun_pass(sun)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 120, 0))
	sun.shadow_caster_mask &= ~(EITerrain.SHADOW_RECEIVER_LAYER | EITerrain.DECAL_LAYER)
	await frames(30)
	var old := await capture(view, map_name + "-old")
	Gfx.setup_sun_casters(sun)
	var fixed := await capture(view, map_name + "-fixed")
	var changed := 0
	var darker := 0
	var first: Image = old.duplicate()
	var second: Image = fixed.duplicate()
	first.resize(320, 240, Image.INTERPOLATE_NEAREST)
	second.resize(320, 240, Image.INTERPOLATE_NEAREST)
	for y in 240:
		for x in 320:
			var before := first.get_pixel(x, y).get_luminance()
			var after := second.get_pixel(x, y).get_luminance()
			if absf(before-after) > 0.025: changed += 1
			if before-after > 0.025: darker += 1
	check(darker > 100, map_name + " hills cast visible sun shadows on the valley")
	check(changed == darker, map_name + " adding hill casters only darkens occluded land")
	var start := camera.transform
	for offset in [-3, 0, 3, 0]:
		camera.transform = start.translated(Vector3(offset, 0, 0))
		await frames(4)
	var restored := await capture(view, map_name + "-restored")
	check(restored.get_data() == fixed.get_data(), map_name + " returning the camera restores identical terrain shadows")
	rows.append({"map":map_name, "focus":str(focus), "changed":changed, "darker":darker, "renderer":RenderingServer.get_current_rendering_method()})
	view.queue_free()
	await frames(6)

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"q_aa":0, "q_shadows":2, "q_shadow_fit":1, "auto_graphics":0}, true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1024, 768)
	Engine.max_fps = 60
	RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals()
	for map_name in ["gz2g", "gz11k"]: await run_case(map_name)
	FileAccess.open("user://terrain-sun-shadows.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows}, "\t"))
	print("TERRAIN_SUN_SHADOWS ", checks, " checks ", failures.size(), " failures ", rows)
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
