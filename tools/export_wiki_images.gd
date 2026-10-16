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
	var framing := {}
	for key: String in plan:
		var destination := output.path_join(key + ".webp")
		if FileAccess.file_exists(destination):
			written += 1
			continue
		if plan[key].kind == "map":
			var map := WikiPreview.map_image(plan[key])
			if map == null: missing.append(key)
			else:
				map.save_webp(destination,false,.9)
				written += 1
			continue
		if not preview.show_model(plan[key]):
			missing.append(key)
			continue
		var descriptor: Dictionary = plan[key]
		if descriptor.has("layer"):
			var texture := EIUnitModel._compose(descriptor.mask, [descriptor.layer] as Array[String])
			if texture == null:
				printerr("Missing authored wiki skin: ", descriptor)
				get_tree().quit(1)
				return
			for mesh: MeshInstance3D in preview.item._model.find_children("*", "MeshInstance3D", true, false):
				var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
				material.albedo_texture = texture
				var scale := 256.0 / float(texture.get_width())
				material.uv1_scale = Vector3(scale, scale, 1)
				material.uv1_offset = Vector3(0, 1.0 - scale, 0)
				mesh.material_override = material
		# Framing, paperdoll pose, transparent target allocation and its first
		# submitted draw must all finish before the readback.
		for i in 7: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = preview.creature._vp if preview.creature != null else preview.item._vp
		var img := viewport.get_texture().get_image()
		if img.is_empty() or img.is_invisible():
			missing.append(key)
		else:
			# A still illustration needs only the visible pose, not the full
			# rotation envelope used by the interactive inventory model.
			var camera: Camera3D
			var model: Node3D
			if preview.creature != null:
				preview.creature.set_process(false)
				camera = preview.creature._cam
				model = preview.creature._model
			else:
				camera = preview.item._fit_camera
				model = preview.item._model
			model.set_process(false)
			for attempt in 4:
				var bounds := img.get_used_rect()
				var dimensions := Vector2(img.get_size())
				var coverage := maxf(bounds.size.x / dimensions.x, bounds.size.y / dimensions.y)
				var offset := Vector2(bounds.get_center()) - dimensions * 0.5
				if absf(coverage - 0.86) < 0.025 and offset.length() < 2.0: break
				var depth := maxf(camera.global_position.distance_to(model.global_position), 0.1)
				camera.global_position += camera.project_position(Vector2(bounds.get_center()), depth) - camera.project_position(dimensions * 0.5, depth)
				if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
					camera.size *= coverage / 0.86
				else:
					camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * coverage / 0.86))
				camera.force_update_transform()
				for frame in 2: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				img = viewport.get_texture().get_image()
			img.resize(280, 280, Image.INTERPOLATE_LANCZOS)
			var bounds := img.get_used_rect()
			framing[key] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
			var error := img.save_webp(destination, false, 0.85)
			if error != OK:
				printerr("Cannot write illustration: ", destination, " (", error, ")")
				get_tree().quit(1)
				return
			written += 1
		if (written + missing.size()) % 100 == 0:
			print("WIKI_IMAGES ", written, "/", plan.size(), " missing=", missing.size())
	preview.clear()
	var result := {"requested": plan.size(), "written": written, "unavailable": missing, "framing": framing}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("WIKI_IMAGES_RESULT ", JSON.stringify(result))
	get_tree().quit()
