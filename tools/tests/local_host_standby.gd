extends Node
## A pre-started simulation worker compiles while the menus run, takes over the
## next campaign start, and otherwise exits cleanly without a crash marker.
## A worker's startup must not remove its running owner's crash marker.
var checks := 0
var failures: Array[String] = []
var rows := []
var out := "user://local-host-standby"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count := 1) -> void:
	for i in count: await get_tree().process_frame

func marker(pid: int) -> String:
	return CrashReport.DIR.path_join("%s%d.cfg" % [CrashReport.MARK_PREFIX, pid])

## Booted: the standby has compiled its scripts and recorded its own state.
func await_booted(pid: int, seconds := 90.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var cfg := ConfigFile.new()
		if cfg.load(marker(pid)) == OK and cfg.get_value("session", "state", "") == "standby":
			return true
		await frames()
	return false

func await_exit(pid: int, seconds := 10.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and OS.is_process_running(pid):
		await frames()
	return not OS.is_process_running(pid)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()

func run() -> void:
	check(LocalHost.standby_supported(), "desktop owner supports a standby worker")
	var own_marker := marker(OS.get_process_id())
	check(FileAccess.file_exists(own_marker), "owner has a running crash marker")

	# 1. A booted standby takes over the next solo start.
	LocalHost.prepare_standby(get_tree())
	var first: Dictionary = LocalHost._standby.duplicate()
	check(not first.is_empty() and OS.is_process_running(int(first.pid)), "standby worker process starts")
	check(FileAccess.file_exists(String(first.config) + LocalHost.STANDBY_HEARTBEAT), "owner publishes a heartbeat")
	LocalHost.prepare_standby(get_tree())
	check(LocalHost._standby.get("pid") == first.get("pid"), "preparing again keeps the same standby")
	check(await await_booted(int(first.pid)), "standby boots and marks itself as standby")
	await frames(10)
	check(FileAccess.file_exists(own_marker), "worker startup keeps the running owner's crash marker")
	var session := Session.new()
	session.name = "Session"
	get_parent().add_child(session)
	var started := Time.get_ticks_msec()
	var error: Error = await session.local_host.start(0, 1, true)
	var takeover_ms := Time.get_ticks_msec() - started
	check(error == OK, "solo start through the standby succeeds")
	check(session.local_host.process_id == int(first.pid), "solo start uses the standby process")
	check(LocalHost._standby.is_empty(), "the standby is consumed")
	check(not FileAccess.file_exists(String(first.config)) and not FileAccess.file_exists(String(first.config) + LocalHost.STANDBY_HEARTBEAT),
		"configuration and heartbeat are removed after the handoff")
	var cfg := ConfigFile.new()
	check(cfg.load(marker(int(first.pid))) == OK and cfg.get_value("session", "state", "") == "foreground",
		"the configured worker is an ordinary foreground session")
	await session.local_host.stop()
	check(await await_exit(int(first.pid)), "configured worker stops with its owner")
	check(not FileAccess.file_exists(marker(int(first.pid))), "stopped worker leaves no crash marker")
	rows.append({"case": "takeover", "ms": takeover_ms})

	# 2. Discarding a waiting standby ends it cleanly.
	LocalHost.prepare_standby(get_tree())
	var second: Dictionary = LocalHost._standby.duplicate()
	check(await await_booted(int(second.pid)), "second standby boots")
	var discarded := Time.get_ticks_msec()
	LocalHost.discard_standby()
	check(await await_exit(int(second.pid)), "discarded standby exits by itself")
	check(not FileAccess.file_exists(marker(int(second.pid))), "discarded standby removes its marker")
	rows.append({"case": "discard", "exit_ms": Time.get_ticks_msec() - discarded})

	# 3. The keeper's exit (owner shutdown) also ends a waiting standby.
	LocalHost.prepare_standby(get_tree())
	var third: Dictionary = LocalHost._standby.duplicate()
	check(await await_booted(int(third.pid)), "third standby boots")
	var keeper := get_tree().root.get_node_or_null("LocalHostStandby")
	check(keeper != null, "standby keeper refreshes the heartbeat")
	if keeper: keeper.queue_free()
	check(await await_exit(int(third.pid)), "owner shutdown ends the waiting standby")
	check(LocalHost._standby.is_empty(), "owner shutdown forgets the standby")

	# 4. Another game folder never adopts a standby for different files.
	LocalHost.prepare_standby(get_tree())
	var fourth: Dictionary = LocalHost._standby.duplicate()
	var root := GameData.root
	GameData.root = root.path_join("other-campaign")
	check(LocalHost._take_standby().is_empty(), "a standby for other game files is not used")
	GameData.root = root
	check(await await_exit(int(fourth.pid), 30.0), "the mismatched standby exits")

	# 5. A waiting standby's marker is never reported as a crash.
	var fake := ConfigFile.new()
	fake.set_value("session", "pid", 999999)
	fake.set_value("session", "session", "standby-test")
	fake.set_value("session", "state", "standby")
	fake.save(marker(999999))
	check(CrashReport.scan(OS.get_process_id()).is_empty() and not FileAccess.file_exists(marker(999999)),
		"an orphaned standby marker is removed without a crash report")

	session.queue_free()
	await frames(4)
	FileAccess.open(out.path_join("local-host-standby.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"))
	print("LOCAL_HOST_STANDBY ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
