extends Node
## P4 diagnostic: native terrain occluders in a frozen real map. No production
## hooks or visibility changes. CPU gameplay nodes remain present throughout.
## Run with --tool=.../terrain_occlusion.gd --occlusion-map=bz13h.
var view: SubViewport
var map: EIMapScene
var camera: Camera3D
var map_name := "bz13h"
var selected_views := PackedStringArray()
var timing := false
var shadows := false
var grass := false
var scenery_only := false
var opaque_objects := false
var rays := 512
var rows := []
var timing_rows := []
var source_stats := {"sectors":0, "vertices":0, "triangles":0, "object_meshes":0, "object_triangles":0, "textures_checked":0, "build_usec":0}
var occluders: Array[OccluderInstance3D] = []
var frozen_shaders := {}
var original_shaders := {}
var draw_start_usec := 0
var last_draw_usec := 0

func begin_draw() -> void:
	draw_start_usec = Time.get_ticks_usec()

func end_draw() -> void:
	last_draw_usec = Time.get_ticks_usec() - draw_start_usec

func tick() -> void:
	# Occlusion hysteresis uses Engine.get_frames_drawn(), which only the
	# normal render loop advances. force_draw-only loops never expire it.
	await RenderingServer.frame_post_draw
	# Mutate scene/material state on the next process step, outside the
	# rendering callback. Timestamp only pre/post draw, not this yield.
	await get_tree().process_frame

func settle(frames := 24) -> void:
	for i in frames: await tick()

func freeze_shaders() -> void:
	for node: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
		var materials: Array = [node.material_override]
		if node is MeshInstance3D and node.mesh:
			for surface in node.mesh.get_surface_count(): materials.append(node.get_active_material(surface))
		for material: Material in materials:
			if material is ShaderMaterial and material.shader and not original_shaders.has(material):
				var source: Shader = material.shader
				if not frozen_shaders.has(source):
					var frozen := Shader.new()
					frozen.code = source.code.replace("TIME", "1.25")
					frozen_shaders[source] = frozen
				original_shaders[material] = source
				material.shader = frozen_shaders[source]

func warm_scene() -> bool:
	map.process_mode = Node.PROCESS_MODE_INHERIT
	var details := map.terrain.details
	for frame in 180:
		await tick()
		if frame >= 3 and (details == null or (details._queue.is_empty() and details._grass_jobs.is_empty())):
			map.process_mode = Node.PROCESS_MODE_DISABLED
			freeze_shaders()
			apply_targets()
			return true
	return false

func density_focus() -> Vector3:
	var counts := {}
	for object: Node3D in map.object_nodes:
		var record: Dictionary = object.get_meta("ei", {})
		if record.get("kind") != "OBJECT" or String(record.get("template", "")).begins_with("ef"): continue
		var cell := Vector2i(floori(object.position.x / 16.0), floori(object.position.z / 16.0))
		counts[cell] = int(counts.get(cell, 0)) + object.find_children("*", "MeshInstance3D", true, false).size()
	var best := Vector2i.ZERO
	for cell: Vector2i in counts:
		if int(counts.get(best, 0)) < counts[cell]: best = cell
	var x := best.x * 16.0 + 8.0; var z := best.y * 16.0 + 8.0
	return Vector3(x, map.terrain.height_at(x, -z), z)

func build_occluders() -> void:
	var start := Time.get_ticks_usec()
	# Use actual authored tile triangles, including x/y offsets and holes.
	# The height grid is insufficient. No simplification/fitted solid boxes.
	for sector: Node in map.terrain.get_children():
		if not sector is EITerrainSector: continue
		var shape := ArrayOccluder3D.new()
		var vertices: PackedVector3Array = sector._arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = sector._arrays[Mesh.ARRAY_INDEX]
		shape.set_arrays(vertices, indices)
		var node := OccluderInstance3D.new()
		node.occluder = shape
		view.add_child(node)
		node.global_transform = sector.global_transform
		occluders.append(node)
		source_stats.sectors += 1; source_stats.vertices += vertices.size(); source_stats.triangles += indices.size() / 3
	if opaque_objects: build_opaque_objects()
	source_stats.build_usec = Time.get_ticks_usec() - start

