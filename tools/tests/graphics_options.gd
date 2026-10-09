extends Node
## Run with a private user:// profile. Exercises the real options screen's
## mouse, controller key bridge and touch routing, plus saved setting keys.
var checks := 0
var failures: Array[String] = []
var panel: OptionsPanel
var page_names := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = panel.p8(point)
		panel._gui_input(event)


func tap(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = panel.get_global_transform_with_canvas() * panel.p8(point)
		TouchInput._input(event)
		await frames(1)


func pad(action: String) -> void:
	PadInput._press(action)
	PadInput._release(action)
	await frames(1)


func row_of(name: String) -> int:
	for row: int in panel._rows:
		if panel._rows[row].name == name:
			return row
	return -1


func link_of(group: int) -> int:
	for row: int in panel._rows:
		if panel._rows[row].get("to", -1) == group:
			return row
	return -1


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	panel.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://graphics-options-" + name + ".png")


func navigation() -> void:
	var seen := {}
	for parent: int in [0, OptionsPanel.REMAKE_GROUP]:
		panel._show_group(parent)
		check(panel._rows.size() <= 14, "root %d fits the fixed grid" % parent)
		for group: int in OptionsPanel.GRAPHICS_LINKS:
			var row := link_of(group)
			check(row >= 0, "root %d links graphics page %d" % [parent, group])
			if row < 0:
				continue
			click(Vector2(350, 168 + 24 * row))
			check(panel._group == group and panel._parent(group) == parent and panel._tab() == parent,
				"mouse link opens page %d under root %d" % [group, parent])
			check(panel._rows.get(OptionsPanel.PRESET_ROW, {}).get("preset", false), "page %d retains Original look" % group)
			check(panel._rows.get(OptionsPanel.BACK_ROW, {}).get("to", -1) == parent, "page %d retains its Back row" % group)
			var names: Array = []
			for item: Dictionary in panel._rows.values():
				if item.kind != "link":
					names.append(item.name)
					if parent == 0:
						check(not seen.has(item.name), "one graphics placement for " + item.name)
						seen[item.name] = group
			page_names[GameData.OPTION_GROUPS[group]] = names
			for option: Array in GameData.OPTIONS:
				if int(option[3]) == group:
					check(option[0] in names, "visible graphics setting " + option[0])
			await pad("up")
			check(panel._sel == OptionsPanel.BACK_ROW, "controller Up wraps to Back on page %d" % group)
			await pad("down")
			check(panel._sel == 0, "controller Down wraps to the first setting on page %d" % group)
			await pad("cancel")
			check(panel._group == parent and panel._sel == row, "controller B returns to the selected link on root %d" % parent)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):
			check(seen.has(option[0]), "all graphics effects reachable: " + option[0])
	panel._show_group(0)
	await pad("up")
	check(panel._sel == 13, "controller can wrap to the fifth graphics link")
	await pad("interact")
	check(panel._group == OptionsPanel.EFFECTS_GROUP, "controller A opens the fifth graphics section")
	await pad("items")
	check(panel._group == OptionsPanel.SCREEN_GROUP, "controller RB steps from graphics subpage to Screen")
	await pad("actions")
	check(panel._group == 0, "controller LB returns to Graphics")
	await tap(Vector2(350, 168 + 24 * link_of(OptionsPanel.WATER_GROUP)))
	check(panel._group == OptionsPanel.WATER_GROUP, "touch opens Water through normal input routing")
	await tap(Vector2(350, 168 + 24 * OptionsPanel.BACK_ROW))
	check(panel._group == 0, "touch Back returns to Graphics")
	TouchInput.enabled = false
	TouchInput.mode_changed.emit()


func localization_and_layout() -> void:
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		for group: int in OptionsPanel.GRAPHICS_LINKS:
			panel._show_group(0)
			panel._show_group(group)
			var pair: Array = GameData.REMAKE_OPTIONS[GameData.OPTION_GROUPS[group]]
			check(language == "en" or (RemakeText.t(pair[0]) != pair[0] and RemakeText.t(pair[1]) != pair[1]),
				"translated section label and help: %s %s" % [language, pair[0]])
			check(panel.text_width(panel._group_label(group), 2) <= 600.0,
				"section breadcrumb fits: %s %s" % [language, pair[0]])
			if language != "en":
				var translated := true
				for row: Dictionary in panel._rows.values():
					if row.kind == "link":
						continue
					for source: String in GameData.REMAKE_OPTIONS[row.name]:
						var translation: Array = RemakeText.TEXTS.get(source, [])
						translated = translated and translation.size() == 2 and not translation.has("")
				check(translated, "all setting labels and help translated: %s %s" % [language, pair[0]])
			await capture("%s-%s" % [language, GameData.OPTION_GROUPS[group]])
		panel._show_group(0)
		await capture(language + "-graphics")
		panel._show_group(OptionsPanel.REMAKE_GROUP)
		await capture(language + "-remake")
		for key: String in ["gfx_water_waves","gfx_depth_of_field","gfx_terrain_cliffs","gfx_weather_mist"]:
			var words: Array = GameData.REMAKE_OPTIONS[key]
			check(language == "en" or (RemakeText.t(words[0]) != words[0] and RemakeText.t(words[1]) != words[1]),
				"translated label and dependency help: " + language + " " + key)
			check(panel.text_width(RemakeText.t(words[0])) <= 260.0,
				"setting label fits without ellipsis: " + language + " " + key)
	RemakeText.lang = "en"


