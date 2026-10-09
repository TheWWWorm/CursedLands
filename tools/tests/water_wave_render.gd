extends "water_wave_field.gd"
## Freeze presentation except explicit terrain-clock/contact updates, so an
## empty field and off/restored controls compare the same rendered surface.

func render_case() -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var river := "--wave-river" in OS.get_cmdline_user_args()
	var t := EITerrain.load_map("zone8" if river else "zone1"); world.add_child(t); world.terrain=t; t.set_process(false)
	var p := centre(t)
	if river:
		var surface := Surface.new(t); surface.begin_frame(false)
		var hit := surface.sample(Vector2(160,-142))
		check(not hit.is_empty(),"authored sloping river surface found")
		p=Vector3(160,hit.height,-142)
	t._water_mat.set_shader_parameter("waves",0.0)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=p+Vector3(3,4,6); camera.look_at(p); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var owner := Interaction.new(); add_child(owner); owner.set_process(false)
	await frames(50)
	GameData.options["gfx_water_waves"]=0; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	var baseline := await snap(view,"wave-off")
	var draws := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	GameData.options["gfx_water_waves"]=1; t.apply_gfx(); owner.refresh(); owner.set_process(false); t._water_mat.set_shader_parameter("waves",0.0)
	check(difference(baseline,await snap(view,"wave-empty")).changed_pixels==0,"empty optional wave shader retains exact pixels")
	var u := unit(world,9101,p-Vector3(0,0.6,0))
	await frames(12)
	owner.step(world,camera,Field.STEP)
	for n in 36:
		u.position.x=p.x-0.6+(n+1)*0.03; u.reset_physics_interpolation()
		t._waves.advance(Field.STEP); t._update_wave_parameters()
		owner.step(world,camera,Field.STEP)
		if owner._field: await settle(owner._field)
	check(owner._field!=null and owner._field.steps_done>=30,"actual visible wader advances persistent field")
	check(not owner._contacts.is_empty(),"real posed actor touches the rendered water")
	var at := Vector2i(floori(p.x/Field.CELL),floori(p.z/Field.CELL))-owner._field.origin
	var domain_at := (at.y*Field.SIZE+at.x)*4
	check(owner._field.domain[domain_at+3]>0,"visible water belongs to the numerical domain")
	check(absf(owner._field.domain[domain_at]-p.y)<0.2,"field height follows the actual water triangle")
	u.hidden=true; u.hide()
	t._waves.advance(0.1); t._update_wave_parameters(); owner.step(world,camera,0.1)
	if owner._field: await settle(owner._field)
	check(owner._contacts.is_empty(),"hidden actor immediately stops pressure/contact admission")
	var lingering := await snap(view,"wave-lingering")
	var peak_trail := 0.0
	for i in Field.SIZE*Field.SIZE: peak_trail=maxf(peak_trail,owner._field.state[i*4+2])
	check(peak_trail>0.1,"source-free field retains a measurable stirred-water trail")
	check(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)==draws,"field retains the original water draw count")
	# Compare against the same option program with its field binding disabled.
	var window: Vector4=t._water_mat.get_shader_parameter("water_wave_window")
	t._water_mat.set_shader_parameter("water_wave_window",Vector4.ZERO)
	var none := await snap(view,"wave-history-control")
	var changed := difference(none,lingering)
	# Fast currents spread the faint trail over more pixels than still water.
	# The deterministic off binding is exact, so broad 1-2/255 changes count.
	check(changed.changed_pixels>100 and changed.peak_delta>=2,"ripples and stirred water remain visible after actor leaves")
	t._water_mat.set_shader_parameter("water_wave_window",window)
	check(difference(lingering,await snap(view,"wave-clock-held")).changed_pixels==0,"held clock preserves field and rendered water exactly")
	# The active history must not spill into alternate liquid branches.
	var original_shader := t._water_mat.shader
	var lava: PackedFloat32Array=t._water_mat.get_shader_parameter("lava")
	var forced := lava.duplicate(); forced.fill(1.0)
	t._water_mat.set_shader_parameter("lava",forced)
	t._water_mat.set_shader_parameter("water_wave_window",Vector4.ZERO)
	var lava_control := await snap(view,"wave-lava-control")
	t._water_mat.set_shader_parameter("water_wave_window",window)
	check(difference(lava_control,await snap(view,"wave-lava")).changed_pixels==0,"active field never changes lava")
	t._water_mat.set_shader_parameter("lava",lava)
	var cells: Texture2D=t._water_mat.get_shader_parameter("terrain_cells")
	var bog := cells.get_image()
	for y in bog.get_height():
		for x in bog.get_width():
			var color := bog.get_pixel(x,y); color.b=14; bog.set_pixel(x,y,color)
	t._water_mat.set_shader_parameter("terrain_cells",ImageTexture.create_from_image(bog))
	t._water_mat.set_shader_parameter("water_wave_window",Vector4.ZERO)
	var bog_control := await snap(view,"wave-swamp-control")
	t._water_mat.set_shader_parameter("water_wave_window",window)
	check(difference(bog_control,await snap(view,"wave-swamp")).changed_pixels==0,"active field never changes swamp")
	t._water_mat.set_shader_parameter("terrain_cells",cells)
	check(t._water_mat.shader==original_shader,"liquid guards use the same production program")
	var steps := owner._field.steps_done
	owner.step(world,camera,0.1) # positive callback dt, unchanged terrain clock
	check(owner._field.steps_done==steps,"controller follows terrain clock instead of callback time")
	var covered := Image.create(1,1,false,Image.FORMAT_RF); covered.fill(Color(1000,0,0))
	t.set_rain_cover(covered)
	check(t._water_mat.get_shader_parameter("rain_cover")==t._rain_cover,"new shader receives late rain-cover publication")
	# Test the existing pause/travel/movie scheduling contract with a live field.
	await scheduling(owner,world,camera)
	var weak := weakref(owner._field)
	GameData.options["gfx_water_waves"]=0; t.apply_gfx(); owner.refresh(); owner.set_process(false); t._water_mat.set_shader_parameter("waves",0.0)
	check(owner._field==null and weak.get_ref()==null and t._water_mat.get_shader_parameter("water_wave_field")==null,"disable releases numerical and GPU histories")
	var off := await snap(view,"wave-disabled")
	GameData.options["gfx_water_waves"]=1; t.apply_gfx(); owner.refresh(); owner.set_process(false); t._water_mat.set_shader_parameter("waves",0.0)
	check(difference(off,await snap(view,"wave-reenabled-empty")).changed_pixels==0,"re-enable starts empty with exact water appearance")
	rows.append({"case":"rendered-lingering","renderer":RenderingServer.get_current_rendering_method(),"map":t.map_name,"difference":changed,"peak_trail":peak_trail,"steps":steps,"focus":str(p)})
	owner.free(); world.erase_unit(u.uid); u.free(); view.free(); await frames(12)

func _ready() -> void:
	for key in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_biome_cover","gfx_vegetation_interaction","gfx_wind","gfx_water_caustics","gfx_water_current","gfx_water_waves","gfx_weather_surfaces","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; GameData.options["gfx_water_interaction"]=1
	GameData.options["gfx_water_current"]=int("--with-current" in OS.get_cmdline_user_args())
	GameData.options["fps_limit"]=3
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	await render_case()
	UnitWounds.shutdown(); TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://water-wave-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATER_WAVE_RENDER checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
