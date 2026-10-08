extends Node
## Diagnostic only. Authored torch lights and scenery, no gameplay simulation.
## Normal rendered frames are required: force_draw() changes the engine's
## multiple-camera/dirty-shadow detection without advancing its frame clock.
var checks := 0
var failures := 0
var view: SubViewport
var world: GameWorld
var camera: Camera3D
var manager: LocalLighting
var game: Game
var fx: ParticleFx
var map_name := "bz2g"
var rows := []
var sources := {} # shared foliage Shader -> original code; diagnostic override only
var expect_cache := false
var warmup_frames := 16

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func tick() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func settle(frames := 16) -> void:
	for i in frames: await tick()

func distribution(values: Array) -> Dictionary:
	values.sort()
	return {"min":values.front(), "median":values[values.size() / 2],
			"p95":values[int(values.size() * 0.95)], "max":values.back(), "samples":values.size()}

func sample(label: String, motion: Callable = Callable()) -> Image:
	await settle(warmup_frames)
	var start := Engine.get_frames_drawn()
	var draws := []; var primitives := []; var visible := []; var cpu := []; var gpu := []
	for i in 48:
		if motion.is_valid(): motion.call(i)
		await tick()
		draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		primitives.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		visible.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
	check(Engine.get_frames_drawn() >= start + 48, "normal render frame clock advances")
	var frames := Engine.get_frames_drawn() - start
	# Compare the same settled endpoint across exports, not render-queue lag
	# while the transform is still changing. Counters above retain moving frames.
	if motion.is_valid(): await settle(4)
	var pixels := view.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	check(pixels.save_png("user://shadow-cache-" + RenderingServer.get_current_rendering_method()
			+ "-" + map_name + "-" + label + ".png") == OK, "capture saved")
	rows.append({"case":label,"shadow_draws":distribution(draws),
			"shadow_primitives":distribution(primitives),
			"visible_draws":distribution(visible),
			"viewport_cpu_ms":distribution(cpu),"viewport_gpu_ms":distribution(gpu),
			"normal_frames":frames,"capture_settle_frames":4 if motion.is_valid() else 0})
	print("SHADOW_CACHE_ROW ", JSON.stringify(rows.back()))
	return pixels

