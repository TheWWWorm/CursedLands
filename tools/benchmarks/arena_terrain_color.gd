extends "arena_host_frame_time.gd"
## Frozen native 4K stress scene: compare the production shared colour cache
## with its original sampler at close/normal/wide spectator views. Pause the
## entire scene, including ArenaOnlineScreen (which otherwise resets time_scale).
## This is image-quality evidence, not a live host FPS benchmark.
func run() -> void:
	await frames(24)
	print("HOST_PROBE configure")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fire-count="): fire_count = int(arg.trim_prefix("--fire-count="))
		if arg == "--onscreen": onscreen = true
	if not onscreen:
		var viewport := SubViewport.new(); viewport.size = Vector2i(3840,2160); viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_parent().add_child(viewport); reparent(viewport)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(3840,2160) if onscreen else Vector2i(320,320)
	print("HOST_PROBE host")
	host = ArenaOnlineSession.new(); host.player_name = "Benchmark host"; add_child(host)
	var error := host.host(29849)
	if error != OK: push_error("Host failed: " + str(error)); get_tree().quit(1); return
	print("HOST_PROBE guest")
	guest = ArenaOnlineSession.new(); guest.player_name = "Benchmark guest"; add_child(guest)
	error = guest.join("127.0.0.1:29849")
	if error != OK: push_error("Guest failed: " + str(error)); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+10000
	while guest.my_seat < 0 and Time.get_ticks_msec() < deadline: await frames(1)
	if guest.my_seat != 1: push_error("Guest handshake timed out"); get_tree().quit(1); return
	guest.request("ready")
	while not host.members.values().all(func(member):return member.ready) and Time.get_ticks_msec() < deadline: await frames(1)
	print("HOST_PROBE begin")
	var message := host.start_game(7319)
	if not message.is_empty(): push_error(message); get_tree().quit(1); return
	host.game.set_process(false)
	print("HOST_PROBE fill")
	host.game.run.wave = 21
	for player in 9:
		var company := host.game.run.company(player)
		company.army.clear(); company.wave = 21; company.training = 126
		company.gold = 50; company.auto_save = false
		for family in [7,9,10,11,17,18,22,23,8]: company._recruit(family,2,10)
		company.arrange()
	host.game.run._prepare_round()
	for plan: Dictionary in host.game.run.bot_plans: plan.done = true
	print("HOST_PROBE prepare")
	host.game._prepare(); await frames(12)
	print("HOST_PROBE screen")
	screen = ArenaOnlineScreen.new(); screen.connection = host; add_child(screen)
	await frames(60)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(3840,2160) if onscreen else Vector2i(320,320)
	Gfx.apply_quality(get_viewport())
	await frames(60)
	print("HOST_PROBE battle")
	host.game.start_round()
	await frames(30)
	var fx := ParticleFx.of(screen.battle.world)
	# Fill with real emitters and let combat settle before freezing all nodes.
	for i in fire_count:
		fx.spawn([0x2001,0x2003,0x2004][i%3],Vector3(27.0+(i%3)*4.0,30.0+(i/3)*0.65,0.5),1.2)
	await frames(30)
	host.game.set_process(true)
	await frames(300)
	host.game.set_process(false)
	Engine.time_scale=0.0
	var paused := []
	for node: Node in get_tree().root.find_children("*","",true,false):
		if node == self: continue
		paused.append([node,node.process_mode])
		node.process_mode = Node.PROCESS_MODE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS
	var terrain := screen.battle.world.terrain as ArenaWinterTerrain
	if terrain == null or terrain._color == null:
		push_error("Arena terrain colour cache is unavailable");get_tree().quit(1);return
	var pairs := []; var shaders := {}; var seen := {}
	for node: MeshInstance3D in terrain.find_children("*","MeshInstance3D",true,false):
		var material := node.get_active_material(0) as ShaderMaterial
		if material == null or seen.has(material): continue
		seen[material] = true
		var candidate := material.shader
		if not candidate.code.contains("#define EI_BAKED_TERRAIN"): continue
		if not shaders.has(candidate):
			var reference := Shader.new()
			reference.code = candidate.code.replace("#define EI_BAKED_TERRAIN", "")
			reference.get_shader_uniform_list(); shaders[candidate] = reference
		pairs.append([material, shaders[candidate], candidate])
	var rows := []
	var poses := [Vector2(-PI/2,8),Vector2(0,8),Vector2(PI/2,8),Vector2(PI,8),Vector2(-PI/2,14.5),Vector2(0,14.5),Vector2(PI/2,35),Vector2(PI,35)]
	for pose_id in poses.size():
		screen.field.yaw=poses[pose_id].x;screen.field.zoom=poses[pose_id].y;screen.field._update_camera()
		screen.field.overlay.queue_redraw()
		for pass_id in [0,1,0]:
			for pair: Array in pairs: pair[0].shader=pair[2] if pass_id == 1 else pair[1]
			await frames(40)
			await RenderingServer.frame_post_draw
			var path := "user://color-quality-%d-%d.png"%[pose_id,rows.size()]
			screen.field.view.get_texture().get_image().save_png(path)
			rows.append({"pose":pose_id,"yaw":screen.field.yaw,"zoom":screen.field.zoom,"case":pass_id,"path":path,"particles":fx.drawn,"time_scale":Engine.time_scale})
			print("COLOR_QUALITY_CAPTURE ",JSON.stringify(rows.back()))
	FileAccess.open("user://arena-terrain-color-quality.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"pairs":pairs.size()},"\t"))
	for pair: Array in paused:
		if is_instance_valid(pair[0]): pair[0].process_mode=pair[1]
	Engine.time_scale=1.0
	host.close(); guest.close(); screen.queue_free(); host.queue_free(); guest.queue_free()
	await frames(4); TexUpscale.shutdown(); get_tree().quit()
