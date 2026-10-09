extends Node
## Actual terrain shader, option lifecycle, cached colour and game-clock checks.
const Caustics = preload("res://src/game/fx/water_caustics.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 12) -> void:
	for i in n:
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame

func difference(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed += int(d>0); over += int(d>2); peak = maxi(peak,d)
	return {"changed_pixels":changed,"pixels_over_2":over,"peak_delta":peak}

func snap(view: SubViewport,label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image()
	image.save_png("user://caustics-"+label+".png")
	return image

func enable(t: EITerrain,value: bool) -> void:
	GameData.options["gfx_water_caustics"] = int(value); t.apply_gfx()
	if is_instance_valid(t.color_cache): t.color_cache.set_process(false)

func matching(a: Image,b: Image,label: String) -> void:
	var delta := difference(a,b); rows.append({"case":label,"difference":delta})
	check(delta.changed_pixels == 0,label)

func cache_bindings(t: EITerrain) -> void:
	if not OS.get_cmdline_user_args().has("--ei-baked-terrain"): return
	check(is_instance_valid(t.color_cache) and not t.color_cache._resident.is_empty(),"baked colour fixture has resident sectors")
	if not is_instance_valid(t.color_cache): return
	for record: Dictionary in t.color_cache._resident.values():
		var m: ShaderMaterial = record.material
		if t._caustics != null and t._caustics.admitted > 0:
			check(m.get_shader_parameter("caustic_bed") == t._caustics.texture and m.shader.code.contains("caustic_pattern"),"resident material uses current caustics")
			check(m.get_shader_parameter("caustic_scroll") == t._land_mat.get_shader_parameter("caustic_scroll"),"resident animation phase matches live terrain")
		else:
			check(m.get_shader_parameter("caustic_bed") == null and not m.shader.code.contains("caustic_pattern"),"resident material releases caustics on disable")

func scheduling(t: EITerrain,world: GameWorld) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t.set_process(true); world.process_mode = Node.PROCESS_MODE_PAUSABLE
	Engine.time_scale = 1.0
	get_tree().paused = true; var before := t._waves.time_ticks(); await frames()
	check(t._waves.time_ticks() == before,"tree pause holds the terrain clock")
	get_tree().paused = false
	world.process_mode = Node.PROCESS_MODE_DISABLED; before = t._waves.time_ticks(); await frames()
	check(t._waves.time_ticks() == before,"disabled travel-map world holds the terrain clock")
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var session := Session.new(); world.session = session
	session.lmp_travel = preload("res://src/game/lmp_travel.gd").new(session)
	before = t._waves.time_ticks(); await frames()
	check(t._waves.time_ticks() == before,"unregistered LMP world holds the terrain clock")
	session.lmp_travel = null
	var elapsed := []
	for scale: float in [1.0,2.0]:
		Engine.time_scale = scale; await frames(4); before = t._waves.time_ticks()
		await frames(30); elapsed.append((t._waves.time_ticks()-before)*EIWaterWaves.TICK)
	check(elapsed[0] > 0.15 and elapsed[1]/elapsed[0] > 1.7 and elapsed[1]/elapsed[0] < 2.3,"2x speed doubles the game clock")
	check(t._land_mat.get_shader_parameter("caustic_scroll").is_equal_approx(Caustics.scroll(t._waves.time_ticks()*EIWaterWaves.TICK)),"render phase follows the terrain clock")
	cache_bindings(t)
	rows.append({"case":"clock","seconds_1x":elapsed[0],"seconds_2x":elapsed[1]})
	world.session = null; session.free(); t.set_process(false); Engine.time_scale = 0
	process_mode = Node.PROCESS_MODE_INHERIT

func fixture() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	var view := SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var map_name := "zone15" if OS.get_cmdline_user_args().has("--caustic-zone15") else "zone1"
	var t := EITerrain.load_map(map_name); world.terrain = t; world.add_child(t); t.set_process(false)
	check(t._caustics == null and t._land_mat.shader == EITerrain._land_shader,"default-off terrain uses the original program")
	var focus := Vector3(151.5,3.591615,-176.5) if map_name == "zone15" else Vector3(132.5,5.758586,-98.5)
	var camera := Camera3D.new(); camera.far = 50.0; view.add_child(camera)
	camera.position = focus+Vector3(4,6,6); camera.look_at(focus-Vector3.UP); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.14,0.24,0.34); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	if OS.get_cmdline_user_args().has("--ei-baked-terrain"):
		t.apply_gfx()
		if is_instance_valid(t.color_cache): t.color_cache.prepare(camera); t.color_cache.set_process(false)
		cache_bindings(t)
	var off: Image
	var draws := 0
	if rendered:
		await frames(48); off = await snap(view,"off")
		matching(off,await snap(view,"off-stable"),"original program is settled")
		draws = view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var started := Time.get_ticks_usec(); enable(t,true); var build_us := Time.get_ticks_usec()-started
	check(t._caustics != null and t._caustics.admitted > 0 and t._land_mat.shader != EITerrain._land_shader,"enabled terrain uses an admitted bed field and a dedicated program")
	var field_ref := weakref(t._caustics); var texture_ref := weakref(t._caustics.texture)
	rows.append({"case":"field","bytes":t._caustics.bytes,"tiles":t._caustics.tiles,"admitted":t._caustics.admitted,"enable_us":build_us})
	enable(t,true); check(field_ref.get_ref() == t._caustics,"option refresh reuses immutable map metadata")
	cache_bindings(t)
	var on: Image
	if rendered:
		for i in 60:
			if Caustics.pattern().get_image() != null: break
			await frames(1)
		check(Caustics.pattern().get_image() != null,"procedural vein texture is ready")
		if Caustics.pattern().get_image() != null: Caustics.pattern().get_image().save_png("user://caustics-pattern.png")
		await frames(36); on = await snap(view,"on")
		var delta := difference(off,on); rows.append({"case":"visible","difference":delta})
		check(delta.pixels_over_2 > 20,"sunlit underwater caustics are visible")
		matching(on,await snap(view,"held"),"zero game time holds caustic animation")
		var on_draws := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		check(draws == on_draws,"caustics add no render draws in the fixture")
		rows.append({"case":"draws","off":draws,"on":on_draws})
	enable(t,false); cache_bindings(t)
	check(t._caustics == null and t._land_mat.shader == EITerrain._land_shader,"disable restores the original shader")
	check(field_ref.get_ref() == null and texture_ref.get_ref() == null,"disable releases per-map caustics metadata and texture")
	if rendered: matching(off,await snap(view,"restored"),"off-on-off restores the image")
	enable(t,true)
	if rendered:
		# Keep water wave geometry frozen while changing just caustic phase.
		t._land_mat.set_shader_parameter("caustic_scroll",Caustics.scroll(6.0))
		if is_instance_valid(t.color_cache): t.color_cache.sync_parameter("caustic_scroll",Caustics.scroll(6.0))
		var moved := await snap(view,"moved")
		var delta := difference(on,moved); rows.append({"case":"animated","difference":delta})
		check(delta.pixels_over_2 > 20,"caustic pattern moves independently of a fixed water mesh")
		t._update_wave_parameters()
		Gfx.set_light(Color(0.5,0.5,0.5),Color.BLACK)
		enable(t,false); var dark := await snap(view,"night-off")
		enable(t,true); matching(dark,await snap(view,"night-on"),"no caustics without sunlight")
		Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
		for m in t.materials.size(): t.set_water_offset(m,-10.0)
		enable(t,false); var dry := await snap(view,"lowered-off")
		enable(t,true); matching(dry,await snap(view,"lowered-on"),"lowering water removes caustics from the exposed bed")
		for m in t.materials.size(): t.set_water_offset(m,0.0)
		for node in t.get_children():
			if node is MeshInstance3D and String(node.name).begins_with("Water_"): node.visible = false
		enable(t,false); var bed := await snap(view,"bed-off")
		enable(t,true); var bed_on := await snap(view,"bed-on")
		check(difference(bed,bed_on).pixels_over_2 > 20,"the opaque terrain receives the effect without a water overlay")
		for node in t.get_children():
			if node is MeshInstance3D and String(node.name).begins_with("Water_"): node.visible = true
	var classification := t.liquid_ground.duplicate()
	for kind: int in [13,14]:
		enable(t,false); t.liquid_ground.fill(kind); enable(t,true)
		check(t._caustics.admitted == 0 and t._land_mat.shader == EITerrain._land_shader,"lava/swamp metadata excludes receivers: "+str(kind))
		if rendered: matching(off,await snap(view,"excluded-"+str(kind)),"excluded liquid keeps original terrain image "+str(kind))
	enable(t,false); t.liquid_ground = classification
	var original_materials := t.materials.duplicate(true)
	for m: Dictionary in t.materials: m.self_illum = 1.0
	enable(t,true); check(t._caustics.admitted == 0,"emissive liquid metadata excludes receivers")
	enable(t,false); t.materials = original_materials; enable(t,true)
	await scheduling(t,world)
	GameData.options["gfx_water"] = 0; t.apply_gfx()
	check(t._caustics == null and t._land_mat.shader == EITerrain._land_shader,"original-water mode disables caustics")
	cache_bindings(t)
	view.free(); await frames()

func _ready() -> void:
	for k: String in ["gfx_hd_textures","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_terrain","confine_mouse","gfx_volumetric","gfx_ssao","gfx_bloom","gfx_water_interaction","gfx_water_caustics","gfx_weather_surfaces","vsync"]: GameData.options[k] = 0
	GameData.options["gfx_water"] = 1
	GameData.options["gfx_terrain"] = int(OS.get_cmdline_user_args().has("--ei-baked-terrain"))
	GameData.options["fps_limit"] = 3; Engine.max_fps = 120; Engine.time_scale = 0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	await fixture()
	TexUpscale.shutdown(); await frames(16)
	FileAccess.open("user://water-caustics.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")+"\n")
	get_tree().quit(1 if failures else 0)
