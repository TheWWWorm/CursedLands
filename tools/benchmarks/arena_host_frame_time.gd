extends Node
## Live 4K Ultra host, one loopback guest, seven bots and nine full armies.
## GPU timestamps are opt-in: FPS acceptance never includes their readback.
var host: ArenaOnlineSession
var guest: ArenaOnlineSession
var screen: ArenaOnlineScreen
var seconds := 30.0
var gpu_queries := false
var fire_count := 18
var onscreen := false
var profile_sim := false
var battle_speed := 1
var samples := []
var census := []

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate(); sorted.sort()
	return {"median":sorted[sorted.size()/2], "p95":sorted[int(sorted.size()*0.95)], "p99":sorted[int(sorted.size()*0.99)], "max":sorted.back()}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	await frames(24)
	print("HOST_PROBE configure")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--fire-count="): fire_count = int(arg.trim_prefix("--fire-count="))
		if arg.begins_with("--speed="): battle_speed = clampi(int(arg.trim_prefix("--speed=")),1,2)
		if arg == "--gpu-queries": gpu_queries = true
		if arg == "--onscreen": onscreen = true
		if arg == "--profile-sim": profile_sim = true
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
	host.game.battle_speed = battle_speed
	host.game.start_round()
	await frames(30)
	var fx := ParticleFx.of(screen.battle.world)
	# Extra real native emitters provide a repeatable dense fire/smoke load;
	# native combat, damage, deaths, packets and clocks remain unmodified.
	for i in fire_count:
		fx.spawn([0x2001,0x2003,0x2004][i%3],Vector3(27.0+(i%3)*4.0,30.0+(i/3)*0.65,0.5),1.2)
	await frames(30)
	RenderingServer.viewport_set_measure_render_time(screen.field.view.get_viewport_rid(),gpu_queries)
	for player in 9: host.game.encounter(player).world.profile_simulation = profile_sim
	host.game.set_process(true)
	var start := Time.get_ticks_usec(); var previous := start; var next_census := start
	var start_sim := host.game.home.world.time
	var gpu := []; var render_cpu := []; var all_frames := []
	while Time.get_ticks_usec()-start < int(seconds*1000000):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var elapsed := (now-previous)/1000.0; previous = now
		all_frames.append(elapsed)
		if host.game.run.stage == "fight": samples.append(elapsed)
		if gpu_queries:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(screen.field.view.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(screen.field.view.get_viewport_rid()))
		if now >= next_census:
			var alive := []; var times := []
			for player in 9:
				var battle := host.game.encounter(player)
				alive.append(battle.world.unit_rows().filter(func(u):return not u.dead).size())
				times.append(battle.world.time)
			census.append({"wall":(now-start)/1000000.0,"stage":host.game.run.stage,"alive":alive,"sim":times,"particles":fx.drawn,"effects":fx.effects.size()})
			print("ARENA_HOST_CENSUS ",JSON.stringify(census.back()))
			next_census = now+1000000
	var scripts := {}
	for node in get_tree().root.find_children("*", "", true, false):
		if node == self or not node.is_processing() or not node.has_method("_process") or node == host.game or node == host or node == guest: continue
		var script: Script = node.get_script()
		if not script: continue
		var begin := Time.get_ticks_usec()
		for i in 4: node.call("_process", 1.0/60.0)
		var cost := (Time.get_ticks_usec()-begin)/4.0
		scripts[script.resource_path] = float(scripts.get(script.resource_path,0.0))+cost
	print("HOST_SCRIPT_COSTS_US ",JSON.stringify(scripts))
	var simulation := []
	for player in 9:
		var world := host.game.encounter(player).world
		simulation.append({"us":world.profile_us,"counts":world.profile_counts,"slow":world.profile_slow})
	var guest_live := guest.peer != null and guest.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host.members.size() == 2 and guest.view.connected
	var report := {"options":GameData.options,"viewport":str(get_viewport().get_visible_rect().size),"render_scale":get_viewport().scaling_3d_scale,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"onscreen":onscreen,"gpu_queries":gpu_queries,"fire_count":fire_count,"guest_connected":guest_live,"guest_status":guest.status,"members":host.members.duplicate(true),"wall_seconds":(previous-start)/1000000.0,"start_sim":start_sim,"frame_ms":distribution(all_frames),"combat_frame_ms":distribution(samples),"combat_frames":samples.size(),"frames":all_frames.size(),"gpu_ms":distribution(gpu),"render_cpu_ms":distribution(render_cpu),"census":census}
	report.simulation = simulation
	report.battle_speed = battle_speed
	report.display = OS.get_environment("DISPLAY")
	report.render_thread = "safe" if RenderingServer.is_on_render_thread() else "separate"
	report.msaa = screen.field.view.msaa_3d
	report.field_size = str(screen.field.view.size)
	report.field_render_scale = screen.field.view.scaling_3d_scale
	FileAccess.open("user://arena-host-frame-time.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARENA_HOST_RESULT ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://arena-host-frame-time.png")
	host.close(); guest.close(); screen.queue_free(); host.queue_free(); guest.queue_free()
	if not guest_live: push_error("Stress fixture lost its guest")
	await frames(4); TexUpscale.shutdown(); get_tree().quit(0 if guest_live else 1)
