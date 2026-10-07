extends Node

func _ready() -> void:
	var config_path := "user://bench.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--throughput-config="): config_path = arg.trim_prefix("--throughput-config=")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	GameData.options.merge({"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"coop_clock":1,"distant_ai":0},true)
	seed(519826)
	var session := Session.new()
	get_parent().add_child(session)
	get_parent().session = session
	# Set the authority role before creating Game: no presentation in the child.
	session.local_host.worker = true
	var game := Game.new()
	game.session = session
	session.game = game
	get_parent().add_child(game)
	get_parent().game = game
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var fixture := FileAccess.open(SaveInfo.path("throughput_fixture"),FileAccess.WRITE)
	fixture.store_buffer(FileAccess.get_file_as_bytes(String(cfg.save)))
	fixture.close()
	if session.host(29903,6) != OK or not await session.load_game_shown("throughput_fixture"):
		push_error("Throughput fixture failed to load"); get_tree().quit(1); return
	var w := session.world
	w.set_process(false)
	# Keep the runtime draw-clock branch. Disabling world physics sends every
	# actor through the legacy physics placement path during catch-up frames.
	session.set_physics_process(false)
	if DisplayServer.get_name() != "headless" or session.zone_id != "gz1h" or w.units.size() != 415:
		push_error("Unexpected throughput fixture: %s / %s / %s" % [DisplayServer.get_name(),session.zone_id,w.units.size()]); get_tree().quit(1); return
	w.profile_simulation = bool(cfg.get("profile",false))
	var events := [0]
	w.combat_event.connect(func(_kind,_a,_b,_amount): events[0] += 1)
	seed(519826)
	var initial := w.time
	var ticks := int(cfg.get("ticks",1100))
	var timings: Array = []
	var started := Time.get_ticks_usec()
	print("SIMULATION_THROUGHPUT_BEGIN ",cfg.name)
	for i in ticks:
		var tick_start := Time.get_ticks_usec()
		w._tick(GameUnit.TICK)
		timings.append(Time.get_ticks_usec()-tick_start)
		if i % 5 == 4: await get_tree().process_frame
	var elapsed := Time.get_ticks_usec()-started
	var tick_total := 0.0
	for duration in timings: tick_total += float(duration)
	var state: Array = []
	for u: GameUnit in w.unit_rows():
		state.append([u.uid,u.pos.x,u.pos.y,u.facing,u.hp,u.mana,u.dead,u.action,u.order.get("type","")])
	timings.sort()
	var result := {"name":cfg.name,"fixture_version":2,"initial_time":initial,"ticks":ticks,"wall_seconds":elapsed/1e6,"tick_seconds":tick_total/1e6,"sim_seconds":w.time-initial,
		"tick_ms":{"p50":timings[timings.size()/2]/1000.0,"p95":timings[int(timings.size()*.95)]/1000.0,"max":timings[-1]/1000.0},
		"zone":session.zone_id,"units":w.units.size(),"events":events[0],"state":state,"rng_next":randi(),
		"display":DisplayServer.get_name(),"worker":session.local_host.worker,"native":ClassDB.class_exists("TerrainSearchKernel"),
		"profile":w.profile_simulation,"world_us":w.profile_us,"counts":w.profile_counts,"activity_us":w.ai.activity.batch_usec,
		"deferred":w.ai.activity.deferred,"considered":w.ai.activity.considered,"profile_slow":w.profile_slow,"config":cfg}
	var out := String(cfg.get("out","user://"+String(cfg.name)+"-simulation.json"))
	var file := FileAccess.open(out,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")); file.close()
	print("SIMULATION_THROUGHPUT_DONE ",JSON.stringify({"name":cfg.name,"fixture_version":2,"initial_time":initial,"ticks":ticks,"wall_seconds":result.wall_seconds,"sim_seconds":result.sim_seconds,"events":events[0],"profile":w.profile_simulation}))
	get_tree().quit()
