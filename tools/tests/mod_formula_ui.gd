extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames() -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0}, true)
	TutorialPanel.auto_show = false
	RenderingServer.set_render_loop_enabled(true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--examples="):
			for name in ["expedition-xp", "quest-focus", "field-medicine"]:
				check(ModStore.import_package(arg.trim_prefix("--examples=").path_join(name + "-1.0.0.eimod")) == "", "install localized example")
	check(ModStore.create_profile("Formula examples") == "", "create example profile")
	check(ModStore.set_packages(["example.expedition-xp@1.0.0", "example.quest-focus@1.0.0", "example.field-medicine@1.0.0"]) == "" and ModStore.mount() == "", "mount examples")
	await frames(); GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		var panel := ModPanel.new(); add_child(panel)
		for shape in [Vector2i(1280,720), Vector2i(540,960)]:
			get_tree().root.size = shape
			for page in ["mods", "options"]:
				panel.open(page); await frames()
				check(panel._body.size.x <= panel._scroll.size.x + 1, language + " " + page + " fits " + str(shape))
				check(panel._apply.get_global_rect().end.y <= panel.size.y + 1, "actions remain visible")
				get_viewport().get_texture().get_image().save_png("user://formula-%s-%s-%d.png" % [language,page,shape.x])
			var slider: HSlider
			for control in panel._controls:
				if control is HSlider: slider = control; break
			check(slider != null, "numeric formula option exists")
			if slider:
				slider.grab_focus()
				var before := slider.value
				panel.pad_press("right","down")
				check(is_equal_approx(slider.value, before + slider.step), "controller edits formula option")
		panel.free()
	print("MOD_FORMULA_UI ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
