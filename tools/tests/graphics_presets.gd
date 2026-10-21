extends Node
## Real settings panel, persistent choice, cancellation and manual overrides.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func frames() -> void:
	for i in 4: await get_tree().process_frame
func _ready() -> void:
	TutorialPanel.auto_show=false
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"volume_sfx":0,"volume_stream":0},true)
	# Finish the startup display transition before capturing localized panels.
	# The X11 fullscreen fallback settles after ten main-loop frames.
	for i in 3: await frames()
	var image := Image.create(800,600,false,Image.FORMAT_RGB8); image.fill(Color(.04,.04,.04))
	var panel := OptionsPanel.new(); add_child(panel); panel.open(image)
	check(panel._rows[8].name=="graphics_preset","main Graphics page exposes the preset selector")
	for preset in [GfxPresets.ORIGINAL, GfxPresets.VERY_LOW, GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.VERY_HIGH, GfxPresets.ULTRA]:
		panel._set_value("graphics_preset",preset)
		check(panel._switch_text(panel._rows[8])==RemakeText.t(GfxPresets.NAMES[preset]),"explicit preset label "+str(preset))
		check(panel._values.auto_graphics==0,"explicit preset disables detection "+str(preset))
		if preset==1:
			var off := true
			for key: String in panel._values:
				if key.begins_with("gfx_") and panel._values[key]!=0: off=false
			check(off,"Original switches off all remake graphics")
		if preset==2: check(panel._values.gfx_grass==0 and panel._values.gfx_ssao==0 and panel._values.gfx_firelight==0,"Low omits geometry, screen-space AO and dynamic firelight")
		var snapshot := GameData.options.duplicate()
		panel._restore(); panel._close()
		check(GameData.options==snapshot,"unconfirmed preset leaves live settings alone")
		panel.open(image)
	# Apply through the actual save path, then read the disk and reopen.
	panel._set_value("graphics_preset",2)
	var applied: Array = []
	var observe := func(): applied.append(GameData.options.duplicate())
	GameData.options_changed.connect(observe)
	panel._accept()
	GameData.options_changed.disconnect(observe)
	check(applied.size()==1,"applying a preset publishes one complete settings change")
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH)==OK and int(cfg.get_value("options","graphics_preset",-1))==2,"Low choice persists in settings.cfg")
	panel.open(image)
	check(panel._values.graphics_preset==2,"reopened panel remembers the explicit choice")
	for i in OptionsPanel.GRAPHICS_LINKS.size():
		panel._show_group(0); panel._toggle(OptionsPanel.GRAPHICS_LINK_ROW+i)
		check(panel._group==OptionsPanel.GRAPHICS_LINKS[i],"advanced graphics page remains reachable "+str(i))
	panel._set_value("gfx_grass",1)
	check(panel._values.graphics_preset==0 and panel._values.auto_graphics==0,"advanced override becomes Custom without restarting detection")
	panel._accept(); panel.open(image)
	check(panel._values.graphics_preset==0 and panel._values.gfx_grass==1,"Custom override persists")
	# Source marker is deliberately distinct even if detection picks the
	# same values as a manual preset. No expensive benchmark is faked here.
	panel._values.graphics_preset=GfxPresets.DETECTED; panel._show_group(0)
	check(panel._switch_text(panel._rows[8])==RemakeText.t("Detected"),"measured automatic choice has its own label")
	panel._values.graphics_preset=GfxPresets.CUSTOM
	for method in ["gl_compatibility","mobile","forward_plus"]:
		for preset in [GfxPresets.ORIGINAL, GfxPresets.VERY_LOW, GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.VERY_HIGH, GfxPresets.ULTRA]:
			var values := GfxPresets.values(preset,method)
			check(not values.has("renderer") and not values.has("resolution") and not values.has("control_mode"),"preset preserves renderer, display and controls "+method+str(preset))
			if method!="forward_plus" and preset != GfxPresets.ULTRA: check(values.gfx_ssao==0 and values.gfx_volumetric==0 and values.gfx_water_reflections==0,"unsupported screen effects stay off "+method+str(preset))
			if method=="gl_compatibility": check(values.q_aa==0,"Compatibility preset avoids unsupported SMAA "+str(preset))
	for method in ["gl_compatibility", "mobile", "forward_plus"]:
		var last := {}
		for preset in GfxPresets.ORDER:
			if preset in [GfxPresets.CUSTOM, GfxPresets.DETECTED]: continue
			var values := GfxPresets.values(preset, method)
			if method == "forward_plus" and preset in [GfxPresets.HIGH, GfxPresets.VERY_HIGH, GfxPresets.ULTRA]:
				check(values.gfx_water_reflections == 2, "enabled preset reflections use Mirror " + str(preset))
			if not last.is_empty():
				var nondecreasing := true
				for key in values:
					if values[key] < last[key]: nondecreasing = false
				check(nondecreasing and last != values, "distinct gradual preset " + method + str(preset))
			last = values
			if preset == GfxPresets.ULTRA:
				for o in GameData.OPTIONS:
					if String(o[0]).begins_with("gfx_"):
						var expected := 2 if o[0] == "gfx_water_reflections" else int(o[2])-1
						check(values[o[0]] == expected, "Ultra enables supported effects without opting into RT: " + o[0] + " on " + method)
	check(panel._preset_picker is OptionButton, "graphics preset is an actual dropdown")
	panel._set_value("graphics_preset", GfxPresets.ULTRA)
	panel._sync_preset_picker()
	check(panel._preset_picker.get_selected_id() == GfxPresets.ULTRA, "dropdown selects Ultra by stable saved ID")
	panel._preset_picker.select(panel._preset_picker.get_item_index(GfxPresets.HIGH))
	panel._preset_picker.item_selected.emit(panel._preset_picker.selected)
	check(panel._values.graphics_preset == GfxPresets.HIGH and panel._values.gfx_water_waves == 1, "dropdown applies High including water effects")
	var defaults := GfxDetect.base_values({})
	check(defaults.gfx_water_reflections == 2, "desktop defaults use Mirror")
	for tier in [0, 1]:
		check(GfxDetect.tier_values(tier, defaults).gfx_water_reflections == 2, "automatic tier keeps Mirror " + str(tier))
	panel._set_value("gfx_water_reflections", 1)
	panel._accept(); panel.open(image)
	check(panel._values.gfx_water_reflections == 1 and panel._values.graphics_preset == GfxPresets.CUSTOM, "explicit Natural choice persists as Custom")
	for lang in ["en","ru","de"]:
		# Language is selected at startup from the supplied game edition.
		# Recreate the panel so controls initialized in _ready use that edition.
		panel._restore(); panel._close(); panel.free()
		RemakeText.lang=lang
		panel=OptionsPanel.new(); add_child(panel); panel.open(image)
		panel._show_group(0)
		for index in panel._preset_picker.item_count:
			var id := panel._preset_picker.get_item_id(index)
			check(panel._preset_picker.get_item_text(index) == RemakeText.t(GfxPresets.NAMES[id]), "localized dropdown choice "+lang+" "+str(id))
		await frames()
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			panel._preset_picker.show_popup()
			await frames()
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png("user://graphics-presets-"+lang+".png")==OK,"capture localized preset selector "+lang)
		panel._preset_picker.get_popup().hide()
	panel._restore(); panel._close(); panel.free()
	FileAccess.open("user://graphics-presets.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("GRAPHICS_PRESETS ", JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown()
	await frames()
	get_tree().quit(1 if failures else 0)
