extends Node
## Rendered captures of the cut-content pages in the native wiki.
func frames(n := 30) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-lang="): RemakeText.lang = arg.trim_prefix("--ui-lang=")
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 720)
	await frames()
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): out = arg.trim_prefix("--capture=")
	var pages: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pages="): pages = arg.trim_prefix("--pages=").split(",")
	var panel := WikiPanel.new()
	add_child(panel)
	panel.open()
	await frames(60)
	get_viewport().get_texture().get_image().save_png(out.path_join("%s-home.png" % RemakeText.lang))
	for spec: String in pages:
		var key := spec.get_slice("@", 0)
		var variant := spec.get_slice("@", 1) if "@" in spec else ""
		assert(panel.catalog.entries.has(key), "Missing requested Cut content page: " + key)
		panel.navigate(key, true, variant)
		await frames(90)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("%s-%s.png" % [RemakeText.lang, (key + "_" + variant).replace("/", "_").replace("%20", "-")]))
		assert(panel.current == key, "Wiki did not navigate to requested page")
		print("CAPTURED ", key, " ", variant)
	print("NATIVE_WIKI ", JSON.stringify({"campaign": GameData.campaign_id, "language": RemakeText.lang, "pages": pages, "version": ProjectSettings.get_setting("application/config/version")}))
	get_tree().quit()
