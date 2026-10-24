extends "local_host_campaign.gd"
## Real authority subprocess, elapsed wall time and replicated simulation clock.
var samples: Array[Dictionary] = []
func sample(s: Session, g: Game, speed: int) -> float:
	click_clock(g,speed)
	await get_tree().create_timer(0.5,true,false,true).timeout
	var start := Time.get_ticks_usec(); var world_start := s.world.time
	await get_tree().create_timer(3.0,true,false,true).timeout
	var elapsed := (Time.get_ticks_usec()-start)/1000000.0
	var advanced := s.world.time-world_start
	var rate := advanced/elapsed
	samples.append({"speed":speed,"seconds":elapsed,"simulation_seconds":advanced,"ratio":rate,"frontend_time_scale":Engine.time_scale,"zone":s.zone_id,"map_open":s.map_open,"shop_available":s.shop_available(),"field_speed":s.field_speed,"movie":s.movie_active()})
	print("WORKER_RATE ",JSON.stringify(samples[-1]))
	check(absf(rate-(55.0/27.0 if speed == 2 else 1.0)) < 0.18,"authority advances at selected wall-time rate "+str(speed))
	return rate
func _ready() -> void:
	var save_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="): save_path=arg.trim_prefix("--resume-save=")
	if not FileAccess.file_exists(save_path):
		printerr("Supply a paused fast-mode save with --resume-save=/absolute/path.sav"); get_tree().quit(2); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData._apply_window()
	var s := Session.new();get_parent().add_child(s)
	var g := Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"solo authority starts")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(save_path,SaveInfo.path("reported")) == OK,"copy reporter save into isolated profile")
	check(await s.load_game_shown("reported"),"reporter save loaded by real worker")
	check(await until(func():return s.world!=null and not s._remote_loading and not s.movie_active(),30),"solo world ready")
	await until(func():return LoadingScreen._current==null and ShaderCompilationScreen._current==null,60)
	var initial := {"speed":g.speed,"paused":get_tree().paused,"scale":Engine.time_scale,"field_speed":s.field_speed}
	print("LOADED_CLOCK ",JSON.stringify(initial))
	check(g.speed==1 and get_tree().paused,"reporter save restores paused fast mode")
	click_clock(g,0)
	await get_tree().create_timer(0.5,true,false,true).timeout
	var t0 := Time.get_ticks_usec(); var w0 := s.world.time
	await get_tree().create_timer(3.0,true,false,true).timeout
	var resumed := (s.world.time-w0)/((Time.get_ticks_usec()-t0)/1000000.0)
	print("RESUMED_FAST_RATE ",resumed)
	check(absf(resumed-55.0/27.0)<0.18,"resuming supplied save preserves real accelerated authority")
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
	for fps: int in [15,5]:
		Engine.max_fps=fps
		await sample(s,g,1)
		await sample(s,g,2)
	Engine.max_fps=30
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	FileAccess.open("user://local-host-simulation-rate.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"\t"))
	print("LOCAL_HOST_SIMULATION_RATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func click_clock(g: Game, sector: int) -> void:
	var d := g.hud._clock_dial
	var angle := (sector+0.5)*PI/6.0
	var pos := d.size-Vector2(cos(angle),sin(angle))*72.0*d._scale()
	var e := InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;e.position=pos
	d._gui_input(e)
