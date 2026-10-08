extends Node
## Real single-player load path, worker, pause, controls and authoritative save.
## Use a disposable profile and --save=<Portal entrance-3 fixture>.
var checks := 0
var failures := 0
var session: Session

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func until(predicate: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func clock_barrier() -> void:
	# Clock and requests share the reliable channel. Wait for authority to
	# consume this change before checking that later refreshes stay still.
	session.local_host._sync_single_clock()
	var answer := await session.local_host.request("measure_save")
	check(answer.get("ok",false), "authority acknowledges clock barrier")
	await wait_real(0.4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":1,"net_lan":0,"net_directory":0,
		"autosave":0,"coop_clock":0,"difficulty":1,"sp_full_xp":0,"coop_full_xp":1},true)
	GameData.difficulty = 1
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var path := "user://fixtures/gz1h.sav"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path=arg.trim_prefix("--save=")
	check(FileAccess.file_exists(path), "save fixture exists")
	if failures:
		get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var slot := "single_process_%d" % Time.get_ticks_usec()
	var file := FileAccess.open(SaveInfo.path(slot), FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(path)); file.close()
	var original := CampaignState.load_from(SaveInfo.path(slot))
	session = Session.new()
	get_parent().add_child(session)
	var game := Game.new()
	game.session=session; session.game=game
	get_parent().add_child(game)
	# Headless tools opt into the transport explicitly; rendered tests exercise
	# the same automatic load path as the game's single-player menu.
	if DisplayServer.get_name()=="headless":
		check(await session.local_host.start(0,1,true)==OK,"headless fixture starts local single-player worker")
	check(await session.load_game_shown(slot), "ordinary load succeeds")
	if session.world==null:
		await session.local_host.stop(); get_tree().quit(1); return
	check(session.local_host.frontend and session.local_host.single_player,"ordinary load separates simulation")
	check(session.online and not session.multiplayer_game,"local transport retains offline gameplay rules")
	check(not session.is_host and session.can_manage_game(),"local player keeps save/load ownership")
	check(session.host_port>0 and session.multiplayer.multiplayer_peer is ENetMultiplayerPeer,"private ephemeral ENet port despite WebSocket preference")
	check(not session.coop_clock_enabled(),"co-op clock option does not govern single player")
	check(not session.world.authority and session.local_host._process_alive(),"live worker owns authoritative world")
	check(session.players.size()==1 and session.my_index==0,"no extra co-op hero")
	check(not session.loading_game and not session._remote_loading,"load transaction completes")
	check(session.state.money==original.money and session.state.items==original.items,"party purse and inventory survive load")
	game.selected.clear()
	game._key_action("select_all")
	check(game.selected.size()==game.my_units().size() and game.selected.size()==2,"single-player Select All remains enabled")
	game.set_speed(0)
	check(get_tree().paused,"clock dial pauses local presentation")
	await clock_barrier()
	var time := session.world.time
	await wait_real(0.5)
	check(session.world.time==time,"clock pause also holds worker simulation")
	var unit: GameUnit=game.my_units()[0]
	var gait := 0 if unit.gait()!=0 else 2
	session.submit({"t":"gait","units":[unit.uid],"gait":gait})
	check(await until(func():return unit.gait()==gait),"orders reach authority and return while paused")
	await wait_real(0.15)
	var saved_slot := slot+"_roundtrip"
	var answer := await session.local_host.request("save",{"slot":saved_slot,"camera":session.local_host.view()})
	check(answer.get("ok",false),"paused single player saves authority state")
	var saved := CampaignState.load_from(SaveInfo.path(saved_slot))
	check(saved!=null and saved.current_zone=="gz1h" and saved.money==original.money,"saved campaign state remains complete")
	check(await session.load_game_shown(saved_slot),"single-player reload through the worker")
	check(not get_tree().paused and is_equal_approx(Engine.time_scale,1.0),"reload resets pause and speed")
	unit=game.my_units()[0]
	check(unit.gait()==gait,"paused order survives authoritative save/reload")
	check(not session.multiplayer_game and not session.coop_clock_enabled(),"reload preserves single-player mode")
	game.set_speed(2)
	check(is_equal_approx(Engine.time_scale,55.0/27.0) and game.speed==1,"original accelerated single-player clock retained")
	time=session.world.time
	var resume_started := Time.get_ticks_msec()
	check(await until(func(): return session.world.time>time),"worker resumes after local speed change")
	print("SINGLE_PLAYER_RESUME_MS ", Time.get_ticks_msec()-resume_started)
	game.set_speed(1)
	game.hud._open_menu()
	await clock_barrier()
	time=session.world.time
	await wait_real(0.5)
	check(get_tree().paused and session.world.time==time,"ordinary menu pause holds both processes")
	game.hud._close_menu()
	check(not get_tree().paused,"closing menu restores running state")
	game.set_speed(0)
	game.hud._open_menu();game.hud._close_menu()
	check(get_tree().paused,"closing menu preserves an existing active pause")
	game.set_speed(1)
	await session.local_host.stop()
	check(not session.local_host._process_alive() and not session.local_host.frontend,"single-player worker exits cleanly")
	check(not session.online and not session.local_host.single_player,"transport mode clears after shutdown")
	print("SINGLE_PLAYER_PROCESS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
