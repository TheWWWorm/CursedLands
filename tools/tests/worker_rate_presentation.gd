extends "local_host_campaign.gd"
## #119: a solo authority that cannot sustain fast speed (emulated with
## --ei-simulation-load-ms) must not be predicted ahead by its owner. The
## owner presents the achieved rate; the dial, requested rate and save keep
## the selected speed. Measures the visible client Eagle Sight counter.
const FAST := 55.0 / 27.0
var samples: Array[Dictionary] = []

func measure(s: Session, label: String, seconds := 5.0) -> Dictionary:
	var u: GameUnit = s.world.party_units()[0]
	var t0 := s.world.time; var e0 := u.effect_ticks("eagle_sight")
	var start := Time.get_ticks_usec()
	var last := e0; var reversals := 0; var back := 0; var largest := 0
	var scale_sum := 0.0; var frames := 0
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await get_tree().process_frame
		frames += 1
		scale_sum += Engine.time_scale
		var now := u.effect_ticks("eagle_sight")
		if now > last:
			reversals += 1; back += now - last; largest = maxi(largest, now - last)
		last = now
	var wall := (Time.get_ticks_usec() - start) / 1000000.0
	var row := {"phase":label, "wall":wall, "world_rate":(s.world.time - t0) / wall,
		"eagle_rate":(e0 - u.effect_ticks("eagle_sight")) * GameUnit.TICK / wall,
		"presented":scale_sum / maxf(frames, 1), "authority_rate":s.local_host.get("authority_rate"),
		"reversals":reversals, "backward_ticks":back, "largest_reversal":largest}
	samples.append(row); print("WORKER_RATE ", JSON.stringify(row))
	return row

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless" and is_instance_valid(CrashReport.instance._performance):
		CrashReport.instance._performance.queue_free()
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1),true)
	check(OS.get_cmdline_user_args().has("--ei-simulation-load-ms=30"), "authority load emulation requested")
	var seed := Session.new(); add_child(seed)
	seed.local_host.worker = true; seed.local_host.single_player = true
	var seed_game := Game.new(); seed_game.session = seed; seed.game = seed_game; add_child(seed_game)
	seed.state.ensure_hero(0, "Human Hero")
	seed._enter_zone("gz3g", 1, false)
	seed.state.god_modes[0] = 1
	var hero: GameUnit = seed.world.party_units()[0]
	hero.aggressive = false
	hero.buffs.eagle_sight = {"until":seed.world.time + 600.0, "_effect_ticks":10800, "sense":[0, 10.0]}
	seed.restore_play_clock({"speed":0, "paused":false})
	check(seed.save_game("worker-rate-seed") == OK, "Foothills fixture saved")
	seed_game.queue_free(); seed.queue_free()
	for i in 8: await get_tree().process_frame
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session = s; s.game = g; get_parent().add_child(g)
	check(await s.local_host.start(0, 1, true) == OK, "separate solo worker starts")
	check((await s.local_host.request("load", {"slot":"worker-rate-seed"})).get("ok", false), "worker loads Foothills")
	check(await until(func(): return s.world != null and not s._remote_loading and LoadingScreen._current == null \
		and ShaderCompilationScreen._current == null, 90), "Foothills ready")

	g.set_speed(1)
	await get_tree().create_timer(5.0, true, false, true).timeout   # post-load warm-up
	var normal := await measure(s, "normal")
	check(absf(float(normal.world_rate) - 1.0) < 0.15, "loaded authority still sustains normal speed")
	check(Engine.time_scale == 1.0 and s.local_host.get("authority_rate") == 1.0, "a sustained rate is presented unchanged")
	check(float(normal.presented) > 0.999, "a sustained rate is never presented slower")

	g.set_speed(2)
	await get_tree().create_timer(3.0, true, false, true).timeout
	var fast := await measure(s, "fast-limited")
	var world_rate := float(fast.world_rate)
	check(world_rate < 1.7, "emulated CPU limit lowers the fast authority rate")
	check(g.speed == 1 and s.field_speed == 1 and Engine.time_scale <= FAST, "dial keeps fast selected")
	check(s.local_host._single_clock.size() > 1 and is_equal_approx(float(s.local_host._single_clock[1]), FAST), "authority is still asked for fast speed")
	check(int(s.saved_play_clock().get("speed", -1)) == 1, "save keeps fast speed")
	check(float(fast.presented) < FAST * 0.9, "owner does not present the unreachable rate")
	check(absf(float(fast.presented) - world_rate) / world_rate < 0.2, "owner presentation follows the achieved rate")
	check(absf(float(fast.eagle_rate) - world_rate) / world_rate < 0.2, "visible Eagle Sight counter follows the achieved rate")
	check(int(fast.largest_reversal) <= 4, "visible Eagle Sight counter is not pulled back by snapshots")
	check(int(fast.backward_ticks) <= 12, "visible Eagle Sight counter rarely moves backwards")

	g.set_speed(1)
	check(Engine.time_scale == 1.0, "returning to normal presents 1x at once")
	await get_tree().create_timer(2.5, true, false, true).timeout
	var again := await measure(s, "normal-again", 3.0)
	check(Engine.time_scale == 1.0 and absf(float(again.world_rate) - 1.0) < 0.15, "normal speed stays exact after a limited fast period")

	g.set_speed(2)
	await get_tree().create_timer(3.0, true, false, true).timeout
	check(Engine.time_scale < FAST * 0.9, "limit applies again on the next fast selection")
	await s.local_host.stop()
	# Ending the session may itself return the dial to normal; either way the
	# presented rate must again equal the selection, not the achieved fraction.
	check(is_equal_approx(Engine.time_scale, FAST if g.speed == 1 else 1.0) and s.local_host.get("authority_rate") != null and float(s.local_host.get("authority_rate")) == 1.0,
		"stopping the authority restores the selected rate")
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	FileAccess.open("user://worker-rate-presentation.json", FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	print("WORKER_RATE_PRESENTATION ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
