extends Node
## Compare a live managed world with an independently rendered, never-batched
## control world. Mutations exercise real transform/visibility/light signals.
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var fixtures: Array[Dictionary] = []
var manager: SceneryBatches
var base: ShaderMaterial
var shared_mesh: BoxMesh
var compatible := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func material(colour: Color) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = Gfx.make_shader(EIFigure.OBJECT_SHADER.replace("TIME", "1.25"))
	result.set_meta("ground_contact_source", EIFigure.OBJECT_SHADER)
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8); pixels.fill(colour)
	result.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(pixels))
	return result

func object(parent: Node3D, x: float, kind := "OBJECT", template := "stone") -> Node3D:
	var root := Node3D.new(); root.set_meta("ei", {"kind":kind, "template":template})
	root.position = Vector3(x, 1, -4); parent.add_child(root)
	var mesh := MeshInstance3D.new(); mesh.mesh = shared_mesh; mesh.material_override = base
	root.add_child(mesh)
	return root

func fixture() -> Dictionary:
	var view := SubViewport.new(); view.size = Vector2i(512, 256); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.11, 0.04, 0.13)
	view.add_child(environment)
	var map := Node3D.new(); view.add_child(map)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28; view.add_child(camera)
	camera.position = Vector3(12, 12, 22); camera.look_at(Vector3(12, 1, -4)); camera.current = true
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -35, 0)
	view.add_child(sun)
	var roots: Array[Node3D] = []; var meshes: Array[MeshInstance3D] = []
	var fade := CameraFade.new()
	for x in [1, 4, 7, 10, 13, 18, 21, 24]:
		var root := object(map, x); roots.append(root)
		meshes.append(root.get_child(0)); fade._nodes.append(root); fade._meshes.append([root.get_child(0)])
	return {"view":view, "map":map, "camera":camera, "sun":sun, "roots":roots, "meshes":meshes, "fade":fade, "lights":[]}

