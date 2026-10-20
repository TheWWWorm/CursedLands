extends "local_host_campaign.gd"
## Real authority subprocess, elapsed wall time and replicated simulation clock.
var samples: Array[Dictionary] = []
func sample(s: Session, g: Game, speed: int) -> float:
	g.set_speed(speed)
	await get_tree().create_timer(0.5,true,false,true).timeout
	var start := Time.get_ticks_usec(); var world_start := s.world.time
	await get_tree().create_timer(3.0,true,false,true).timeout
	var elapsed := (Time.get_ticks_usec()-start)/1000000.0
	var advanced := s.world.time-world_start
	var rate := advanced/elapsed
	samples.append({"speed":speed,"seconds":elapsed,"simulation_seconds":advanced,"ratio":rate,"frontend_time_scale":Engine.time_scale})
	print("WORKER_RATE ",JSON.stringify(samples[-1]))
	check(absf(rate-(55.0/27.0 if speed == 2 else 1.0)) < 0.18,"authority advances at selected wall-time rate "+str(speed))
	return rate
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	var s := Session.new();get_parent().add_child(s)
	var g := Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"solo authority starts")
	await s.new_campaign(false)
	check(await until(func():return s.world!=null and not s._remote_loading and not s.movie_active(),30),"solo world ready")
	var normal := await sample(s,g,1)
	var fast := await sample(s,g,2)
	check(fast/normal>1.8 and fast/normal<2.25,"fast mode changes actual authority time, not just presentation")
	get_tree().paused=true
	await get_tree().create_timer(0.3,true,false,true).timeout
	var frozen := s.world.time
	await get_tree().create_timer(0.6,true,false,true).timeout
	check(s.world.time==frozen,"authority clock stops when owner pauses")
	get_tree().paused=false
	await sample(s,g,1)
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	FileAccess.open("user://local-host-simulation-rate.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"\t"))
	print("LOCAL_HOST_SIMULATION_RATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
