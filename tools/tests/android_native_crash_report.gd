extends Node
## Two-launch Android 12+ test in an isolated, debuggable QA package only.
## After native-crash-ready.json appears, the external controller sends SIGABRT
## to its PID as the package's UID, waits for death, then relaunches this fixture.
## No crash trigger is included in the plugin or player build.

var checks := 0
var failures := 0
var notices_finished := false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _ready() -> void:
	_run.call_deferred()


func _notices() -> void:
	await get_parent().startup_notices()
	notices_finished = true


func _run() -> void:
	var cr := CrashReport.instance
	check(OS.has_feature("android"), "runs on Android")
	check(bool(cr.info.get("android_exit_registered", false)), "session registered with Android")
	if failures:
		_finish({})
		return
	if not FileAccess.file_exists("user://native-crash-ready.json"):
		GameData.trace("native crash fixture: waiting for external SIGABRT")
		FileAccess.open("user://native-crash-ready.json", FileAccess.WRITE).store_string(JSON.stringify(cr.info))
		print("NATIVE_CRASH_READY")
		return
	var first: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://native-crash-ready.json"))
	var previous := cr.previous.duplicate(true)
	check(previous.get("session") == first.session, "previous session matched")
	var exit_info: Dictionary = previous.get("android_exit", {})
	check(exit_info.get("session") == first.session and int(exit_info.get("pid", 0)) == int(first.pid), "OS record matched to session and PID")
	check(int(exit_info.get("reason", 0)) == 5, "OS classified a native crash")
	check(int(exit_info.get("status", 0)) == 6, "OS recorded SIGABRT")
	var trace := String(exit_info.get("native_trace", ""))
	check(trace.contains("signal: 6 SIGABRT"), "real tombstone signal decoded")
	check(trace.contains("#0 pc ") and trace.contains(".so"), "real native library stack decoded")
	check(trace.contains("BuildId:"), "symbolication build ID preserved")
	var plugin := CrashReport._android_diagnostics()
	var started := Time.get_ticks_usec()
	var repeat: Dictionary = JSON.parse_string(plugin.previous_exit_report(int(first.pid), first.session))
	var read_usec := Time.get_ticks_usec() - started
	check(repeat == exit_info, "repeat read gives the same crash")
	check(JSON.parse_string(plugin.previous_exit_report(int(first.pid), "000000000000")) == {}, "wrong session rejected despite matching PID")
	check(JSON.parse_string(plugin.previous_exit_report(-1, first.session)) == {}, "invalid PID rejected")
	check(JSON.parse_string(plugin.previous_exit_report(OS.get_process_id(), first.session)) == {}, "new process cannot inherit the previous crash")
	check(not bool(plugin.register_crash_session("not-a-session")), "invalid session token rejected")
	CrashReport.save_dir_override = "user://reports/native"
	RendererChoice.notice = ""
	_notices.call_deferred()
	for i in 6:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var box := get_parent().get_node_or_null("StartupNotices/CrashReportBox") as CrashReportBox
	check(box != null and not notices_finished, "real native crash offered before the menu")
	check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "report needs no 3D menu")
	if box:
		box.act(0)
		var files := DirAccess.get_files_at(CrashReport.save_dir_override)
		check(files.size() == 1, "native report saved")
		if files.size() == 1:
			var report := FileAccess.get_file_as_string(CrashReport.save_dir_override.path_join(files[0]))
			check(report.contains(trace), "saved report contains the full decoded crash trace")
		get_viewport().get_texture().get_image().save_png("user://native-crash-report.png")
		box._answer(true)
		await get_tree().process_frame
		check(notices_finished, "dismissing report releases startup")
	_finish({"exit_info": exit_info, "read_usec": read_usec})


func _finish(extra: Dictionary) -> void:
	extra.merge({"checks": checks, "failures": failures})
	FileAccess.open("user://android-native-crash-report.json", FileAccess.WRITE).store_string(JSON.stringify(extra, "\t") + "\n")
	print("ANDROID_NATIVE_CRASH_REPORT ", JSON.stringify(extra))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
