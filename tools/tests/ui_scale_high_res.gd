extends Node
## The encyclopedia at 1280x720, 2560x1440 and 3840x2160 in EN/RU/DE: the
## secondary labels (subtitle, status, version and model titles), the rune
## family tabs and the rune pieces of the spell constructor follow the reading
## scale, wrap without clipping and stay inside the panel; so do the toolbar
## buttons and the spell constructor's selector (title, search, spell rows).
## The panel is built once per language so every label is in that language.
## Captures are kept as user://wiki-scale-<lang>-<height>.png.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames() -> void:
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func fits(label: Label, host: Control, what: String) -> void:
	if not label.visible or label.text.is_empty(): return
	check(label.get_line_count() == label.get_visible_line_count(), what + " wraps without clipping")
	check(host.get_global_rect().grow(1.0).encloses(label.get_global_rect()), what + " stays inside the panel")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	RenderingServer.set_render_loop_enabled(true)
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var original_language := RemakeText.lang
	var measured := {}
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		var panel := WikiPanel.new()
		add_child(panel)
		panel.open()
		await frames()
		var spell := ""
		for key: String in panel.catalog.ordered:
			if panel.catalog.entries[key].kind == "spell": spell = key; break
		check(spell != "", language + ": a spell article exists")
		for shape: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440), Vector2i(3840,2160)]:
			get_tree().root.size = shape
			await frames()
			panel.navigate(spell)
			if not panel._workbench_open: panel._workbench_toggle.pressed.emit()
			await frames()
			var tag := "%s %dp" % [language, shape.y]
			var pieces: Array = panel._rune_palette.get_children().filter(func(n: Node): return n.get_meta("rune_piece", false))
			var tabs: Array = panel._rune_families.get_children().filter(func(n: Node): return n.get_meta("rune_family", false))
			check(not pieces.is_empty() and not tabs.is_empty(), tag + " constructor shows rune families and pieces")
			var scale: float = panel._ui_scale
			var constructor: WikiCampConstructor = panel._camp_constructor
			var choices: Array = constructor._spell_list.get_children() if constructor._spell_list else []
			var row := {"scale": scale,
				"subtitle": panel._page_subtitle.get_theme_font_size("font_size"),
				"version": panel._version_title.get_theme_font_size("font_size"),
				"model": panel._model_title.get_theme_font_size("font_size"),
				"status": panel._status.get_theme_font_size("font_size"),
				"toolbar": panel._share.get_theme_font_size("font_size"),
				"selector_title": constructor._selector_title.get_theme_font_size("font_size") if constructor._selector_title else 0,
				"selector_search": constructor._selector_search.get_theme_font_size("font_size") if constructor._selector_search else 0,
				"choice": (choices[0] as Button).get_theme_font_size("font_size") if not choices.is_empty() else 0,
				"choice_row": (choices[0] as Button).custom_minimum_size.y if not choices.is_empty() else 0.0,
				"tab": (tabs[0] as Button).get_theme_font_size("font_size") if not tabs.is_empty() else 0,
				"piece": (pieces[0] as Button).custom_minimum_size.x if not pieces.is_empty() else 0.0}
			row.note = constructor._selector_notes[0].get_theme_font_size("font_size") if not constructor._selector_notes.is_empty() else 0
			measured[[language, shape.y]] = row
			print("WIKI_SCALE ", tag, " ", JSON.stringify({"panel": scale, "constructor": constructor.ui_scale, "row": row,
				"selector": var_to_str(constructor._selector.get_global_rect()), "constructor_rect": var_to_str(constructor.get_global_rect())}))
			check(row.subtitle == roundi(13 * scale) and row.tab == roundi(14 * scale) and is_equal_approx(row.piece, 44 * scale), tag + " labels, tabs and pieces use the reading scale %.2f" % scale)
			check(row.toolbar == roundi(16 * scale), tag + " toolbar buttons use the reading scale")
			check(not choices.is_empty() and row.selector_title == roundi(24 * scale) and row.selector_search == roundi(16 * scale) and row.choice == roundi(16 * scale) and row.choice_row == roundi(44 * scale) and row.note == roundi(16 * scale), tag + " spell selector title, search, rows and notes use the reading scale")
			check(constructor._selector.visible and constructor.get_global_rect().grow(1.0).encloses(constructor._selector.get_global_rect()), tag + " spell selector stays inside the constructor")
			for piece: Button in pieces:
				check(piece.get_global_rect().size.x >= 44 * scale - 1.0 and piece.get_global_rect().size.y >= 44 * scale - 1.0, tag + " rune piece is at least 44 px at scale")
				break
			fits(panel._page_subtitle, panel, tag + " subtitle")
			fits(panel._version_title, panel, tag + " version title")
			fits(panel._model_title, panel, tag + " model title")
			fits(panel._status, panel, tag + " status")
			fits(panel._action_status, panel, tag + " action status")
			get_viewport().get_texture().get_image().save_png("user://wiki-scale-%s-%d.png" % [language, shape.y])
		var low: Dictionary = measured[[language, 720]]
		var high: Dictionary = measured[[language, 2160]]
		for key: String in ["subtitle", "version", "model", "status", "toolbar", "selector_title", "selector_search", "choice", "choice_row", "tab", "piece"]:
			check(float(high[key]) >= 2.5 * float(low[key]), "%s %s grows at least 2.5x from 720p to 2160p (%s -> %s)" % [language, key, str(low[key]), str(high[key])])
		panel.close(); panel.free()
	RemakeText.lang = original_language
	print("UI_SCALE_HIGH_RES ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
