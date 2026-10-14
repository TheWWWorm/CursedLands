extends Node
## Render the recovery actions with real menu assets in an isolated profile.
var checks := 0
var failures := 0
var probe_result := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func settle() -> void:
	for i in 4:
		await RenderingServer.frame_post_draw

func tap(box: CrashReportBox, index: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = box.p8((box._rects().rows[index] as Rect2).get_center())
	box._gui_input(event)

func answer(box: MessageBox, yes: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = box.p8((box._rects().ok if yes else box._rects().cancel).get_center())
	box._gui_input(event)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	TutorialPanel.auto_show = false
	GameData.options.confine_mouse = 0
	GameData.options.display_mode = 0
	var previous := {"session":"recovery-test", "zone":"(menu)", "last":"startup: building main menu"}
	var original := GameData.options.duplicate(true)
	GameData.options.auto_graphics = 1
	GameData.save_settings()
	var options_before := GameData.options.duplicate(true)
	var settings_before := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	var record_before := GfxDetect.load_record()
	var box := CrashReportBox.open(get_parent(), previous, true)
	await settle()
	check(box._row_defs().size() == 4, "startup crash offers recovery actions")
	check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "actions are available before any 3D menu")
	check(GameData.options == options_before, "opening recovery leaves settings alone")
	tap(box, 3)
	await settle()
	check(box._confirm != null and box._probing and not box.visible, "touch asks before the graphics check")
	check(get_parent().find_children("*", "StartupGraphicsProbe", true, false).is_empty(), "probe is not constructed before consent")
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == settings_before, "asking does not change saved settings")
	answer(box._confirm, false)
	await settle()
	check(not box._probing and box.visible, "declining returns to the report")
	check(GameData.options == options_before and GfxDetect.load_record() == record_before, "declining leaves graphics and records unchanged")
	tap(box, 3)
	await settle()
	answer(box._confirm, true)
	await settle()
	check(box._probing and not box.visible, "accepting starts the graphics check")
	# Hidden recovery controls must not resume startup during a probe.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	box._unhandled_key_input(escape)
	box.act(2)
	check(not box.is_queued_for_deletion() and GameData.options == options_before, "recovery ignores actions while probing")
	var deadline := Time.get_ticks_msec() + 180000
	var calibration_seen := false
	var rollback_seen := false
	while box._probing and Time.get_ticks_msec() < deadline:
		calibration_seen = calibration_seen or get_tree().root.get_children().any(func(n): return n is GfxDetect)
		var pending := GfxDetect.load_record()
		if pending.get("testing", false):
			rollback_seen = pending.get("original_recovery", false) and pending.before.auto_graphics == 0 and GfxDetect.original_look_on(pending.before)
		await RenderingServer.frame_post_draw
	check(not box._probing and box.visible, "probe returns to the report")
	check(not calibration_seen, "probe never starts automatic calibration, even with auto enabled")
	check(rollback_seen, "probe saves an Original fallback while checking enhanced graphics")
	check(GameData.options == options_before, "probe keeps all option values")
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == settings_before, "completed probe restores the saved preferences exactly")
	check(GfxDetect.load_record() == record_before, "probe keeps the calibration record")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://startup-graphics-probe.json"))
	if parsed is Dictionary: probe_result = parsed
	check(probe_result.get("ok", false), "actual loading picture and menu stages render without engine errors")
	var stages: Array = probe_result.get("rows", [])
	check(stages.map(func(row): return row.stage) == ["loading_picture", "menu_build", "sky", "terrain", "water", "objects", "signpost", "whole_scene", "menu_screens"], "all nine stages execute in order")
	check(get_parent().find_children("*", "MenuScene", true, false).is_empty(), "probe releases its 3D scenes")
	CrashReport.save_dir_override = "user://recovery-reports-" + str(Time.get_ticks_usec())
	tap(box, 0)
	var files := DirAccess.get_files_at(CrashReport.save_dir_override)
	check(files.size() == 1, "probe result can be saved with the existing report action")
	if files.size() == 1:
		var report := FileAccess.get_file_as_string(CrashReport.save_dir_override.path_join(files[0]))
		check(report.contains("startup graphics probe: result") and report.contains("whole_scene"), "saved report includes stages and result")
	box.queue_free()
	await settle()
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		GameData.options = options_before.duplicate(true)
		GameData.options.render_scale = [0, 1, 4][["en", "ru", "de"].find(language)]
		var before := GameData.options.duplicate(true)
		box = CrashReportBox.open(get_parent(), previous, true)
		await settle()
		box._status = RemakeText.t("Report saved:") + " /storage/emulated/0/Download/CursedLands-report-20261014-160000.txt"
		box.queue_redraw()
		await settle()
		var rects := box._rects()
		check(rects.top >= 0 and (rects.ok as Rect2).end.y <= 600, language + " recovery fits vertically after saving")
		for row: Array in box._row_defs():
			check(box.text_width(RemakeText.t(row[0]), 2) <= 340, language + " action label fits")
			for key: String in row:
				check(language == "en" or RemakeText.t(key) != key, language + " action and help translated")
		for key: String in StartupGraphicsProbe.LABELS + ["Startup graphics check", "The graphics check finished. Save the report before continuing.", "The graphics check found an error. Save the report before continuing."]:
			check(language == "en" or RemakeText.t(key) != key, language + " probe text translated")
		get_viewport().get_texture().get_image().save_png("user://startup-recovery-" + language + ".png")
		tap(box, 2)
		await settle()
		check(not is_instance_valid(box), language + " basic graphics closes the recovery dialog")
		var allowed: Array = Array(GfxDetect.keys()) + ["auto_graphics", "fps_limit", "graphics_preset"]
		for key: String in before:
			if not key in allowed: check(GameData.options[key] == before[key], language + " unrelated setting retained: " + key)
		check(Array(GfxDetect.keys()).all(func(k): return not String(k).begins_with("gfx_") or GameData.option(k) == 0), language + " all enhanced effects disabled")
		check(GameData.option("render_scale") == mini(before.render_scale, 2), language + " basic graphics never increases resolution")
		check(GameData.option("q_aa") == 0 and GameData.option("q_shadows") == 0 and GameData.option("fps_limit") == 1, language + " basic graphics uses low rendering cost")
		check(GameData.option("auto_graphics") == 0, language + " automatic calibration disabled")
		var saved := ConfigFile.new()
		check(saved.load(GameData.CONFIG_PATH) == OK and saved.get_value("options", "auto_graphics") == 0 and saved.get_value("options", "gfx_water") == 0, language + " recovery persists across restarts")
	RemakeText.lang = "en"
	for context in [false, true]:
		var report := {} if not context else {"zone":"zone1"}
		box = CrashReportBox.open(get_parent(), report, true)
		check(box._row_defs().size() == 2, "ordinary report does not offer startup actions")
		box.queue_free()
		await settle()
	GameData.set_options(original)
	var result := {"checks":checks, "failures":failures, "probe":probe_result, "renderer":RenderingServer.get_current_rendering_method(), "platform":OS.get_name()}
	FileAccess.open("user://startup-graphics-recovery.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("STARTUP_GRAPHICS_RECOVERY ", JSON.stringify(result))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
