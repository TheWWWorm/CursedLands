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
		return args
class DiagnosticGuest extends ArenaOnlineSession:
	func fail(reason: String) -> void:
		print("GUEST_DISCONNECT_DIAGNOSTIC ", JSON.stringify({"at":Time.get_ticks_msec(),"reason":reason,"last_frame_age":Time.get_ticks_msec()-_last_frame_at,"connected":_connected,"started":started,"transport_state":peer.get_connection_status() if peer else -1}))
		super.fail(reason)
var base := ""
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="): battle_speed = clampi(int(arg.trim_prefix("--speed=")),1,2)
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(3840,2160)
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
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(3840,2160)
	Gfx.apply_quality(get_viewport()); await frames(60)
	FileAccess.open(base+".round",FileAccess.WRITE).store_string(str(battle_speed))
	if not await wait_file(".battle"): await finish(1);return
	await frames(30)
	var fx:=ParticleFx.of(screen.battle.world)
	for i in fire_count: fx.spawn([0x2001,0x2003,0x2004][i%3],Vector3(27.0+(i%3)*4.0,30.0+(i/3)*0.65,0.5),1.2)
	await frames(30)
	FileAccess.open(base+".run",FileAccess.WRITE).store_string("run")
	var start:=Time.get_ticks_usec(); var previous:=start; var next:=start
	while Time.get_ticks_usec()-start<int(seconds*1000000):
		await frames(1)
		var now:=Time.get_ticks_usec(); samples.append((now-previous)/1000.0); previous=now
		if now<next: continue
		var row:={"wall":(now-start)/1000000.0,"particles":fx.drawn,"effects":fx.effects.size()}
		if FileAccess.file_exists(base+".census"): row.authority=JSON.parse_string(FileAccess.get_file_as_string(base+".census"))
		census.append(row); print("HOST_PROCESS_CENSUS ",JSON.stringify(row)); next=now+1000000
	var guest_live := guest.peer != null and guest.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host.members.size() == 2 and guest.view.connected
	var report:={"scope":"Production local-authority owner (seat zero), real guest and seven bots; deterministic nine-army stress setup in an external child fixture.","speed":battle_speed,"frames":samples.size(),"wall_seconds":(previous-start)/1000000.0,"frame_ms":distribution(samples),"census":census,"options":GameData.options,"msaa":screen.field.view.msaa_3d,"render_scale":screen.field.view.scaling_3d_scale,"field_size":str(screen.field.view.size),"adapter":RenderingServer.get_video_adapter_name(),"render_thread":"safe" if RenderingServer.is_on_render_thread() else "separate","owns_game":host.owns_game(),"seat":host.my_seat,"guest_connected":guest_live,"guest_status":guest.status,"members":host.members.duplicate(true),"fire_count":fire_count,"worker_pid":host.local_host.process_id,"worker_data":base+".worker.json"}
	FileAccess.open("user://arena-host-process.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HOST_PROCESS_RESULT ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://arena-host-process.png")
	if not guest_live: push_error("Stress fixture lost its guest")
	await finish(0 if guest_live else 1)
