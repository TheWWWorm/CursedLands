extends Node
## Optional illustrations for export_wiki.gd. Requires a rendered invocation.
## The plan is produced locally by export_wiki.gd; only thumbnails are public.

func _ready() -> void:
	var plan_path := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-image-plan="): plan_path = arg.trim_prefix("--wiki-image-plan=")
		if arg.begins_with("--wiki-images="): output = arg.trim_prefix("--wiki-images=")
	if plan_path.is_empty() or output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a rendered invocation with --wiki-image-plan and --wiki-images")
		get_tree().quit(1)
		return
	for i in 20: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.size = Vector2i(320, 320)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var preview := WikiPreview.new()
	preview.position = Vector2(20, 20)
	preview.size = Vector2(280, 280)
	add_child(preview)
	DirAccess.make_dir_recursive_absolute(output)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var written := 0
	var missing := []
	for key: String in plan:
		var destination := output.path_join(key + ".webp")
		if FileAccess.file_exists(destination):
			written += 1
			continue
		if not preview.show_model(plan[key]):
			missing.append(key)
			continue
		# Framing, paperdoll pose, transparent target allocation and its first
		# submitted draw must all finish before the readback.
		for i in 7: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = preview.creature._vp if preview.creature != null else preview.item._vp
		var img := viewport.get_texture().get_image()
		if img.is_empty() or img.is_invisible():
			missing.append(key)
		else:
			img.resize(280, 280, Image.INTERPOLATE_LANCZOS)
			var error := img.save_webp(destination, false, 0.85)
			if error != OK:
				printerr("Cannot write illustration: ", destination, " (", error, ")")
				get_tree().quit(1)
				return
			written += 1
		if (written + missing.size()) % 100 == 0:
			print("WIKI_IMAGES ", written, "/", plan.size(), " missing=", missing.size())
	preview.clear()
	var result := {"requested": plan.size(), "written": written, "unavailable": missing}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("WIKI_IMAGES_RESULT ", JSON.stringify(result))
	get_tree().quit()
