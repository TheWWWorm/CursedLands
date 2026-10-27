extends "startup_graphics_recovery.gd"
## An unsupported saved request must never read as an enabled technology.
func _run() -> void:
	TutorialPanel.auto_show = false
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().borderless = true
	var original := GameData.options.duplicate(true)
	check(not RtxGraphics.facts().api, "fixture uses an unsupported NVIDIA presentation backend")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().size = resolution
		await settle()
		for language: String in ["en","ru","de"]:
			RemakeText.lang = language
			GameData.options.merge({"q_aa":0,"rtx_upscaling":4,"rtx_frame_generation":1,"pt_mode":1,"rt_shadows":1},true)
			var panel := OptionsPanel.new(); add_child(panel); panel.open()
			panel._show_group(OptionsPanel.SCREEN_GROUP); await settle()
			var fg: OptionButton = panel._screen_pickers[FsrGraphics.FRAME_GENERATION]
			var aa: OptionButton = panel._screen_pickers["q_aa"]
			var tag := "%s-%dx%d" % [language,resolution.x,resolution.y]
			check(fg.text == RemakeText.t("Off (unavailable)"), "FG caption reports inactive saved request " + tag)
			check(aa.text == RemakeText.t("%s (fallback)") % aa.get_item_text(0), "AA caption reports actual fallback " + tag)
			check(fg.is_item_disabled(3) and not fg.is_item_disabled(0) and not fg.disabled, "unsupported FG remains recoverable " + tag)
			check(fg.tooltip_text.contains(RemakeText.t(RtxGraphics.reason(RtxGraphics.FRAME_GENERATION))), "FG tooltip explains why the requested mode is unavailable " + tag)
			for picker in [fg,aa]:
				check(picker.get_theme_font("font").get_string_size(picker.text,HORIZONTAL_ALIGNMENT_LEFT,-1,picker.get_theme_font_size("font_size")).x < picker.size.x-24*panel.kv().x, "inactive caption fits without clipping " + tag)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://unavailable-graphics-" + tag + ".png")
			check(GameData.option(RtxGraphics.FRAME_GENERATION)==1, "viewing inactive state preserves saved request " + tag)
			panel._screen_pickers[FsrGraphics.FRAME_GENERATION].item_selected.emit(0)
			check(panel._values[RtxGraphics.FRAME_GENERATION]==0, "Off clears unavailable request " + tag)
			panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			for row: Dictionary in panel._rows.values():
				if row.get("name","") in ["pt_mode","rt_shadows"] and not preload("res://src/game/fx/scene_raytrace_device.gd").supported():
					check(panel._switch_text(row)==RemakeText.t("Off (unavailable)"), "unsupported ray setting reports inactive state " + tag)
			panel._close(); panel.queue_free(); await settle()
	GameData.options = original
	print("UNAVAILABLE_GRAPHICS_UI ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
