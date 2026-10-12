extends "wan_coop_stress.gd"
## Additional independently rendered client. Own process, save directory,
## global UI singletons and real ENet socket through its own impaired link.
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stress-plan="): stress_path=arg.trim_prefix("--stress-plan=")
	stress_plan=JSON.parse_string(FileAccess.get_file_as_string(stress_path)); seconds=float(stress_plan.seconds)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"coop_clock":1,"auto_exit":0,"scroll_border":0,"confine_mouse":0,
		"vsync":0,"fps_limit":0,"display_mode":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	var sizes := GameData.resolutions(); var ri := sizes.find(Vector2i(1280,720))
	if ri>=0: GameData.options.resolution=ri
	for i in 5: await get_tree().process_frame
	GameData._apply_window(); Engine.max_fps=60
	guest=ObservedSession.new(); get_parent().add_child(guest); get_parent().session=guest
	gg=Game.new(); gg.session=guest; guest.game=gg; get_parent().add_child(gg); get_parent().game=gg
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f := FileAccess.open(SaveInfo.path("external_origin"),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(String(stress_plan.source))); f.close()
	CoopProgress.bring_slot="external_origin"; GameData.player_name="Independent Guest"
	check(guest.join("127.0.0.1",int(stress_plan.proxy_port)+1)==OK,"independent client uses its own impaired ENet link")
	check(await until(func():return guest.my_index==2 and guest.world!=null and guest.zone_id==String(stress_plan.zone) and not guest._remote_loading and not guest.loading_game and LoadingScreen._current==null,180),"independent client completes normal campaign loading")
	if failures: await done(); return
	var leader: GameUnit=guest.party_units(2)[0]
	var route := plan_route(leader,24.0,true)
	check(route.size()==2,"independent client has a 24-metre route")
	if failures: await done(); return
	long_routes[2]={"points":route,"index":1}
	gg.selected.assign([leader]); gg.hud.unit_panel.examine=leader
	var ready := FileAccess.open(String(stress_plan.directory).path_join("third-ready"),FileAccess.WRITE); ready.store_string("ready"); ready.close()
	check(await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("actors.json")),90),"independent client waits for shared crowd start")
	await wait_real(2.0)
	check(guest.clock_speed==int(stress_plan.speed)-1,"independent client receives the requested shared game speed")
	var started := Time.get_ticks_msec(); var last := started; var move_at := started; var shot_at := started+10000
	var ids := []
	for u: GameUnit in guest.world.party_units(): ids.append(u.uid)
	work={"commands":[],"motion":{},"frames":[],"pings":[]}
	guest.begin(started,ids)
	var sample_at := started
	while Time.get_ticks_msec()<started+int(seconds*1000):
		var now := Time.get_ticks_msec(); var dt := now-last; last=now
		work.frames.append(dt)
		if now>=move_at: move_at=now+int(stress_plan.command_ms); long_move(guest,2,now-started)
		for u: GameUnit in guest.world.party_units(): sample_actor(u,null,dt,"independent guest")
		gg.rig.focus(leader.global_position)
		if now>=sample_at:
			sample_at=now+1000; work.pings.append({"wall_ms":now-started,"game_ping":guest.net.status.duplicate(true),"enet":peer_stats(guest)})
		if bool(stress_plan.capture) and now>=shot_at and now-started<30000:
			shot_at=now+200; video_frames.append(get_viewport().get_texture().get_image()); video_times.append(now-started)
		await get_tree().process_frame
	guest.recording=false
	var stream := stream_summary(guest,leader.uid)
	check(stream.party_updates>seconds*4,"independent client receives sustained party updates")
	check(stream.party_arrival_gap_ms.max<int(stress_plan.max_gap_ms),"independent client packet gaps stay within link budget")
	check(stats(work.frames).max<1000,"independent renderer avoids multi-second frames")
	for m: Dictionary in work.motion.values():
		m.erase("last_pos"); m.erase("last_draw")
		check(m.max_pending_freeze_ms<1000,"independent view actor %d avoids presentation freeze"%int(m.uid))
		check(m.dead_frames==0 and m.visible_model_frames>0,"independent view actor %d remains alive and rendered"%int(m.uid))
	check(work.motion["independent guest:%d"%leader.uid].draw_distance>seconds*.5,"independent player covers a sustained route")
	var status_pings := []; var own_pings := []
	var peer_id := guest.multiplayer.get_unique_id()
	for sample: Dictionary in work.pings:
		for state: Dictionary in sample.game_ping.values(): status_pings.append(int(state.ping))
		if sample.game_ping.has(peer_id): own_pings.append(int(sample.game_ping[peer_id].ping))
	var report := {"checks":checks,"failures":failures,"pid":OS.get_process_id(),"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"stream":stream,"frame_ms":stats(work.frames),"motion":work.motion,"commands":work.commands,"pings":work.pings,
		"network_peer_id":peer_id,"status_ping_ms":stats(status_pings),"own_status_ping_ms":stats(own_pings),
		"route":route,"video_times_ms":video_times,"renderer":{"adapter":RenderingServer.get_video_adapter_name(),"method":RenderingServer.get_current_rendering_method(),"size":get_viewport().get_visible_rect().size}}
	if not video_frames.is_empty():
		var directory := String(stress_plan.directory).path_join("independent-guest-frames"); DirAccess.make_dir_recursive_absolute(directory)
		for i in video_frames.size(): video_frames[i].save_png(directory.path_join("%04d.png"%i))
		video_frames.clear()
	FileAccess.open(String(stress_plan.directory).path_join("independent-guest.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("INDEPENDENT_GUEST %d checks %d failures"%[checks,failures])
	await done()

func done() -> void:
	if is_instance_valid(guest): guest.online=false; guest.multiplayer.multiplayer_peer.close()
	get_tree().quit(1 if failures else 0)
