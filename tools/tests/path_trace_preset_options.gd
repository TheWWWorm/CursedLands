extends "res://tools/tests/scene_raytrace_options.gd"
## Exercise the normal player menu, including saved legacy settings. Run
## without --ei-pt-tuning; the detailed regression suites use that flag.
const HIDDEN := ["pt_accumulation", "pt_target_fps", "pt_sharc", "pt_denoiser",
	"pt_ray_reconstruction", "pt_restir", "pt_refraction"]

func row_named(panel: OptionsPanel, name: String) -> Dictionary:
	for row: Dictionary in panel._rows.values():
		if row.get("name", "") == name: return row
	return {}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(not OS.get_cmdline_user_args().has("--ei-pt-tuning"), "player preset test uses the normal menu")
	GameData.options.merge({"pt_mode":2, "pt_accumulation":1, "pt_target_fps":3,
		"pt_sharc":1, "pt_denoiser":1, "pt_ray_reconstruction":0, "pt_restir":0,
		"pt_refraction":0, "q_rt_lighting":2, "rt_shadows":1, "rt_gi":1,
		"confine_mouse":0, "show_fps":1, "volume_sfx":0, "volume_stream":0,
		"volume_voice":0, "auto_graphics":0}, true)
	var retained := GameData.options.duplicate(true)
	var panel := OptionsPanel.new(); add_child(panel); panel.open(); panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(row_named(panel, "pt_mode").get("choices", []) == RemakeText.tl(["Off", "Balanced", "Quality"]), "player chooses a preset instead of isolated bounce tuning")
	for name in HIDDEN:
		check(row_named(panel, name).is_empty(), "internal tuning absent from player menu: " + name)
	check(panel._rows.size() == 3, "active PT menu has only preset, Screen link and Back")
	check(row_named(panel, "q_rt_lighting").is_empty(), "standalone RT quality is hidden during PT")
	panel._set_value("pt_mode", 1)
	check(GameData.options.pt_mode == 2, "preset changes remain pending until Apply")
	panel._restore(); panel._close(); panel.open(); panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(panel._values.pt_mode == 2, "Cancel restores the saved preset")
	panel._set_value("pt_mode", 1); panel._accept()
	check(GameData.option("pt_mode") == 1 and GameData.option("pt_accumulation") == 0
		and GameData.option("pt_target_fps") == 0 and GameData.option("pt_denoiser") == 0,
		"Apply selects a coherent responsive preset despite incompatible legacy settings")
	var config := ConfigFile.new(); var loaded := config.load(GameData.CONFIG_PATH) == OK
	for name in HIDDEN + ["q_rt_lighting", "rt_shadows", "rt_gi"]:
		check(loaded and config.get_value("options", name, -1) == retained[name], "Apply preserves the stored preference " + name)
	panel.open(); panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	panel._set_value("pt_mode", 0)
	check(row_named(panel, "q_rt_lighting").get("choices", []) == GameData.option_choices("q_rt_lighting")
		and panel._values.q_rt_lighting == 2, "PT Off exposes the retained standalone RT quality")
	check(not row_named(panel, "rt_shadows").is_empty() and not row_named(panel, "rt_gi").is_empty(), "PT Off restores standalone RT controls")
	panel._accept()
	check(GameData.option("q_rt_lighting") == 2 and GameData.option("rt_shadows") == 1 and GameData.option("rt_gi") == 1, "standalone RT preferences survive the full preset round trip")
	panel.queue_free(); await frames(12); GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	# Windows restores the decorated window asynchronously after leaving a
	# maximized/native-size state. Set client dimensions only after both that
	# restore and the borderless transition have landed.
	await frames(12); GameData._window_gen += 1
	get_window().borderless = true
	await frames(4)
	for size: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440), Vector2i(3840,2160)]:
		get_window().size = size
		await get_tree().create_timer(.3, true, false, true).timeout
		for language in ["en", "ru", "de"]:
			RemakeText.lang = language
			panel = OptionsPanel.new(); add_child(panel); panel.open(); panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			check(get_window().size == size, "preset UI has requested pixel extent " + str(size))
			var row := row_named(panel, "pt_mode")
			check(panel.text_width(row.get("label", "")) <= 260, "preset label fits " + language)
			for choice: String in row.get("choices", []): check(panel.text_width(choice) <= 160, "preset choice fits " + language + choice)
			# The legacy menu deliberately fails this check without dereferencing
			# nonexistent new APIs: this regression must expose the old layout.
			check(panel._rows.get(1, {}).get("to", -1) == OptionsPanel.SCREEN_GROUP, "Screen settings are directly reachable " + language)
			if panel._rows.get(1, {}).get("to", -1) == OptionsPanel.SCREEN_GROUP:
				check(panel.text_width(panel._rows[1].label) <= 420, "Screen link fits " + language)
			panel._values.pt_mode = 1; panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			get_window().grab_focus(); GameData._tips.delay = .1
			Input.warp_mouse(Vector2(20,20)); await frames()
			var at := panel.p8(Vector2(400, panel._row_y(0) + 12))
			Input.warp_mouse(at); var motion := InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion)
			await get_tree().create_timer(.4, true, false, true).timeout
			check(GameData._tips._panel.visible, "preset help opens " + language)
			check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position, GameData._tips._panel.size)), "preset help fits " + language + str(size))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("presets-%s-%dx%d.png" % [language,size.x,size.y]))
			GameData._tips._hide(); panel._close(); panel.queue_free(); await frames()
	RemakeText.lang = "en"
	FileAccess.open(out.path_join("preset-options.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown(); print("PT_PRESET_OPTIONS ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
