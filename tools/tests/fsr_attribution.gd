extends Node
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func settle() -> void:
	for i in 6: await RenderingServer.frame_post_draw

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	MoviePlayer.enabled = false
	await settle()
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	if OS.get_name() == "Windows":
		check(ProjectSettings.get_setting(GraphicsAttribution.AMD_FLAG, false), "exported package declares AMD SDK")
		check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/branding/splash-fsr.png", "native boot uses FSR splash")
	ProjectSettings.set_setting(GraphicsAttribution.AMD_FLAG, false)
	check(GraphicsAttribution.credits_bbcode().is_empty(), "ordinary build has no SDK claims")
	check(not Engine.has_singleton("Streamline"), "engine has no private SDK singleton")
	check(not ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"), "engine has no private upscaling mode")
	check(not ResourceLoader.exists("res://src/platform/rtx_graphics.gd"), "package omits private script")
	check(not ResourceLoader.exists("res://assets/branding/vendors/nvidia-geforce-rtx-white.png"), "package omits private artwork")
	check(not ResourceLoader.exists("res://assets/branding/splash-graphics.png"), "package omits combined splash")
	check(not GameData.OPTION_GROUPS.has("r_rtx"), "no private options group")
	for option: Array in GameData.OPTIONS:
		check(not str(option[0]).begins_with("rtx_"), "option is publishable: " + str(option[0]))
	ProjectSettings.set_setting(GraphicsAttribution.AMD_FLAG, true)
	for resolution: Vector2i in [Vector2i(800, 600), Vector2i(1280, 720)]:
		GameData.options.resolution = GameData.resolutions().find(resolution)
		GameData._window_state.clear()
		GameData._apply_window()
		await get_tree().create_timer(0.3).timeout
		GameData._window_gen += 1
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = resolution
		await get_tree().create_timer(0.3).timeout
		await settle()
		check(get_window().size == resolution, "actual window size " + str(resolution))
		var splash := ColorRect.new()
		splash.color = ProjectSettings.get_setting("application/boot_splash/bg_color")
		splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(splash)
		var picture := TextureRect.new()
		picture.texture = load("res://assets/branding/splash-fsr.png")
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		splash.add_child(picture)
		await settle()
		get_viewport().get_texture().get_image().save_png("user://attribution-splash-%d.png" % resolution.x)
		splash.queue_free()
		await settle()
		for language: String in ["en", "ru", "de"]:
			RemakeText.lang = language
			for key: String in GraphicsAttribution.TEXTS:
				check(language == "en" or RemakeText.TEXTS.has(key) and RemakeText.t(key) != key, language + " translation: " + key)
			var panel := CreditsPanel.new()
			add_child(panel)
			await settle()
			panel.set_process(false)
			panel._layout()
			check(panel._text.get_content_height() > 500, language + " SDK and original credits loaded")
			check(panel._text.text.contains(GraphicsAttribution.credits_bbcode()), language + " actual credits include SDK attribution")
			check(not panel._text.text.contains("NVIDIA DLSS"), language + " no private attribution")
			check(panel._text.size.x <= panel._clip.size.x, language + " credits wrap in clip width")
			panel._text.position.y = 0
			await settle()
			# Find the first line containing the AMD logos, then align it with the clip.
			var parsed := panel._text.get_parsed_text()
			var needle := RemakeText.t(GraphicsAttribution.AMD_CREDIT)
			var char_at := parsed.find(needle)
			check(char_at >= 0, language + " AMD attribution is present")
			var line := panel._text.get_character_line(char_at)
			panel._text.position.y = -panel._text.get_line_offset(maxi(0, line - 3))
			await settle()
			get_viewport().get_texture().get_image().save_png("user://attribution-amd-%s-%d.png" % [language,resolution.x])
			panel.set_process(true)
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			panel._unhandled_key_input(escape)
			await settle()
			check(not is_instance_valid(panel), language + " Escape closes credits")
	RemakeText.lang = "en"
	var report := {"checks":checks,"failures":failures,"resolutions":[[800,600],[1280,720]],"languages":["en","ru","de"]}
	FileAccess.open("user://attribution-check.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ATTRIBUTION ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
