extends Node
## Real first-import cache lookup, then Options touch save/discard/return.
## Run in a disposable profile with --touch. Captures include missing artwork.
var checks := 0
var failures := 0
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func settle() -> void:
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func tap(control: Interface800, rect: Rect2) -> void:
	var point := control.get_global_transform_with_canvas() * control.p8(rect.get_center())
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = point
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame
	await settle()

func capture(box: MessageBox, label: String) -> void:
	await settle()
	var img := get_viewport().get_texture().get_image()
	check(img.save_png("user://first-import-" + label + ".png") == OK, label + " capture")
	for key in ["ok", "cancel"]:
		var r := box.r8(box._rects()[key]) as Rect2
		check(Rect2(Vector2.ZERO, Vector2(img.get_size())).encloses(r), label + " " + key + " fits")
		var region := img.get_region(Rect2i(r))
		var lit := 0
		for y in region.get_height():
			for x in region.get_width():
				var c := region.get_pixel(x, y)
				if maxf(c.r, maxf(c.g, c.b)) > 0.3: lit += 1
		check(lit > 30, label + " " + key + " visibly drawn")
		samples.append({"label": label, "action": key, "visible_pixels": lit, "rect": str(r)})

func _ready() -> void:
	GameData.options.merge({"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,
		"confine_mouse":0,"show_tutorial":0,"display_mode":0},true)
	TutorialPanel.auto_show = false
	TouchInput.pinned = true
	TouchInput.enabled = true
	await settle()
	var root_path := GameData.root
	GameData.textures = null
	Interface800.clear_cache()
	# CampaignChoices is drawn by the real portable setup before import.
	var choices := CampaignChoices.new()
	add_child(choices)
	check(choices.buttons.size() == 2, "real pre-import campaign choices built")
	check(not Interface800._tex.has("saveload"), "pre-import miss is not retained")
	choices.free()
	var box := MessageBox.new()
	box.title = RemakeText.t("Options")
	box.message = RemakeText.t("Some settings were changed but not applied. Save them?")
	add_child(box)
	await capture(box, "no-archives")
	box.free()
	check(GameData.open(root_path) == "", "first import opens real archives in same process")
	var atlas := Interface800.tex("saveload")
	check(atlas != null, "first import resolves button atlas without restart")
	check(atlas == Interface800.tex("saveload"), "successful artwork is cached")
	# Continue even on the failing baseline to qualify its existing input path.
	Interface800.clear_cache()
	check(Interface800.tex("saveload") != null, "fresh-process artwork control")
	var options := OptionsPanel.new()
	add_child(options)
	var frame := Image.create(800, 600, false, Image.FORMAT_RGB8)
	frame.fill(Color(0.035, 0.035, 0.035))
	for lang in ["en", "ru", "de"]:
		RemakeText.lang = lang
		options.open(frame)
		var original := GameData.option("volume_voice")
		var changed := 37 if original != 37 else 23
		options._set_value("volume_voice", changed)
		options._cancel()
		check(MessageBox.is_up(options._box), lang + " unsaved modal opens")
		await capture(options._box, lang + "-unsaved")
		check(not options._box._rects().has("back"), lang + " keeps the original two decision buttons")
		await tap(options._box, options._box._rects().cancel)
		check(not options.visible and GameData.option("volume_voice") == original, lang + " touch discard restores value and closes")
		options.open(frame)
		options._set_value("volume_voice", changed)
		options._cancel()
		await settle()
		await tap(options._box, options._box._rects().ok)
		check(not options.visible and GameData.option("volume_voice") == changed, lang + " touch save applies and closes")
		var cfg := ConfigFile.new()
		check(cfg.load(GameData.CONFIG_PATH) == OK and int(cfg.get_value("options", "volume_voice", -1)) == changed, lang + " save persists")
		options.open(frame)
		check(options._values.volume_voice == changed, lang + " reopen sees saved value")
		options._set_value("volume_voice", 64)
		options._cancel()
		await settle()
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		await settle()
		check(options.visible and not MessageBox.is_up(options._box), lang + " Escape resumes editing")
		options._restore()
		options._close()
	if OS.has_feature("android"):
		options.open(frame)
		options._set_value("volume_voice", 65)
		options._cancel()
		await settle()
		FileAccess.open("user://first-import-back-ready.json", FileAccess.WRITE).store_string("ready")
		var until := Time.get_ticks_msec() + 15000
		while MessageBox.is_up(options._box) and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		check(options.visible and not MessageBox.is_up(options._box), "system Android Back resumes editing once")
		options._restore()
		options._close()
	options.free()
	await settle()
	var result := {"checks":checks,"failures":failures,"samples":samples,
		"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(get_viewport().get_visible_rect().size),
		"device":OS.get_model_name(),"android":OS.has_feature("android")}
	FileAccess.open("user://first-import-dialog.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("FIRST_IMPORT_DIALOG ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
