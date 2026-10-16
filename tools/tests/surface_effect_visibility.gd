extends "water_interaction.gd"
## Paired native-texture controls from the raised camera, with/without HD Lands.

func capture(view: SubViewport, label: String) -> Image:
	await frames(6)
	var image := view.get_texture().get_image()
	image.save_png("user://surface-" + label + ".png")
	return image

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"auto_graphics":0,"gfx_water":1,"gfx_water_reflections":0,
		"gfx_weather_surfaces":1,"gfx_materials":1,"marks":1,"footprints":1,"q_aa":0,
		"q_shadows":0,"vsync":0,"confine_mouse":0,"fps_limit":0}, true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS; RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var view := SubViewport.new(); view.size = Vector2i(1280,720); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.current = true; camera.fov = 50
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.15,.25,.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(.5,.5,.5), Color(.75,.75,.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_sky", Color(.45,.55,.65))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(180,260,0))
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var terrain := EITerrain.load_map("zone1"); world.add_child(terrain); terrain.set_process(false); world.terrain = terrain
	terrain._water_mat.set_shader_parameter("waves", 0.0)
	terrain._waves.advance(7.37); terrain._update_wave_parameters()
	var point := centre(terrain)
	for distance: float in [12.0,24.0,45.0,60.0,72.0]:
		camera.position = point + Vector3(0,.75,.661438) * distance; camera.look_at(point)
		Gfx.set_surface_weather(1.0, 0.0)
		var dry := await capture(view,"water-%.0f-dry" % distance)
		Gfx.set_surface_weather(1.0, 1.0)
		var rain := await capture(view,"water-%.0f-rain" % distance)
		var d := difference(dry,rain)
		rows.append({"kind":"rain","distance":distance,"difference":d,"point":str(point)})
		print("RAIN_DISTANCE ",distance," ",JSON.stringify(d))
		check(d.peak_delta >= 6 and d.pixels_over_2 >= 1000,"resolved water rain visible at %.0f metres" % distance)
	# Shelter and the weather-surfaces setting must suppress the new crest
	# as well as the original slope. Compare actual rendered water pixels.
	var cover: Texture2D = terrain._water_mat.get_shader_parameter("rain_cover")
	var covered := Image.create(1,1,false,Image.FORMAT_RF); covered.fill(Color(10000,0,0,1))
	terrain._water_mat.set_shader_parameter("rain_cover",ImageTexture.create_from_image(covered))
	Gfx.set_surface_weather(1,0); var sheltered_dry := await capture(view,"sheltered-dry")
	Gfx.set_surface_weather(1,1); var sheltered_rain := await capture(view,"sheltered-rain")
	check(difference(sheltered_dry,sheltered_rain).changed_pixels==0,"sheltered water has no rain rings")
	terrain._water_mat.set_shader_parameter("rain_cover",cover)
	RenderingServer.global_shader_parameter_set(&"ei_surface_fx",Vector3(1,1,0))
	Gfx.set_surface_weather(1,0); var disabled_dry := await capture(view,"disabled-dry")
	Gfx.set_surface_weather(1,1); var disabled_rain := await capture(view,"disabled-rain")
	check(difference(disabled_dry,disabled_rain).changed_pixels==0,"weather-surfaces option suppresses rain rings")
	RenderingServer.global_shader_parameter_set(&"ei_surface_fx",Vector3.ONE)
	Gfx.set_surface_weather(0,0)
	var marks := GroundMarks.of(world); marks.set_process(false)
	for texture: String in ["footprints","footprints1","footprints2","bloodprints"]:
		var image := GameData.load_image(texture); image.save_png("user://"+texture+".png")
		var original := GameData.load_original_image(texture)
		print("MARK_TEXTURE ",texture," size=",image.get_size()," original=",original.get_size()," identical=",image.get_data()==original.get_data())
	# Open dry ground near the river, so terrain and lighting are unchanged.
	var at := Vector2.ZERO
	var score := INF
	for y in range(8, int(terrain.size_ei().y)-8, 8):
		for x in range(8, int(terrain.size_ei().x)-8, 8):
			var suitable := true
			for dy in [-4,0,4]:
				for dx in [-1,0,1]:
					if terrain.mark_ground(x+dx,y+dy) != 0: suitable = false
			if suitable and Vector2(x,y).distance_squared_to(terrain.size_ei()*.5) < score:
				score = Vector2(x,y).distance_squared_to(terrain.size_ei()*.5); at = Vector2(x,y)
	check(at != Vector2.ZERO, "dry grass footprint site")
	point = Vector3(at.x, terrain.height_at(at.x,at.y), -at.y)
	print("MARK_ROWS ",JSON.stringify(marks._tables)," ground=",terrain.mark_ground(at.x,at.y))
	for distance: float in [12.0,24.0,45.0,60.0,72.0]:
		camera.position = point + Vector3(0,.75,.661438) * distance; camera.look_at(point)
		for blood: int in [-1,0,1]:
			for mark: GroundMarks.Mark in marks.foot_marks: mark.decal.visible = false
			var clean := await capture(view,"foot-%.0f-%d-off" % [distance,blood])
			for step in 16:
				var p := at + Vector2(float(step % 2)*.24-.12, float(step)*.45-3.6)
				marks.add_footprint(p.x,p.y,.05,.12,0.0, (step%2)<<16, blood)
			var marked := await capture(view,"foot-%.0f-%d-on" % [distance,blood])
			var d := difference(clean, marked)
			rows.append({"kind":"foot","blood":blood,"distance":distance,"difference":d})
			print("FOOT_DISTANCE ",distance," blood=",blood," ",JSON.stringify(d))
			if RenderingServer.get_current_rendering_method() != "gl_compatibility":
				check(d.peak_delta>2 and d.pixels_over_2>0,"ordinary/red/green footprints visible at %.0f metres (%d)" % [distance,blood])
	var last: GroundMarks.Mark = marks.foot_marks[-1]
	last.life=last.fade+2; marks._update(last); var opaque := last.decal.modulate.a
	last.life=maxi(2,last.fade/2); marks._update(last)
	check(last.decal.modulate.a>0 and last.decal.modulate.a<opaque,"footprints fade gradually")
	last.life=1; marks._update(last)
	check(last.decal.modulate.a==0,"footprint lifetime ends transparent")
	GameData.options.footprints=0; marks._apply_options()
	check(marks.foot_marks.all(func(mark): return not mark.decal.visible),"footprints option hides existing marks")
	GameData.options.footprints=1; marks._apply_options()
	check(marks.foot_marks.all(func(mark): return mark.decal.visible),"footprints option restores existing marks")
	view.free(); TexUpscale.shutdown(); await frames(8)
	FileAccess.open("user://surface-visibility.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("SURFACE_VISIBILITY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
