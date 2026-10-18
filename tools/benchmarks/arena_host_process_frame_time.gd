extends "arena_host_frame_time.gd"
## Same nine stress armies as the inline benchmark, with the actual seat-zero
## host frontend and authority lifecycle. Only the child fixture setup differs
## from ordinary hosting. The fixture is never part of the shipped protocol.
class FixtureHost extends ArenaLocalHost:
	var fixture_path := ""
	func _arguments() -> PackedStringArray:
		var args := super._arguments()
		for i in args.size():
			if args[i].begins_with("--autochess-host-config="):
				args[i] = args[i].replace("--autochess-host-config=", "--arena-stress-config=")
		args.append("--tool=" + fixture_path)
		if "--expanded-roster" in OS.get_cmdline_user_args(): args.append("--expanded-roster")
		return args
class DiagnosticGuest extends ArenaOnlineSession:
	func fail(reason: String) -> void:
		print("GUEST_DISCONNECT_DIAGNOSTIC ", JSON.stringify({"at":Time.get_ticks_msec(),"reason":reason,"last_frame_age":Time.get_ticks_msec()-_last_frame_at,"connected":_connected,"started":started,"transport_state":peer.get_connection_status() if peer else -1}))
		super.fail(reason)
var base := ""
var render_times := []
var render_started := 0
func minimum_second_fps(values: Array) -> float:
	var window := 0.0; var first := 0; var minimum := INF; var elapsed := 0.0; var minimum_at := 0.0
	for index in values.size():
		window += float(values[index]); elapsed += float(values[index])
		while first < index and window-float(values[first]) >= 1000.0:
			window -= float(values[first]); first += 1
		if window >= 1000.0:
			var fps := 1000.0*(index-first+1)/window
			if fps < minimum: minimum = fps; minimum_at = elapsed/1000.0
	print("MINIMUM_SECOND_END ",minimum_at)
	return minimum
func wait_file(suffix: String) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while not FileAccess.file_exists(base+suffix) and Time.get_ticks_msec()<deadline and host.local_host.alive(): await frames(1)
	return FileAccess.file_exists(base+suffix)
func finish(code := 0) -> void:
	if guest: guest.close(); guest.queue_free()
	if host: await host.close_shown()
	if screen: screen.queue_free()
	if host: host.queue_free()
	await frames(4); TexUpscale.shutdown(); get_tree().quit(code)
