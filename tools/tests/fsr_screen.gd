extends "startup_graphics_recovery.gd"
## Exercise the actual controls with the current renderer's real capabilities.
## Run on SDK D3D12 and Compatibility, including saved unsupported requests.

func _run() -> void:
	TutorialPanel.auto_show = false
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"display_mode":0}, true)
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	var facts := FsrGraphics.facts()
	for size: Vector2i in [Vector2i(800, 600), Vector2i(1280, 720),Vector2i(2560,1600)]:
		get_window().size = size
		await settle()
		for language: String in ["en", "ru", "de"]:
			RemakeText.lang = language
			var panel := OptionsPanel.new()
			get_parent().add_child(panel)
			panel.open()
			panel._show_group(OptionsPanel.SCREEN_GROUP)
			await settle()
			var aa: OptionButton = panel._screen_pickers["q_aa"]
			var quality: OptionButton = panel._screen_pickers[FsrGraphics.QUALITY]
			var fg: OptionButton = panel._screen_pickers[FsrGraphics.FRAME_GENERATION]
			for name: String in ["resolution","render_scale"]:
				var picker: OptionButton = panel._screen_pickers[name]
				check(picker.visible and panel._rows[OptionsPanel.SCREEN_PICKER_ROWS[name]].kind == "dropdown",name + " uses a Screen dropdown")
				var choices := GameData.option_choices(name)
				check(picker.item_count == choices.size() and picker.get_item_text(0) == choices[0],language + " translated choices retained for " + name)
			check(aa.visible and quality.visible and fg.visible, "all three controls are directly in Screen")
			check(aa.item_count == 8 and aa.get_item_text(6) == "FSR 3.1" and aa.get_item_text(7) == "FSR 4", "AA includes ordinary modes and explicit FSR versions")
			check(panel._rows[10].name == "brightness" and panel._rows[12].name == "gamma", "original screen controls retained")
			if RendererChoice.available(): check(panel._rows[13].name == "renderer", "renderer remains on Screen")
			for i in [6, 7]:
				check(aa.is_item_disabled(i) == not facts["sr" + str(i - 3)], "unsupported AA version visibly disabled")
			for i in [1, 2]:
				check(fg.is_item_disabled(i) == not facts["fg" + str(i + 2)], "unsupported FG version visibly disabled")
			check(aa.get_theme_color("font_color") == panel.TEXT, "editable dropdown uses enabled text color")
			check(FsrGraphics.QUALITY in GameData.OPTIONS_APPLIED and FsrGraphics.FRAME_GENERATION in GameData.OPTIONS_APPLIED, "implemented FSR labels are not painted as stubs")
			# Old saves must remain recoverable on a different renderer/GPU.
			panel._values[FsrGraphics.UPSCALING] = 2
			panel._values[FsrGraphics.FRAME_GENERATION] = 2
			panel._show_group(OptionsPanel.SCREEN_GROUP)
			check(aa.selected == 7 and not aa.disabled and not fg.disabled, "saved unsupported requests can be turned off")
			aa.item_selected.emit(0)
			fg.item_selected.emit(0)
			check(panel._values[FsrGraphics.UPSCALING] == 0 and panel._values.q_aa == 0 and panel._values[FsrGraphics.FRAME_GENERATION] == 0, "ordinary AA and FG Off clear saved requests")
			check(quality.disabled and panel._rows[4].disabled, "quality is disabled until FSR AA selected")
			if facts.sr3:
				aa.item_selected.emit(6)
				quality.item_selected.emit(3)
				check(panel._values[FsrGraphics.UPSCALING] == 1 and panel._values[FsrGraphics.QUALITY] == 3 and not quality.disabled, "FSR AA enables its quality dropdown")
			else:
				aa.item_selected.emit(6)
				check(panel._values[FsrGraphics.UPSCALING] == 0, "unavailable AA cannot be activated")
			if facts.fg3:
				aa.item_selected.emit(1)
				fg.item_selected.emit(1)
				check(panel._values[FsrGraphics.UPSCALING] == 0 and panel._values[FsrGraphics.FRAME_GENERATION] == 1, "FG can be selected independently of FSR AA")
				if facts.sr3: aa.item_selected.emit(6)
			else:
				fg.item_selected.emit(1)
				check(panel._values[FsrGraphics.FRAME_GENERATION] == 0 and fg.disabled, "unavailable FG cannot be activated")
			if OS.get_name() == "Windows" and not facts.api:
				check(panel._fsr_hint == RemakeText.t(FsrGraphics.RENDERER_HINT), "wrong renderer shows apply/restart instructions without hovering")
			check(panel.text_width(panel._fsr_hint, 1) <= 592, language + " renderer hint fits")
			await settle()
			get_viewport().get_texture().get_image().save_png("user://fsr-screen-" + language + "-" + str(size.x) + ".png")
			for row_id in [1, 2, 3, 4, 5]:
				var row: Dictionary = panel._rows[row_id]
				var picker: OptionButton = panel._screen_pickers[row.name]
				check(panel.text_width(row.label, 2) <= 260, language + " label fits: " + row.label)
				for choice: String in row.choices:
					check(panel.text_width(choice, 1) <= 136, language + " dropdown choice fits: " + choice)
				check(get_viewport().get_visible_rect().encloses(picker.get_global_rect()), language + " dropdown fits screen")
				if size.x == 800:
					panel._sel = row_id
					GameData._tips.delay = 0.001
					Input.warp_mouse(panel.get_global_transform_with_canvas() * panel.p8(Vector2(400, panel._row_y(row_id) + 10)))
					await settle()
					GameData._tips._since = 0
					GameData._tips._process(0)
					await settle()
					check(GameData._tips._panel.visible and GameData._tips._text == row.tip, language + " help displays for enabled and disabled rows")
					check(get_viewport().get_visible_rect().encloses(GameData._tips._panel.get_rect()), language + " help fits 800x600")
					get_viewport().get_texture().get_image().save_png("user://fsr-help-" + language + "-" + str(row_id) + ".png")
			GameData._tips.delay = 100
			Input.warp_mouse(Vector2(20, 20))
			await settle()
			aa.show_popup()
			await settle()
			check(aa.get_popup().visible, "AA dropdown opens")
			var popup := aa.get_popup()
			check(aa._popup_bounds().encloses(Rect2(popup.position,popup.size)),language + " taller dropdown remains within the screen")
			check(popup.max_size.y > 360 if size.y > 600 else popup.max_size.y <= size.y,language + " dropdown uses the enlarged screen-bounded height budget")
			get_viewport().get_texture().get_image().save_png("user://fsr-aa-" + language + "-" + str(size.x) + ".png")
			aa.get_popup().hide()
			panel.queue_free()
			await settle()
	RemakeText.lang = "en"
	var result := {"checks":checks,"failures":failures,"facts":facts}
	FileAccess.open("user://fsr-screen.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("FSR_SCREEN ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
