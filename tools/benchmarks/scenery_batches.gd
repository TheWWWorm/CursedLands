extends Node
## Diagnostic prototype only: compare frozen original map meshes with 16 m
## MultiMesh groups. This intentionally does not implement gameplay lifetime,
## fading, movement or light-membership updates and is not a production switch.
var view: SubViewport
var map: EIMapScene
var groups := {}
var originals: Array[MeshInstance3D] = []
var batches: Array[MultiMeshInstance3D] = []

func settle() -> void:
	for i in 8:
		RenderingServer.force_draw()
		await get_tree().process_frame

func capture(label: String) -> Dictionary:
	await settle()
	var pixels := view.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var path := "user://scenery-batches-" + RenderingServer.get_current_rendering_method() + "-" + label + ".png"
	pixels.save_png(path)
	return {"image": pixels, "draws": view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
			Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), "path": ProjectSettings.globalize_path(path)}

func compare(a: Image, b: Image) -> Dictionary:
	var first := a.get_data()
	var second := b.get_data()
	var changed := 0
	var maximum := 0
	var sum := 0
	for p in range(0, first.size(), 4):
		var error := 0
		for c in 3:
			var delta := absi(first[p + c] - second[p + c])
			error = maxi(error, delta)
			sum += delta
		maximum = maxi(maximum, error)
		changed += int(error > 2)
	return {"pixels_over_2": changed, "max_byte_difference": maximum,
			"mean_channel_difference": float(sum) / (a.get_width() * a.get_height() * 3)}

func collect() -> Vector3:
	var density := {}
	for object: Node3D in map.object_nodes:
		var record: Dictionary = object.get_meta("ei")
		if record.kind != "OBJECT" or record.template.begins_with("ef"):
			continue
		for mesh: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or mesh.mesh.get_blend_shape_count() > 0 or mesh.skin != null \
					or mesh.material_overlay != null or not mesh.is_visible_in_tree():
				continue
			var cell := Vector2i(floori(mesh.global_position.x / 16.0), floori(mesh.global_position.z / 16.0))
			var height: Variant = null if Portability.compatibility() else mesh.get_instance_shader_parameter("part_y")
			var key := [cell, mesh.mesh.get_rid(), mesh.material_override.get_rid(), mesh.layers, mesh.cast_shadow, height]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(mesh)
			density[cell] = int(density.get(cell, 0)) + 1
	var best := Vector2i.ZERO
	var count := 0
	for cell: Vector2i in density:
		if density[cell] > count:
			count = density[cell]
			best = cell
	var x := best.x * 16.0 + 8.0
	var z := best.y * 16.0 + 8.0
	return Vector3(x, map.terrain.height_at(x, -z), z)

func batch() -> void:
	for key: Array in groups:
		var members: Array = groups[key]
		if members.size() < 2:
			continue
		var first := members[0] as MeshInstance3D
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = first.mesh
		multi.instance_count = members.size()
		var box := AABB()
		for i in members.size():
			var mesh := members[i] as MeshInstance3D
			multi.set_instance_transform(i, mesh.global_transform)
			var bounds := mesh.global_transform * mesh.get_aabb()
			box = bounds if i == 0 else box.merge(bounds)
			originals.append(mesh)
			# Keep logical visibility and light masks unchanged. Safe here only
			# because this fixture freezes all transforms and object lifecycle.
			RenderingServer.instance_set_visible(mesh.get_instance(), false)
		multi.custom_aabb = box
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = first.material_override
		node.layers = first.layers
		node.cast_shadow = first.cast_shadow
		if key[5] != null:
			node.set_instance_shader_parameter("part_y", key[5])
		view.add_child(node)
		batches.append(node)

func unbatch() -> void:
	for node in batches:
		node.free()
	batches.clear()
	for mesh in originals:
		RenderingServer.instance_set_visible(mesh.get_instance(), true)
	originals.clear()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("SCENERY_BATCHES requires a real renderer")
		get_tree().quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 30
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["gfx_volumetric"] = 0
	view = SubViewport.new()
	view.size = Vector2i(800, 600)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	map = EIMapScene.load_map("bz13h", "bz13h", false)
	if map == null:
		get_tree().quit(2)
		return
	view.add_child(map)
	var focus := collect()
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position = focus + Vector3(24, 22, 28)
	camera.look_at(focus + Vector3.UP * 2.0)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	view.add_child(sun)
	var shaders := {}
	for mesh: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material and material.shader and not shaders.has(material.shader):
			shaders[material.shader] = true
			material.shader.code = material.shader.code.replace("TIME", "1.25")
	var rows := []
	for lights in [0, 4, 12]:
		var local_lights: Array[OmniLight3D] = []
		if lights > 0:
			for i in lights:
				var light := OmniLight3D.new()
				view.add_child(light)
				light.position = focus + Vector3((i % 4 - 1.5) * 6, 2.5, (i / 4 - 1) * 6)
				light.omni_range = 14.0
				light.light_color = [Color(1, .25, .1), Color(.1, .4, 1), Color(.1, 1, .3)][i % 3]
				light.light_energy = 3.0
				light.light_specular = Gfx.LOCAL_SPECULAR
				local_lights.append(light)
		var before := await capture(str(lights) + "-before")
		batch()
		var count := batches.size()
		var parts := originals.size()
		var after := await capture(str(lights) + "-after")
		unbatch()
		var restored := await capture(str(lights) + "-restored")
		rows.append({"lights": lights, "batches": count, "parts": parts, "before_draws": before.draws,
				"after_draws": after.draws, "restored_draws": restored.draws,
				"difference": compare(before.image, after.image),
				"restoration": compare(before.image, restored.image)})
		for light in local_lights:
			light.free()
	print("SCENERY_BATCHES ", JSON.stringify({"map": "bz13h", "focus": str(focus), "rows": rows,
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
			"adapter": RenderingServer.get_video_adapter_name()}))
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
