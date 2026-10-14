extends Node
## Rendered regression for an undefined reflection-camera marker in a shadow
## pass. Force that bit in the shader to make the engine's intermittent input
## deterministic; compare with an independent shader that has no clipping.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
const MARKER := "(CAMERA_VISIBLE_LAYERS & 1048576u) != 0u"
var checks := 0
var failures: Array[String] = []
var rows := []
var view: SubViewport
var camera: Camera3D
var sun: DirectionalLight3D
var model: EIUnitModel
var fence: Node3D
var sources := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)


func frames(count := 8) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func variant(kind: String, marked := true) -> void:
	for shader: Shader in sources:
		var code: String = sources[shader]
		if kind == "reference":
			code = code.replace(Reflection.CLIP, "")
		elif kind == "broken":
			code = code.replace("!IN_SHADOW_PASS && ", "")
		if kind != "reference":
			# Colour cameras still have their actual masks. Only the shadow
			# pass gets the arbitrary bit that 4.7 leaves uninitialized.
			code = code.replace(MARKER, "(IN_SHADOW_PASS || (" + MARKER + "))" if marked else "(!IN_SHADOW_PASS && (" + MARKER + "))")
		shader.code = code


func changed(a: Image, b: Image) -> int:
	var first: Image = a.duplicate()
	var second: Image = b.duplicate()
	first.resize(320, 240, Image.INTERPOLATE_NEAREST)
	second.resize(320, 240, Image.INTERPOLATE_NEAREST)
	var count := 0
	for y in 240:
		for x in 320:
			var ca := first.get_pixel(x, y)
			var cb := second.get_pixel(x, y)
			if maxf(absf(ca.r-cb.r), maxf(absf(ca.g-cb.g), absf(ca.b-cb.b))) > 0.025: count += 1
	return count


func capture(label: String) -> Image:
	await frames()
	var pixels := view.get_texture().get_image()
	check(pixels.save_png("user://reflection-shadow-" + label + ".png") == OK, "save " + label)
	return pixels


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("REFLECTION_SHADOW_INTEGRITY requires Forward+")
		get_tree().quit(2)
		return
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"auto_graphics":0, "gfx_detailed_heads":1, "q_aa":0, "q_shadows":2, "display_mode":0}, true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1024, 768)
	Engine.max_fps = 60
	RenderingServer.set_render_loop_enabled(true)
	view = SubViewport.new()
	view.size = Vector2i(1024, 768)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	Gfx.ensure_globals()
	Gfx.apply_quality(view)
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.mesh.size = Vector2(30, 30)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.8, 0.8)
	floor.material_override = material
	view.add_child(floor)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.2, 0.2, 0.2)
	view.add_child(env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 100
	view.add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 100
	camera.current = true
	view.add_child(camera)
	model = EIUnitModel.create({"prototype":"Human Hero"}, false)
	check(model != null, "original humanoid model loads")
	if model == null: get_tree().quit(1); return
	view.add_child(model)
	model.act("idle", 1, 0)
	model.set_process(false)
	model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.player.seek(0, true)
	model.flush_pending_pose()
	fence = Node3D.new()
	view.add_child(fence)
	# Fence geometry shares the production scenery shader's reflection clip.
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.2, 0.1))
	var fence_material := ShaderMaterial.new()
	fence_material.shader = Gfx.make_shader(EIFigure.FOLIAGE_SHADER)
	fence_material.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(image))
	fence_material.set_shader_parameter("wind", 0.0)
	for shape: Vector4 in [Vector4(-1, 1, 0.2, 2), Vector4(1, 1, 0.2, 2), Vector4(0, 0.5, 2.2, 0.15), Vector4(0, 1.2, 2.2, 0.15)]:
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		post.mesh.size = Vector3(shape.z, shape.w, 0.2)
		post.position = Vector3(shape.x, shape.y, 0)
		post.material_override = fence_material
		fence.add_child(post)
	for mesh: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
		var materials := [mesh.material_override]
		for i in mesh.mesh.get_surface_count(): materials.append(mesh.get_active_material(i))
		for mat: Material in materials:
			if mat is ShaderMaterial and mat.shader and mat.shader.code.contains(Reflection.CLIP):
				sources[mat.shader] = mat.shader.code
	check(sources.size() >= 2, "test uses production unit and scenery shader families")
	for subject: String in ["npc", "first-person", "fence"]:
		model.visible = subject != "fence"
		fence.visible = subject == "fence"
		model.set_first_person_view(subject == "first-person")
		for pose in 2:
			camera.position = Vector3(3 + pose, 4, 6)
			camera.look_at(Vector3(0, 0.8, 0))
			RenderingServer.global_shader_parameter_set(&"ei_water_mirror", Vector3(1.4, 0, 0))
			var label := subject + "-" + str(pose)
			variant("reference")
			var reference := await capture(label + "-reference")
			variant("fixed")
			var fixed := await capture(label + "-fixed")
			variant("broken")
			var broken := await capture(label + "-broken")
			variant("broken", false)
			var clear := await capture(label + "-clear")
			var fixed_delta := changed(reference, fixed)
			var broken_delta := changed(reference, broken)
			var clear_delta := changed(reference, clear)
			rows.append({"case":label, "fixed_changed":fixed_delta, "broken_changed":broken_delta, "clear_changed":clear_delta})
			check(fixed_delta == 0, label + " retains the complete reference shadow with the arbitrary marker set")
			check(broken_delta > 50, label + " reproduces clipped shadow with the old shader")
			check(clear_delta == 0, label + " old shadow returns when the arbitrary marker clears")
	for shader: Shader in sources: shader.code = sources[shader]
	RenderingServer.global_shader_parameter_set(&"ei_water_mirror", Vector3.ZERO)
	FileAccess.open("user://reflection-shadow-integrity.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "rows":rows}, "\t"))
	print("REFLECTION_SHADOW_INTEGRITY ", checks, " checks ", failures.size(), " failures ", rows)
	view.queue_free()
	await frames(10)
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
