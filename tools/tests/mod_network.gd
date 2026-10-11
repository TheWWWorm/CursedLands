extends Node
## Run host/client/reject in separate processes with disposable user folders.
var checks := 0
var failures := 0
var role := "host"
var coordination := ""
var port := 29884
var session: Session
var refused := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func until(condition: Callable, seconds := 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await get_tree().process_frame
	return condition.call()

func marker(name: String) -> String:
	return coordination.path_join(name)

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"auto_graphics":0},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--coordination="): coordination = arg.trim_prefix("--coordination=")
		if arg.begins_with("--port="): port = arg.trim_prefix("--port=").to_int()
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import example")
	check(not coordination.is_empty(), "explicit shared test directory")
	check(ModStore.create_profile(role) == "", "create independent local profile")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "same gameplay content mounts")
	ModStore.apply_rules({"coop_full_xp":1 if role == "host" else 0})
	if role == "reject": ModStore.apply_values({"example.quick-recovery:seconds":9.0})
	GameData.player_name = "Mod " + role
	CoopProgress.bring_slot = CoopProgress.NEW if role == "client" else ""
	session = Session.new()
	session.name = "Session"
	get_parent().add_child(session)
	if role == "host":
		check(session.host(port, 3) == OK, "real ENet host starts")
		ModStore.atomic_write(marker("ready"), "ready".to_utf8_buffer())
		check(await until(func(): return session.players.size() == 2), "matching client admitted")
		check(session.coop.joiners.has("mod client"), "compatible brought hero is accepted before admission")
		check(await until(func(): return FileAccess.file_exists(marker("client-ready"))), "client receives rules")
		check(session.mod_config.rules.coop_full_xp == 1, "guest RPC cannot overwrite host rule")
		check(session.apply_mod_rules({"auto_exit":0},{"example.quick-recovery:seconds":4.5}) == "", "host applies shared option transaction")
		check(await until(func(): return FileAccess.file_exists(marker("client-updated"))), "client acknowledges new revision")
		check(await until(func(): return session.players.size() == 1), "ordinary disconnect removes client")
		ModStore.atomic_write(marker("reconnect-ready"), "ready".to_utf8_buffer())
		check(await until(func(): return session.players.size() == 2), "updated client can reconnect")
		check(await until(func(): return FileAccess.file_exists(marker("client-reconnected"))), "reconnected client receives current rules")
		check(await until(func(): return session.players.size() == 1), "reconnected client disconnects")
		ModStore.atomic_write(marker("reject-ready"), "ready".to_utf8_buffer())
		check(await until(func(): return FileAccess.file_exists(marker("rejected"))), "mismatching client receives actionable refusal")
		check(session.players.size() == 1, "incompatible client never enters player list")
	else:
		check(await until(func(): return FileAccess.file_exists(marker("ready"))), "host ready")
		session.net.refused.connect(func(_title, _text): refused = true)
		check(session.join("127.0.0.1",port) == OK, "real client connects")
		if role == "reject":
			check(await until(func(): return refused), "different mod options rejected")
			ModStore.atomic_write(marker("rejected"), "done".to_utf8_buffer())
		else:
			check(await until(func(): return session.players.size() == 2 and session.mod_config.rules.coop_full_xp == 1), "host rules replace local rules after hello")
			check(ModStore.profile().rules.coop_full_xp == 0, "host leaves local defaults intact")
			session._rpc_mod_rules.rpc_id(1, {"coop_full_xp":0}, {}, int(session.mod_config.revision))
			await get_tree().create_timer(0.2).timeout
			ModStore.atomic_write(marker("client-ready"), "ready".to_utf8_buffer())
			check(await until(func(): return session.mod_config.values["example.quick-recovery:seconds"] == 4.5), "runtime update reaches client")
			check(ModStore.capability("revival.seconds") == 4.5, "gameplay reads host value")
			ModStore.atomic_write(marker("client-updated"), "done".to_utf8_buffer())
			session.online = false
			session.multiplayer.multiplayer_peer.close()
			session.players.clear()
			check(await until(func(): return FileAccess.file_exists(marker("reconnect-ready"))), "host ready for reconnect")
			CoopProgress.bring_slot = ""
			check(session.join("127.0.0.1",port) == OK, "reconnect existing run")
			check(await until(func(): return session.players.size() == 2 and session.mod_config.values["example.quick-recovery:seconds"] == 4.5), "reconnect retains the authoritative mod options")
			ModStore.atomic_write(marker("client-reconnected"), "done".to_utf8_buffer())
			await get_tree().create_timer(0.2).timeout
	session.online = false
	session.multiplayer.multiplayer_peer.close()
	session.free()
	check(ModStore.session() == null, "session configuration detached")
	print("MOD_NETWORK ", role, " ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
