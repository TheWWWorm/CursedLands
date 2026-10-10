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
	var image := Image.create(800,600,false,Image.FORMAT_RGB8); image.fill(Color(.04,.04,.04))
	var panel := OptionsPanel.new(); add_child(panel); panel.open(image)
	check(panel._rows[8].name=="graphics_preset","main Graphics page exposes the preset selector")
	for preset in [1,2,3,4]:
		panel._set_value("graphics_preset",preset)
		check(panel._switch_text(panel._rows[8])==RemakeText.t(GfxPresets.NAMES[preset]),"explicit preset label "+str(preset))
		check(panel._values.auto_graphics==0,"explicit preset disables detection "+str(preset))
		check(panel._values.gfx_clouds==0 and panel._values.gfx_ground_contact==0 and panel._values.gfx_depth_of_field==0,"expensive optional effects stay opt-in "+str(preset))
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
		for preset in [1,2,3,4]:
			var values := GfxPresets.values(preset,method)
			check(not values.has("renderer") and not values.has("resolution") and not values.has("control_mode"),"preset preserves renderer, display and controls "+method+str(preset))
			if method!="forward_plus": check(values.gfx_ssao==0 and values.gfx_volumetric==0 and values.gfx_water_reflections==0,"unsupported screen effects stay off "+method+str(preset))
			if method=="gl_compatibility": check(values.q_aa==0,"Compatibility preset avoids unsupported SMAA "+str(preset))
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang; panel._show_group(0)
		await frames()
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png("user://graphics-presets-"+lang+".png")==OK,"capture localized preset selector "+lang)
	panel._restore(); panel._close(); panel.free()
	print("GRAPHICS_PRESETS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
