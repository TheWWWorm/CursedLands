extends "ground_contact.gd"
## Normal-frame counterpart to the historical forced-draw contact fixture.
## Separate synchronous refresh, first draw, settling and steady viewport cost.
## Use frozen baseline/candidate packs and isolated cold/warm driver caches.
const WARMUP := 96
const SAMPLES := 240
var terrain_mode := 1
var deform := 1

func tick() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func settle(frames: int) -> void:
	for i in frames: await tick()

func distribution(values: Array) -> Dictionary:
	var ordered := values.duplicate(); ordered.sort()
	return {"min":ordered[0], "median":ordered[ordered.size() / 2],
		"p95":ordered[int(ordered.size() * 0.95)], "max":ordered.back()}

func measure(view: SubViewport, owner: GroundContact, label: String, enabled: bool, capture: bool) -> Dictionary:
	print("GROUND_CONTACT_COST_BEGIN ", label)
	GameData.options.gfx_ground_contact = int(enabled)
	var start := Time.get_ticks_usec()
	owner.refresh()
	var refresh_ms := (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	await tick()
	var first_frame_ms := (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	await settle(WARMUP - 1)
	var remaining_warmup_ms := (Time.get_ticks_usec() - start) / 1000.0
	var cpu := []; var gpu := []; var wall := []; var draws := []; var primitives := []
	var invalid := 0; var first_draw := Engine.get_frames_drawn()
	for i in SAMPLES:
		start = Time.get_ticks_usec(); await tick()
		wall.append((Time.get_ticks_usec() - start) / 1000.0)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		var ms := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		gpu.append(ms); invalid += int(not is_finite(ms) or ms <= 0.0)
		draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		primitives.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	check(invalid == 0, label + " positive finite GPU timestamps")
	check(Engine.get_frames_drawn() >= first_draw + SAMPLES, label + " normal frame clock advances")
	check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, label + " uncapped timing")
	check(draws.min() > 10 and primitives.min() > 0, label + " authored scenery submitted")
	var variants := 0
	for family: Dictionary in owner._variants.values(): variants += family.size()
	var result := {"refresh_ms":refresh_ms, "first_frame_ms":first_frame_ms, "remaining_warmup_ms":remaining_warmup_ms,
		"warmup_frames":WARMUP, "sample_frames":SAMPLES, "viewport_cpu_ms":distribution(cpu), "viewport_gpu_ms":distribution(gpu),
		"frame_wall_ms":distribution(wall), "visible_draws":distribution(draws), "visible_primitives":distribution(primitives),
		"registered_parts":owner._meshes.size(), "base_materials":owner._variants.size(), "contact_materials":variants,
		"surface_texture_bytes":0}
	if owner.surface:
		# Readback is after sampling and is excluded from all measured phases.
		result.surface_texture_bytes = owner.surface.vertices.get_image().get_data().size() + owner.surface.normals.get_image().get_data().size()
	if capture:
		var pixels := view.get_texture().get_image(); pixels.convert(Image.FORMAT_RGBA8)
		check(pixels.save_png("user://ground-contact-cost-" + label + ".png") == OK, label + " capture saved")
		result.image = pixels
	var log_row := result.duplicate(); log_row.erase("image")
	print("GROUND_CONTACT_COST_ARM ", label, " ", JSON.stringify(log_row))
	return result

func scene(map_name: String) -> void:
	GameData.options.gfx_ground_contact = 0
	var view := SubViewport.new(); view.size = Vector2i(800, 600)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view); RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	var start := Time.get_ticks_usec()
	var map := EIMapScene.load_map(map_name, "", false)
	check(map != null, map_name + " loaded")
	if map == null: view.free(); return
	view.add_child(map); map.terrain.set_process(false)
	map.terrain.details.soft_ground.set_process(false)
	map.terrain._water_mat.set_shader_parameter("waves", 0.0)
	var load_ms := (Time.get_ticks_usec() - start) / 1000.0
	var target := focus(map)
	check(not target.is_empty(), map_name + " scenery fixture")
	if target.is_empty(): view.free(); return
	var p: Vector3 = target.point
	var camera := Camera3D.new(); camera.far = 120; camera.near = 0.05
	view.add_child(camera); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	Gfx.setup_original_env(env.environment); env.environment.background_mode = Environment.BG_COLOR
	view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.light_specular = Gfx.SUN_MARK
	view.add_child(sun); sun.rotation_degrees = Vector3(-40, -35, 0)
	# Hold native dynamic shadows so neither changing projections nor a shadow
	# policy difference can be mistaken for a contact-query improvement.
	sun.shadow_enabled = true; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	Gfx.setup_sun_casters(sun); Gfx.sync_sun_pass(sun)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	var owner := map.terrain.contact
	check(owner != null and owner._meshes.size() > 0, map_name + " placed scenery registered")
	for distance_mode: String in ["near", "far"]:
		camera.position = p + (Vector3(8, 6, 10) if distance_mode == "near" else Vector3(30, 24, 36))
		camera.position.y = maxf(camera.position.y, map.terrain.height_at(camera.position.x, -camera.position.z) + 6.0)
		camera.look_at(p + Vector3.UP)
		var label := map_name + "-" + distance_mode
		var off := await measure(view, owner, label + "-off", false, true)
		var on := await measure(view, owner, label + "-on", true, true)
		var repeat_on := await measure(view, owner, label + "-repeat-on", true, false)
		var restored := await measure(view, owner, label + "-restored", false, true)
		var change := compare(off.image, on.image)
		var restoration := compare(off.image, restored.image)
		check(restoration.peak == 0, label + " exact restored RGB " + JSON.stringify(restoration))
		check(off.visible_draws == on.visible_draws and off.visible_primitives == on.visible_primitives, label + " same geometry and draws")
		check(on.visible_draws == repeat_on.visible_draws and on.visible_primitives == repeat_on.visible_primitives, label + " repeated on same geometry and draws")
		if distance_mode == "near": check(change.changed > 25, map_name + " visible authored contact band")
		for arm: Dictionary in [off, on, repeat_on, restored]: arm.erase("image")
		rows.append({"map":map_name, "distance":distance_mode, "focus":str(p), "object":target.object, "template":target.template,
			"load_ms":load_ms, "off":off, "on":on, "repeat_on":repeat_on, "restored":restored, "difference":change, "restoration":restoration})
	view.free(); await settle(8)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GROUND_CONTACT_COST requires a real renderer"); get_tree().quit(2); return
	var maps := ["bz2g", "bz10k", "bz13h"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-map="): maps = [arg.trim_prefix("--contact-map=")]
		if arg == "--contact-natural": terrain_mode = 2
		if arg == "--contact-no-deform": deform = 0
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_terrain":terrain_mode, "gfx_materials":1, "gfx_soft_ground":deform,
		"q_aa":0, "auto_graphics":0, "confine_mouse":0, "vsync":0, "fps_limit":0}, true)
	EIFigure.set_wind(false); Gfx.ensure_globals(); Gfx.apply_surface_options()
	Engine.time_scale = 0; process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	Gfx.set_light(Color(0.3, 0.3, 0.3), Color(0.7, 0.7, 0.7))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	await settle(16); Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for map_name: String in maps: await scene(map_name)
	TexUpscale.shutdown(); await settle(12)
	var report := {"checks":checks, "failures":failures, "rows":rows, "renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(), "size":[800, 600], "editor":OS.has_feature("editor"),
		"terrain_mode":terrain_mode, "deformation":deform,
		"scope":"Held authored scenery, normal frames. Refresh includes synchronous field/material/uniform work; first frame and settling include remaining driver preparation. Steady viewport samples are not gameplay FPS or target-device acceptance."}
	FileAccess.open("user://ground-contact-cost.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("GROUND_CONTACT_COST checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
