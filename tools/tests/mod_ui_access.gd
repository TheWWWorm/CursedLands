extends Node
## Real popup sizing, explicit switches and transactional first-time activation.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame
	await RenderingServer.frame_post_draw
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0},true)
	RenderingServer.set_render_loop_enabled(true)
	await frames(15);GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	check(ModStore.create_profile("My Profile").is_empty(),"create test profile")
	var id := ModStore.active_id()
	check(ModStore.select_profile("default").is_empty(),"start with ordinary saves")
	for language: String in ["en","ru","de"]:
		RemakeText.lang = language
		var panel := ModPanel.new(); add_child(panel)
		for shape: Vector2i in [Vector2i(1280,720),Vector2i(540,960),Vector2i(3840,2160)]:
			get_tree().root.size = shape;panel.open();await frames()
			check(panel._page == "mods", "opens installed mods directly")
			check(panel._body.size.x <= panel._scroll.size.x + 1, language+" mods fit "+str(shape))
			check(panel._surface.get_global_rect().end.y <= panel.size.y + 1, "footer fits viewport")
			check(not panel._download.busy, "opening mods does not start a download")
			get_viewport().get_texture().get_image().save_png("user://mods-%s-%d.png"%[language,shape.x])
			panel._show_page("profiles");await frames();panel._chooser.show_popup();await frames()
			var popup := panel._chooser.get_popup()
			check(popup.get_theme_font_size("font_size") <= 22, "popup uses logical font units once")
			check(popup.size.y < 140 * panel._ui_scale,"two-entry popup stays compact at "+str(shape))
			get_viewport().get_texture().get_image().save_png("user://profile-popup-%s-%d.png"%[language,shape.x])
			popup.hide()
		panel.free()
	RemakeText.lang = "en"
	var panel := ModPanel.new();add_child(panel);panel.open()
	var previous := ModStore.profiles.size()
	panel._packages.assign(["missing.mod@1.0.0"])
	check(not panel._save_packages().is_empty() and ModStore.active_id()=="default" and ModStore.profiles.size()==previous,"invalid activation cannot create or switch a profile")
	var key := "community.hd-lands-textures@1.4.0"
	if ModStore.catalog.has(key):
		panel.open();await frames()
		var toggle: CheckButton
		for control in panel._controls:
			if control is CheckButton:toggle=control;break
		check(toggle!=null and not toggle.disabled and toggle.text==RemakeText.t("Off"),"installed mod can be enabled from default profile with explicit Off label")
		toggle.grab_focus();panel.pad_press("interact","down");await frames()
		check(toggle.button_pressed and toggle.text==RemakeText.t("On") and key in panel._packages,"controller toggles labelled switch")
		check(panel._save_packages().is_empty() and ModStore.active_id()!="default" and key in ModStore.profile().packages,"one transaction creates profile and enables package")
		check(ModStore.profiles.has(id),"existing named profile retained")
		get_viewport().get_texture().get_image().save_png("user://mods-enabled.png")
	panel.free()
	print("MOD_UI_ACCESS ",JSON.stringify({"checks":checks,"failures":failures}));get_tree().quit(1 if failures else 0)
