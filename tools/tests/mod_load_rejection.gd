extends "coop_story.gd"
## An incompatible saved option set must leave the running co-op world usable.
var checks := 0
var failures := 0
var rows := []
var shown := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	rows.append({"label":label, "ok":ok})
	print("PASS " if ok else "FAIL ", label)

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0,
		"net_directory":0, "auto_graphics":0, "control_mode":1, "pad_enabled":0, "coop_clock":1}, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import example package")
		if arg == "--shown": shown = true
	check(ModStore.create_profile("Load rejection") == "", "create disposable mod profile")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "mount matching gameplay package")
	var a := branch("Host", true); host = a.s; hg = a.g
	var b := branch("Guest", false); client = b.s; cg = b.g
	check(host.host(29937, 2) == OK, "real ENet host starts")
	GameData.player_name = "Load guard guest"
	check(client.join("127.0.0.1", 29937) == OK, "real guest connects")
	if not await until(func(): return host.players.size() == 2 and client.my_index == 1):
		check(false, "guest admitted"); await finish(); return
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero"); host.state.ensure_hero(1, "Human Hero", "Load guard guest")
	await host.enter_zone("bz1g", 1, false)
	check(await until(func(): return client.world != null and not client.loading_game and not client._remote_loading), "both peers load original village")
	check(host.save_game("mod_load_guard") == OK, "save current options")
	check(host.apply_mod_rules({}, {"example.quick-recovery:seconds":7.5}) == "", "host changes a live mod option at camp")
	check(await until(func(): return client.mod_config.values.get("example.quick-recovery:seconds") == 7.5), "guest receives the changed option")
	var saved := CampaignState.load_from(SaveInfo.path("mod_load_guard"))
	check(saved != null and ModStore.progress_signature(saved.mod_config) != ModStore.progress_signature(host.mod_config), "readable save has different valid mod options")
	var before_world := host.world
	var before_state := host.state
	var generation := host._load_serial
	var answer: bool = await host.load_game_shown("mod_load_guard") if shown else host.load_game("mod_load_guard")
	check(not answer, "running co-op group rejects incompatible saved options")
	await frames(12)
	check(host.world == before_world and host.state == before_state, "refusal preserves current world and campaign")
	check(not host.loading_game and host.world.process_mode != Node.PROCESS_MODE_DISABLED, "refusal leaves host simulation enabled")
	check(not client.loading_game and not client._remote_loading, "refusal leaves guest out of loading state")
	check(host._load_serial == generation and client._pool_epoch == generation, "refusal preserves command generation")
	check(LoadingScreen._current == null, "refusal leaves no loading overlay")
	var clock := host.world.time
	check(await until(func(): return host.world.time > clock + 0.2, 3.0), "simulation advances after refusal")
	var hero: GameUnit = host.party_units(0)[0]
	var gait := 3 if hero.gait() != 3 else 2
	host.submit({"t":"gait", "units":[hero.uid], "gait":gait})
	check(await until(func(): return hero.gait() == gait, 2.0), "player command works after refusal")
	check(host.save_game("mod_load_after_refusal") == OK, "saving still works after refusal")
	host.set_coop_clock(2)
	host.set_coop_clock(0)
	check(await until(func(): return client.clock_paused and client.clock_speed == 1), "both peers deliberately pause at double speed")
	answer = await host.load_game_shown("mod_load_guard") if shown else host.load_game("mod_load_guard")
	check(not answer, "paused group also rejects incompatible saved options")
	await frames(12)
	check(host.clock_paused and client.clock_paused and get_tree().paused, "refusal preserves the intentional pause")
	check(host.clock_speed == 1 and client.clock_speed == 1 and Engine.time_scale == 2.0, "refusal preserves the selected speed")
	check(host._load_serial == generation and client._pool_epoch == generation, "paused refusal preserves command generation")
	host.set_coop_clock(1)
	check(await until(func(): return not client.clock_paused and client.clock_speed == 0), "host can resume after refusal")
	answer = await host.load_game_shown("mod_load_after_refusal") if shown else host.load_game("mod_load_after_refusal")
	check(answer, "compatible saved options still load with a connected guest")
	check(await until(func(): return not client.loading_game and not client._remote_loading and client._pool_epoch == host._load_serial), "compatible load completes on both peers")
	check(not host.loading_game and host.world != before_world and host.state != before_state, "compatible load replaces the world and campaign")
	clock = host.world.time
	check(await until(func(): return host.world.time > clock + 0.2, 3.0), "simulation advances after compatible load")
	await finish()

func finish() -> void:
	FileAccess.open("user://mod-load-rejection.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"shown":shown,"rows":rows}, "  "))
	LoadingScreen.end(); get_tree().paused = false; Engine.time_scale = 1.0
	for s: Session in [host, client]:
		if is_instance_valid(s):
			s.online = false
			if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	await frames()
	print("MOD_LOAD_REJECTION ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