func run() -> void:
	await frames(24)
	var target_size := Vector2i(3840,2160)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="): battle_speed = clampi(int(arg.trim_prefix("--speed=")),1,2)
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--fire-count="): fire_count = clampi(int(arg.trim_prefix("--fire-count=")),0,60)
		if arg.begins_with("--host-size="):
			var dimensions := arg.trim_prefix("--host-size=").split("x")
			if dimensions.size() == 2: target_size = Vector2i(clampi(int(dimensions[0]),640,7680),clampi(int(dimensions[1]),480,4320))
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED; get_window().size=target_size
	host=ArenaOnlineSession.new(); host.player_name="Benchmark host"; add_child(host)
	host.local_host.free()
	var fixture := FixtureHost.new(); fixture.session = host
	fixture.fixture_path = get_script().resource_path.get_base_dir().path_join("arena_host_process_fixture.gd")
	host.local_host = fixture; host.add_child(fixture)
	if await host.host_shown(29849) != OK or not host.owns_game(): await finish(1); return
	base=host.local_host._config
	guest=DiagnosticGuest.new(); guest.player_name="Benchmark guest"; add_child(guest)
	if guest.join("127.0.0.1:29849")!=OK: await finish(1);return
	var deadline:=Time.get_ticks_msec()+15000
	while guest.my_seat<0 and Time.get_ticks_msec()<deadline: await frames(1)
	if guest.my_seat!=1: await finish(1);return
	guest.request("ready")
	while not host.members.values().all(func(m): return m.ready) and Time.get_ticks_msec()<deadline: await frames(1)
	if not host.start_game(7319).is_empty() or not await wait_file(".prepared"): await finish(1);return
	while not host.started: await frames(1)
	print("HOST_PROCESS_SCREEN_BEGIN ",Time.get_ticks_msec())
	screen=ArenaOnlineScreen.new(); screen.connection=host; add_child(screen)
	print("HOST_PROCESS_SCREEN_BUILT ",Time.get_ticks_msec())
	await frames(60)
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED; get_window().size=target_size
	Gfx.apply_quality(get_viewport()); await frames(60)
	var pointer := screen.field.get_global_rect().get_center()
	Input.warp_mouse(pointer)
	var motion := InputEventMouseMotion.new(); motion.position = pointer
	Input.parse_input_event(motion)
	FileAccess.open(base+".round",FileAccess.WRITE).store_string(str(battle_speed))
	if not await wait_file(".battle"): await finish(1);return
	await frames(30)
	var fx:=ParticleFx.of(screen.battle.world)
	for i in fire_count: fx.spawn([0x2001,0x2003,0x2004][i%3],Vector3(27.0+(i%3)*4.0,30.0+(i/3)*0.65,0.5),1.2)
	await frames(30)
	FileAccess.open(base+".run",FileAccess.WRITE).store_string("run")
	var pointer_over_field := get_viewport().gui_get_hovered_control() == screen.field
	var diagnose := "--diagnose" in OS.get_cmdline_user_args()
	var gpu := []; var render_cpu := []; var root_gpu := []
	if diagnose:
		RenderingServer.viewport_set_measure_render_time(screen.field.view.get_viewport_rid(),true)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
		RenderingServer.frame_pre_draw.connect(func(): render_started = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(func(): render_times.append((Time.get_ticks_usec()-render_started)/1000.0))
	var start:=Time.get_ticks_usec(); var previous:=start; var next:=start
	while Time.get_ticks_usec()-start<int(seconds*1000000):
		await frames(1)
		var now:=Time.get_ticks_usec()
		if screen.battle.phase == ArenaMatch.Phase.FIGHT: samples.append((now-previous)/1000.0)
		if diagnose:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(screen.field.view.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(screen.field.view.get_viewport_rid()))
			root_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		previous=now
		if now<next: continue
		# At 2x the watched fight can end before the sample window. Its effect
		# node is deliberately freed after settling; do not retain that reader.
		var row:={"wall":(now-start)/1000000.0,"particles":fx.drawn if is_instance_valid(fx) else 0,"effects":fx.effects.size() if is_instance_valid(fx) else 0}
		if FileAccess.file_exists(base+".census"): row.authority=JSON.parse_string(FileAccess.get_file_as_string(base+".census"))
		census.append(row); print("HOST_PROCESS_CENSUS ",JSON.stringify(row)); next=now+1000000
	var guest_live := guest.peer != null and guest.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host.members.size() == 2 and guest.view.connected
	var report:={"scope":"Production local-authority owner (seat zero), real guest and seven bots; deterministic nine-army stress setup in an external child fixture.","speed":battle_speed,"frames":samples.size(),"wall_seconds":(previous-start)/1000000.0,"frame_ms":distribution(samples),"census":census,"options":GameData.options,"msaa":screen.field.view.msaa_3d,"render_scale":screen.field.view.scaling_3d_scale,"field_size":str(screen.field.view.size),"adapter":RenderingServer.get_video_adapter_name(),"render_thread":"safe" if RenderingServer.is_on_render_thread() else "separate","owns_game":host.owns_game(),"seat":host.my_seat,"guest_connected":guest_live,"guest_status":guest.status,"members":host.members.duplicate(true),"fire_count":fire_count,"worker_pid":host.local_host.process_id,"worker_data":base+".worker.json"}
	report.combat_seconds = samples.reduce(func(a,b):return a+b,0.0)/1000.0
	report.expanded_roster = "--expanded-roster" in OS.get_cmdline_user_args()
	report.pointer = str(screen.field.pointer_position())
	report.pointer_over_field = pointer_over_field
	report.diagnose = diagnose
	if diagnose: report.render = {"field_gpu":distribution(gpu),"field_cpu":distribution(render_cpu),"root_gpu":distribution(root_gpu),"wall":distribution(render_times)}
	report.mean_fps = samples.size()/report.combat_seconds
	report.min_1s_fps = minimum_second_fps(samples)
	FileAccess.open("user://arena-host-process.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HOST_PROCESS_RESULT ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://arena-host-process.png")
	if not guest_live: push_error("Stress fixture lost its guest")
	await finish(0 if guest_live else 1)
