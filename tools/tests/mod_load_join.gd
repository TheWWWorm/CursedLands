extends "coop_story.gd"
## Hold a solo host's saved-config transition open across a real ENet hello.
var checks := 0
var failures := 0
var rows := []
var refusal := ""

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
		"net_directory":0, "auto_graphics":0, "control_mode":1, "pad_enabled":0}, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import example package")
	check(ModStore.create_profile("Load join") == "", "create disposable mod profile")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "mount matching gameplay package")
	var a := branch("Host", true); host = a.s; hg = a.g
	var b := branch("Guest", false); client = b.s; cg = b.g
	client.net.refused.connect(func(_title, reason): refusal = reason)
	check(host.host(29938, 2) == OK, "real ENet host starts alone")
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	await host.enter_zone("bz1g", 1, false)
	check(host.save_game("mod_load_join") == OK, "save initial options")
	check(host.apply_mod_rules({}, {"example.quick-recovery:seconds":7.5}) == "", "host changes a live option at camp")
	var saved := CampaignState.load_from(SaveInfo.path("mod_load_join"))
	check(saved != null and host._can_load_saved_state(saved), "host alone can restore different saved options")
	client.mod_config = host.mod_config.duplicate(true)
	GameData.player_name = "Load transition guest"
	# Deliberately hold this normally short transition until a real guest hello
	# arrives. The actual saved-state restore and subsequent join run normally.
	host._begin_host_load(saved.current_zone, true, saved.mod_config)
	check(client.join("127.0.0.1", 29938) == OK, "guest connects with the previous live settings")
	check(await until(func(): return not refusal.is_empty()), "join receives a refusal during settings restoration")
	check(refusal.contains("finish loading"), "refusal explains when the guest can retry")
	check(host.players.size() == 1, "transitional join never enters the player list")
	check(host._load_state("mod_load_join", saved), "solo saved-state restoration completes")
	check(not host.loading_game and host.mod_config.values["example.quick-recovery:seconds"] == 3, "saved option values become effective")
	client.online = false
	client.multiplayer.multiplayer_peer.close()
	await frames(16)
	client.mod_config = host.mod_config.duplicate(true)
	refusal = ""
	check(client.join("127.0.0.1", 29938) == OK, "guest reconnects with the restored settings")
	check(await until(func(): return host.players.size() == 2 and client.world != null and not client.loading_game and not client._remote_loading), "matching guest joins and receives the restored world")
	check(refusal.is_empty(), "load transition does not leave a stale join refusal")
	var clock := host.world.time
	check(await until(func(): return host.world.time > clock + 0.2, 3.0), "host simulation advances after the join")
	check(host.save_game("mod_load_join_after") == OK, "saving works after restored-settings join")
	await finish()

func finish() -> void:
	FileAccess.open("user://mod-load-join.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows}, "  "))
	LoadingScreen.end(); get_tree().paused = false; Engine.time_scale = 1.0
	for s: Session in [host, client]:
		if is_instance_valid(s):
			s.online = false
			if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	await frames()
	print("MOD_LOAD_JOIN ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
