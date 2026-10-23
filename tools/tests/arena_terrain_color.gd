extends Node
## Real courtyard materials through native track installation, option changes,
## board sharing and destruction. Run on Forward+, then other renderers to
## check their unmodified fallback. Native game data is required.
var checks := 0
var failures := 0
var captures := {}


func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL ", label)


func frames(count := 12) -> void:
	for i in count: await get_tree().process_frame


func capture(view: SubViewport, label: String) -> Image:
	await frames(30)
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.save_png("user://arena-terrain-color-" + label + ".png")
	captures[label] = "arena-terrain-color-" + label + ".png"
	return image


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA), true)
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "net_upnp":0,
		"net_lan":0, "net_directory":0, "vsync":0, "fps_limit":0}, true)
	await frames(24)
	var view := SubViewport.new(); view.size = Vector2i(1280, 720)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view); Gfx.apply_quality(view)
	var camera := Camera3D.new(); view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 9
	camera.position = Vector3(32, 10, -23); camera.look_at(Vector3(32,0,-32))
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); view.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-52,-35,0); view.add_child(sun)
	Gfx.update_original(environment.environment, sun, EILights.load_for("Ingos",false), 14, false)
	var terrain := ArenaTerrain.create() as ArenaWinterTerrain; view.add_child(terrain)
	var other := ArenaTerrain.create() as ArenaWinterTerrain
	var authority := ArenaTerrain.create(false) as ArenaWinterTerrain
	check(authority._color == null, "navigation-only authority does not allocate the colour cache")
	authority.free()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	check((terrain._color != null) == forward, "cache uses only the tested Forward+ renderer")
	var shared: WeakRef = weakref(terrain._color) if terrain._color else null
	if forward:
		check(other._color == terrain._color, "two rendered boards share the same array")
		check(terrain._color.get_layers() == 4, "all four sectors are resident")
		check(int(terrain._color.get_meta("bytes")) <= ArenaTerrainColor.BUDGET_BYTES, "shared texture stays within 128 MiB")
		check(terrain._land_mat.get_shader_parameter("baked_ground") == terrain._color, "base terrain binds the shared array")
		var old_size := terrain._atlas_source_size
		terrain._atlas_source_size = terrain.texture_size * 8
		check(not ArenaTerrainColor.available(terrain), "higher-resolution replacement art retains its original sampler")
		terrain._atlas_source_size = old_size
	other.free()
	var soft := terrain.details.soft_ground
	soft.set_process(false); soft._age = 100
	var before := await capture(view, "before")
	for point: Vector2 in [Vector2(31.5,31.5),Vector2(32.5,31.5),Vector2(31.5,32.5),Vector2(32.5,32.5)]:
		soft.add_step(point, Vector2(0.35,0.55), 0.3)
	for i in 8: soft._process(0); soft._finish_mesh_jobs(true)
	check(soft.sectors.size() == 4, "native tracks installed on both sides of the sector seams")
	for key: Vector2i in soft.sectors:
		var rec: Dictionary = soft.sectors[key]
		var node: MeshInstance3D = rec.node.get_ref()
		check(node.mesh != rec.source and node.get_active_material(0) == rec.material, "deformed mesh uses its live material")
		check(rec.material.get_shader_parameter("soft_tracks") == true, "live footprint sampling remains enabled")
		if forward: check(rec.material.get_shader_parameter("baked_ground") == terrain._color, "tracks retain shared colour")
	var tracked := await capture(view, "tracks")
	check(before.get_data() != tracked.get_data(), "native footprints change the rendered image")
	# Toggle static terrain detail while keeping the installed footprint field.
	var track_texture := soft.field.texture
	for mode in [0,1,2]:
		GameData.options.gfx_terrain = mode; Gfx.apply_surface_options(); terrain.apply_gfx()
		check(soft.field.texture == track_texture and soft.sectors.size() == 4, "detail change preserves installed tracks")
		for rec: Dictionary in soft.sectors.values():
			if forward:
				check((rec.material.get_shader_parameter("baked_ground") != null) == (mode != 0), "detail option selects the correct live material")
		await capture(view, "detail-%d" % mode)
	GameData.options.gfx_terrain = 2
	GameData.options.gfx_soft_ground = 0; Gfx.apply_surface_options(); terrain.apply_gfx()
	check(terrain.details.soft_ground == null, "disabling deformation restores ordinary terrain meshes")
	await frames(4)
	GameData.options.gfx_soft_ground = 1; Gfx.apply_surface_options(); terrain.apply_gfx()
	check(is_instance_valid(terrain.details.soft_ground), "deformation can be enabled again")
	if forward: check(terrain._land_mat.get_shader_parameter("baked_ground") == shared.get_ref(), "option changes reuse the same derived colour")
	await capture(view, "restored")
	# All worlds/materials are gone; the sharing index must not retain pixels.
	track_texture = null; soft = null
	view.free()
	# Coroutine locals can retain the last inspected sector dictionary until
	# this function returns, including its material. Check ownership afterwards.
	finish.call_deferred(shared, forward)


func finish(shared: WeakRef, forward: bool) -> void:
	await frames(4)
	if forward: check(shared.get_ref() == null, "last board destruction releases the shared texture")
	FileAccess.open("user://arena-terrain-color.json", FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"captures":captures},"\t"))
	print("ARENA_TERRAIN_COLOR ", checks, " checks; failures=", failures)
	TexUpscale.shutdown(); get_tree().quit(int(failures > 0))
