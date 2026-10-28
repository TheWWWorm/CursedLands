extends Node
## UiScale is the one source of the interface scale rules. Each rule must
## equal the formula the screens used before (so layouts did not move), and
## the encyclopedia must size its secondary labels, rune family tabs and rune
## pieces from the reading scale instead of fixed 13/14/44 px values that
## stayed a third of their intended size at 2160p.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-6

func _ready() -> void:
	for size: Vector2 in [Vector2(1280,720), Vector2(2560,1440), Vector2(3840,2160), Vector2(800,600), Vector2(600,800), Vector2(1024,1366)]:
		var tag := "%dx%d" % [int(size.x), int(size.y)]
		check(near(UiScale.fit(size), minf(size.x / 800.0, size.y / 600.0)), tag + " fit keeps the 800x600 frame inside")
		check(near(UiScale.by_height(size), size.y / 600.0), tag + " by_height")
		check(near(UiScale.by_width(size), size.x / 800.0) and near(UiScale.by_width(size, 40.0), size.x / 40.0), tag + " by_width")
		check(near(UiScale.by_min_side(size), minf(size.x, size.y) / 600.0), tag + " by_min_side")
		check(near(UiScale.fit_frame(size, 1248.0, 768.0), minf(size.x / 1248.0, size.y / 768.0)), tag + " fit_frame")
		var k := size.y / 600.0
		var within := minf(k, size.x / 380.0) if size.x < size.y else k
		check(near(UiScale.by_height_within(size, 380.0), within), tag + " by_height_within narrows only portrait rooms")
		for slot in 3:
			check(UiScale.font_px(k, slot) == maxi(6, int(round(800.0 * k * Interface800.FONT_EM[slot]))), tag + " font_px slot %d" % slot)
			check(UiScale.font_px_for_width(size.x, slot) == maxi(6, int(round(size.x * Interface800.FONT_EM[slot]))), tag + " font_px_for_width slot %d" % slot)
		check(UiScale.font_px(k, 1, 9) >= 9 and UiScale.font_px(0.0, 1) == 6, tag + " font floors")
		var safe := size - Vector2(32, 32)
		check(near(UiScale.dialog(safe), clampf(minf(safe.x / 1248.0, safe.y / 768.0), 1.0, 3.0)), tag + " dialog surface scale")
		check(near(UiScale.reading(size.y - 28.0), clampf((size.y - 28.0) / 900.0, 0.85, 3.0)), tag + " reading scale")
	check(Interface800.FONT_EM == UiScale.FONT_EM, "Interface800 shares the font table")
	check(UiScale.font_px(2.0, 1, 0) == int(round(1600.0 * 0.01867)), "floor 0 keeps the raw size")

	# The encyclopedia at 720p and 2160p: every label and the rebuilt
	# workbench buttons follow the reading scale.
	var panel := WikiPanel.new()
	add_child(panel)
	var sizes := {}
	for shape: Vector2i in [Vector2i(1280, 720), Vector2i(3840, 2160)]:
		get_tree().root.size = shape
		for i in 4: await get_tree().process_frame
		panel._layout()
		var piece := Button.new(); piece.set_meta("rune_piece", true); panel._rune_palette.add_child(piece)
		var tab := Button.new(); tab.set_meta("rune_family", true); panel._rune_families.add_child(tab)
		panel._scale_workbench_button(piece); panel._scale_workbench_button(tab)
		# A later relayout at the same scale must keep them; a scale change resizes them.
		panel._ui_scale = -1.0; panel._layout()
		sizes[shape.y] = {
			"scale": panel._ui_scale,
			"subtitle": panel._page_subtitle.get_theme_font_size("font_size"),
			"action": panel._action_status.get_theme_font_size("font_size"),
			"version": panel._version_title.get_theme_font_size("font_size"),
			"model": panel._model_title.get_theme_font_size("font_size"),
			"builder": panel._builder_status.get_theme_font_size("font_size"),
			"status": panel._status.get_theme_font_size("font_size"),
			"toolbar": panel._share.get_theme_font_size("font_size"),
			"search": panel._query.get_theme_font_size("font_size"),
			"category": panel._category.get_theme_font_size("font_size"),
			"tab": tab.get_theme_font_size("font_size"),
			"piece": piece.custom_minimum_size.x,
			"piece_font": piece.get_theme_font_size("font_size"),
			"icon": piece.get_theme_constant("icon_max_width"),
		}
		piece.queue_free(); tab.queue_free()
	var low: Dictionary = sizes[720]
	var high: Dictionary = sizes[2160]
	check(high.scale >= 2.5 * low.scale, "reading scale grows with the window (%.2f -> %.2f)" % [low.scale, high.scale])
	for key: String in ["subtitle", "action", "version", "model", "builder", "status", "toolbar", "search", "category", "tab", "piece", "piece_font", "icon"]:
		check(float(high[key]) >= 2.5 * float(low[key]), "%s scales with the reading scale (%s -> %s)" % [key, str(low[key]), str(high[key])])
	check(low.subtitle == roundi(13 * low.scale) and is_equal_approx(low.piece, 44 * low.scale), "720p sizes equal the authored 13 px / 44 px at the reading scale")
	check(low.toolbar == roundi(16 * low.scale) and low.search == roundi(16 * low.scale), "toolbar and search use the theme's 16 px at the reading scale")
	panel.free()
	print("UI_SCALE_RULES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
