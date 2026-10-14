extends Node
## Exercise the real startup notice coroutine before any movie or 3D menu.
## Run with an isolated user-data directory; writes reports and UI captures.

var checks := 0
var failures := 0
var completed := false
var main: Node


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func run_notices() -> void:
	completed = false
	await main.startup_notices()
	completed = true


func settle() -> void:
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func check_layout(box: CrashReportBox, label: String) -> void:
	var r := box._rects()
	check(r.top >= 0 and (r.ok as Rect2).end.y <= 600, label + " fits vertically")
	for key: String in [box.title, box.message, RemakeText.t("Save report"), RemakeText.t("Copy to clipboard")]:
		for line: String in box.wrap_text(key, 370, 2):
			check(box.text_width(line, 2) <= 371, label + " text fits horizontally")


func _ready() -> void:
	main = get_parent()
	_run.call_deferred()


func _run() -> void:
	var cr := CrashReport.instance
	cr.previous = {}
	RendererChoice.notice = ""
	await run_notices()
	check(completed and main.get_node_or_null("StartupNotices") == null, "clean startup needs no acknowledgement")
	var logfile := "user://startup-previous.log"
	FileAccess.open(logfile, FileAccess.WRITE).store_string("SIMULATED PREVIOUS SESSION\nstartup: building main menu\n")
	var previous := {"session": "startup-recovery-fixture", "version": "1.1.0", "state": "foreground",
		"focus": "in", "last": "startup: building main menu", "log": logfile}
	if DisplayServer.get_name() == "headless":
		cr.previous = previous
		await run_notices()
		check(completed and main.get_node_or_null("StartupNotices") == null, "headless startup never blocks on a dialog")
		_finish()
		return
	GameData.options.merge({"auto_graphics": 0, "display_mode": 0, "confine_mouse": 0}, true)
	if not OS.has_feature("android"):
		await settle()   # GameData applies the saved window size after three frames.
		await GameData._place_window(0, Vector2i(960, 540), false)
		await settle()
		check(get_viewport().get_visible_rect().size == Vector2(960, 540), "compact layout uses the requested viewport")
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		cr.previous = previous.duplicate()
		RendererChoice.notice = RendererChoice.FAILED if lang == "de" else ""
		run_notices.call_deferred()
		await settle()
		var ui := main.get_node_or_null("StartupNotices")
		check(ui != null and not completed, lang + " startup waits for the report")
		if ui == null:
			continue
		var box := ui.get_node_or_null("CrashReportBox") as CrashReportBox
		check(box != null and box.is_visible_in_tree(), lang + " report is visible")
		if box == null:
			continue
		check(cr.previous.is_empty(), lang + " previous report offered once")
		check(main.find_children("*", "MenuScene", true, false).is_empty(), lang + " no 3D island required")
		check(main.find_children("*", "StartupScreen", true, false).is_empty(), lang + " no loading animation required")
		check(main.find_children("*", "GfxDetect", true, false).is_empty(), lang + " no calibration required")
		check_layout(box, lang)
		get_viewport().get_texture().get_image().save_png("user://startup-report-" + lang + ".png")
		CrashReport.save_dir_override = "user://reports/" + lang
		box.act(0)
		await settle()
		var files := DirAccess.get_files_at(CrashReport.save_dir_override)
		check(files.size() == 1, lang + " report can be saved before loading the menu")
		if files.size() == 1:
			var text := FileAccess.get_file_as_string(CrashReport.save_dir_override.path_join(files[0]))
			check(text.contains("SIMULATED PREVIOUS SESSION") and text.contains("startup-recovery-fixture"), lang + " saved report retains the previous session")
		check_layout(box, lang + " saved")
		get_viewport().get_texture().get_image().save_png("user://startup-report-" + lang + "-saved.png")
		if not OS.has_feature("android"):
			box.act(1)
			check(DisplayServer.clipboard_get().contains("SIMULATED PREVIOUS SESSION"), lang + " previous log can be copied")
		if lang == "ru":
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
		else:
			# Tap the same hit target as the mobile UI, not a direct close call.
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = box.p8((box._rects().ok as Rect2).get_center())
			box._gui_input(click)
		await settle()
		if lang == "de":
			check(not completed and is_instance_valid(ui), "renderer notice follows the report")
			var boxes := ui.find_children("*", "MessageBox", true, false)
			check(boxes.size() == 1, "exactly one renderer notice")
			if boxes.size() == 1:
				check(boxes[0].message == RemakeText.t(RendererChoice.FAILED), "renderer notice is localized")
				boxes[0]._answer(true)
				await settle()
		check(completed and main.get_node_or_null("StartupNotices") == null, lang + " dismissal releases startup and cleans up UI")
	RemakeText.lang = "en"
	await run_notices()
	check(completed and main.get_node_or_null("StartupNotices") == null, "notices are not shown twice")
	var menu: Control = await main.open_menu()
	await settle()
	check(menu != null and menu._scene != null and menu._mods_button.is_visible_in_tree(), "normal 3D menu still opens after notices")
	check(not main.get_children().any(func(c): return c is StartupScreen), "loading animation releases input")
	menu.queue_free()
	await settle()
	_finish()


func _finish() -> void:
	var result := {"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "platform": OS.get_name()}
	FileAccess.open("user://startup-crash-report.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("STARTUP_CRASH_REPORT ", JSON.stringify(result))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
