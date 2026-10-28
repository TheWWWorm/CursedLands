extends Node
## Render the actual first-run and Options setup screens at phone, desktop and
## 4K sizes without original UI archives. Exercise both campaign and import
## state changes in an isolated development profile.

var checks := 0
var failures := 0
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func settle() -> void:
	for i in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func inspect_controls(node: Node, label: String) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var control := node as Control
		if control is Button or control is LineEdit or control is Label:
			var minimum := control.get_combined_minimum_size()
			check(control.size.x + 1 >= minimum.x and control.size.y + 1 >= minimum.y,
				label + " fits " + str(control.name) + " " + str(control.size) + " >= " + str(minimum))
		if control is Label:
			var text := control as Label
			check(text.get_line_count() <= text.get_visible_line_count(), label + " shows all label lines: " + text.text)
	for child in node.get_children():
		inspect_controls(child, label)

func _ready() -> void:
	var old_root: String = GameData.root
	var old_roots: Dictionary = GameData.campaign_roots.duplicate()
	var old_textures = GameData.textures
	var old_lang: String = RemakeText.lang
	GameData.root = ""
	GameData.campaign_roots.clear()
	GameData.textures = null
	Interface800.clear_cache()
	var sizes := [Vector2i(390, 844), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]
	for variant: String in ["desktop", "portable"]:
		for lang: String in ["en", "ru", "de"]:
			RemakeText.lang = lang
			for dimensions: Vector2i in sizes:
				var viewport := SubViewport.new()
				viewport.size = dimensions
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var screen: Control = (load("res://src/ui/setup_screen.gd") if variant == "desktop" else load("res://src/ui/portable_setup.gd")).new()
				if dimensions == Vector2i(960, 540):
					screen.back_text = RemakeText.t("Back to options")
				viewport.add_child(screen)
				await settle()
				var label := "%s %s %s" % [variant, lang, dimensions]
				var layout: GameFilesPresentation = screen._presentation
				check(layout.scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, label + " horizontal scrolling disabled")
				check(layout.body.size.x <= layout.scroll.size.x + 1, label + " content fits viewport width")
				check(layout._choices.buttons.size() == 2, label + " both campaigns shown")
				check(screen._play.disabled, label + " play disabled without installed data")
				var logo := layout.body.find_child("Logo", true, false) as TextureRect
				check(logo != null and logo.texture == load("res://icon.png"), label + " approved logo is present")
				if logo:
					check(logo.get_global_rect().end.y <= layout._title.get_global_rect().position.y + 1, label + " logo is above the title")
					check(logo.size.x > 0 and logo.size.y > 0 and logo.texture.get_size().x >= logo.size.x, label + " logo uses sufficient source resolution")
				check(layout._title.get_theme_font_size("font_size") >= roundi(31 * layout._ui_scale), label + " native font scales with UI")
				check(layout.body.scale == Vector2.ONE, label + " controls do not magnify a rasterized surface")
				inspect_controls(layout.body, label)
				if variant == "desktop":
					for button: Button in [screen._buttons[1], screen._buttons[3]]:
						check(button.size.y < 85 * layout._ui_scale, label + " browse row remains compact")
						check(button.size.x >= button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + 20 * layout._ui_scale, label + " browse label fits")
				if dimensions == Vector2i(3840, 2160) or (dimensions == Vector2i(390, 844) and variant == "portable") or (dimensions in [Vector2i(1280, 720), Vector2i(2560, 1440)] and variant == "desktop" and lang == "en"):
					var path := "user://game-files-%s-%s-%dx%d.png" % [variant, lang, dimensions.x, dimensions.y]
					check(viewport.get_texture().get_image().save_png(path) == OK, label + " capture")
				if dimensions == Vector2i(1280, 720):
					var all_buttons: Array = []
					all_buttons.append_array(screen._buttons)
					all_buttons.append(screen._cancel)
					all_buttons.append_array(layout._choices.buttons.values())
					for button: Button in all_buttons:
						for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
							check(button.get_theme_stylebox(state) is StyleBoxFlat, label + " untextured " + state + " button")
					var campaign_button: Button = layout._choices.buttons[CampaignProfile.ORIGINAL]
					var selected: StyleBox = campaign_button.get_theme_stylebox("pressed")
					var unselected: StyleBox = campaign_button.get_theme_stylebox("normal")
					if selected is StyleBoxFlat and unselected is StyleBoxFlat:
						check(selected.bg_color != unselected.bg_color and selected.border_color != unselected.border_color, label + " selected campaign has a distinct fill and border")
					else:
						check(false, label + " selected campaign uses a flat style")
					layout._choices.buttons[CampaignProfile.ASTRAL].pressed.emit()
					await settle()
					check(screen.selected_campaign == CampaignProfile.ASTRAL, label + " expansion selected")
					check(screen._iso_button.visible, label + " expansion ISO action visible")
					inspect_controls(layout.body, label + " expansion")
					if lang == "ru":
						var expansion_path := "user://game-files-%s-ru-expansion.png" % variant
						check(viewport.get_texture().get_image().save_png(expansion_path) == OK, label + " expansion capture")
					layout._choices.buttons[CampaignProfile.ORIGINAL].pressed.emit()
					check(screen.selected_campaign == CampaignProfile.ORIGINAL and not screen._iso_button.visible, label + " main campaign hides ISO action")
					GameData.campaign_roots[CampaignProfile.ORIGINAL] = old_root
					screen._choose_campaign(CampaignProfile.ORIGINAL)
					check(not screen._play.disabled, label + " installed campaign enables play")
					GameData.campaign_roots.clear()
					screen._choose_campaign(CampaignProfile.ORIGINAL)
					if variant == "desktop":
						screen._path.text = ""
						screen._try_open()
						check(not screen._status.text.is_empty() and GameData.root.is_empty(), label + " invalid folder reports an error without switching")
						screen._prepare_pack()
						check(screen._cancel.visible and screen._buttons[1].disabled, label + " import busy state")
						screen._pack_done("", "fixture error")
						check(not screen._cancel.visible and not screen._buttons[1].disabled, label + " failed import restores actions")
					else:
						screen._busy(true)
						check(screen._cancel.visible and screen._buttons[1].disabled, label + " import busy state")
						screen._busy(false)
						check(not screen._cancel.visible and not screen._buttons[1].disabled, label + " import restores actions")
						screen._browser_result(["progress", "Checking your local game files…"])
						check(screen._cancel.visible and screen._buttons[1].disabled, label + " browser progress state")
						screen._browser_result(["error", "Could not write imported game data."])
						check(not screen._cancel.visible and not screen._buttons[1].disabled and not screen._status.text.is_empty(), label + " browser error restores actions")
				if dimensions == Vector2i(960, 540):
					check(layout.body.find_child("Current", true, false) != null, label + " options return shows current files")
					var returned := [false]
					screen.cancelled.connect(func(): returned[0] = true)
					var back: Button = null
					for button: Button in screen._buttons:
						if button.text == screen.back_text: back = button
					check(back != null, label + " options return button exists")
					if back:
						back.pressed.emit()
						check(returned[0], label + " options return emits cancellation")
				samples.append({"screen":variant,"language":lang,"size":str(dimensions),"scale":layout._ui_scale,"content_width":layout.body.size.x,"scroll_width":layout.scroll.size.x})
				viewport.queue_free()
				await get_tree().process_frame
	# Exercise resizing the same screen, including a short viewport that needs
	# vertical scrolling, rather than testing only separately constructed views.
	RemakeText.lang = "en"
	var live_viewport := SubViewport.new()
	live_viewport.size = Vector2i(3840, 2160)
	live_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(live_viewport)
	var live: Control = load("res://src/ui/setup_screen.gd").new()
	live.back_text = RemakeText.t("Back to options")
	live_viewport.add_child(live)
	live._choose_campaign(CampaignProfile.ASTRAL)
	await settle()
	check(is_equal_approx(live._presentation._ui_scale, 3.0), "live resize starts at 4K scale")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(390, 400), Vector2i(3840, 2160)]:
		live_viewport.size = dimensions
		await settle()
		var unit := clampf(minf(dimensions.x / 1280.0, dimensions.y / 720.0), 1.0, 3.0)
		check(is_equal_approx(live._presentation._ui_scale, unit), "live resize uses current scale " + str(dimensions))
		check(live._presentation._title.get_theme_font_size("font_size") == roundi(31 * unit), "live resize rasterizes title at the new size " + str(dimensions))
		check(live.selected_campaign == CampaignProfile.ASTRAL and live._iso_button.visible, "live resize retains expansion selection " + str(dimensions))
		check(live._presentation.body.size.x <= live._presentation.scroll.size.x + 1, "live resize keeps content within width " + str(dimensions))
		if dimensions == Vector2i(390, 400):
			var scroll: ScrollContainer = live._presentation.scroll
			var bar := scroll.get_v_scroll_bar()
			check(bar.max_value > bar.page, "short view offers vertical scrolling")
			scroll.scroll_vertical = roundi(bar.max_value)
			await settle()
			check(scroll.scroll_vertical > 0, "short view scrolls")
			check(scroll.get_global_rect().intersection(live._status.get_global_rect()).has_area(), "short view can reveal the last status")
	live_viewport.queue_free()
	await get_tree().process_frame
	GameData.root = old_root
	GameData.campaign_roots = old_roots
	GameData.textures = old_textures
	RemakeText.lang = old_lang
	Interface800.clear_cache()
	# The actual desktop folder action still opens a verified installed game.
	var open_screen: Control = load("res://src/ui/setup_screen.gd").new()
	add_child(open_screen)
	var opened := [false]
	open_screen.opened.connect(func(): opened[0] = true)
	open_screen._path.text = old_root
	open_screen._try_open()
	check(opened[0] and GameData.root == old_root, "using the real installed folder still opens the game")
	open_screen.queue_free()
	var result := {"checks":checks,"failures":failures,"samples":samples}
	FileAccess.open("user://game-files-presentation.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("GAME_FILES_PRESENTATION ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
