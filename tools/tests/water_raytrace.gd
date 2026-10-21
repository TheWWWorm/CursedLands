extends Node
var out := "user://water-raytrace"
var failures := []
var checks := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name+".png"))

func _ready() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":0,"vsync":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"gfx_water":1,"gfx_water_reflections":2,"gfx_sky":1,"autosave":0,"show_tutorial":0,
		"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280,720))
	Engine.max_fps = 60
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var zone := s.campaign.zone_by_map("zone3obr")
	s._enter_zone(zone.id,1,false)
	s.state.world_time = 12.0
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear()
	g.rig.set_process(false); g.direct.set_process(false)
	g.hud.process_mode = Node.PROCESS_MODE_DISABLED; g.hud.hide()
	var camera := Camera3D.new(); g.add_child(camera)
	camera.fov = 65; camera.near = 0.08; camera.current = true
	camera.global_position = Vector3(183.065,8.676689,-150.5906)
	camera.look_at(Vector3(171.2955,7.045171,-148.2495))
	for u: GameUnit in s.world.units.values(): u.hide(); u.set_process(false)
	await frames(60)
	g.set_process(false); s.world.terrain.set_process(false)
	var t := s.world.terrain
	var supported := t.WaterReflection.RayDevice.supported()
	print("RT_CAPABILITY ",supported)
	for mode in [0,2,3]:
		GameData.options.gfx_water_reflections = mode
		t.apply_gfx()
		await frames(15)
		if mode == 3 and supported:
			for i in 1200:
				if t._reflection._rt_ready or t._reflection._rt_failed: break
				await frames(1)
			check(t._reflection._rt_ready,"hardware RT scene prepares successfully")
			print("RT_STATS ",JSON.stringify(t._reflection.rt_stats))
		await frames(10)
		await shot("water-mode-%d"%mode)
		if mode >= 2 and t._reflection:
			var tex: Texture2D = t._water_mat.get_shader_parameter("planar_texture")
			if tex: tex.get_image().save_png(out.path_join("reflection-mode-%d.png"%mode))
		Engine.max_fps = 0
		await frames(30)
		var times := PackedFloat64Array()
		var last := Time.get_ticks_usec()
		for i in 120:
			await frames(1)
			var now := Time.get_ticks_usec()
			times.append((now-last)/1000.0); last = now
		times.sort()
		rows.append({"mode":mode,"median_ms":times[60],"p95_ms":times[114],
			"stats":t._reflection.rt_stats.duplicate() if t._reflection else {}})
		Engine.max_fps = 60
	if supported:
		check(t._reflection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"RT replaces the planar draw pass")
		check(t._reflection.rt_stats.get("triangles",0) > 100,"real map geometry is in the acceleration structure")
		var rt_image: Image = t._reflection._rt.output.get_image() if t._reflection._rt else null
		var hits := 0
		if rt_image:
			for y in range(0,rt_image.get_height(),4):
				for x in range(0,rt_image.get_width(),4):
					if rt_image.get_pixel(x,y).a > 0.5: hits += 1
		check(hits > 100,"hardware trace returns visible scenery hits")
		# Reprojection must change immediately during a camera turn.
		camera.rotate_y(0.3)
		await frames(5); await shot("water-turned")
		check(t._reflection._rt_ready,"camera rotation retains the static acceleration structure")
		camera.rotate_y(-0.3)
		t.hide(); await frames(3)
		check(not t._reflection.rt_stats.get("active",false),"hidden terrain suspends hardware tracing")
		t.show(); await frames(4)
		check(t._reflection._rt_ready,"showing the terrain reuses its static snapshot")
		# A tree bank gives a less obstructed comparison than the bridge.
		var tree: Node3D = s.world.objects[4442]
		var found := false
		for i in 32:
			var angle := i*TAU/32
			var p := Vector2(tree.global_position.x,-tree.global_position.z)+Vector2(cos(angle),sin(angle))*14.0
			var level := t.water_at(p.x,p.y)
			if not is_finite(level) or t.height_at(p.x,p.y) >= level-0.3: continue
			camera.global_position = Vector3(p.x,level+1.8,-p.y)
			camera.look_at(tree.global_position+Vector3.UP*1.8)
			found = true
			break
		check(found,"tree-bank comparison camera is above open water")
		if found:
			for mode in [2,3]:
				GameData.options.gfx_water_reflections = mode; t.apply_gfx(); await frames(10)
				if mode == 3:
					for i in 1200:
						if t._reflection._rt_ready or t._reflection._rt_failed: break
						await frames(1)
					check(t._reflection._rt_ready,"moving to a new water view rebuilds the snapshot")
				await frames(5); await shot("tree-water-mode-%d"%mode)
		# Simulate the backend reporting an allocation/pipeline failure after
		# its texture was already being used; the water must recover to Mirror.
		t._reflection._raytrace_prepared(false)
		await frames(5)
		check(t._reflection._rt == null and t._reflection._rt_failed,"backend failure releases hardware resources")
		check(t._water_mat.get_shader_parameter("planar_texture") == t._reflection.viewport.get_texture(),"backend failure restores the planar texture")
	else:
		check(t._reflection == null or t._reflection.viewport != null,"unsupported renderer retains its established reflection path")
	GameData.options.gfx_water_reflections = 2; t.apply_gfx(); await frames(5)
	if t._reflection:
		check(t._reflection._rt == null,"Mirror releases ray tracing resources")
		check(t._reflection.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Mirror restores the raster reflection")
	GameData.options.gfx_water_reflections = 0; t.apply_gfx(); await frames(5)
	check(t._reflection == null,"Off releases the reflection owner")
	# Every dynamically selected choice and help is translated.
	for language in ["en","ru","de"]:
		RemakeText.lang = language
		var choices := GameData.option_choices("gfx_water_reflections")
		check(choices.size() == 4,"all reflection choices exist in "+language)
		check(language == "en" or choices[3] != "Ray traced (test)","RT choice is translated in "+language)
		var panel := OptionsPanel.new(); add_child(panel); panel.open()
		panel._values.gfx_water_reflections = 3; panel._show_group(OptionsPanel.WATER_GROUP)
		await frames(4); await shot("water-options-"+language)
		get_window().grab_focus()
		GameData._tips.delay = 0.1
		Input.warp_mouse(Vector2(20,20)); await frames(3)
		var at := panel._origin()+Vector2(400,panel._row_y(1)+12)*panel.kv()
		Input.warp_mouse(at)
		var motion := InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion)
		await get_tree().create_timer(0.4,true,false,true).timeout
		check(GameData._tips._panel.visible,"water reflection help is visible in "+language)
		check(GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS.gfx_water_reflections[1])),"localized help matches the selected option in "+language)
		check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"water reflection help fits in "+language)
		await shot("water-help-"+language)
		panel.queue_free(); await frames(2)
	g.queue_free(); s.queue_free(); await frames(15)
	TexUpscale.shutdown()
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":rows,"supported":supported,
		"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name()},"\t"))
	print("WATER_RT ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
