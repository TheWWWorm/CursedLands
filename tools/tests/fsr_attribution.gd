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
	var packaged_dlss := bool(ProjectSettings.get_setting(GraphicsAttribution.NVIDIA_FLAG, false))
	var packaged_nrd := bool(ProjectSettings.get_setting(GraphicsAttribution.NRD_FLAG, false))
	var packaged_amd := bool(ProjectSettings.get_setting(GraphicsAttribution.AMD_FLAG, false))
	check(packaged_nrd, "desktop package declares bundled NRD")
	check(packaged_dlss == (OS.get_name() == "Windows"), "DLSS attribution matches platform contents")
	check(packaged_amd == (OS.get_name() == "Windows"), "AMD SDK attribution matches platform contents")
	if packaged_dlss:
		check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/branding/splash-graphics.png", "native boot uses combined attribution splash")
	for flag in [GraphicsAttribution.NVIDIA_FLAG,GraphicsAttribution.NRD_FLAG,GraphicsAttribution.SHARC_FLAG,GraphicsAttribution.RTXDI_FLAG,GraphicsAttribution.AMD_FLAG]: ProjectSettings.set_setting(flag,false)
	check(GraphicsAttribution.credits_bbcode().is_empty(), "unbundled SDKs have no credits claim")
	ProjectSettings.set_setting(GraphicsAttribution.NRD_FLAG,true)
	check(GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.NRD_CREDIT)), "NRD-only package has credits")
	check(not GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.NVIDIA_CREDIT)), "NRD-only package does not claim DLSS")
	ProjectSettings.set_setting(GraphicsAttribution.SHARC_FLAG,true)
	check(GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.SHARC_CREDIT)), "SHaRC package has explicit attribution")
	ProjectSettings.set_setting(GraphicsAttribution.RTXDI_FLAG,true)
	check(GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.RTXDI_CREDIT)), "RTXDI package has explicit attribution")
	ProjectSettings.set_setting(GraphicsAttribution.NVIDIA_FLAG,packaged_dlss)
	ProjectSettings.set_setting(GraphicsAttribution.AMD_FLAG,packaged_amd)
	GameData.options.rtx_upscaling=0;GameData.options.pt_mode=0
	check(GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.NRD_CREDIT)), "turning features off keeps package attribution")
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
		picture.texture = load(ProjectSettings.get_setting("application/boot_splash/image"))
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
			check(panel._text.text.contains(RemakeText.t(GraphicsAttribution.NRD_CREDIT)), language + " NRD attributed")
			check(panel._text.size.x <= panel._clip.size.x, language + " credits wrap in clip width")
			panel._text.position.y = 0
			await settle()
			for credit: String in [GraphicsAttribution.NRD_CREDIT,GraphicsAttribution.RTXDI_CREDIT,GraphicsAttribution.AMD_CREDIT] if packaged_amd else [GraphicsAttribution.NRD_CREDIT,GraphicsAttribution.RTXDI_CREDIT]:
				var parsed := panel._text.get_parsed_text()
				var char_at := parsed.find(RemakeText.t(credit))
				check(char_at >= 0, language + " technology attribution is present")
				var line := panel._text.get_character_line(char_at)
				panel._text.position.y = -panel._text.get_line_offset(maxi(0, line - 4))
				await settle()
				get_viewport().get_texture().get_image().save_png("user://attribution-%s-%s-%d.png" % ["nvidia" if credit==GraphicsAttribution.NRD_CREDIT else ("rtxdi" if credit==GraphicsAttribution.RTXDI_CREDIT else "amd"),language,resolution.x])
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