func presets_and_persistence() -> void:
	for key: String in ["gfx_waterfalls","gfx_ambient_wildlife","gfx_ambient_particles","gfx_clouds","gfx_depth_of_field","gfx_terrain_cliffs","gfx_weather_mist"]:
		check(GameData.option(key)==0 and key in GameData.OPTIONS_APPLIED,"new effect is opt-in and registered: "+key)
		for tier in GfxDetect.LAST+1:
			check(int(GfxDetect.tier_values(tier,GfxDetect.base_values({})).get(key,-1))==0,"automatic tier %d leaves %s off"%[tier,key])
	check(GameData.option("gfx_water_waves") == 0, "new wave setting starts off")
	check("gfx_water_waves" in GameData.OPTIONS_APPLIED, "wave setting is applied by the settings screen")
	var base := GfxDetect.base_values({})
	for tier in GfxDetect.LAST + 1:
		check(GfxDetect.tier_values(tier, base).gfx_water_waves == 0, "automatic tier %d keeps waves opt-in" % tier)
	base.gfx_water_waves = 1
	check(GfxDetect.tier_values(2, base).gfx_water_waves == 0, "lower graphics tier clears explicitly enabled waves")
	base.gfx_depth_of_field=1;base.gfx_terrain_cliffs=1;base.gfx_weather_mist=1
	check(GfxDetect.tier_values(1,base).gfx_weather_mist==0,"first lower tier clears mist together with required volumetric fog")
	check(GfxDetect.tier_values(1,base).gfx_depth_of_field==0,"first lower tier clears explicitly enabled DOF")
	check(GfxDetect.tier_values(2,base).gfx_terrain_cliffs==0,"second lower tier clears explicitly enabled cliff textures")
	panel._show_group(OptionsPanel.WATER_GROUP)
	panel._set_value("gfx_water_waves", 1)
	panel._set_value("gfx_depth_of_field",1)
	panel._set_value("gfx_weather_mist",1)
	var quality := int(panel._values.q_aniso)
	click(Vector2(580, 168 + 24 * OptionsPanel.PRESET_ROW))
	check(GfxDetect.original_look_on(panel._values) and panel._values.gfx_water_waves == 0, "Original look covers all five pages and new waves")
	check(panel._values.gfx_weather_mist==0,"Original look clears optional local water mist")
	check(panel._values.gfx_depth_of_field==0,"Original look clears the optional camera lens")
	check(panel._values.q_aniso == quality, "Original look keeps texture filtering")
	click(Vector2(580, 168 + 24 * OptionsPanel.PRESET_ROW))
	check(not GfxDetect.original_look_on(panel._values) and panel._values.gfx_water_waves == 0, "leaving Original look restores platform defaults with waves off")
	panel._close()
	panel.open()
	panel._show_group(0)
	panel._show_group(OptionsPanel.TERRAIN_GROUP)
	var row := row_of("gfx_biome_cover")
	click(Vector2(580, 168 + 24 * row))
	panel._show_group(OptionsPanel.WATER_GROUP)
	row = row_of("gfx_water_waves")
	click(Vector2(580, 168 + 24 * row))
	check(panel._values.gfx_biome_cover == 1 and panel._values.gfx_water_waves == 1,
		"pending changes survive switching between the new sections")
	check(GameData.option("gfx_biome_cover") == 0 and GameData.option("gfx_water_waves") == 0, "graphics edits wait for Accept")
	await pad("pause")
	check(not panel.visible and GameData.option("gfx_biome_cover") == 1 and GameData.option("gfx_water_waves") == 1,
		"controller Y accepts changes on different graphics pages")
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH) == OK and cfg.get_value("options", "gfx_biome_cover", -1) == 1
		and cfg.get_value("options", "gfx_water_waves", -1) == 1, "original setting keys and new wave key persist")
	panel.open()
	panel._show_group(OptionsPanel.WATER_GROUP)
	check(panel._values.gfx_water_waves == 1, "reopened Water page shows saved value")
	click(Vector2(580, 168 + 24 * row_of("gfx_water_waves")))
	await pad("menu")
	check(is_instance_valid(panel._box), "controller Menu asks to save the pending wave change")
	if is_instance_valid(panel._box):
		panel._box.answered.emit(false)
	check(not panel.visible and GameData.option("gfx_water_waves") == 1, "discard preserves saved wave value")
	panel.open()
	check(panel._values.gfx_water_waves == 1, "discarded change is absent on reopen")


func _ready() -> void:
	await frames()
	GameData.options.merge({"show_tutorial": 0, "auto_graphics": 0, "confine_mouse": 0,
		"gfx_biome_cover": 0, "gfx_water_waves": 0}, true)
	get_window().size = Vector2i(800, 600)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	panel = OptionsPanel.new()
	add_child(panel)
	panel.open()
	await frames()
	check(get_viewport().get_visible_rect().size == Vector2(800, 600), "fixture uses the minimum 800 by 600 display size")
	await navigation()
	await localization_and_layout()
	await presets_and_persistence()
	panel.queue_free()
	await frames()
	var receipt := {"checks": checks, "failures": failures, "pages": page_names,
		"renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name()}
	FileAccess.open("user://graphics-options.json", FileAccess.WRITE).store_string(JSON.stringify(receipt, "\t"))
	print("GRAPHICS_OPTIONS ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
