extends Node
## Frozen-map comparison: default uses the diagnostic prototype; pass
## --scenery-batches to exercise the real map hook and production manager.
## Gameplay lifetime is covered separately by tests/scenery_batches.gd.
var view: SubViewport
var map: EIMapScene
var groups := {}
var originals: Array[MeshInstance3D] = []
var batches: Array[MultiMeshInstance3D] = []
var light_plan: Script
var preserve_lights := false
var rank_overflow := false
var map_name := "bz13h"
var no_wind := false
var shadows := false
var build_usec := 0
var scene_warmup_frames := 0
var runtime := false
var contact := false
var churn := false
var idle_usec: Array[int] = []
var movement_usec: Array[int] = []
var movement_rebuilds: Array[int] = []
var near_clip := 0.05
var game_camera := false
var timing := false
var timing_rows: Array = []
var light_counts := [0, 4, 12]
var reinsert_control := false
var reinserted_meshes := 0
var trace_pixels := false
var traced_pixels: Array = []
var _face_cache := {}

func settle() -> void:
	for i in 8:
		RenderingServer.force_draw()
		if runtime and is_instance_valid(map.scenery_batches) and map.scenery_batches._enabled:
			idle_usec.append(map.scenery_batches.last_update_usec)
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

func distribution(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size() / 2], "p95":values[int(values.size() * 0.95)],
		"min":values.front(), "max":values.back(), "samples":values.size()}

func trace_difference(first: Image, second: Image) -> void:
	# Inspect at most 16 changed pixel centres against the original CPU faces.
	# This is an attribution aid for rigid geometry, not an oracle for GPU wind.
	var camera := view.get_camera_3d()
	var transform := camera.global_transform
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y); var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= 2.0 / 255.0: continue
			var origin := transform.origin
			var direction := (transform.basis * camera.project_local_ray_normal(Vector2(x + 0.5, y + 0.5))).normalized()
			var end := origin + direction * camera.far
			var hits := []
			for root: Node3D in map.object_nodes:
				var record: Dictionary = root.get_meta("ei", {})
				for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
					if not node.is_visible_in_tree() or (node.global_transform * node.get_aabb()).intersects_segment(origin, end) == null: continue
					if not _face_cache.has(node.mesh): _face_cache[node.mesh] = node.mesh.get_faces()
					var faces: PackedVector3Array = _face_cache[node.mesh]
					var inverse := node.global_transform.affine_inverse()
					var local_start := inverse * origin; var local_end := inverse * end
					for i in range(0, faces.size(), 3):
						var local: Variant = Geometry3D.segment_intersects_triangle(local_start, local_end, faces[i], faces[i + 1], faces[i + 2])
						if local == null: continue
						var point: Vector3 = node.global_transform * local
						hits.append({"nid":record.get("nid"), "template":record.get("template"), "texture":record.get("texture"),
							"part":str(root.get_path_to(node)), "triangle":i / 3, "distance":origin.distance_to(point), "world":str(point)})
			hits.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
			traced_pixels.append({"pixel":[x, y], "hits":hits.slice(0, 4)})
			if traced_pixels.size() >= 16: return

func measure_runtime(label: String, local_lights: Array) -> void:
	if not runtime or not is_instance_valid(map.scenery_batches): return
	var owner := map.scenery_batches
	var old_fps := Engine.max_fps; Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	var origin := Vector3.ZERO if local_lights.is_empty() else (local_lights[0] as Node3D).position
	for moving in [false, true] if local_lights.size() == 4 else [false]:
		for enabled: bool in [false, true, true, false, false, true]:
			owner.set_enabled(enabled)
			# Default-off maps have no manager. Disconnect its draw callback for
			# the timing control so baseline does not pay even the light poll.
			if enabled and not RenderingServer.frame_pre_draw.is_connected(owner.flush):
				RenderingServer.frame_pre_draw.connect(owner.flush)
			elif not enabled and RenderingServer.frame_pre_draw.is_connected(owner.flush):
				RenderingServer.frame_pre_draw.disconnect(owner.flush)
			var wall: Array = []; var cpu: Array = []; var gpu: Array = []; var updates: Array = []
			for step in 120:
				if moving: local_lights[0].position = origin + Vector3(sin(step * 0.2) * 3.0, 0, 0)
				await get_tree().process_frame
				var start := Time.get_ticks_usec()
				RenderingServer.force_draw(false)
				var elapsed := Time.get_ticks_usec() - start
				if step < 24: continue
				wall.append(elapsed)
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
				updates.append(owner.last_update_usec if enabled else 0)
			timing_rows.append({"case":label, "enabled":enabled, "moving_light":moving,
				"force_draw_usec":distribution(wall), "viewport_cpu_ms":distribution(cpu),
				"viewport_gpu_ms":distribution(gpu), "manager_usec":distribution(updates)})
			print("SCENERY_TIMING ", JSON.stringify(timing_rows.back()))
	if not local_lights.is_empty(): local_lights[0].position = origin
	owner.set_enabled(false)
	if not RenderingServer.frame_pre_draw.is_connected(owner.flush): RenderingServer.frame_pre_draw.connect(owner.flush)
	Engine.max_fps = old_fps

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

