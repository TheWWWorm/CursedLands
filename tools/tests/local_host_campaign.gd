extends Node
## Real local owner and separate authority: new campaign, movie barrier,
## deferred save, a second start, shutdown and cancellation during startup.
class HeldMovie extends MoviePlayer:
	var starts := 0
	func play(_movie: String) -> void:
		starts += 1
		_state = PLAYING
		visible = true
	func _process(_dt: float) -> void: pass

var checks := 0
var failures := 0
var startup_done := false
var startup_result := OK

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func until(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func launch(s: Session) -> void:
	startup_result = await s.local_host.start(29923,2)
	startup_done = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,
		"net_directory":0,"autosave":0,"coop_clock":1},true)
	var s := Session.new()
	get_parent().add_child(s)
	var g := Game.new()
	g.session = s; s.game = g
	get_parent().add_child(g)
	g.hud._movie.queue_free()
	var movie := HeldMovie.new()
	movie.hud = g.hud
	g.hud._movie = movie
	g.hud._add_ui(movie)
	movie.finished.connect(g.hud._movie_finished)
	var err := await s.local_host.start(29923,2)
	check(err == OK,"owner starts")
	if err != OK:
		get_tree().quit(1)
		return
	var answer := await s.local_host.request("campaign",{"intro":true})
	check(answer.get("ok",false),"worker starts new campaign")
	check(await until(func():return s.world != null and s.zone_id=="gz1g" and not s._remote_loading),"owner receives fresh first zone")
	check(await until(func():return movie.starts>0),"owner receives opening movie")
	check(movie.starts==1 and s.movie_active(),"opening movie starts exactly once")
	check(s.my_index==0 and s.players.size()==1 and not g.my_units().is_empty(),"fresh campaign preserves original host party")
	await get_tree().create_timer(0.3,true,false,true).timeout
	var time := s.world.time
	await get_tree().create_timer(0.4,true,false,true).timeout
	check(s.world.time==time,"movie holds simulation while owner is presenting")
	answer = await s.local_host.request("save",{"slot":"during_movie","camera":s.local_host.view()})
	check(answer.get("queued",false) and not FileAccess.file_exists(SaveInfo.path("during_movie")),"save defers behind actual worker movie barrier")
	var serial := int(s._movie_ev.serial)
	s.submit({"t":"movie_done","serial":serial-1})
	await get_tree().create_timer(0.1,true,false,true).timeout
	check(s.movie_active(),"old completion cannot release current movie")
	movie.stop()
	check(await until(func():return not s.movie_active() and not movie.visible),"owner completion releases worker with no phantom host acknowledgement")
	check(await until(func():return FileAccess.file_exists(SaveInfo.path("during_movie"))),"deferred save completes after movie")
	check(await until(func():return s.world.time>time),"normal simulation resumes after movie")
	var saved := CampaignState.load_from(SaveInfo.path("during_movie"))
	check(saved != null and saved.current_zone=="gz1g" and saved.heroes.has(0),"saved fresh campaign contains real authority state")
	var first_world := s.world.get_instance_id()
	answer = await s.local_host.request("campaign",{"intro":false})
	check(answer.get("ok",false) and await until(func():return s.world != null and s.world.get_instance_id()!=first_world and not s._remote_loading),"second campaign replaces both worlds")
	check(movie.starts==1 and not s.movie_active() and s.players.size()==1,"second campaign does not replay intro or duplicate player")
	var pid := s.local_host.process_id
	await s.local_host.stop()
	check(not OS.is_process_running(pid),"campaign authority shuts down")
	launch(s)
	for i in 2: await get_tree().process_frame
	pid = s.local_host.process_id
	await s.local_host.stop()
	check(await until(func():return startup_done),"cancelled start resolves pending coroutine")
	check(startup_result != OK and not s.local_host.frontend and not s.online,"cancelled start never leaves a false lobby")
	check(pid <= 0 or not CrashReport.alive(pid),"cancelled child does not linger")
	print("LOCAL_HOST_CAMPAIGN ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
