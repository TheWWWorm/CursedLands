extends "ground_contact.gd"
## Real figure materials, native shadow counters and live wind/option changes.
## Covers dither copies created while wind is off, including contact variants.

func frame() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func wait_frames(count: int) -> void:
	for i in count: await frame()

func pixels(view: SubViewport) -> Image:
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func difference(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	var changed := 0; var peak := 0
	for p in range(0,aa.size(),4):
		var local := 0
		for c in 3: local = maxi(local,absi(aa[p+c]-bb[p+c]))
		peak = maxi(peak,local); changed += int(local > 2)
	return {"pixels_over_2":changed,"max_channel_delta":peak}

func test_material(situation: String) -> void:
	var still := situation.contains("still")
	var contact := situation.contains("contact")
	var faded := situation.contains("fade")
	EIFigure.set_wind(false)
	GameData.options["gfx_ground_contact"] = int(contact)
	var view := SubViewport.new(); view.size = Vector2i(384,384)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.positional_shadow_atlas_size = 1024
	add_child(view)
	var terrain := terrain_fixture(); terrain.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(terrain)
	var base := EIFigure.foliage_material_for("tree02", not still) as ShaderMaterial
	var material := EIFigure.foliage_variant(base, 3.0) if Portability.compatibility() else base
	var tree := object_fixture(terrain, material, Vector2(3,4))
	tree.position.y = 2
	if not Portability.compatibility(): tree.set_instance_shader_parameter("part_y",3.0)
	var owner := owner_fixture(terrain)
	if contact: owner.register(tree.get_parent())
	var fade := CameraFade.new()
	if faded:
		fade._nodes.append(tree.get_parent()); fade._meshes.append([tree])
		fade._set_alpha(0,0.375)
	var retained := tree.material_override as ShaderMaterial
	var program := retained.shader
	var albedo: Variant = retained.get_shader_parameter("albedo_tex")
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new()
	plane.size = Vector2(16,16); ground.mesh = plane
	ground.position = Vector3(16,0,-16)
	ground.material_override = base_material(false)
	view.add_child(ground)
	var light := OmniLight3D.new(); light.position = Vector3(13,5,-12)
	light.omni_range = 12; light.omni_attenuation = 0.0; light.light_energy = 0.7
	light.light_specular = Gfx.LOCAL_SPECULAR
	light.shadow_bias = 0.025; light.shadow_normal_bias = 0.35
	view.add_child(light); Gfx.set_local_shadow(light,true)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0)
	view.add_child(sun)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15,0.15,0.15)
	view.add_child(environment)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7; camera.position = Vector3(16,7,-7)
	view.add_child(camera); camera.look_at(Vector3(16,2,-16)); camera.current = true
	# Measure steady rendering after a fixed startup warm-up. Cold Mobile
	# exhibits the same one-time 7/255 lighting change on baseline and candidate
	# (identical before/after images), so it is not a shadow-cache regression.
	await wait_frames(120)
	var stable_image: Image
	var step := 0
	for enabled in [false,true,false,true]:
		EIFigure.set_wind(enabled)
		Gfx.set_wind_frame(terrain.wind_frame())
		await wait_frames(16)
		check(tree.material_override == retained and retained.shader == program,
				"wind toggle preserves " + situation + " resource identities")
		check(retained.get_shader_parameter("albedo_tex") == albedo, "texture survives recomposition")
		if faded:
			var alpha: float = retained.get_shader_parameter("cam_fade") if Portability.compatibility() else tree.get_instance_shader_parameter("cam_fade")
			check(is_equal_approx(alpha,0.375), "active fade survives wind toggle")
		var before := pixels(view)
		var minimum := 2147483647; var maximum := 0
		var start := Engine.get_frames_drawn()
		for i in 48:
			terrain._waves.advance(1.0/60.0)
			Gfx.set_wind_frame(terrain.wind_frame())
			await frame()
			var count := view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			minimum = mini(minimum,count); maximum = maxi(maximum,count)
		var after := pixels(view)
		var moving := before.get_data() != after.get_data()
		var delta := difference(before,after)
		if moving and (not enabled or still):
			var label := "user://shadow-cache-" + RenderingServer.get_current_rendering_method() + "-" + situation + "-" + str(step)
			before.save_png(label + "-before.png"); after.save_png(label + "-after.png")
		check(Engine.get_frames_drawn() >= start + 48, "real render frames advance")
		if enabled and not still:
			check(moving and maximum > 0, "wind and animated shadow updates restore for " + situation)
		else:
			check(not moving and maximum == 0, "inactive foliage is stable and shadow depth is reused for " + situation)
			if stable_image: check(stable_image.get_data() == after.get_data(), "wind round trip restores original geometry and lighting")
			stable_image = after
		rows.append({"case":situation,"wind":enabled,"still":still,"moving_pixels":moving,
				"pixel_delta":delta,
				"shadow_primitives_min":minimum,"shadow_primitives_max":maximum})
		print("FOLIAGE_SHADOW_CACHE_ROW ",JSON.stringify(rows.back()))
		# A separate material-option recompose must retain the current wind
		# specialization in the same active dither and contact programs.
		GameData.options["gfx_materials"] = 1
		Gfx.apply_surface_options()
		step += 1
		GameData.options["gfx_materials"] = 0
		Gfx.apply_surface_options()
	if faded: fade._set_alpha(0,0.0)
	view.free()
	await get_tree().process_frame

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FOLIAGE_SHADOW_CACHE requires a real renderer"); get_tree().quit(2); return
	for key in ["gfx_hd_textures","gfx_volumetric","gfx_terrain","gfx_soft_ground","gfx_weather_surfaces","gfx_materials","confine_mouse","vsync"]:
		GameData.options[key] = 0
	GameData.options["fps_limit"] = 3
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	Gfx.apply_surface_options()
	Gfx.set_light(Color(0.2,0.2,0.2),Color(0.5,0.5,0.5))
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(80,90,0))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3(0.4,0.7,0.5).normalized())
	var cases := ["base","fade","contact","contact-fade","still","still-fade","still-contact-fade"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--foliage-cache-cases="): cases = Array(arg.trim_prefix("--foliage-cache-cases=").split(","))
	for situation: String in cases:
		await test_material(situation)
	var report := {"checks":checks,"failures":failures,"rows":rows,
			"renderer":RenderingServer.get_current_rendering_method(),"normal_loop":true,
			"initial_warmup_frames":120,"switch_warmup_frames":16,"sample_frames":48}
	FileAccess.open("user://foliage-shadow-cache-" + RenderingServer.get_current_rendering_method() + ".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	print("FOLIAGE_SHADOW_CACHE ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