func difference(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var first := a.get_data(); var second := b.get_data(); var changed := 0; var peak := 0
	for p in range(0, first.size(), 4):
		var delta := 0
		for c in 3: delta = maxi(delta, absi(first[p + c] - second[p + c]))
		peak = maxi(peak, delta); changed += int(delta > 2)
	return {"pixels_over_2":changed, "peak_byte_difference":peak}

func frame(label: String, count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		RenderingServer.force_draw()
		var control: Image = fixtures[0].view.get_texture().get_image()
		var managed: Image = fixtures[1].view.get_texture().get_image()
		var delta := difference(control, managed)
		var draws: Array[int] = []
		for item: Dictionary in fixtures:
			draws.append(item.view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		rows.append({"case":label, "frame":i, "difference":delta, "draws":draws, "batches":manager._batches.size(),
			"update_usec":manager.last_update_usec, "rebuilt_groups":manager.last_rebuilt_groups})
		check(delta.pixels_over_2 == 0, label + " frame " + str(i) + " " + JSON.stringify(delta))
		if delta.pixels_over_2 > 0 or label == "initial":
			control.save_png("user://scenery-runtime-" + label + "-" + str(i) + "-control.png")
			managed.save_png("user://scenery-runtime-" + label + "-" + str(i) + "-managed.png")

func add_light(position: Vector3, reach: float) -> void:
	for item: Dictionary in fixtures:
		var light := OmniLight3D.new(); light.omni_range = reach; light.position = position
		light.light_energy = 3; light.light_color = Color(0.2, 0.7, 1); light.light_specular = Gfx.LOCAL_SPECULAR
		item.map.add_child(light); item.lights.append(light)

func lifecycle() -> void:
	await frame("initial", 3)
	check(manager._batches.size() == (2 if compatible else 0), "only Compatibility groups the two cells")
	for mesh: MeshInstance3D in fixtures[1].meshes:
		check(mesh.visible and mesh.is_visible_in_tree(), "logical scenery visibility remains intact")
	for item: Dictionary in fixtures:
		item.camera.position += Vector3(8, 4, -5)
		item.camera.look_at(Vector3(12, 1, -4))
	await frame("camera_moved", 3)
	var idle: Array[int] = []
	var before := manager.rebuilds
	for i in 80:
		manager.flush(); idle.append(manager.last_update_usec)
	idle.sort()
	check(manager.rebuilds == before, "idle frames do not rebuild")
	rows.append({"case":"idle", "samples":idle.size(), "median_usec":idle[idle.size() / 2], "max_usec":idle.back()})
	# Deferred transform notifications must remove the old instance on the first
	# drawn frame, including inherited movement and a different spatial cell.
	for item: Dictionary in fixtures: item.roots[0].position += Vector3(17, 0.5, -2)
	await frame("move_between_cells", 3)
	check(manager._entries[fixtures[1].meshes[0].get_instance_id()].batch == 0, "moved object retains original interpolation")
	for item: Dictionary in fixtures: item.roots[1].hide()
	await frame("hide", 2)
	for item: Dictionary in fixtures: item.roots[1].show()
	await frame("show", 2)
	for item: Dictionary in fixtures: item.fade._set_alpha(2, 0.375)
	await frame("fade_start", 2)
	before = manager.rebuilds
	for item: Dictionary in fixtures: item.fade._set_alpha(2, 0.625)
	await frame("fade_continues", 2)
	check(manager.rebuilds == before, "ongoing fade does not churn batches")
	var replacement := material(Color(0.05, 0.85, 0.12))
	for item: Dictionary in fixtures: GroundContact._replace(item.meshes[2], replacement)
	await frame("material_while_fading", 2)
	for item: Dictionary in fixtures: item.fade._set_alpha(2, 0.0)
	await frame("fade_restore", 2)
	for item: Dictionary in fixtures: GroundContact._replace(item.meshes[2], base)
	await frame("material_restore", 2)
	shared_mesh.size = Vector3(1.8, 2.4, 1.4)
	await frame("mesh_resource_changed", 3)
	for item: Dictionary in fixtures:
		SceneryBatches.changed(item.meshes[3]); item.meshes[3].layers = 2
	await frame("render_state_changed", 2)
	for item: Dictionary in fixtures:
		SceneryBatches.changed(item.meshes[3]); item.meshes[3].layers = 1
	await frame("render_state_restored", 2)
	# Both worlds have visually equal lights but distinct instance IDs. Only the
	# managed world's lights may appear in its membership snapshots.
	add_light(Vector3(12, 5, -4), 35)
	await frame("new_light", 3)
	check(manager._light_rows.size() == 1, "only own-world local lights are tracked")
	before = manager.rebuilds
	for item: Dictionary in fixtures: item.lights[0].position += Vector3(0.1, 0, 0)
	await frame("same_light_membership", 2)
	check(manager.rebuilds == before, "moving light with the same membership retains draw objects")
	for item: Dictionary in fixtures: item.lights[0].light_energy = 12
	await frame("energy_only", 3)
	check(manager.rebuilds == before, "energy-only changes preserve pairing history")
	for item: Dictionary in fixtures: item.lights[0].omni_range = 7
	await frame("range", 3)
	for item: Dictionary in fixtures: item.lights[0].position += Vector3(7, 0, 0)
	await frame("moving_light", 3)
	for item: Dictionary in fixtures: item.lights[0].hide()
	await frame("light_hidden", 2)
	for item: Dictionary in fixtures: item.lights[0].show()
	await frame("light_shown", 2)
	for item: Dictionary in fixtures: item.lights[0].free(); item.lights.clear()
	await frame("light_freed", 3)
	# More than the startup per-object budget must fall back to originals.
	for i in manager._limit + 1: add_light(Vector3(12, 4 + i * 0.2, -4), 45)
	await frame("over_light_budget", 3)
	check(manager._batches.is_empty(), "truncated light lists retain original instances")
	for item: Dictionary in fixtures:
		for light: Light3D in item.lights: light.free()
		item.lights.clear()
	await frame("budget_cleared", 3)
	var probe := ReflectionProbe.new(); fixtures[1].map.add_child(probe)
	probe.cull_mask = 0; probe.intensity = 0
	await frame("probe_fallback", 2)
	check(manager._batches.is_empty(), "unmodeled reflection volume disables grouping")
	probe.free()
	await frame("probe_removed", 2)
	for item: Dictionary in fixtures:
		item.roots[4].reparent(item.view)
	await frame("reparent_outside_map", 3)
	for item: Dictionary in fixtures:
		item.roots[4].reparent(item.map)
	await frame("reparent_back", 3)
	for item: Dictionary in fixtures: item.roots[5].queue_free()
	await frame("object_deleted", 3)
	for item: Dictionary in fixtures:
		var root := object(item.map, 20); item.roots.append(root)
		if item == fixtures[1]: manager.register(root)
	await frame("object_created", 3)
	manager.set_enabled(false)
	await frame("disabled", 3)
	check(manager._batches.is_empty(), "off restores original renderer")
	manager.set_enabled(true)
	await frame("enabled", 3)
	for item: Dictionary in fixtures: item.map.position = Vector3(0, 0, 1)
	await frame("parent_transform", 3)
	check(manager._batches.is_empty(), "inherited movement also restores original instances")
	var parent := manager.get_parent(); parent.remove_child(manager)
	await frame("manager_detached", 2)
	parent.add_child(manager)
	await frame("manager_reattached", 3)
	check(manager._batches.size() > 0 if compatible else manager._batches.is_empty(), "manager re-entry observes remaining roots")
	var observer := (fixtures[1].meshes[0].get_meta(SceneryBatches.WATCH) as WeakRef).get_ref() as Node
	var observer_ref: WeakRef = weakref(observer); var manager_ref: WeakRef = weakref(manager)
	manager.free(); manager = null
	await get_tree().process_frame
	check(manager_ref.get_ref() == null and observer_ref.get_ref() == null, "manager teardown releases watchers")
	check(not fixtures[1].meshes[0].has_meta(SceneryBatches.WATCH), "teardown clears mesh hook")
	RenderingServer.force_draw()
	check(difference(fixtures[0].view.get_texture().get_image(), fixtures[1].view.get_texture().get_image()).pixels_over_2 == 0,
		"manager teardown restores final pixels")

func cached_bounds_boundary() -> void:
	# A group initially ends before x=25. Resize its shared mesh so it reaches
	# x=29, then introduce an over-budget light set at x=28. Reusing the old
	# union would miss the lights and leave the enlarged end pieces batched.
	shared_mesh = BoxMesh.new(); shared_mesh.size = Vector3(1.5, 2, 1.5)
	fixtures = [fixture(), fixture()]
	manager = SceneryBatches.create(fixtures[1].map, fixtures[1].roots)
	add_light(Vector3(100, 100, 100), 1)
	await frame("bounds_seed", 2)
	shared_mesh.size = Vector3(10, 2, 1.5)
	await frame("bounds_expanded", 2)
	for i in manager._limit + 1: add_light(Vector3(28, 1 + i * 0.2, -4), 2.2)
	await frame("bounds_new_edge_lights", 3)
	check(manager._entries[fixtures[1].meshes[7].get_instance_id()].batch == 0,
		"lights beyond the previous bounds restore the enlarged end piece")
	check(manager._batches.size() == (1 if compatible else 0), "only the unaffected cell remains batched")
	for item: Dictionary in fixtures: item.view.free()
	fixtures.clear(); manager = null
	await get_tree().process_frame

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("SCENERY_RUNTIME needs a real renderer"); get_tree().quit(2); return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	GameData.options["gfx_hd_textures"] = 0; GameData.options["gfx_volumetric"] = 0
	GameData.options["gfx_materials"] = 0; GameData.options["gfx_ground_contact"] = 0
	Gfx.set_light(Color.WHITE, Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(100, 200, 0))
	compatible = Portability.compatibility()
	base = material(Color(0.65, 0.24, 0.08))
	shared_mesh = BoxMesh.new(); shared_mesh.size = Vector3(1.5, 2, 1.5)
	fixtures = [fixture(), fixture()]
	manager = SceneryBatches.create(fixtures[1].map, fixtures[1].roots)
	await lifecycle()
	for item: Dictionary in fixtures: item.view.free()
	fixtures.clear()
	await cached_bounds_boundary()
	CameraFade._derived.clear(); CameraFade._shaders.clear()
	base = null; shared_mesh = null
	RenderingServer.force_draw()
	await get_tree().process_frame
	var report := {"checks":checks, "failures":failures, "rows":rows, "renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://scenery-runtime-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SCENERY_RUNTIME checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
