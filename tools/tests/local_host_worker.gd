extends Node
## Run with a disposable user profile and --save=/path/to/a/copied/Portal.sav.
## Exercises the real worker process and the local owner's production RPCs.
var checks := 0
var failures := 0
var session: Session


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LOCAL_HOST " + label)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	GameData.options.net_upnp = 0
	GameData.options.net_websocket = int(OS.get_cmdline_user_args().has("--websocket"))
	GameData.options.coop_clock = 1
	GameData.options.autosave = 0
	GameData.player_name = "WorkerOwner"
	var roundtrip_slot := "worker_roundtrip_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			path = arg.trim_prefix("--save=")
	check(not path.is_empty() and FileAccess.file_exists(path), "save fixture exists")
	if failures:
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f := FileAccess.open(SaveInfo.path("worker_fixture"), FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(path))
	f.close()
	session = Session.new()
	get_parent().add_child(session)
	var game := Game.new()
	game.session = session
	session.game = game
	get_parent().add_child(game)
	var err := await session.local_host.start(29917, 2)
	check(err == OK, "worker starts and authenticates")
	if err != OK:
		get_tree().quit(1)
		return
	var pid := session.local_host.process_id
	check(pid > 0 and session.local_host._process_alive(), "separate live process")
	check(not session.is_host and session.can_manage_game(), "owner controls without simulating")
	check(session.my_index == 0 and session.players.size() == 1, "one host player, no phantom hero")
	check(session.players.has(session.multiplayer.get_unique_id()), "network identity owns player zero")
	check(session.host_player_id() == session.multiplayer.get_unique_id(), "host identity follows player slot")
	check(not session.local_host.authorized(1), "frontend cannot authorize server actions")
	check(await session.load_game_shown("worker_fixture"), "owner loads save through worker")
	if session.world == null:
		await session.local_host.stop()
		get_tree().quit(1)
		return
	check(not session.world.authority, "presentation world is a replica")
	check(session.zone_id == "gz1h", "loaded Portal")
	check(not session.loading_game and not session._remote_loading, "load transaction completes")
	check(session.state.heroes.has(0) and not game.my_units().is_empty(), "original host party stays controlled")
	var original := CampaignState.load_from(SaveInfo.path("worker_fixture"))
	check(is_equal_approx(game.rig.yaw, float(original.camera.get("yaw", 0.0))) and
		is_equal_approx(game.rig.distance, float(original.camera.get("distance", 0.0))), "saved camera restored before load returns")
	await frames(10)
	session.set_coop_clock(0)
	var deadline := Time.get_ticks_msec() + 5000
	while not session.clock_paused and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(session.clock_paused, "owner pauses shared clock")
	var view := session.local_host.view()
	var selected: GameUnit = game.my_units()[0]
	var gait_before := selected.gait()
	var gait_after := 0 if gait_before != 0 else 2
	var command_at := Time.get_ticks_msec()
	session.submit({"t": "gait", "units": [selected.uid], "gait": gait_after})
	while selected.gait() != gait_after and Time.get_ticks_msec() - command_at < 5000:
		await frames(1)
	check(selected.gait() == gait_after, "paused owner command is reflected without resuming")
	print("LOCAL_HOST_PAUSED_COMMAND_MS ", Time.get_ticks_msec() - command_at)
	# Allow any pre-pause packet to settle, then ensure neither world time nor
	# action playback advances while periodic paused refreshes keep arriving.
	await get_tree().create_timer(0.35, true, false, true).timeout
	var paused_time := session.world.time
	var paused_action := selected._action_serial
	var paused_animation := selected.model.player.current_animation_position
	await get_tree().create_timer(0.6, true, false, true).timeout
	check(session.world.time == paused_time, "paused refreshes do not advance simulation")
	check(selected._action_serial == paused_action and selected.model.player.current_animation_position == paused_animation,
		"duplicate refreshes neither restart nor advance paused animation")
	await session.local_host.measure_save()
	check(session.save_bytes_needed() > 100000, "save size comes from authoritative world")
	var answer := await session.local_host.request("save", {"slot": roundtrip_slot, "name": "Worker roundtrip", "camera": view})
	check(answer.get("ok", false) and FileAccess.file_exists(SaveInfo.path(roundtrip_slot)), "owner saves authoritative state")
	var saved := CampaignState.load_from(SaveInfo.path(roundtrip_slot))
	check(saved != null and saved.current_zone == "gz1h", "save has full zone state")
	check(saved.camera == view, "save uses visible camera")
	check(SaveInfo.read(roundtrip_slot).name == "Worker roundtrip", "save metadata belongs to owner")
	if DisplayServer.get_name() != "headless":
		var shot_path := SaveInfo.path(roundtrip_slot, "shot.png")
		deadline = Time.get_ticks_msec() + 5000
		while not FileAccess.file_exists(shot_path) and Time.get_ticks_msec() < deadline:
			await frames(1)
		var shot := Image.load_from_file(shot_path) if FileAccess.file_exists(shot_path) else null
		check(shot != null and shot.get_size() == SaveInfo.SHOT_SIZE, "worker-initiated save captures owner's image")
		if shot:
			var different := false
			var first := shot.get_pixel(0,0)
			for y in range(0,shot.get_height(),8):
				for x in range(0,shot.get_width(),8):
					if shot.get_pixel(x,y) != first: different = true
			check(different, "owner thumbnail contains the rendered scene")
		var captured_serial := int(session.local_host._pending_shots.get(roundtrip_slot, -1))
		var manual := Image.create(32,32,false,Image.FORMAT_RGB8)
		manual.fill(Color(0.2,0.4,0.6))
		answer = await session.local_host.request("save", {"slot":roundtrip_slot,"camera":view,"image":manual.save_png_to_buffer()})
		check(answer.get("ok",false), "manual image replaces pending capture")
		var stale := Image.create(SaveInfo.SHOT_SIZE.x, SaveInfo.SHOT_SIZE.y, false, Image.FORMAT_RGB8)
		stale.fill(Color.RED)
		session.local_host._rpc_save_shot_image.rpc_id(1, roundtrip_slot, session.zone_id, captured_serial, stale.save_png_to_buffer())
		await frames(8)
		shot = Image.load_from_file(shot_path)
		check(shot.get_pixel(0,0).is_equal_approx(manual.get_pixel(0,0)), "explicit image survives later callbacks")
	check(await session.load_game_shown(roundtrip_slot), "owner can reload after shared pause")
	check(not session.clock_paused and not get_tree().paused, "load resets shared clock")
	check(session.players.size() == 1 and session.my_index == 0, "load does not add a co-op player")
	check(game.my_units()[0].gait() == gait_after, "paused command survives authoritative save and reload")
	await session.local_host.stop()
	check(not session.local_host._process_alive(), "worker exits cleanly")
	session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	check(not session.local_host.frontend, "owner lifecycle closes")
	print("LOCAL_HOST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)