func build_opaque_objects() -> void:
	# Frozen-scene experiment, NOT a runtime eligibility policy. Live fades,
	# movement and alpha/material changes would invalidate these occluders.
	# Keep actual triangles/holes; an object's AABB is not a solid occluder.
	var textures := {}; var shapes := {}
	for root: Node3D in map.object_nodes:
		var record: Dictionary = root.get_meta("ei", {})
		if record.get("kind") != "OBJECT" or String(record.get("template", "")).begins_with("ef"): continue
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null or mesh.skin != null or mesh.mesh.get_blend_shape_count() > 0 \
					or mesh.transparency != 0.0 or mesh.material_overlay != null or mesh.mesh.get_surface_count() != 1: continue
			var material := mesh.get_active_material(0) as ShaderMaterial
			if material == null or material.next_pass != null or material.get_meta("ground_contact_source", "") != EIFigure.OBJECT_SHADER: continue
			var diffuse: Variant = material.get_shader_parameter("ei_material_diffuse")
			if diffuse != null:
				if diffuse is Vector4 and diffuse.w != 1.0: continue
				if diffuse is Color and diffuse.a != 1.0: continue
				if not diffuse is Vector4 and not diffuse is Color: continue
			var texture := material.get_shader_parameter("albedo_tex") as Texture2D
			if texture == null: continue
			if not textures.has(texture):
				var pixels := texture.get_image()
				var opaque := pixels != null
				if opaque and pixels.is_compressed(): opaque = pixels.decompress() == OK
				if opaque:
					pixels.convert(Image.FORMAT_RGBA8)
					var data := pixels.get_data() # Include authored mip levels too.
					for i in range(3, data.size(), 4):
						if data[i] != 255: opaque = false; break
				textures[texture] = opaque
			if not textures[texture]: continue
			if not shapes.has(mesh.mesh):
				var arrays := mesh.mesh.surface_get_arrays(0)
				var shape := ArrayOccluder3D.new()
				shape.set_arrays(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX])
				shapes[mesh.mesh] = shape
			var node := OccluderInstance3D.new(); node.occluder = shapes[mesh.mesh]
			view.add_child(node); node.global_transform = mesh.global_transform
			occluders.append(node)
			source_stats.object_meshes += 1
			source_stats.object_triangles += node.occluder.indices.size() / 3
	source_stats.textures_checked = textures.size()

func apply_targets() -> void:
	if scenery_only:
		for node: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
			node.ignore_occlusion_culling = true
		for root: Node3D in map.object_nodes:
			var record: Dictionary = root.get_meta("ei", {})
			if record.get("kind") != "OBJECT" or String(record.get("template", "")).begins_with("ef"): continue
			for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				mesh.ignore_occlusion_culling = false

