extends "arena_local_host.gd"
## Private transport parity against the same frozen native combat, plus pause,
## 2x timing, empty armies, ownership and process cleanup.
var prepared: Dictionary={}
var outcomes: Dictionary={}
var states: Dictionary={}
var visual_events: Dictionary={}
func _ready()->void:run.call_deferred()
func run()->void:
	GameData.options.merge({"net_lan":1,"net_upnp":0,"net_directory":0,"autosave":0,"auto_graphics":0},true)
	Engine.max_fps=120
	var host:=connection("Solo fixture")
	host.solo_prepared.connect(func(data):prepared=data)
	host.solo_result.connect(func(data):outcomes[int(data.seat)]=data)
	host.board_received.connect(func(data):states[int(data.seat)]=data)
	host.effects_received.connect(func(data):visual_events[int(data.seat)]=int(visual_events.get(int(data.seat),0))+data.events.size())
	check(await host.local_host.start(0,false,true)==OK,"private worker starts on an ephemeral port")
	if not host.local_host.owned:get_tree().quit(1);return
	var child:=host.local_host.process_id
	var league:=ArenaTournamentRun.new();league.auto_save=false;league.live_boards=true;league.begin(7319)
	league.wave=12
	for player in 9:
		var company:=league.company(player);company.army.clear();company.wave=12;company.training=126
		for family in ([7,17,26] if player!=0 else [28,26,27]):company._recruit(family,1,10)
		company.arrange()
	league._prepare_round()
	for plan:Dictionary in league.bot_plans:plan.done=true
	var snapshot:=league.snapshot()
	host._send(1,{"t":"solo_prepare","snapshot":snapshot,"speed":2})
	check(await until(func():return not prepared.is_empty(),30),"frozen round is prepared")
	check(not prepared.get("error",false) and prepared.get("boards",[]).size()==9,"all private boards prepare")
	await frames(20)
	check(outcomes.is_empty() and states.is_empty(),"combat waits for the frontend bell")
	host._send(1,{"t":"view","seat":-1})
	host._send(1,{"t":"solo_clock","round":12,"paused":false,"speed":2})
	check(await until(func():return float(states.get(0,{}).get("time",0))>1),"2x combat advances")
	host._send(1,{"t":"solo_clock","round":12,"paused":true,"speed":2})
	await frames(30);var stopped:=float(states.get(0,{}).get("time",0))
	await frames(30)
	check(float(states.get(0,{}).get("time",0))==stopped,"private combat pauses")
	host._send(1,{"t":"solo_clock","round":12,"paused":false,"speed":2})
	check(await until(func():return outcomes.size()==9,75),"every board returns an outcome")
	var oracle:=ArenaOnlineGame.new();add_child(oracle);oracle.begin(7319,{0:""});oracle.set_process(false)
	check(oracle.run.restore(snapshot),"inline oracle restores the identical preparation")
	oracle._prepare();oracle.start_round()
	for tick in 2300:
		if oracle.run.stage!="fight":break
		oracle.advance_clock(GameUnit.TICK)
		if tick%80==0:await frames(1)
	for player in 9:
		check(outcomes.has(player),"board outcome exists")
		check(int(visual_events.get(player,0))>0,"staggered overview delivers effects for board %d"%player)
		if not outcomes.has(player):continue
		var expected:Dictionary=oracle.run.board_results[player]
		check(int(outcomes[player].winner)==int(expected.winner) and Array(outcomes[player].survivors)==Array(expected.survivors),"worker preserves native result for board %d"%player)
		print("WORKER_CLOCK ",player," worker=",outcomes[player].time," inline=",oracle.encounter(player).world.time)
		check(is_equal_approx(float(outcomes[player].time),oracle.encounter(player).world.time),"worker preserves native clock for board %d"%player)
	oracle.queue_free()
	# A vacant player's immediate loss must not vanish before the bell.
	prepared={};outcomes.clear();states.clear();league.army.clear()
	host._send(1,{"t":"solo_prepare","snapshot":league.snapshot(),"speed":1})
	check(await until(func():return not prepared.is_empty(),30),"empty player round prepares")
	host._send(1,{"t":"solo_clock","round":12,"paused":false,"speed":1})
	check(await until(func():return outcomes.has(0)),"empty player receives immediate outcome")
	await host.close_shown();check(not OS.is_process_running(child),"solo worker exits with frontend")
	host.queue_free();await frames(4)
	print("ARENA_SOLO_WORKER ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
