extends Node
## Render the catalog in EN/RU/DE at desktop and phone widths; controller and
## close/cancel behavior use the actual controls. Isolated --mod-tests only.
var checks := 0
var failures := 0
var panel: ModPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames() -> void:
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func button(label: String) -> Button:
	for control in panel._controls:
		if control is Button and control.text == RemakeText.t(label): return control
	return null

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	TutorialPanel.auto_show = false
	RenderingServer.set_render_loop_enabled(true)
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var original_language := RemakeText.lang
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		if panel != null: panel.free()
		panel = ModPanel.new()
		add_child(panel)
		for shape: Vector2i in [Vector2i(1280,720), Vector2i(540,960)]:
			get_tree().root.size = shape
			panel.open("downloads")
			await frames()
			check(not panel._download.busy and panel._download._http == null, "opening catalog does not contact the network")
			check(panel._body.size.x <= panel._scroll.size.x + 1, language + " catalog fits " + str(shape))
			check(panel._surface.get_global_rect().end.y <= panel.size.y + 1, "catalog actions stay on screen")
			var install := button("Download & install")
			check(install != null and not install.disabled, "install action is available")
			check(button("Source page") != null, "original source link is available")
			get_viewport().get_texture().get_image().save_png("user://downloads-%s-%d.png" % [language, shape.x])
			install.grab_focus()
			await frames()
			check(panel._scroll.get_global_rect().encloses(install.get_global_rect()), "focused install button scrolls fully into view")
	RemakeText.lang = "en"
	panel.free()
	panel = ModPanel.new()
	add_child(panel)
	panel.open("downloads")
	var install := button("Download & install")
	install.grab_focus()
	check(panel.pad_press("interact", "down") and panel._download.busy, "controller starts download through the real button")
	await frames()
	get_viewport().get_texture().get_image().save_png("user://downloads-progress.png")
	check(button("Cancel download") != null, "progress view offers cancellation")
	panel._show_page("profiles")
	check(button("Show download") != null and button("Activate selected mods and restart") == null, "profile changes cannot race the installer")
	var work := panel._download._work
	panel.pad_press("cancel", "down")
	check(not panel.visible and not panel._download.busy, "controller close cancels the download")
	check(not DirAccess.dir_exists_absolute(work), "closing removes the partial download")
	panel.open("downloads")
	check(not button("Download & install").disabled, "cancelled download can be retried")
	var session := Session.new()
	get_parent().add_child(session)
	panel.open("downloads")
	check(button("Download & install") == null, "downloads cannot install during gameplay")
	panel.close(); session.free(); panel.free()
	RemakeText.lang = original_language
	print("MOD_DOWNLOADS_UI ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