func nearby_foliage(light: OmniLight3D) -> int:
	var count := 0
	for root: Node3D in world.map.object_nodes:
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var m := mesh.material_override as ShaderMaterial
			if m == null or not m.has_meta("sway"): continue
			var box := mesh.global_transform * mesh.get_aabb()
			var closest := light.global_position.clamp(box.position, box.end)
			if closest.distance_to(light.global_position) <= light.omni_range: count += 1
	return count

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("LOCAL_SHADOW_CACHE requires a real renderer"); get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--local-shadow-map="): map_name = arg.trim_prefix("--local-shadow-map=")
		if arg == "--expect-wind-cache": expect_cache = true
		if arg.begins_with("--shadow-cache-warmup="):
			warmup_frames = clampi(int(arg.trim_prefix("--shadow-cache-warmup=")),16,600)
	for key in ["gfx_hd_textures","gfx_volumetric","gfx_ground_contact","gfx_soft_ground",
			"gfx_grass","gfx_water","gfx_heat_haze","gfx_torch_glow","gfx_lava_light","confine_mouse","vsync"]:
		GameData.options[key] = 0
	GameData.options["gfx_firelight"] = 1
	GameData.options["fps_limit"] = 3
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	# Leave this off-screen window drawable; minimizing suppresses normal draws.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	EIFigure.set_wind(true)
	view = SubViewport.new(); view.size = Vector2i(640, 480); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.positional_shadow_atlas_size = 2048
	add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	world = GameWorld.new(); world.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(world)
	check(world.load_map(map_name, map_name, false), "authored map loads")
	if world.map == null: get_tree().quit(1); return
	fx = ParticleFx.of(world)
	fx.setup_zone() # The actual authored torch offsets, radii and enhancement.
	check(not fx.lights.is_empty(), "map contains authored torches")
	if fx.lights.is_empty(): get_tree().quit(1); return
	var target: OmniLight3D = fx.lights[0].light
	var overlap := -1
	for d: Dictionary in fx.lights:
		var count := nearby_foliage(d.light)
		if count > overlap: overlap = count; target = d.light
	var focus := target.global_position
	camera = Camera3D.new(); camera.far = 90; camera.fov = CameraRig.MODERN_FOV
	view.add_child(camera); camera.position = focus + Vector3(10, 10, 12)
	camera.look_at(focus); camera.current = true
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.1, 0.1)
	view.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0)
	view.add_child(sun) # No directional shadows: counters contain local maps only.
	Gfx.set_light(Color(0.12,0.12,0.12),Color(0.35,0.35,0.35))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(80,90,0))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	game = Game.new(); game.world = world
	manager = LocalLighting.new(game); view.add_child(manager); manager.set_process(false)
	manager._world = world
	manager._assign_shadows(fx,camera,focus)
	manager._advance_shadows(0.4); manager._advance_shadows(0.4)
	check(target.shadow_enabled, "authored target is selected by production manager")
	var selected := []
	for d: Dictionary in fx.lights:
		if d.light.shadow_enabled: selected.append({"position":str(d.light.global_position),"range":d.light.omni_range})
	await sample("wind-on")
	EIFigure.set_wind(false)
	var before := await sample("wind-off")
	if expect_cache: check(rows.back().shadow_primitives.max == 0, "inactive wind allows native shadow reuse")
	# Isolate whether disabled wind's TIME reference prevents native map reuse.
	for node: MeshInstance3D in world.map.find_children("*", "MeshInstance3D", true, false):
		var material := node.material_override as ShaderMaterial
		if material and material.shader and material.has_meta("sway") and not sources.has(material.shader):
			sources[material.shader] = material.shader.code
			material.shader.code = material.shader.code.replace("TIME", "0.0")
	var frozen := await sample("wind-off-without-time")
	check(before.get_data() == frozen.get_data(), "removing inactive wind time preserves the captured scene")
	check(rows.back().shadow_primitives.max == 0, "time-free static scenery reuses its native shadow map")
	var energy := target.light_energy
	await sample("energy-and-opacity", func(i: int):
		target.light_energy = energy * (1.0 + sin(i * 0.3) * 0.08)
		target.shadow_opacity = 0.5 + sin(i * 0.4) * 0.25)
	check(rows.back().shadow_primitives.max == 0, "illumination and opacity changes do not invalidate static depth")
	target.light_energy = energy; target.shadow_opacity = 1.0
	var origin := target.position
	await sample("moving-light", func(i: int): target.position = origin + Vector3(sin(i * 0.15) * 0.5,0,0))
	check(rows.back().shadow_primitives.max > 0, "moving authored light redraws shadow depth")
	target.position = origin
	var stable := await sample("light-restored")
	check(frozen.get_data() == stable.get_data(), "restoring the carried light restores the image")
	var caster: MeshInstance3D
	var closest_distance := INF
	var caster_key := ""
	for root: Node3D in world.map.object_nodes:
		for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if not node.is_visible_in_tree() or node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
			var box := node.global_transform * node.get_aabb()
			var distance := target.global_position.distance_to(target.global_position.clamp(box.position, box.end))
			var key := "%s/%s" % [root.get_meta("ei",{}).get("nid",0),root.get_path_to(node)]
			if distance < closest_distance or (distance == closest_distance and key < caster_key):
				closest_distance = distance; caster = node; caster_key = key
	check(caster != null and closest_distance < target.omni_range, "authored caster overlaps selected light")
	if caster:
		var caster_origin := caster.position
		await sample("moving-caster", func(i: int): caster.position = caster_origin + Vector3(sin(i * 0.2) * 0.25,0,0))
		check(rows.back().shadow_primitives.max > 0, "moving authored caster redraws shadow depth")
		caster.position = caster_origin
		stable = await sample("caster-restored")
		check(frozen.get_data() == stable.get_data(), "restoring the caster restores the image")
	for shader: Shader in sources: shader.code = sources[shader]
	var restored := await sample("shader-restored")
	check(before.get_data() == restored.get_data(), "diagnostic shader override restores exactly")
	EIFigure.set_wind(true)
	await sample("wind-restored")
	if overlap > 0: check(rows.back().shadow_primitives.max > 0, "wind restores animated caster updates")
	var report := {"map":map_name,"checks":checks,"failures":failures,"rows":rows,
			"warmup_frames":warmup_frames,"sample_frames":48,
			"moving_caster":caster_key,"moving_caster_light_distance":closest_distance,
			"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),
			"torch_count":fx.lights.size(),"selected":selected,"target_foliage_overlap":overlap,
			"foliage_shaders":sources.size(),"atlas":view.positional_shadow_atlas_size,
			"normal_loop":true,"simulation":false,"units":false,"grass":false,"directional_shadows":false}
	var file := FileAccess.open("user://shadow-cache-" + map_name + "-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t") + "\n")
	print("LOCAL_SHADOW_CACHE ",JSON.stringify(report))
	manager.free(); game.free(); view.free()
	get_tree().quit(1 if failures else 0)
