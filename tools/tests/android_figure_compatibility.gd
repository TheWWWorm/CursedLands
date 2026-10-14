extends Node
## Compare the shipped figure math with disabled-feature specialization on
## real menu assets and rendered material controls. No player-facing probe.
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var view: SubViewport
var rendered := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func capture() -> Image:
	for i in 4: await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image != null and not image.is_empty(), "GPU readback succeeds")
	image.convert(Image.FORMAT_RGBA8)
	rendered += 1
	return image

func difference(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data()
	var bb := b.get_data()
	var maximum := 0
	var changed := 0
	var over_one := 0
	for i in aa.size():
		var delta := absi(int(aa[i]) - int(bb[i]))
		maximum = maxi(maximum, delta)
		if delta > 0: changed += 1
		if delta > 1: over_one += 1
	return {"max_channel_delta":maximum, "changed_channels":changed, "channels_over_one":over_one}

func options(mask: int) -> void:
	GameData.options.gfx_materials = mask & 1
	GameData.options.gfx_foliage_light = (mask >> 1) & 1
	GameData.options.gfx_sharp_units = (mask >> 2) & 1
	Gfx.apply_surface_options()

func compare(label: String) -> Image:
	Gfx._compact_figures = false
	Gfx.apply_surface_options()
	var reference := await capture()
	Gfx._compact_figures = true
	Gfx.apply_surface_options()
	var candidate := await capture()
	var delta := difference(reference, candidate)
	check(delta.channels_over_one == 0, label + " retains pixels within 1/255")
	rows.append({"case":label, "difference":delta})
	print("GRAPHICS_FIGURE_CASE ", label, " ", JSON.stringify(delta))
	if label.ends_with("-0"):
		reference.save_png("user://figure-compat-" + label + "-reference.png")
		candidate.save_png("user://figure-compat-" + label + "-candidate.png")
	return candidate

func menu() -> void:
	options(0)
	var scene := MenuScene.create()
	check(scene != null, "real menu loads")
	if scene == null: return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(scene)
	scene.camera.current = true
	var count := 0
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if node.is_visible_in_tree(): count += 1
	check(count > 160, "menu has the actual figure, terrain and signpost meshes")
	var first: Image
	for mask in [0, 1, 3, 2, 6, 7, 5, 4, 0]:
		options(mask)
		var result := await compare("menu-" + str(mask))
		if first == null: first = result
		elif mask == 0: check(difference(first, result).changed_channels == 0, "returning to Original restores the frozen menu exactly")
	scene.free()
	await capture()

func texture(wound := false) -> ImageTexture:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var odd := ((x / 4 + y / 4) % 2) != 0
			var color := Color(0.7 if odd else 0.15, float(y) / 40.0, float(x) / 40.0, 1.0)
			if wound: color = Color(0.6, 0.04, 0.02, float(x) / 40.0)
			elif x < 3 or y < 3: color.a = 0.0
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func solid(value: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(value)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func controls() -> void:
	options(0)
	var root := Node3D.new()
	view.add_child(root)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 8)
	root.add_child(camera); camera.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.025, 0.04, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 25, 0)
	sun.light_specular = Gfx.SUN_MARK
	root.add_child(sun)
	RenderingServer.global_shader_parameter_set(&"ei_ambient", Vector3(0.3, 0.32, 0.35))
	RenderingServer.global_shader_parameter_set(&"ei_sun", Vector3(0.5, 0.55, 0.6))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", Vector3(0.3, 0.4, 1).normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(5, 24, 0))
	RenderingServer.global_shader_parameter_set(&"ei_fog_col", Vector3(0.25, 0.35, 0.45))
	# Four mapped lights, an overflow light, and a remake local light. Preserve
	# both the original max-colour path and the separate-pass approximations.
	for i in 6:
		var light := OmniLight3D.new()
		light.position = Vector3(-3 + i, 1.4, 2.5)
		light.omni_range = 7.0
		light.omni_attenuation = 0.0
		light.light_color = Color(0.7, 0.3 + i * 0.1, 0.3)
		light.light_energy = 0.2
		light.light_specular = 0.026 if i == 5 else 0.0
		light.shadow_enabled = i == 5
		root.add_child(light)
		if i < Gfx.PASS_LIGHTS:
			RenderingServer.global_shader_parameter_set(StringName("ei_pl%d" % i), Vector4(light.position.x, light.position.y, light.position.z, 7))
			RenderingServer.global_shader_parameter_set(StringName("ei_plc%d" % i), Vector4(0.35, 0.2, 0.15, 0))
	var albedo := texture()
	var wound := texture(true)
	var profile := solid(Color(0.7, 0.35, 0.6))
	var foliage := solid(Color(0.8, 0.5, 0))
	var materials: Array[ShaderMaterial] = []
	for source: String in [EIFigure.OBJECT_SHADER, EIFigure.FOLIAGE_SHADER, EIFigure.FOLIAGE_STILL_SHADER]:
		var material := ShaderMaterial.new()
		material.shader = Gfx.make_shader(source)
		material.set_shader_parameter("albedo_tex", albedo)
		material.set_shader_parameter("surface_profile", Vector4(0.7, 0.35, 0.6, 0.8))
		material.set_shader_parameter("foliage_mask", foliage)
		material.set_shader_parameter("ei_material_diffuse", Color(0.9, 0.85, 1, 0.9))
		material.set_shader_parameter("ei_material_emissive", Vector3(0.08, 0.015, 0.03))
		materials.append(material)
	for preview in [false, true]:
		for soft in [false, true]:
			var material := EIUnitModel._material(preview, soft) as ShaderMaterial
			material.albedo_texture = albedo
			material.wound_texture = wound
			material.set_shader_parameter("surface_tex", profile)
			materials.append(material)
	for i in materials.size():
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new() if i == 0 else QuadMesh.new()
		mesh.position = Vector3(-2.7 + (i % 4) * 1.8, 0.9 - (i / 4) * 1.8, 0)
		mesh.material_override = materials[i]
		root.add_child(mesh)
	var shaders := materials.map(func(m): return m.shader)
	var fade := CameraFade.dither_shader(shaders[3])
	var original_pixels: Image
	var enabled_pixels: Image
	for aa in [Viewport.MSAA_DISABLED, Viewport.MSAA_4X]:
		view.msaa_3d = aa
		sun.shadow_enabled = aa == Viewport.MSAA_4X
		Gfx.sync_sun_pass(sun)
		for mask in [0, 1, 3, 2, 6, 7, 5, 4, 0]:
			options(mask)
			var result := await compare("controls-%d-%d" % [aa, mask])
			if aa == Viewport.MSAA_DISABLED:
				if mask == 0: original_pixels = result
				if mask == 7: enabled_pixels = result
			for i in materials.size():
				check(materials[i].shader == shaders[i], "live material retains shader identity")
				check(materials[i].get_shader_parameter("albedo_tex") == albedo, "base texture survives option changes")
				if i >= 3: check(materials[i].wound_texture == wound, "wound texture survives option changes")
			check(CameraFade.dither_shader(shaders[3]) == fade and fade.code == CameraFade._dither_code(shaders[3].code), "camera-fade shader follows specialization")
			var unit := RenderingServer.shader_get_code(shaders[3].get_rid())
			var plant := RenderingServer.shader_get_code(shaders[1].get_rid())
			check(unit.contains("texelFetch") == bool(mask & 4), "disabled sharp sampling is absent before GPU compilation")
			check(unit.contains("uniform sampler2D surface_tex") == bool(mask & 1), "disabled unit surface sampler is absent")
			check(plant.contains("ei_relief_normal") == bool(mask & 1), "disabled relief functions are absent")
			check(plant.contains("uniform sampler2D foliage_mask") == bool(mask & 3), "foliage sampler follows both independent options")
			if mask & 1: check(materials[3].get_shader_parameter("surface_tex") == profile, "surface binding restores after absent uniform")
	check(difference(original_pixels, enabled_pixels).channels_over_one > 100, "enabled controls produce a visible change")
	# Quality-only updates also refresh world and both preview shader caches.
	options(0)
	GameData.options.gfx_sharp_units = 1
	Gfx.apply_quality(view)
	for i in range(3, 7):
		check(RenderingServer.shader_get_code(shaders[i].get_rid()).contains("texelFetch"), "quality-only update enables sharp sampling")
	GameData.options.gfx_sharp_units = 0
	Gfx.apply_quality(view)
	for i in range(3, 7):
		check(not RenderingServer.shader_get_code(shaders[i].get_rid()).contains("texelFetch"), "quality-only update removes sharp sampling")
	var changed := [0]
	var listener := func(): changed[0] += 1
	for shader: Shader in shaders: shader.changed.connect(listener)
	fade.changed.connect(listener)
	Gfx.apply_surface_options(); Gfx.apply_quality(view)
	check(changed[0] == 0, "unchanged settings do not recompile world, preview or fade shaders")
	# Cached shaders outlive this temporary fixture. Release its closure while
	# the script is alive, rather than leaving it for engine static teardown.
	for shader: Shader in shaders: shader.changed.disconnect(listener)
	fade.changed.disconnect(listener)
	var wounded := await capture()
	for i in range(3, 7): materials[i].wound_texture = null
	var healthy := await compare("healthy-0")
	check(difference(wounded, healthy).channels_over_one > 100, "wounds remain visible with compact Original shaders")
	for i in range(3, 7): materials[i].wound_texture = wound
	check(difference(wounded, await capture()).changed_channels == 0, "restoring wounds restores exact pixels")
	rows.append({"case":"preprocessed-original", "object_chars":RenderingServer.shader_get_code(shaders[0].get_rid()).length(), "unit_chars":RenderingServer.shader_get_code(shaders[3].get_rid()).length(), "foliage_chars":RenderingServer.shader_get_code(shaders[1].get_rid()).length()})
	root.free()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2); return
	check(Gfx._compact_figures == (OS.has_feature("android") and Portability.compatibility()), "shipping default is restricted to Android GLES")
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "q_aa":0, "q_shadows":0, "volume_sfx":0, "volume_stream":0, "volume_voice":0}, true)
	Gfx.ensure_globals(); Gfx.apply_surface_options(); Gfx.set_foliage_wind(false)
	Engine.time_scale = 0
	Engine.max_fps = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = SubViewport.new()
	view.size = Vector2i(640, 480)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.positional_shadow_atlas_size = 1024
	add_child(view)
	await menu()
	await controls()
	view.free()
	TexUpscale.shutdown(); UnitWounds.shutdown()
	for i in 4: await RenderingServer.frame_post_draw
	var result := {"checks":checks, "failures":failures.size(), "failure_labels":failures, "rows":rows, "gpu_readbacks":rendered, "renderer":RenderingServer.get_current_rendering_method(), "gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open("user://android-figure-compatibility.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("GRAPHICS_FIGURE_COMPATIBILITY ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
