extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func frames() -> void:
	for i in 8: await get_tree().process_frame

func echo_is(on: bool) -> bool:
	for i in SoundMixer.CHANNELS:
		if AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("EISample%d" % i), 1) != on: return false
	return true

func _ready() -> void:
	GameData.options.merge({"show_tutorial":0, "auto_graphics":0, "confine_mouse":0}, true)
	await frames()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lang="): RemakeText.lang = arg.get_slice("=", 1)
	if DisplayServer.get_name() != "headless":
		GameData._window_gen += 1
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1280, 800)
		get_window().position = Vector2i.ZERO
		await frames()
	check(GameData.option("cave_echo") == 1, "echo defaults on for an existing settings file without the option")
	var mixer := SoundMixer.new(); add_child(mixer)
	check(echo_is(false), "outdoor channels are dry")
	mixer.set_reverb(true)
	check(echo_is(true), "cave enables every sample-channel reverb")
	var panel := OptionsPanel.new(); add_child(panel); panel.open(); panel._show_group(1)
	await frames()
	check(panel._rows[5].name == "cave_echo" and panel._rows[5].label == RemakeText.t("Cave echo"), "localized Audio row")
	check(panel._rows[5].tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.cave_echo[1])), "localized help")
	check(panel._rows[5].choices == RemakeText.tl(["Off", "On"]), "both choices are localized")
	panel._toggle(5)
	check(echo_is(false) and mixer.reverb, "toggle removes echo immediately while retaining cave state")
	panel._sel = 5
	if DisplayServer.get_name() != "headless":
		await frames(); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://audio-echo-" + RemakeText.lang + ".png")
	panel._show_group(10)
	check(panel._rows[12].name == "wiki_context" and panel._rows[12].label == RemakeText.t("Wiki under pointer"), "localized wiki binding appears under Windows")
	check(panel._rows[12].tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.wiki_context[1])), "wiki binding help is translated")
	if DisplayServer.get_name() != "headless":
		panel._sel = 12
		await frames(); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://wiki-binding-" + RemakeText.lang + ".png")
	panel._restore(); panel._close()
	check(echo_is(true) and GameData.option("cave_echo") == 1, "discard restores the live echo setting")
	panel.open(); panel._show_group(1); panel._toggle(5); panel._apply(); panel._close()
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH) == OK and cfg.get_value("options", "cave_echo", -1) == 0, "accept saves disabled echo")
	panel.open(); panel._show_group(1)
	check(panel._switch_text(panel._rows[5]) == RemakeText.t("Off"), "reopened Audio page retains Off")
	panel._close()
	mixer.set_reverb(false); mixer.set_reverb(true)
	check(echo_is(false), "changing zones cannot re-enable disabled echo")
	mixer.queue_free(); await frames()
	mixer = SoundMixer.new(); add_child(mixer); mixer.set_reverb(true)
	check(echo_is(false), "replacement mixer honors the saved preference")
	GameData.set_option("cave_echo", 1)
	check(echo_is(true), "re-enabling echo in the same cave applies immediately")
	mixer.set_reverb(false)
	GameData.set_option("cave_echo", 0); GameData.set_option("cave_echo", 1)
	check(echo_is(false), "changing the preference outdoors never adds cave echo")
	mixer.queue_free(); panel.queue_free(); await frames()
	print("AUDIO_ECHO_OPTIONS ", RemakeText.lang, " ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
