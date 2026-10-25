extends "local_host_campaign.gd"
## Exercise the real solo worker and HUD dial across Ruins/Foothills travel.
## God mode isolates clock delivery from game-over pauses, without removing AI.
var samples: Array[Dictionary] = []

func sample(s: Session, g: Game, sector: int) -> float:
	var dial := g.hud._clock_dial
	var angle := (sector + 0.5) * PI / 6.0
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = dial.size - Vector2(cos(angle), sin(angle)) * 72.0 * dial._scale()
	dial._gui_input(event)
	await get_tree().create_timer(1.0, true, false, true).timeout
	var started := Time.get_ticks_usec()
	var world_start := s.world.time
	await get_tree().create_timer(2.0, true, false, true).timeout
	var rate := (s.world.time - world_start) / ((Time.get_ticks_usec() - started) / 1000000.0)
	samples.append({"zone":s.zone_id, "sector":sector, "actual":rate, "scale":Engine.time_scale, "field":s.field_speed, "fps_limit":Engine.max_fps})
	print("TRAVEL_RATE ", JSON.stringify(samples[-1]))
	check(absf(rate - (55.0 / 27.0 if sector == 2 else 1.0)) < 0.2, "authority wall-time rate follows HUD dial after travel")
	return rate

func compare_rates(s: Session, g: Game) -> void:
	var normal := await sample(s, g, 1)
	var fast := await sample(s, g, 2)
	check(fast / normal > 1.8, "fast/normal authority time remains distinct in " + s.zone_id)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# GPU Lab's CLI returns bounded tails. This fixture records its own
	# clock samples; omit verbose owner scene dumps so startup proof survives.
	if DisplayServer.get_name() != "headless" and is_instance_valid(CrashReport.instance._performance):
		CrashReport.instance._performance.queue_free()
	GameData.options.merge({"net_upnp":0, "net_websocket":0, "net_lan":0, "net_directory":0, "autosave":0, "show_tutorial":0}, true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	var seed := Session.new(); add_child(seed)
	seed.local_host.worker = true; seed.local_host.single_player = true
	var seed_game := Game.new(); seed_game.session = seed; seed.game = seed_game; add_child(seed_game)
	seed.state.ensure_hero(0, "Human Hero")
	seed._enter_zone("gz1g", 1, false)
	seed.state.god_modes[0] = 1
	seed.restore_play_clock({"speed":1, "paused":false})
	check(seed.save_game("travel-seed") == OK, "Ruins fixture saved")
	seed_game.queue_free(); seed.queue_free()
	for i in 8: await get_tree().process_frame
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session = s; s.game = g; get_parent().add_child(g)
	check(await s.local_host.start(0, 1, true) == OK, "separate solo worker starts")
	var answer := await s.local_host.request("load", {"slot":"travel-seed"})
	check(answer.get("ok", false), "worker loads initial field")
	check(await until(func():return s.world != null and not s._remote_loading, 30), "initial world ready")
	check(await until(func():return LoadingScreen._current == null and ShaderCompilationScreen._current == null, 60), "initial loading cover releases")
	# Reproduce a stale last-sent 1x cache after the worker restores the fast save.
	# The initial restore and user click can share an owner frame.
	s.local_host._single_clock = [false, 1.0, false, 0]
	await compare_rates(s, g)
	for zone: String in ["gz3g", "gz1g", "bz1g", "gz3g"]:
		s.submit({"t":"console", "line":"travel " + zone, "request":1})
		check(await until(func():return s.zone_id == zone and not s._remote_loading, 60), "arrives in " + zone)
		check(await until(func():return LoadingScreen._current == null and ShaderCompilationScreen._current == null, 60), "arrival loading cover releases")
		if zone.begins_with("bz"):
			g.set_speed(2)
			check(g.speed == 0 and s.field_speed == 1, "village masks speed without losing the field choice")
		else:
			await compare_rates(s, g)
	Engine.max_fps = 5
	await compare_rates(s, g)
	Engine.max_fps = 30
	await s.local_host.stop()
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	FileAccess.open("user://worker-travel-clock.json", FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	print("WORKER_TRAVEL_CLOCK ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
