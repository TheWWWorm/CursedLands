extends Node
## Real worker response and clock diagnostic; fixed frontend cadence for comparison.
var session: Session
var game: Game
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds,true,false,true).timeout

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,
		"autosave":0,"coop_clock":0,"difficulty":0,"distant_ai":0},true)
	GameData.difficulty=0
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var path := "user://fixtures/gz1h.sav"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path=arg.trim_prefix("--save=")
	check(FileAccess.file_exists(path),"save fixture exists")
	if failures: get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var slot := "worker_response_%d" % Time.get_ticks_usec()
	var f := FileAccess.open(SaveInfo.path(slot),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(path));f.close()
	session=Session.new(); get_parent().add_child(session)
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game)
	if DisplayServer.get_name()=="headless":
		check(await session.local_host.start(0,1,true)==OK,"headless starts worker")
	check(await session.load_game_shown(slot),"load through single-player worker")
	if session.world==null: await session.local_host.stop();get_tree().quit(1);return
	check(session.local_host.single_player and not session.multiplayer_game,"offline rules")
	Engine.max_fps=60
	game.set_speed(0)
	session.local_host._sync_single_clock()
	check((await session.local_host.request("measure_save")).get("ok",false),"pause acknowledged")
	await wait_real(0.5)
	var paused_time := session.world.time
	var unit: GameUnit=game.my_units()[0]
	var latencies: Array[int]=[]
	for i in 12:
		var gait := 0 if unit.gait()!=0 else 2
		var start := Time.get_ticks_msec()
		session.submit({"t":"gait","units":[unit.uid],"gait":gait})
		check(await until(func():return unit.gait()==gait),"paused command %d" % i)
		latencies.append(Time.get_ticks_msec()-start)
		check(session.world.time==paused_time,"paused simulation %d" % i)
		await wait_real(0.075)
	var rates: Array=[]
	for speed in [1,2]:
		var phase_start := Time.get_ticks_usec()
		var phase_time := session.world.time
		game.set_speed(speed)
		var old := session.world.time
		var resume := Time.get_ticks_msec()
		check(await until(func():return session.world.time>old),"resumes at speed %d" % speed)
		var latency := Time.get_ticks_msec()-resume
		await wait_real(1.0)
		var started := Time.get_ticks_usec()
		var before := session.world.time
		await wait_real(8.0)
		var wall := (Time.get_ticks_usec()-started)/1e6
		var simulated := session.world.time-before
		var requested := 1.0 if speed==1 else 55.0/27.0
		var phase_wall := (Time.get_ticks_usec()-phase_start)/1e6
		var phase_sim := session.world.time-phase_time
		# A cropped interval can repay earlier retained debt. Check overrun
		# from the speed request, including first progress and warm-up.
		check(simulated>0.0 and phase_sim<phase_wall*requested+0.25,"complete speed phase advances without overrun")
		if speed==1: check(phase_wall-phase_sim<0.5,"one-times full phase catches up to real time")
		rates.append({"speed":speed,"wall_seconds":wall,"sim_seconds":simulated,"requested_rate":requested,"resume_ms":latency,"phase_wall_seconds":phase_wall,"phase_sim_seconds":phase_sim})
	await session.local_host.stop()
	check(not session.local_host._process_alive(),"worker shuts down")
	latencies.sort()
	print("WORKER_RESPONSE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"latencies_ms":latencies,"rates":rates}))
	get_tree().quit(1 if failures else 0)
