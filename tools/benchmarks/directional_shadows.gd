extends Node
## Diagnostic only: frozen real-map pixels under continuous, 1/512-component
## snapped, and existing held sun directions. Direct lighting remains fixed to
## isolate shadow projection changes. No production policy is changed.
var view: SubViewport
var sun: DirectionalLight3D
var game: Game

func settle(frames: int = 3) -> void:
	for i in frames:
		RenderingServer.force_draw()
		await get_tree().process_frame

func pixels() -> Image:
	await settle()
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func changes(a: Image, b: Image) -> int:
	var aa := a.get_data()
	var bb := b.get_data()
	var count := 0
	for p in range(0, aa.size(), 4):
		for channel in 3:
			if absi(aa[p + channel] - bb[p + channel]) > 2:
				count += 1
				break
	return count

func save(p: Image, name: String) -> void:
	p.save_png("user://directional-shadows-" + RenderingServer.get_current_rendering_method() + "-" + name + ".png")

func snapped_direction(d: Vector3) -> Vector3:
	# R0 retained_static_submission.cpp:shadow_projection_lighting.
	return (d.normalized() * 512.0).round().normalized()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("DIRECTIONAL_SHADOWS requires a real renderer")
		get_tree().quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["gfx_volumetric"] = 0
	GameData.options["q_shadow_fit"] = 1
	GameData.options["gfx_far_view"] = 0
	view = SubViewport.new()
	view.size = Vector2i(480, 360)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var map := EIMapScene.load_map("bz13h", "bz13h", false)
	if map == null:
		get_tree().quit(2)
		return
	view.add_child(map)
	var focus := Vector3(88, map.terrain.height_at(88, 56), -56)
	var camera := Camera3D.new()
	camera.far = 100
	view.add_child(camera)
	camera.position = focus + Vector3(24, 22, 28)
	camera.look_at(focus + Vector3.UP * 2)
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.15, 0.15, 0.15)
	view.add_child(env)
	Gfx.ensure_globals()
	Gfx.set_light(Color(0.15, 0.15, 0.15), Color(0.7, 0.7, 0.7))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	sun = DirectionalLight3D.new()
	view.add_child(sun)
	sun.light_specular = Gfx.SUN_MARK
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 2.0 if Portability.held_sun() else 1.2
	Gfx.setup_sun_casters(sun)
	Gfx.sync_sun_pass(sun)
	Gfx.fit_shadows(sun, map.terrain.size_ei())
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	var shaders := {}
	for mesh: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material and material.shader and not shaders.has(material.shader):
			shaders[material.shader] = true
			material.shader.code = material.shader.code.replace("TIME", "1.25")
	game = Game.new() # Use the production aiming policy without starting gameplay.
	game._sun = sun
	game.sun_grid_lock = Portability.held_sun()
	var initial := Vector3(-0.4, -0.7, -0.5).normalized()
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", -initial)
	var rows := []
	for mode in ["continuous", "snap512", "held"]:
		game.sun_aim_mode = 0 if mode == "held" else 1
		game.reaim_sun()
		var previous: Image
		var first: Image
		var previous_direction := Vector3.ZERO
		var direction_changes := 0
		var counts := []
		var max_error := 0.0
		for step in 31:
			var exact := initial.rotated(Vector3.UP, deg_to_rad(step * 0.02))
			var direction := snapped_direction(exact) if mode == "snap512" else exact
			game._aim_sun(direction, false)
			max_error = maxf(max_error, rad_to_deg(game._held_sun.angle_to(exact)))
			if step == 0:
				await settle(8)
			var current := await pixels()
			if previous != null:
				counts.append(changes(previous, current))
				direction_changes += int(previous_direction != game._held_sun)
			else:
				first = current
				save(current, mode + "-first")
			previous = current
			previous_direction = game._held_sun
		save(previous, mode + "-last")
		var sorted := counts.duplicate()
		sorted.sort()
		rows.append({"mode": mode, "step_changed_pixels": counts,
				"median": sorted[15], "peak": sorted.back(), "direction_changes": direction_changes,
				"max_direction_error_degrees": max_error, "first_to_last": changes(first, previous)})
	# Control: changing the projected direction without shadows must not change
	# lighting, frozen foliage, fog, or terrain animation in this fixture.
	sun.shadow_enabled = false
	Gfx.sync_sun_pass(sun)
	game.sun_aim_mode = 1
	game._aim_sun(initial, false)
	var unshadowed_first := await pixels()
	game._aim_sun(initial.rotated(Vector3.UP, deg_to_rad(0.6)), false)
	var unshadowed_last := await pixels()
	print("DIRECTIONAL_SHADOWS ", JSON.stringify({"map": "bz13h", "rows": rows,
			"unshadowed_control_pixels": changes(unshadowed_first, unshadowed_last),
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
			"adapter": RenderingServer.get_video_adapter_name(), "atlas": 2048,
			"grid_lock": game.sun_grid_lock, "size": str(view.size)}))
	game.free()
	view.free()
	get_tree().quit()