func light_snapshot() -> Array:
	var snapshot := []
	for node: Node in view.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light is DirectionalLight3D or not light.is_visible_in_tree(): continue
		var kind := 0 if light is OmniLight3D else 1
		snapshot.append({"id":light.get_instance_id(), "kind":kind, "mask":light.light_cull_mask,
			"bounds":light.global_transform * light.get_aabb(), "energy":light.light_energy,
			"range":light.omni_range if light is OmniLight3D else light.spot_range})
	return snapshot

func batch() -> void:
	var start := Time.get_ticks_usec()
	if reinsert_control:
		reinserted_meshes = 0
		# Change only renderer-tree insertion/order: no MultiMesh is created.
		for root: Node3D in map.object_nodes:
			var record: Dictionary = root.get_meta("ei", {})
			if record.get("kind", "") != "OBJECT" or String(record.get("template", "")).begins_with("ef"): continue
			for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				if not node.is_visible_in_tree(): continue
				RenderingServer.instance_set_visible(node.get_instance(), false)
				RenderingServer.instance_set_visible(node.get_instance(), true)
				reinserted_meshes += 1
		build_usec = Time.get_ticks_usec() - start
		return
	if runtime:
		if is_instance_valid(map.scenery_batches):
			map.scenery_batches.set_enabled(true)
			map.scenery_batches.flush()
		build_usec = Time.get_ticks_usec() - start
		return
	var snapshot := light_snapshot()
	var limit := int(ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_lights_per_object"))
	var total_limit := int(ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_renderable_lights"))
	for key: Array in groups:
		var partitions: Array = [groups[key]]
		if preserve_lights:
			var records := []
			for mesh: MeshInstance3D in groups[key]:
				records.append({"item":mesh, "bounds":mesh.global_transform * mesh.get_aabb().grow(mesh.extra_cull_margin), "layers":mesh.layers})
			partitions = light_plan.partition(records, snapshot, limit, total_limit, rank_overflow)
		for members: Array in partitions:
			if members.size() < 2: continue
			make_batch(members, key)
	build_usec = Time.get_ticks_usec() - start

func make_batch(members: Array, key: Array) -> void:
	var first := members[0] as MeshInstance3D
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = first.mesh
	multi.instance_count = members.size()
	var box := AABB()
	for i in members.size():
		var mesh := members[i] as MeshInstance3D
		multi.set_instance_transform(i, mesh.global_transform)
		var bounds := mesh.global_transform * mesh.get_aabb().grow(mesh.extra_cull_margin)
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
	if runtime:
		if is_instance_valid(map.scenery_batches): map.scenery_batches.set_enabled(false)
		return
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
	GameData.options["gfx_ground_contact"] = 0
	for arg in OS.get_cmdline_user_args():
		if arg == "--scenery-batches": runtime = true
		if arg == "--scenery-contact": contact = true; GameData.options["gfx_ground_contact"] = 1
		if arg == "--scenery-churn": churn = true
		if arg == "--scenery-light-partition": preserve_lights = true
		if arg == "--scenery-ranked-lights": preserve_lights = true; rank_overflow = true
		if arg == "--scenery-no-wind": no_wind = true
		if arg == "--scenery-shadows": shadows = true
		if arg.begins_with("--scenery-map="): map_name = arg.trim_prefix("--scenery-map=")
		if arg.begins_with("--scenery-near="): near_clip = float(arg.trim_prefix("--scenery-near="))
		if arg == "--scenery-game-camera": game_camera = true
		if arg == "--scenery-timing": timing = true
		if arg == "--scenery-reinsert-control": reinsert_control = true
		if arg == "--scenery-trace-pixels": trace_pixels = true
		if arg.begins_with("--scenery-lights="):
			light_counts = Array(arg.trim_prefix("--scenery-lights=").split(",")).map(func(value: String): return int(value))
	if timing and reinsert_control:
		printerr("SCENERY_BATCHES choose runtime timing or reinsertion control"); get_tree().quit(2); return
	light_plan = SceneryLightGroups
	if no_wind: EIFigure.set_wind(false)
	view = SubViewport.new()
	view.size = Vector2i(800, 600)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	map = EIMapScene.load_map(map_name, map_name, false)
	if map == null:
		get_tree().quit(2)
		return
	view.add_child(map)
	if runtime: unbatch()
	var focus := collect()
	var camera := Camera3D.new()
	camera.near = near_clip
	if game_camera:
		camera.fov = CameraRig.MODERN_FOV
		camera.far = Gfx.far_clip()
	view.add_child(camera)
	camera.position = focus + Vector3(24, 22, 28)
	camera.look_at(focus + Vector3.UP * 2.0)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	view.add_child(sun)
	if shadows:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.light_specular = Gfx.SUN_MARK
		Gfx.set_light(Color(0.3, 0.3, 0.3), Color(0.7, 0.7, 0.7))
		Gfx.setup_sun_casters(sun); Gfx.sync_sun_pass(sun)
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	# Grass chunks are created after the camera arrives, including worker
	# results. Comparing before that completes measures streaming, not batches.
	var details := map.terrain.details
	for frame in 180:
		RenderingServer.force_draw()
		await get_tree().process_frame
		scene_warmup_frames = frame + 1
		if frame >= 3 and (details == null or (details._queue.is_empty() and details._grass_jobs.is_empty())):
			break
	if details and (not details._queue.is_empty() or not details._grass_jobs.is_empty()):
		printerr("SCENERY_BATCHES grass streaming did not settle")
		get_tree().quit(2); return
	# Freeze CPU-driven water/terrain changes as well as shader time. All
	# intended live-light mutations below happen explicitly in this fixture.
	map.process_mode = Node.PROCESS_MODE_DISABLED
	var shaders := {}
	for mesh: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material and material.shader and not shaders.has(material.shader):
			shaders[material.shader] = true
			material.shader.code = material.shader.code.replace("TIME", "1.25")
	var rows := []
	for lights in light_counts:
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
				light.shadow_enabled = shadows and i < 4
				local_lights.append(light)
		for phase: String in ["initial", "energy_change"] if lights == 12 else ["initial"]:
			if phase == "energy_change": local_lights[11].light_energy *= 8.0
			var label := str(lights) + "-" + phase
			var before := await capture(label + "-before")
			batch()
			var count := batches.size()
			var parts := originals.size()
			if runtime and is_instance_valid(map.scenery_batches):
				count = map.scenery_batches._batches.size()
				for group: Dictionary in map.scenery_batches._batches.values(): parts += group.members.size()
			var after := await capture(label + "-after")
			unbatch()
			var restored := await capture(label + "-restored")
			rows.append({"lights": lights, "phase":phase, "build_usec":build_usec, "batches": count, "parts": parts, "before_draws": before.draws,
					"after_draws": after.draws, "restored_draws": restored.draws,
					"difference": compare(before.image, after.image),
					"restoration": compare(before.image, restored.image)})
			if trace_pixels and rows.size() == 1: trace_difference(before.image, after.image)
		if timing: await measure_runtime(str(lights), local_lights)
		if runtime and churn and lights == 4 and is_instance_valid(map.scenery_batches):
			batch()
			var origin := local_lights[0].position
			for step in 32:
				local_lights[0].position = origin + Vector3(sin(step * 0.2) * 3.0, 0, 0)
				await get_tree().process_frame
				RenderingServer.force_draw()
				movement_usec.append(map.scenery_batches.last_update_usec)
				movement_rebuilds.append(map.scenery_batches.last_rebuilt_groups)
			unbatch()
		for light in local_lights:
			light.free()
	idle_usec.sort()
	var report := {"map": map_name, "focus": str(focus), "rows": rows, "runtime":runtime, "contact":contact,
			"camera_near":near_clip, "camera_far":camera.far, "camera_fov":camera.fov, "game_camera":game_camera,
			"timing_rows":timing_rows,
			"reinsert_control":reinsert_control, "reinserted_meshes":reinserted_meshes, "traced_pixels":traced_pixels,
			"idle_update_usec":idle_usec,
			"moving_light_update_usec":movement_usec, "moving_light_rebuilt_groups":movement_rebuilds,
			"light_partition":preserve_lights, "rank_overflow":rank_overflow, "no_wind":no_wind, "shadows":shadows,
			"scene_warmup_frames":scene_warmup_frames,
			"light_limit":ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_lights_per_object"),
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
			"adapter": RenderingServer.get_video_adapter_name()}
	FileAccess.open("user://scenery-batches-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SCENERY_BATCHES ", JSON.stringify(report))
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
