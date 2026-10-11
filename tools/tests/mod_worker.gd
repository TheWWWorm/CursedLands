extends Node
## Actual separate simulation owner, rules acknowledgement, sandbox and saves.
var checks := 0
var failures := 0
var acked := false
var problem := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func until(condition: Callable, seconds := 45.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await get_tree().process_frame
	return condition.call()

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"auto_graphics":0,"show_tutorial":0},true)
	TutorialPanel.auto_show = false
	MoviePlayer.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import example")
	check(ModStore.create_profile("Worker sandbox", true) == "", "create worker profile")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "mount owner package")
	var s := Session.new()
	s.name = "Session"
	get_parent().add_child(s)
	var g := Game.new()
	g.session = s; s.game = g
	get_parent().add_child(g)
	s.mod_rules_result.connect(func(error): acked = true; problem = error)
	var result := await s.local_host.start(0,1,true)
	check(result == OK and s.local_host.frontend and not s.is_host, "separate authority starts and authenticates owner")
	if result != OK: get_tree().quit(1); return
	s.request_mod_rules({"sandbox_invulnerable":1}, {"example.quick-recovery:seconds":7.5})
	check(await until(func(): return acked), "owner receives explicit settings acknowledgement")
	check(problem == "" and ModStore.capability("revival.seconds") == 7.5 and s.mod_config.rules.sandbox_invulnerable == 1, "worker publishes accepted effective values")
	check(ModStore.profile().values["example.quick-recovery:seconds"] == 3, "running edits leave next-run defaults intact")
	acked = false
	s._rpc_mod_rules.rpc_id(1, {"sandbox_invulnerable":0}, {}, int(s.mod_config.revision)-1)
	check(await until(func(): return acked) and problem != "" and s.mod_config.rules.sandbox_invulnerable == 1, "stale owner edit is refused without partial application")
	var answer := await s.local_host.request("campaign", {"intro":false})
	check(answer.get("ok",false), "worker starts campaign with effective configuration")
	check(await until(func(): return s.world != null and not s._remote_loading), "owner receives first zone")
	if s.world != null:
		var before := s.state.money
		answer = await s.local_host.request("sandbox", {"action":"gold"})
		check(answer.get("ok",false), "sandbox command accepted by authority")
		check(await until(func(): return s.state.money == before + 1000), "sandbox gold synchronizes to owner")
		answer = await s.local_host.request("save", {"slot":"mod_worker", "camera":s.local_host.view()})
		check(answer.get("ok",false) and await until(func(): return FileAccess.file_exists(SaveInfo.path("mod_worker"))), "worker writes profile save")
		var saved := CampaignState.load_from(SaveInfo.path("mod_worker"))
		check(saved != null and saved.mod_config.sandbox and saved.mod_config.values["example.quick-recovery:seconds"] == 7.5, "save captures effective sandbox and mod options")
		check(not FileAccess.file_exists(CampaignProfile.save_directory(GameData.campaign_id).path_join("mod_worker.sav")), "ordinary save namespace untouched")
		acked = false
		s.request_mod_rules({"sandbox_invulnerable":0}, {})
		check(await until(func(): return acked) and problem == "", "live sandbox toggle changes after saving")
		answer = await s.local_host.request("load", {"slot":"mod_worker"})
		check(answer.get("ok", false) and await until(func(): return not s._remote_loading and s.mod_config.rules.sandbox_invulnerable == 1), "real worker reload restores saved effective rules")
	var pid := s.local_host.process_id
	await s.local_host.stop()
	check(not OS.is_process_running(pid), "authority child stops cleanly")
	g.queue_free(); s.queue_free()
	for i in 5: await get_tree().process_frame
	check(ModStore.session() == null, "owner teardown detaches rules")
	print("MOD_WORKER ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
