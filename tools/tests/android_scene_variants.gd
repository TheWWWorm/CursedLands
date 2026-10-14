extends "./android_figure_compatibility.gd"
## Engine comparison fixture. Run the same frozen pack on both GLES engines;
## compare every capture hash, not only the figure-specialization pairs.
## The base fixture must be in this directory when installed in a QA profile.
var captures: Array[Dictionary] = []

func capture() -> Image:
	for child in view.get_children():
		if child is MenuScene: child.set_hour(12.0)
	var image: Image = await super.capture()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	var filename := "engine-%02d.png" % rendered
	image.save_png("user://"+filename)
	captures.append({"file":filename,"sha256":hash.finish().hex_encode()})
	return image

func engine_modes() -> void:
	print("EI_ENGINE_MODES_BEGIN")
	view.msaa_3d = Viewport.MSAA_DISABLED
	var root := Node3D.new()
	view.add_child(root)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(7, 6, 8)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.15
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var shader := Shader.new()
	var code := "shader_type spatial; uniform vec4 colour: source_color = vec4(0.8,0.15,0.4,1.0); void fragment() { ALBEDO=colour.rgb; ROUGHNESS=0.8; }"
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	var floor_material := ShaderMaterial.new()
	floor_material.shader = shader
	floor_material.set_shader_parameter("colour", Color(0.55, 0.65, 0.75))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	ground.position.y = -0.6
	ground.material_override = floor_material
	root.add_child(ground)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.material_override = material
	root.add_child(mesh)
	var ordinary := await capture()
	print("EI_ENGINE_MODES_INSTANCED")
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = MultiMesh.new()
	instances.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instances.multimesh.mesh = BoxMesh.new()
	instances.multimesh.instance_count = 2
	instances.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(-2, 0, -0.5)))
	instances.multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0.5)))
	instances.material_override = material
	root.add_child(instances)
	var instanced := await capture()
	check(difference(ordinary, instanced).channels_over_one > 100, "instanced colour mode renders visible instances")
	print("EI_ENGINE_MODES_DEPTH")
	sun.shadow_enabled = true
	var shadowed := await capture()
	check(difference(instanced, shadowed).channels_over_one > 100, "ordinary and instanced depth modes render visible shadows")
	var omni := OmniLight3D.new()
	omni.position = Vector3(1, 3, 2)
	omni.omni_range = 10
	omni.light_energy = 0.6
	omni.shadow_enabled = true
	root.add_child(omni)
	var spot := SpotLight3D.new()
	root.add_child(spot)
	spot.position = Vector3(-2, 4, 3)
	spot.look_at(Vector3.ZERO)
	spot.spot_range = 12
	spot.light_energy = 0.8
	spot.shadow_enabled = true
	var lit := await capture()
	check(difference(shadowed, lit).channels_over_one > 100, "omni and spot specializations render visible lighting")
	shader.code = code.replace("colour.rgb", "colour.bgr")
	var altered := await capture()
	check(difference(lit, altered).channels_over_one > 100, "live shader code change reaches colour and instanced draws")
	shader.code = code
	check(difference(lit, await capture()).changed_channels == 0, "restoring shader code restores exact pixels")
	root.free()
	print("EI_ENGINE_MODES_END")


func _run() -> void:
	seed(0)
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
	await engine_modes()
	view.free()
	TexUpscale.shutdown(); UnitWounds.shutdown()
	for i in 4: await RenderingServer.frame_post_draw
	var result := {"checks":checks, "failures":failures.size(), "failure_labels":failures, "rows":rows, "gpu_readbacks":rendered,"captures":captures, "renderer":RenderingServer.get_current_rendering_method(), "gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open("user://android-scene-variants.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("ANDROID_SCENE_VARIANTS ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
