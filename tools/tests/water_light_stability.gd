extends "water_interaction.gd"
## Bounded reproducer for the open Adreno/Mobile held-water flicker. Keep exact
## comparisons: a stable clock/camera must not require a tolerance for pixels
## changing between sky-coloured water and the surface behind it.


func pipeline_counts() -> Vector2i:
	return Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))


func held_scene() -> void:
	var view := SubViewport.new(); view.size = Vector2i(640,480)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(view)
	var terrain := EITerrain.load_map("zone1"); view.add_child(terrain); terrain.set_process(false)
	var target := centre(terrain)
	var camera := Camera3D.new(); view.add_child(camera)
	camera.position = target+Vector3(3,4,6); camera.look_at(target); camera.current = true
	var camera_pose := camera.transform
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0)
	sun.shadow_enabled = true; view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	terrain._waves.set_wind(Vector3(1,1,1),1.0)
	terrain._waves.advance(9.17); terrain._update_wave_parameters()
	var ticks := terrain._waves.time_ticks()
	await frames(60)
	var states := [Vector2i(0,1),Vector2i(1,1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]
	for phase in states.size():
		var clouds: bool = states[phase].x != 0
		var materials: bool = states[phase].y != 0
		GameData.options["gfx_clouds"] = int(clouds)
		GameData.options["gfx_cloud_shadows"] = int(clouds)
		GameData.options["gfx_cloud_reflections"] = int(clouds)
		GameData.options["gfx_materials"] = int(materials)
		Gfx._set_vol_fog(false); terrain.apply_gfx()
		Gfx.set_surface_weather(0.8,0.9)
		RenderingServer.global_shader_parameter_set(&"ei_cloud_state",Vector4(0.5,0.28,160.0,1.0))
		RenderingServer.global_shader_parameter_set(&"ei_cloud_phases",Vector4(0.13,0.23,0.37,0.41))
		RenderingServer.global_shader_parameter_set(&"ei_cloud_noise",Gfx.noise("clouds",256,0.018,3))
		var shader := terrain._water_mat.shader
		var code := shader.code
		check(code.contains("global uniform sampler2D ei_cloud_noise") == clouds,"cloud consumer program matches phase "+str(phase))
		check(code.contains("if (1.0 > 0.5)") == materials,"material lighting is specialized for phase "+str(phase))
		FileAccess.open("user://water-light-stability-%d.gdshader"%phase,FileAccess.WRITE).store_string(code)
		# Allow background pipeline specialization to settle after each option
		# transition. Record counters as well; compilation is not pixel motion.
		await frames(240)
		var pipelines := [str(pipeline_counts())]
		var first: Image
		var last: Image
		var differences := []
		for frame in 8:
			var current := await snap(view,"light-stability-%d-%d"%[phase,frame])
			pipelines.append(str(pipeline_counts()))
			if first:
				var delta := difference(first,current)
				differences.append({"first":delta,"last":difference(last,current)})
				check(delta.changed_pixels == 0,"held water phase %d frame %d retains exact pixels"%[phase,frame])
			else: first = current
			last = current
		check(terrain._waves.time_ticks() == ticks and camera.transform == camera_pose and shader.code == code,"clock, camera and shader remain fixed in phase "+str(phase))
		rows.append({"phase":phase,"clouds":clouds,"materials":materials,"held":differences,
			"shader_sha256":code.sha256_text(),"ticks":ticks,"target":str(target),"pipelines":pipelines})
		print("WATER_LIGHT_HELD ",phase," ",JSON.stringify(differences))
	view.free(); await frames(12)


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"auto_graphics":0,"q_aa":0,"q_shadows":1,"vsync":0,"confine_mouse":0,
		"gfx_water":1,"gfx_water_reflections":2,"gfx_weather_surfaces":1,"gfx_materials":1,
		"gfx_water_interaction":1,"fps_limit":3},true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS; RenderingServer.set_render_loop_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	await held_scene()
	TexUpscale.shutdown(); await frames(12)
	var report := {"checks":checks,"failures":failures,"rows":rows,
		"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://water-light-stability.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATER_LIGHT_STABILITY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