func capture(label: String) -> Dictionary:
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := "user://terrain-occlusion-%s-%s.png" % [RenderingServer.get_current_rendering_method(), label]
	image.save_png(path)
	return {"image":image, "path":ProjectSettings.globalize_path(path),
		"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}

func difference(first: Image, second: Image) -> Dictionary:
	var a := first.get_data(); var b := second.get_data()
	var peak := 0; var count := 0; var total := 0
	for pixel in range(0, a.size(), 4):
		var error := 0
		for channel in 3:
			var delta := absi(a[pixel + channel] - b[pixel + channel])
			error = maxi(error, delta); total += delta
		peak = maxi(peak, error); count += int(error > 2)
	return {"pixels_over_2":count, "max_byte_difference":peak, "mean_channel_difference":float(total) / (first.get_width() * first.get_height() * 3)}

func distribution(samples: Array) -> Dictionary:
	samples.sort()
	return {"median":samples[samples.size() / 2], "p95":samples[int(samples.size() * 0.95)],
		"min":samples.front(), "max":samples.back(), "samples":samples.size()}

func measure(label: String) -> void:
	for enabled: bool in [false, true, true, false, false, true]:
		view.use_occlusion_culling = enabled
		var wall := []; var cpu := []; var gpu := []; var draws := []
		var frame_counter_start := Engine.get_frames_drawn()
		for frame in 96:
			await tick()
			var elapsed := last_draw_usec
			if frame < 32: continue
			wall.append(elapsed)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		var row := {"view":label, "occlusion_enabled":enabled, "render_usec":distribution(wall),
			"normal_frames_advanced":Engine.get_frames_drawn() - frame_counter_start,
			"viewport_cpu_ms":distribution(cpu), "viewport_gpu_ms":distribution(gpu), "draws":distribution(draws)}
		timing_rows.append(row)
		print("OCCLUSION_TIMING ", JSON.stringify(row))

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TERRAIN_OCCLUSION requires a real renderer"); get_tree().quit(2); return
	if OS.get_cmdline_user_args().has("--scenery-batches"):
		printerr("TERRAIN_OCCLUSION requires original scenery instances"); get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--occlusion-map="): map_name = arg.trim_prefix("--occlusion-map=")
		if arg.begins_with("--occlusion-views="): selected_views = arg.trim_prefix("--occlusion-views=").split(",")
		if arg.begins_with("--occlusion-rays="): rays = int(arg.trim_prefix("--occlusion-rays="))
		if arg == "--occlusion-timing": timing = true
		if arg == "--occlusion-shadows": shadows = true
		if arg == "--occlusion-grass": grass = true
		if arg == "--occlusion-scenery-only": scenery_only = true
		if arg == "--occlusion-opaque-objects": opaque_objects = true
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["gfx_volumetric"] = 0
	GameData.options["gfx_ground_contact"] = 0
	GameData.options["gfx_soft_ground"] = 0
	GameData.options["gfx_grass"] = int(grass)
	# GameData reapplies window options after three startup frames. Set its
	# options too, otherwise that delayed update restores VSync during a run.
	GameData.options["vsync"] = 0
	GameData.options["fps_limit"] = 0
	var old_fps := Engine.max_fps; Engine.max_fps = 0
	var old_vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var old_loop := RenderingServer.is_render_loop_enabled()
	RenderingServer.set_render_loop_enabled(true)
	RenderingServer.frame_pre_draw.connect(begin_draw)
	RenderingServer.frame_post_draw.connect(end_draw)
	var old_rays: int = ProjectSettings.get_setting_with_override("rendering/occlusion_culling/occlusion_rays_per_thread")
	RenderingServer.viewport_set_occlusion_rays_per_thread(rays)
	view = SubViewport.new(); view.size = Vector2i(800, 600); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	map = EIMapScene.load_map(map_name, map_name, false)
	if map == null:
		printerr("TERRAIN_OCCLUSION map not found"); get_tree().quit(2); return
	view.add_child(map)
	camera = Camera3D.new(); camera.fov = CameraRig.MODERN_FOV; camera.far = Gfx.far_clip()
	view.add_child(camera); camera.current = true
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -35, 0)
	view.add_child(sun)
	if shadows:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.light_specular = Gfx.SUN_MARK
		Gfx.set_light(Color(0.3, 0.3, 0.3), Color(0.7, 0.7, 0.7))
		Gfx.setup_sun_casters(sun); Gfx.sync_sun_pass(sun)
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized())
	build_occluders()
	var focus := density_focus()
	var size := map.terrain.size_ei()
	var center := Vector3(size.x * 0.5, map.terrain.height_at(size.x * 0.5, size.y * 0.5), -size.y * 0.5)
	var poses := [
		["dense_overview", focus, Vector3(24, 22, 28)],
		["dense_low", focus, Vector3(12, 8, 14)],
		["dense_opposite", focus, Vector3(-24, 22, -28)],
		["center_overview", center, Vector3(24, 22, 28)],
		["center_high", center, Vector3(0, 60, 10)],
		["center_low", center, Vector3(12, 8, 14)]]
	for pose: Array in poses:
		var label: String = pose[0]
		if not selected_views.is_empty() and not selected_views.has(label): continue
		view.use_occlusion_culling = false
		camera.position = pose[1] + pose[2]
		camera.position.y = maxf(camera.position.y, map.terrain.height_at(camera.position.x, -camera.position.z) + 1.8)
		camera.look_at(pose[1] + Vector3.UP * 2.0)
		camera.reset_physics_interpolation()
		if not await warm_scene():
			printerr("TERRAIN_OCCLUSION scene streaming did not settle"); get_tree().quit(2); return
		await settle()
		var before := capture(label + "-off")
		view.use_occlusion_culling = true
		await tick()
		var first := capture(label + "-first")
		await settle()
		var after := capture(label + "-on")
		view.use_occlusion_culling = false
		await settle()
		var restored := capture(label + "-restored")
		var row := {"view":label, "camera":str(camera.global_transform), "focus":str(pose[1]),
			"off":before.duplicate(), "on":after.duplicate(), "restored":restored.duplicate(),
			"first_difference":difference(before.image, first.image),
			"difference":difference(before.image, after.image), "restoration":difference(before.image, restored.image)}
		for key in ["off", "on", "restored"]: row[key].erase("image")
		rows.append(row)
		print("OCCLUSION_VIEW ", JSON.stringify(row))
		if timing: await measure(label)
	if rows.is_empty():
		printerr("TERRAIN_OCCLUSION no requested view exists"); get_tree().quit(2); return
	var report := {"map":map_name, "renderer":RenderingServer.get_current_rendering_method(),
		"engine":Engine.get_version_info(), "adapter":RenderingServer.get_video_adapter_name(),
		"sources":source_stats, "rows":rows, "timing_rows":timing_rows, "grass":grass, "shadows":shadows,
		"scenery_only":scenery_only, "opaque_object_occluders":opaque_objects,
		"rays_per_thread":rays, "worker_pool_max_threads":ProjectSettings.get_setting_with_override("threading/worker_pool/max_threads"),
		"camera_near":camera.near, "camera_far":camera.far, "camera_fov":camera.fov,
		"vsync_mode":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps,
		"automatic_render_loop":RenderingServer.is_render_loop_enabled(),
		"soft_ground":false, "ground_contact":false, "frozen_scene":true, "authored_occluder_geometry":true}
	FileAccess.open("user://terrain-occlusion-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("TERRAIN_OCCLUSION ", JSON.stringify({"map":map_name, "views":rows.size(), "sources":source_stats}))
	view.use_occlusion_culling = false
	view.free()
	for material: ShaderMaterial in original_shaders: material.shader = original_shaders[material]
	original_shaders.clear(); frozen_shaders.clear()
	RenderingServer.viewport_set_occlusion_rays_per_thread(old_rays)
	Engine.max_fps = old_fps
	DisplayServer.window_set_vsync_mode(old_vsync)
	RenderingServer.set_render_loop_enabled(old_loop)
	RenderingServer.frame_pre_draw.disconnect(begin_draw)
	RenderingServer.frame_post_draw.disconnect(end_draw)
	await get_tree().process_frame
	get_tree().quit()
