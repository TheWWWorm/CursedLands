extends "water_wave_field.gd"
## Actual water programs with all optional samplers, including depth/SSR and
## cloud composition. Compare captures across builds; retain strict empty
## history controls on the smallest tested GLES texture budget.
var legacy := "--legacy-water" in OS.get_cmdline_user_args()
var measured := "--water-timing" in OS.get_cmdline_user_args()


func prepare_material(_terrain: EITerrain) -> void:
	pass # Device source-substitution fixtures override only this boundary.


func texture_data(material: ShaderMaterial) -> void:
	if not Portability.compatibility() or legacy: return
	var table: Texture2D = material.get_shader_parameter("water_tables")
	var noise: Texture2DArray = material.get_shader_parameter("water_noise")
	check(table != null and noise != null,"packed resources are bound by terrain")
	if table == null or noise == null: return
	var expected := EITerrain.wave_sine_texture().get_image().get_data()
	expected.append_array(EITerrain.wave_phase_texture().get_image().get_data())
	check(table.get_image().get_data() == expected,"GPU float tables retain all 1536 source values exactly")
	var sources := [Gfx.noise("wave_a",256,0.018,4,true,5.0),Gfx.noise("wave_b",256,0.03,3,true,4.0),Gfx.noise("foam",256,0.03,4)]
	for i in 3:
		var original: Image = sources[i].get_image().duplicate()
		original.convert(Image.FORMAT_RGB8)
		check(noise.get_layer_data(i).get_data()==original.get_data(),"GPU noise layer "+str(i)+" retains every source texel and mip")


func sample_cost(view: SubViewport, label: String) -> Dictionary:
	if not measured: return {}
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	await frames(32)
	var gpu := []; var cpu := []; var wall := []
	var previous := Time.get_ticks_usec()
	for i in 96:
		await frames(1)
		var now := Time.get_ticks_usec()
		wall.append((now-previous)/1000.0); previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
	print("WATER_BUDGET_TIMING ",label)
	return {"gpu_ms":distribution(gpu),"cpu_ms":distribution(cpu),"wall_ms":distribution(wall)}


func scene(map_name: String) -> void:
	var view := SubViewport.new(); view.size=Vector2i(1280,720) if measured else Vector2i(640,480)
	view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(view)
	var t := EITerrain.load_map(map_name); view.add_child(t); t.set_process(false)
	var p := centre(t)
	if map_name=="zone8":
		var surface := Surface.new(t); surface.begin_frame(false)
		p=Vector3(160,surface.sample(Vector2(160,-142)).height,-142)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=p+Vector3(3,4,6); camera.look_at(p); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.shadow_enabled=true; view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	Gfx.set_surface_weather(0.8,0.9)
	t._waves.set_wind(Vector3(1,1,1),1.0); t._waves.advance(9.17); t._update_wave_parameters()
	await frames(60)
	var history := Image.create(128,128,false,Image.FORMAT_RGBAF)
	for y in 128:
		for x in 128: history.set_pixel(x,y,Color(sin(x*0.25)*0.1,0,0.5,p.y))
	var field := ImageTexture.create_from_image(history)
	var table: Variant; var noise: Variant
	for clouds in [0,1,2,3]:
		GameData.options["gfx_clouds"]=int(clouds!=0)
		GameData.options["gfx_cloud_shadows"]=clouds&1
		GameData.options["gfx_cloud_reflections"]=(clouds>>1)&1
		Gfx._set_vol_fog(false)
		var empty_controls := {}
		for mode in 6:
			if measured and (clouds not in [0,3] or mode not in [0,5]): continue
			GameData.options["gfx_water_current"]=int(mode in [2,3,5])
			GameData.options["gfx_water_interaction"]=int(mode in [1,3,4,5])
			GameData.options["gfx_water_waves"]=int(mode in [4,5])
			t.apply_gfx(); prepare_material(t)
			if t._current:
				for i in 600:
					t._current.poll()
					if t._current._job==null: break
					await get_tree().process_frame
			Gfx.set_surface_weather(0.8,0.9)
			RenderingServer.global_shader_parameter_set(&"ei_cloud_state",Vector4(0.5,0.28,160.0,1.0))
			RenderingServer.global_shader_parameter_set(&"ei_cloud_phases",Vector4(0.13,0.23,0.37,0.41))
			RenderingServer.global_shader_parameter_set(&"ei_cloud_noise",Gfx.noise("clouds",256,0.018,3))
			t._water_mat.set_shader_parameter("water_wave_window",Vector4.ZERO)
			var code := t._water_mat.shader.code
			check(code.contains("global uniform sampler2D ei_cloud_noise")==(clouds!=0),"cloud sampler follows the actual composed program")
			var samplers := 0
			for match_ in RegEx.create_from_string("(?:global )?uniform sampler[^;]+;").search_all(code):
				if not "hint_depth_texture" in match_.get_string() and not "hint_screen_texture" in match_.get_string(): samplers+=1
			if Portability.compatibility() and not legacy:
				check(samplers<=9,"water leaves GLES scene depth and screen slots available")
			var label := map_name+"-cloud"+str(clouds)+"-mode"+str(mode)
			var empty := await snap(view,"budget-"+label+"-empty")
			if mode in [1,3]: empty_controls[mode]=empty
			if mode in [4,5] and not measured:
				check(difference(empty_controls[1 if mode==4 else 3],empty).changed_pixels==0,"empty history retains exact depth/SSR with all options: "+label)
			if mode in [4,5]:
				t._water_mat.set_shader_parameter("water_wave_field",field)
				t._water_mat.set_shader_parameter("water_wave_window",Vector4(p.x-16,p.z-16,1.0/32.0,1.0))
				await snap(view,"budget-"+label+"-active")
			var cost := await sample_cost(view,label)
			rows.append({"map":map_name,"clouds":clouds,"mode":mode,"samplers":samplers,"cost":cost})
			if Portability.compatibility() and not legacy:
				if table==null:
					table=t._water_mat.get_shader_parameter("water_tables"); noise=t._water_mat.get_shader_parameter("water_noise")
					texture_data(t._water_mat)
				else:
					check(table==t._water_mat.get_shader_parameter("water_tables") and noise==t._water_mat.get_shader_parameter("water_noise"),"settings reuse shared water textures")
	view.free(); await frames(12)


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"q_aa":0,"q_shadows":1,"vsync":0,"confine_mouse":0,
		"gfx_water":1,"gfx_water_reflections":2,"gfx_weather_surfaces":1,"gfx_materials":1,"fps_limit":0 if measured else 3},true)
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=0 if measured else 120
	process_mode=Node.PROCESS_MODE_ALWAYS; RenderingServer.set_render_loop_enabled(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	for map_name: String in ["zone1","zone8"]: await scene(map_name)
	TexUpscale.shutdown(); await frames(12)
	var report := {"checks":checks,"failures":failures,"rows":rows,"legacy":legacy,
		"renderer":RenderingServer.get_current_rendering_method(),"measured":measured}
	FileAccess.open("user://water-sampler-budget.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATER_SAMPLER_BUDGET checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
