extends Node
## Compare the production sector partition against its full Natural shader,
## including mixed-sector views, live settings and real deformation ownership.
const Field = preload("res://src/game/fx/terrain_transition.gd")
const SITES := [
	{"map":"zone15", "tile":Vector2i(40,56)},
	{"map":"zone12", "tile":Vector2i(40,72)},
	{"map":"zone11", "tile":Vector2i(216,168)},
]
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames(count := 8) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func guards() -> void:
	# A junction outside the mesh can still affect its edge relief tap.
	for point in [Vector2i(16,16), Vector2i(31,31), Vector2i(15,15), Vector2i(32,32),
		Vector2i(15,24), Vector2i(32,24), Vector2i(24,15), Vector2i(24,32)]:
		for bit in 4:
			var field := Field.new(); field.tile_size = Vector2i(48,48)
			field.rows.resize(48*48); field.admitted = 1; field.junctions = 1
			field.rows[point.y*48+point.x] = Color(1,2,1 << (20+bit),65)
			check(not field.pair_sector_allowed(Vector2i(16,16)), "junction/relief halo rejects " + str(point))
	var clear := Field.new(); clear.tile_size = Vector2i(48,48)
	clear.rows.resize(48*48); clear.admitted = 1; clear.junctions = 1
	clear.rows[14*48+14] = Color(1,2,15 << 20,65)
	check(clear.pair_sector_allowed(Vector2i(16,16)), "distant junction does not disqualify whole map")
	check(clear.pair_sector_allowed(Vector2i(16,16)), "immutable classification can be reused")
	for origin in [Vector2i(-16,0), Vector2i(48,0), Vector2i(0,48), Vector2i(1,16)]:
		check(not clear.pair_sector_allowed(origin), "unknown/outside sector retains general sampler")
	var empty := Field.new()
	check(not empty.pair_sector_allowed(Vector2i.ZERO), "unbuilt metadata fails closed")
	clear.rows.clear()
	check(not clear.pair_sector_allowed(Vector2i(16,16)), "invalidated field cannot use stale classification")

func uniforms(terrain: EITerrain, label: String) -> void:
	if terrain._pair_land_mat == null: return
	for parameter in terrain._land_mat.shader.get_shader_uniform_list():
		var key: StringName = parameter.name
		check(terrain._land_mat.get_shader_parameter(key) == terrain._pair_land_mat.get_shader_parameter(key),
			"identical shared live parameter " + label + " " + str(key))

