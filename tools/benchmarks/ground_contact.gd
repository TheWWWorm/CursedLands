extends Node
## Frozen authored maps, paired off/on/off captures and viewport render cost.
## GPU timings are device/scene samples, not gameplay FPS or mobile evidence.
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func focus(map: EIMapScene) -> Dictionary:
	var best := {}; var best_score := -INF
	for object: Node3D in map.object_nodes:
		var record: Dictionary = object.get_meta("ei")
		if record.kind != "OBJECT" or record.template.begins_with("ef"):
			continue
		var p := object.global_position
		var size := map.terrain.size_ei()
		if p.x < 14 or -p.z < 14 or p.x > size.x - 14 or -p.z > size.y - 14:
			continue
		var bounds := AABB(); var first := true
		for mesh: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			var box := mesh.global_transform * mesh.mesh.get_aabb()
			bounds = box if first else bounds.merge(box); first = false
		if first or bounds.size.y < 1.5 or bounds.size.y > 10 or bounds.size.x > 18 or bounds.size.z > 18:
			continue
		var score := minf(bounds.size.x, 8) + minf(bounds.size.z, 8)
		if "rock" in String(record.get("name", "")).to_lower(): score += 100
		if score > best_score:
			best_score = score
			best = {"point":p, "object":record.get("name", ""), "template":record.template, "bounds":str(bounds)}
	return best

func settle(frames: int) -> void:
	for i in frames:
		RenderingServer.force_draw()
		await get_tree().process_frame

