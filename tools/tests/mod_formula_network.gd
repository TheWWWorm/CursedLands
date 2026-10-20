extends "mod_network.gd"
## Real ENet peers: admission, reward replication, host options, saves and errors.
var view: Game
var examples := ""
var baseline := 0.0

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--coordination="): coordination = arg.trim_prefix("--coordination=")
		if arg.begins_with("--examples="): examples = arg.trim_prefix("--examples=")
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"auto_graphics":0,"show_tutorial":0}, true)
	TutorialPanel.auto_show = false
	MoviePlayer.enabled = false
	for name in ["expedition-xp", "quest-focus"]:
		check(ModStore.import_package(examples.path_join(name + "-1.0.0.eimod")) == "", "import " + name)
	check(ModStore.create_profile("Formula " + role, true) == "", "create independent profile")
	check(ModStore.set_packages(["example.quest-focus@1.0.0", "example.expedition-xp@1.0.0"]) == "" and ModStore.mount() == "", "mount ordered formulas")
	check(ModStore.apply_rules({"coop_full_xp":1, "sandbox_invulnerable":1}) == "", "set shared fixture rules")
	if role == "reject":
		check(ModStore.apply_values({"example.expedition-xp:multiplier":2.0}) == "", "mismatching client options")
	GameData.player_name = "Formula " + role
	session = Session.new(); session.name = "Session"; get_parent().add_child(session)
	if role == "host":
		check(session.host(0, 3) == OK, "start host")
		ModStore.atomic_write(marker("ready"), str(session.host_port).to_utf8_buffer())
		check(await until(func(): return FileAccess.file_exists(marker("rejected"))), "wrong options rejected before gameplay")
		check(session.players.size() == 1, "incompatible peer never admitted")
		check(await until(func(): return session.players.size() == 2), "matching peer admitted")
	elif role == "reject":
		session.net.refused.connect(func(_title, _text): refused = true)
		check(await until(func(): return FileAccess.file_exists(marker("ready"))), "host ready")
		session.join("127.0.0.1", FileAccess.get_file_as_string(marker("ready")).to_int())
		check(await until(func(): return refused), "mismatched formulas refused")
		ModStore.atomic_write(marker("rejected"), "done".to_utf8_buffer())
		await finish(); return
	else:
		check(await until(func(): return FileAccess.file_exists(marker("rejected"))), "refusal test complete")
		check(session.join("127.0.0.1", FileAccess.get_file_as_string(marker("ready")).to_int()) == OK, "connect matching client")
	view = Game.new(); view.session = session; session.game = view; get_parent().add_child(view)
	if role == "host":
		session.state = CoopProgress.fresh_state()
		session.state.mod_config = session.mod_config.duplicate(true)
		session.state.ensure_hero(1, "Human Hero", "Formula client")
		await session.enter_zone("bz1g", 1, false)
	check(await until(func(): return session.world != null and not session.loading_game and not session._remote_loading and not session.party_units(session.my_index).is_empty(), 60), "shared village loads")
	if failures: await finish(); return
	var hero := session.party_units(session.my_index)[0] as GameUnit
	baseline = float(hero.get_meta("hero").exp_total)
	ModStore.atomic_write(marker(role + "-loaded"), str(baseline).to_utf8_buffer())
	check(await until(func(): return FileAccess.file_exists(marker("host-loaded")) and FileAccess.file_exists(marker("client-loaded"))), "both replicas ready")
	var calls := ModFormula.invocations
	if role == "host":
		check(session.apply_mod_rules({}, {"example.expedition-xp:multiplier":2.0}) == "", "host changes options at camp")
		check(await until(func(): return FileAccess.file_exists(marker("options"))), "client receives option revision")
		XpRules.give(session, 100.0, "quest")
		check(ModFormula.invocations == calls + 2, "host invokes each reward formula exactly once")
		check(session.save_game("formula-network") == OK, "host saves modded campaign")
		var save := CampaignState.load_from(SaveInfo.path("formula-network"))
		check(save != null and save.mod_config.values["example.expedition-xp:multiplier"] == 2.0, "network save preserves formula option")
		check(await until(func(): return FileAccess.file_exists(marker("reward"))), "client receives transformed reward")
		session.stop_mod_script("Deliberate network failure fixture")
		check(await until(func(): return FileAccess.file_exists(marker("stopped"))), "client receives mod failure")
		var before := session.world.time
		await get_tree().create_timer(0.3).timeout
		check(session.world.time == before and session.save_game("forbidden") == ERR_UNAVAILABLE, "failed simulation freezes and refuses saves")
	else:
		check(await until(func(): return session.mod_config.values.get("example.expedition-xp:multiplier") == 2.0), "host formula options replicate")
		ModStore.atomic_write(marker("options"), "ready".to_utf8_buffer())
		var h: Dictionary = hero.get_meta("hero")
		var expected := 250.0 * pow(1.04, float(h.int) + Perks.attr_bonus(h, "int") - 25.0)
		check(await until(func(): return float(hero.get_meta("hero").exp_total) > baseline), "client receives experience")
		check(absf(float(hero.get_meta("hero").exp_total) - baseline - expected) < 0.01, "replica receives one transformed reward")
		check(ModFormula.invocations == calls, "replica executes no formula callbacks")
		ModStore.atomic_write(marker("reward"), "done".to_utf8_buffer())
		check(await until(func(): return session.mod_script_failed), "failure reaches remote client")
		check(session.save_game("forbidden") == ERR_UNAVAILABLE, "client blocks saves after failure")
		session.coop._origin_new = true
		var merged := session.coop.merged_count
		session.coop._rpc_package({"mod_config":session.mod_config})
		check(session.coop.merged_count == merged, "failed run cannot overwrite returned co-op progress")
		ModStore.atomic_write(marker("stopped"), "done".to_utf8_buffer())
		await get_tree().create_timer(0.5).timeout
	await finish()

func finish() -> void:
	session.online = false; session.multiplayer.multiplayer_peer.close()
	if view: view.queue_free()
	session.queue_free()
	for i in 5: await get_tree().process_frame
	print("MOD_FORMULA_NETWORK ", role, " ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