func compare(view: SubViewport, terrain: EITerrain, label: String) -> void:
	await frames(20)
	var optimized := view.get_texture().get_image(); optimized.convert(Image.FORMAT_RGBA8)
	var saved := {}
	for sector in terrain.get_children():
		if sector is EITerrainSector:
			saved[sector] = sector._material
			sector.set_base_material(terrain._land_mat)
	await frames(20)
	var full := view.get_texture().get_image(); full.convert(Image.FORMAT_RGBA8)
	check(optimized.get_data() == full.get_data(), "exact full-sampler pixels " + label)
	check(optimized.save_png("user://pair-" + label + "-optimized.png") == OK, "capture optimized " + label)
	check(full.save_png("user://pair-" + label + "-full.png") == OK, "capture control " + label)
	for sector: EITerrainSector in saved: sector.set_base_material(saved[sector])
	await frames()
	var restored := view.get_texture().get_image(); restored.convert(Image.FORMAT_RGBA8)
	check(restored.get_data() == optimized.get_data(), "exact partition restoration " + label)
	records.append({"view":label, "exact":optimized.get_data()==full.get_data(),
		"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"triangles":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})

func apply(terrain: EITerrain) -> void:
	Gfx.apply_surface_options(); terrain.apply_gfx()

func scene(site: Dictionary) -> void:
	for key in ["gfx_water", "gfx_water_caustics", "gfx_terrain_cliffs", "gfx_soft_ground", "gfx_materials", "gfx_weather_surfaces"]: GameData.options[key] = 0
	GameData.options.gfx_terrain = 2; Gfx.apply_surface_options()
	var view := SubViewport.new(); view.size = Vector2i(1280,720); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var terrain := EITerrain.load_map(site.map); view.add_child(terrain); terrain.set_process(false); terrain.apply_gfx()
	var expected := RenderingServer.get_current_rendering_method() == "forward_plus"
	check((terrain._pair_land_mat != null) == expected, "backend admission " + site.map)
	var eligible := 0; var general := 0
	for sector in terrain.get_children():
		if not sector is EITerrainSector: continue
		var first_tile := int(sector._arrays[Mesh.ARRAY_TEX_UV2][0].y + 0.5)
		check(first_tile == sector.tile_origin.y * terrain.sectors_x * 16 + sector.tile_origin.x,
			"sector classification uses actual authored global tile coordinates")
		if sector._material == terrain._pair_land_mat: eligible += 1
		else: general += 1
	check(general > 0 and (eligible > 0 if expected else eligible == 0), "mixed original sector ownership " + site.map)
	uniforms(terrain, site.map)
	var point: Vector2 = Vector2(site.tile * 2) + Vector2.ONE
	var focus := Vector3(point.x, terrain.height_at(point.x,point.y), -point.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 48
	camera.position = focus + Vector3(0,100,0); camera.look_at(focus,Vector3.FORWARD)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-30,0); view.add_child(sun)
	Gfx.set_light(Color(0.65,0.65,0.65),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await compare(view,terrain,site.map+"-boundaries")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE; camera.fov = 65
	camera.position = focus + Vector3(0,35,35); camera.look_at(focus,Vector3.UP)
	await compare(view,terrain,site.map+"-oblique")
	var pixels := terrain._transitions.tiles.get_image().get_data()
	for mode in [1,0,2]:
		var old := weakref(terrain._pair_land_mat) if terrain._pair_land_mat else null
		GameData.options.gfx_terrain = mode; apply(terrain)
		await frames()
		if mode != 2:
			check(terrain._pair_land_mat == null and (old == null or old.get_ref() == null), "disable releases specialization")
			for sector in terrain.get_children():
				if sector is EITerrainSector: check(sector._material == terrain._land_mat, "Original/Detailed use shared original material")
	check(terrain._transitions.tiles.get_image().get_data() == pixels, "re-enable retains exact authored metadata")
	await compare(view,terrain,site.map+"-reenabled")
	for key in ["gfx_water", "gfx_water_caustics", "gfx_terrain_cliffs", "gfx_soft_ground", "gfx_materials", "gfx_weather_surfaces"]: GameData.options[key] = 1
	apply(terrain); Gfx.set_surface_weather(0.8,0.5); uniforms(terrain,site.map+"-composed")
	var cover := Image.create(2,2,false,Image.FORMAT_RF); cover.fill(Color(-10000,0,0))
	terrain.set_rain_cover(cover); terrain.set_water_offset(0,0.12)
	terrain._waves.advance(1.25); terrain._update_wave_parameters()
	uniforms(terrain,site.map+"-live-water-weather")
	await compare(view,terrain,site.map+"-composed")
	if site.map == "zone11":
		var soft := terrain.details.soft_ground
		check(soft != null and soft.step_allowed(point), "original snow witness permits real footprints")
		soft.add_step(point,Vector2(0.18,0.3),0.3)
		for i in 5: soft._process(0); soft._finish_mesh_jobs(true)
		check(not soft.sectors.is_empty(), "real dense sector installed")
		apply(terrain)
		await compare(view,terrain,site.map+"-deformed")
		GameData.options.gfx_soft_ground = 0; apply(terrain)
		check(terrain.details.soft_ground == null, "live disable releases deformation")
		await compare(view,terrain,site.map+"-tracks-disabled")
	var retained := weakref(terrain._pair_land_mat) if terrain._pair_land_mat else null
	view.free(); await frames()
	check(retained == null or retained.get_ref() == null, "map unload releases shared specialized material")

func _ready() -> void:
	guards()
	if DisplayServer.get_name() != "headless":
		for option: Array in GameData.OPTIONS:
			if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
		GameData.options.merge({"q_aa":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
		Gfx.ensure_globals(); Gfx.apply_surface_options(); Engine.time_scale = 0; process_mode = Node.PROCESS_MODE_ALWAYS
		RenderingServer.set_render_loop_enabled(true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		await frames(); Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for site: Dictionary in SITES: await scene(site)
		TexUpscale.shutdown(); await frames()
	FileAccess.open("user://terrain-pair-sectors.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,
		"renderer":RenderingServer.get_current_rendering_method()},"\t")+"\n")
	print("TERRAIN_PAIR_SECTORS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
