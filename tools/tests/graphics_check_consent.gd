extends Node
## Rendered handheld opt-in, decline persistence, manual decline and layout.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(count := 4) -> void:
	for i in count: await RenderingServer.frame_post_draw

func prompt() -> GraphicsCheckBox:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		for node in get_tree().root.get_children():
			if node is GfxDetect and node._box is GraphicsCheckBox: return node._box
		await RenderingServer.frame_post_draw
	return null

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2); return
	GameData.options.merge(GfxDetect.base_values(), true)
	GameData.options.merge({"auto_graphics":1, "confine_mouse":0, "display_mode":0}, true)
	TutorialPanel.auto_show = false
	GfxDetect.save_record({})
	GameData.save_settings()
	var saved := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	await get_parent().open_menu()
	var box := await prompt()
	check(box != null, "first start asks for consent")
	if box == null: _finish(); return
	await frames(10)
	check(not GfxDetect.load_record().get("testing", false), "waiting for an answer does not start a trial")
	check(GfxDetect.original_look_on(GameData.options) and Engine.max_fps == 30, "waiting menu remains at basic graphics")
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == saved, "unanswered prompt does not write preferences")
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		box.title = RemakeText.t("Graphics check")
		box.message = RemakeText.t(GraphicsCheckBox.WARNING)
		box.queue_redraw()
		await frames()
		var rects := box._rects()
		check(rects.top >= 0 and (rects.ok as Rect2).end.y <= 600, lang + " warning and buttons fit vertically")
		for key: String in ["Graphics check", GraphicsCheckBox.WARNING, "Run check", "Skip", GfxDetect.ORIGINAL_RECOVERY_NOTICE]:
			check(lang == "en" or RemakeText.t(key) != key, lang + " prompt and recovery notice translated")
		for key: String in ["Run check", "Skip"]:
			check(box.text_width(RemakeText.t(key), 2) <= 165, lang + " decision label fits")
		get_viewport().get_texture().get_image().save_png("user://graphics-check-" + lang + ".png")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = box.p8((box._rects().cancel as Rect2).get_center())
	box._gui_input(click)
	await frames()
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH) == OK, "declined first startup persists")
	check(cfg.get_value("options", "auto_graphics", 1) == 0, "decline disables automatic checks across launches")
	for k: String in GfxDetect.keys():
		if k.begins_with("gfx_"): check(cfg.get_value("options", k, -1) == 0, "decline keeps Original graphics: " + k)
	GfxDetect.auto_start()
	await frames()
	check(not get_tree().root.get_children().any(func(n): return n is GfxDetect), "declined check is not offered again automatically")
	# Declining a manual retry must preserve an enhanced configuration too.
	GameData.set_options({"gfx_water":1})
	var before := GameData.options.duplicate(true)
	saved = FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	GfxDetect.start(true)
	box = await prompt()
	check(box != null, "manual retry also asks before testing")
	if box == null: _finish(); return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	box._unhandled_key_input(escape)
	await frames()
	check(GameData.options == before, "Escape preserves manual graphics")
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == saved, "manual decline leaves saved preferences unchanged")
	check(not GfxDetect.load_record().get("testing", false), "decline leaves no interrupted trial")
	RemakeText.lang = "en"
	_finish()

func _finish() -> void:
	var result := {"checks":checks, "failures":failures, "renderer":RenderingServer.get_current_rendering_method(), "platform":OS.get_name()}
	FileAccess.open("user://graphics-check-consent.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("GRAPHICS_CHECK_CONSENT ", JSON.stringify(result))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
