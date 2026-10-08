extends Node
## Shared Compatibility foliage uniforms must preserve per-part height,
## per-object camera fades, wind toggles, weak lifetime and rendered pixels.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func model() -> Node3D:
	return EIFigure.instantiate("nafltr56", "tree02", Vector3(0.5, 0.5, 0.5),
			PackedStringArray(), false, true)

func test_ownership() -> void:
	var a := model()
	var b := model()
	check(a != null and b != null, "real tree figures loaded")
	if a == null or b == null:
		return
	add_child(a)
	add_child(b)
	b.position.x = 20.0
	var am := a.find_children("*", "MeshInstance3D", true, false)
	var bm := b.find_children("*", "MeshInstance3D", true, false)
	check(am.size() > 0 and am.size() == bm.size(), "real tree parts present")
	for i in am.size():
		check(am[i].mesh == bm[i].mesh, "existing geometry sharing retained")
		check(am[i].material_override == bm[i].material_override, "identical placements share foliage material")
	var original: Material = am[0].material_override
	var fade := CameraFade.new()
	fade._nodes = [a, b]
	fade._meshes = [am, bm]
	fade._set_alpha(0, 0.5)
	check(am[0].material_override != original, "fading object owns a dither material")
	check(bm[0].material_override == original, "neighbor remains on its original material")
	if Portability.compatibility():
		check(am[0].material_override.get_shader_parameter("cam_fade") == 0.5, "individual fade reaches shader")
	fade._set_alpha(0, 0.0)
	check(am[0].material_override == original, "fade completion rejoins shared material")
	a.free()
	b.free()

func test_variants() -> void:
	var base := EIFigure.foliage_material_for("tree02", true, false, 18) as ShaderMaterial
	var first := EIFigure.foliage_variant(base, 0.25)
	check(first == EIFigure.foliage_variant(base, 0.25), "same base and exact height reuse variant")
	check(first.get_shader_parameter("part_y") == 0.25, "part offset supplied")
	var close := EIFigure.foliage_variant(base, 0.2500000001)
	check(close != first, "nearby heights never merge through string rounding")
	check(close.get_shader_parameter("part_y") == 0.2500000001, "exact alternate height retained")
	for other: ShaderMaterial in [
			EIFigure.foliage_material_for("tree02", false, false, 18),
			EIFigure.foliage_material_for("tree02", true, true, 18),
			EIFigure.foliage_material_for("tree02", true, false, 19),
			EIFigure.foliage_material_for("tree04", true, false, 18)]:
		check(EIFigure.foliage_variant(other, 0.25) != first, "different base look stays separate")
	var still := EIFigure.foliage_variant(EIFigure.foliage_material_for("tree02", false, false, 18), 0.25)
	EIFigure.set_wind(false)
	check(first.get_shader_parameter("wind") == 1.0 and still.get_shader_parameter("wind") == 0.0, "wind switch preserves authored strengths for material copies")
	EIFigure.set_wind(true)
	check(first.get_shader_parameter("wind") == 1.0 and still.get_shader_parameter("wind") == 0.0, "wind restores authored sway eligibility")
	var transient := EIFigure.foliage_variant(base, 123.0)
	var ref: WeakRef = weakref(transient)
	transient = null
	check(ref.get_ref() == null, "cache does not keep unused material alive")
	EIFigure.set_wind(true)
	check(not EIFigure._foliage_local[base].has(123.0), "wind update prunes dead variant keys")
	EIFigure.clear_cache()
	check(EIFigure._foliage_local.is_empty(), "data-source switch clears variants")
	check(first.get_shader_parameter("part_y") == 0.25, "clearing cache does not mutate live owners")
	check(EIFigure.foliage_variant(base, 0.25) != first, "new cache cannot reuse stale variant")

func render_comparison() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 30
	var views: Array[SubViewport] = []
	for control in [true, false]:
		var view := SubViewport.new()
		view.size = Vector2i(384, 384)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		views.append(view)
		var camera := Camera3D.new()
		view.add_child(camera)
		camera.position = Vector3(6, 5, 12)
		camera.look_at(Vector3(0, 2, 0))
		camera.current = true
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, -35, 0)
		view.add_child(sun)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.12, 0.16, 0.2)
		view.add_child(env)
		for i in 9:
			var tree := model()
			view.add_child(tree)
			tree.position = Vector3((i % 3 - 1) * 2.0, 0, (i / 3 - 1) * 2.0)
			for mesh: MeshInstance3D in tree.find_children("*", "MeshInstance3D", true, false):
				# Freeze the shared shader's wind clock for a pixel comparison.
				var material := mesh.material_override as ShaderMaterial
				material.shader.code = material.shader.code.replace("TIME", "1.25")
				if control:
					mesh.material_override = material.duplicate()
	for i in 8:
		RenderingServer.force_draw()
		await get_tree().process_frame
	var before := views[0].get_texture().get_image()
	var after := views[1].get_texture().get_image()
	check(before.get_data() == after.get_data(), "GPU pixels equal independent per-mesh material copies")
	var colors := {}
	for pixel in before.get_data():
		colors[pixel] = true
	check(colors.size() > 20, "GPU comparison contains rendered figure detail")
	var method := RenderingServer.get_current_rendering_method()
	check(after.save_png("user://foliage-materials-" + method + ".png") == OK, "comparison capture saved")
	print("FOLIAGE_GPU ", JSON.stringify({"renderer": method, "equal": before.get_data() == after.get_data(),
			"control_draws": views[0].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"shared_draws": views[1].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}))
	for view in views:
		view.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	GameData.options["gfx_hd_textures"] = 0
	test_ownership()
	test_variants()
	if DisplayServer.get_name() != "headless":
		await render_comparison()
	print("FOLIAGE_MATERIALS ", JSON.stringify({"checks": checks, "failures": failures,
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor")}))
	get_tree().quit(1 if failures else 0)
