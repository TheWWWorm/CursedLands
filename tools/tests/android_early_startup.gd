extends Node
## Isolated Android QA package. The controller interrupts Java startup before
## native engine initialization, then supplies early-expected.json for recovery.
## No crash trigger or hold is included in the production template.
var checks := 0
var failures := 0
var notices_finished := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func settle() -> void:
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _notices() -> void:
	await get_parent().startup_notices()
	notices_finished = true

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://early-expected.json"))
	var cr := CrashReport.instance
	var plugin := CrashReport._android_diagnostics()
	check(OS.has_feature("android") and plugin != null, "uses Android diagnostics")
	var boot := CrashReport.android_startup()
	var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://crash/android-startup.json"))
	check(not journal.has("active") and boot.get("current") == null, "durable game marker completes early tracking")
	var marker := ConfigFile.new()
	check(marker.load("user://crash/running_%d.cfg" % OS.get_process_id()) == OK, "regular marker exists")
	check(marker.get_value("session", "session", "") == cr.info.session, "regular marker retains the early session token")
	check(RenderingServer.get_current_rendering_method() == expected.get("renderer", "gl_compatibility"), "expected renderer actually runs")
	check(cr.startup_failures.size() == int(expected.get("count", 1)), "expected retained launch count")
	check(not plugin.complete_startup_tracking("000000000000"), "unrelated token cannot complete a launch")
	plugin.acknowledge_startup_report("000000000000")
	check(CrashReport.android_startup().get("failures", []).size() == cr.startup_failures.size(), "unrelated token cannot discard a failure")
	if expected.has("session"):
		var failed: Dictionary = cr.startup_failures[-1]
		check(failed.session == expected.session, "failed launch identity retained across restart")
		check(failed.requested_renderer == expected.get("requested", "mobile"), "attempted Vulkan method retained")
		check(failed.startup_stage == "native_engine_initializing", "failure happened before engine initialization")
		check(failed.get("android_exit", {}).get("native_trace_status") == "available", "real native tombstone retained")
		var trace := String(failed.get("android_exit", {}).get("native_trace", ""))
		check(trace.contains("signal: 6 SIGABRT") and trace.contains("BuildId:"), "native signal, library addresses and build IDs survive")
		check(cr.previous.get("session") == failed.session, "failed launch is offered to the player")
		if expected.get("fallback", false):
			check(RendererChoice.chosen() == 0 and GameData.option("renderer") == 0, "failed Vulkan attempt selects Compatibility")
			check(RendererChoice.notice == RendererChoice.FAILED, "recovery explains renderer fallback")
		check(cr.report_text(cr.previous, 5000).contains(trace), "export text includes full cached native trace")
		# An ordinary Export log must also contain retained failures, even if
		# the previous crash dialog has already been dismissed.
		check(cr.report_text({}, 5000).contains(trace), "normal log export retains early failures")
		FileAccess.open("user://retained-early-trace.txt", FileAccess.WRITE).store_string(trace)
	if expected.get("ui", false):
		for lang: String in ["en", "ru", "de"]:
			RemakeText.lang = lang
			var box := CrashReportBox.open(get_parent(), cr.previous, true)
			await settle()
			var rects := box._rects()
			check(rects.top >= 0 and rects.ok.end.y <= 600, lang + " recovered report fits")
			check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "report is accessible without 3D menu")
			get_viewport().get_texture().get_image().save_png("user://early-recovery-" + lang + ".png")
			box.queue_free(); await settle()
		RemakeText.lang = "en"
	if expected.get("save", false):
		CrashReport.save_dir_override = "/proc/cursedlands-invalid-report-folder"
		check(cr.save_report(cr.previous).is_empty(), "failed export is reported")
		check(CrashReport.android_startup().get("failures", []).size() == cr.startup_failures.size(), "failed export preserves diagnostics")
		CrashReport.save_dir_override = "user://reports/early"
		RendererChoice.notice = ""
		_notices.call_deferred(); await settle()
		var box := get_parent().get_node_or_null("StartupNotices/CrashReportBox") as CrashReportBox
		check(box != null and not notices_finished, "startup waits for early crash report")
		if box:
			box.act(0)
			check(CrashReport.android_startup().get("failures", []).is_empty(), "successful export acknowledges retained failures")
			var reports := DirAccess.get_files_at(CrashReport.save_dir_override)
			check(reports.size() == 1, "full recovery report saved")
			if reports.size() == 1:
				var report := FileAccess.get_file_as_string(CrashReport.save_dir_override.path_join(reports[0]))
				check(report.contains(FileAccess.get_file_as_string("user://retained-early-trace.txt")), "saved report includes exact retained trace")
			box._answer(true); await settle()
			check(notices_finished, "report dismissal releases startup")
	if expected.get("confirm", false):
		RendererChoice.confirm()
		check(RendererChoice.chosen() == 2 and not FileAccess.file_exists(RendererChoice.TRIAL), "successful Mobile startup remains selected")
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"session":cr.info.session,"retained":cr.startup_failures.size()}
	FileAccess.open("user://android-early-startup-result.json", FileAccess.WRITE).store_string(JSON.stringify(result))
	print("ANDROID_EARLY_STARTUP ", JSON.stringify(result))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