func sample(view: SubViewport, name: String) -> Dictionary:
	print("GROUND_CONTACT_MAP_BEGIN ", name)
	var start := Time.get_ticks_msec()
	await settle(24)
	var warmup_ms := Time.get_ticks_msec() - start
	var cpu := PackedFloat64Array(); var gpu := PackedFloat64Array()
	for i in 60:
		RenderingServer.force_draw()
		await get_tree().process_frame
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
	cpu.sort(); gpu.sort()
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://ground-contact-map-" + RenderingServer.get_current_rendering_method() + "-" + name + ".png")
	return {"image":image, "warmup_ms":warmup_ms, "cpu_median_ms":cpu[30], "gpu_median_ms":gpu[30], "cpu_p95_ms":cpu[57], "gpu_p95_ms":gpu[57],
		"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}

func compare(first: Image, second: Image) -> Dictionary:
	var a := first.get_data(); var b := second.get_data()
	var changed := 0; var peak := 0; var sum := 0
	for i in range(0, a.size(), 4):
		var error := 0
		for c in 3: error = maxi(error, absi(a[i + c] - b[i + c]))
		changed += int(error > 2); peak = maxi(peak, error); sum += error
	return {"changed":changed, "peak":peak, "mean":float(sum) / (a.size() / 4)}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GROUND_CONTACT_MAP requires a real renderer"); get_tree().quit(2); return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 120
	for key in ["gfx_hd_textures", "gfx_grass", "gfx_wind", "gfx_volumetric", "gfx_water", "gfx_weather_surfaces", "gfx_ground_contact"]:
		GameData.options[key] = 0
	for key in ["gfx_terrain", "gfx_materials", "gfx_soft_ground"]: GameData.options[key] = 1
	EIFigure.set_wind(false)
	Gfx.apply_surface_options()
	Gfx.set_light(Color(0.3, 0.3, 0.3), Color(0.7, 0.7, 0.7))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	var maps := ["bz2g", "bz10k", "bz13h"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-map="): maps = [arg.trim_prefix("--contact-map=")]
	for map_name in maps:
		var view := SubViewport.new(); view.size = Vector2i(800, 600)
		view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
		var map := EIMapScene.load_map(map_name, "", false)
		check(map != null, map_name + " loaded")
		if map == null: view.free(); continue
		view.add_child(map); map.terrain.set_process(false)
		if is_instance_valid(map.terrain.details.soft_ground):
			map.terrain.details.soft_ground.set_process(false)
		map.terrain._water_mat.set_shader_parameter("waves", 0.0)
		var target := focus(map)
		check(not target.is_empty(), map_name + " scenery fixture")
		if target.is_empty(): view.free(); continue
		var p: Vector3 = target.point
		var camera := Camera3D.new(); camera.far = 120; camera.near = 0.05
		view.add_child(camera); camera.current = true
		var env := WorldEnvironment.new(); env.environment = Environment.new()
		Gfx.setup_original_env(env.environment); env.environment.background_mode = Environment.BG_COLOR
		view.add_child(env)
		var sun := DirectionalLight3D.new(); sun.light_specular = Gfx.SUN_MARK
		view.add_child(sun); sun.rotation_degrees = Vector3(-40, -35, 0)
		sun.shadow_enabled = true; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		Gfx.setup_sun_casters(sun); Gfx.sync_sun_pass(sun)
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
		var owner := map.terrain.contact
		check(owner != null and owner._meshes.size() > 0, "placed scenery registered")
		for distance_mode in ["near", "far"]:
			camera.position = p + (Vector3(8, 6, 10) if distance_mode == "near" else Vector3(30, 24, 36))
			camera.position.y = maxf(camera.position.y, map.terrain.height_at(camera.position.x, -camera.position.z) + 6.0)
			camera.look_at(p + Vector3.UP)
			GameData.options["gfx_ground_contact"] = 0; owner.refresh()
			var off := await sample(view, map_name + "-" + distance_mode + "-off")
			GameData.options["gfx_ground_contact"] = 1; owner.refresh()
			var on := await sample(view, map_name + "-" + distance_mode + "-on")
			if OS.get_cmdline_user_args().has("--contact-native-control"):
				# Submitted draw counts cannot detect a linked-but-invalid GLES
				# draw. Exercise the same shader/bindings at zero blend strength.
				for family: Dictionary in owner._variants.values():
					for material: ShaderMaterial in family.values(): material.set_shader_parameter("contact_strength", 0.0)
				var neutral := await sample(view, map_name + "-" + distance_mode + "-neutral")
				check(compare(off.image, neutral.image).changed == 0, "zero strength retains native scenery within two bytes")
				for family: Dictionary in owner._variants.values():
					for material: ShaderMaterial in family.values(): material.set_shader_parameter("contact_strength", 0.7)
				var strength_restored := await sample(view, map_name + "-" + distance_mode + "-strength-restored")
				check(compare(on.image, strength_restored.image).peak == 0, "contact strength restores exact pixels")
			var variants := 0
			for family: Dictionary in owner._variants.values(): variants += family.size()
			var base_count := owner._variants.size()
			GameData.options["gfx_ground_contact"] = 0; owner.refresh()
			var restored := await sample(view, map_name + "-" + distance_mode + "-restored")
			var change := compare(off.image, on.image)
			var restoration := compare(off.image, restored.image)
			check(restoration.changed == 0, map_name + " " + distance_mode + " restored pixels " + JSON.stringify(restoration))
			check(off.draws > 10, map_name + " " + distance_mode + " visible map rendered")
			check(off.draws == on.draws, map_name + " " + distance_mode + " no extra draws")
			if distance_mode == "near": check(change.changed > 25, map_name + " visible authored contact band")
			off.erase("image"); on.erase("image"); restored.erase("image")
			var row := {"map":map_name, "distance":distance_mode, "focus":str(p), "object":target.object, "template":target.template,
				"registered_parts":owner._meshes.size(), "base_materials":base_count, "contact_materials":variants,
				"off":off, "on":on, "restored":restored, "difference":change, "restoration":restoration}
			rows.append(row); print("GROUND_CONTACT_MAP_CASE ", JSON.stringify(row))
		view.free(); await get_tree().process_frame
	var report := {"checks":checks, "failures":failures, "rows":rows, "renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(), "size":"800x600", "editor":OS.has_feature("editor")}
	FileAccess.open("user://ground-contact-map-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("GROUND_CONTACT_MAP checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
