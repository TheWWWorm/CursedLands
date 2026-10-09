extends Node
## Deterministic pressure history plus real authored grass and human poses.
const Pressure = preload("res://src/game/fx/vegetation_interaction.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 10) -> void:
	for i in count:
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
	var image := view.get_texture().get_image(); image.save_png("user://vegetation-"+label+".png"); return image

func field_rules() -> void:
	var field := Pressure.new()
	check(field._pixels.size() == 65536,"field payload is bounded to 64 KiB")
	var inputs: Array[Dictionary] = [{"id":1,"p":Vector2(-0.1,0.1),"extent":Vector2(0.3,0.3),"angle":0.0}]
	for i in 4: field.advance(inputs,Vector2.ZERO,0.05)
	check(not field._cells.is_empty(),"standing contact presses the field")
	check(field._cells.has(Vector2i(-1,0)) and field._cells.has(Vector2i(0,0)),"contact crosses the texture wrap seam")
	var data := field.texture.get_image().get_data(); var count := field.updates
	field.advance(inputs,Vector2.ZERO,0.0)
	check(field.updates == count and field.texture.get_image().get_data() == data,"zero game time holds field and upload")
	field.advance([],Vector2(8,0),0.05)
	check(not field._cells.is_empty(),"chunk-sized camera shift retains local history")
	field.advance([],Vector2(128,0),0.05)
	check(field._cells.is_empty(),"distant camera shift retires old toroidal cells")
	field.advance([],Vector2.ZERO,0.05)
	check(field._cells.is_empty(),"returning camera cannot resurrect wrapped pressure")
	field.clear()
	inputs[0].p = Vector2.ZERO
	for i in 4: field.advance(inputs,Vector2.ZERO,0.05)
	inputs[0].p = Vector2(10,0)
	field.advance(inputs,Vector2.ZERO,0.05)
	check(not field._cells.has(Vector2i(10,0)),"teleport never draws a connecting trail")
	for i in 100: field.advance([],Vector2.ZERO,0.05)
	check(field._cells.is_empty(),"departed contact recovers completely")
	count = field.updates; field.advance([],Vector2.ZERO,0.1)
	check(field.updates == count,"empty settled field does not upload")
	rows.append({"case":"pressure-history","payload_bytes":field._pixels.size(),"updates":field.updates})
	var details := TerrainDetails.new()
	var wall := AABB(Vector3(8,0,-10),Vector3(1,1,2))
	details._index_scenery_box(wall,Transform3D.IDENTITY)
	check(details.scenery_clear(Vector2(7.2,9),0.0),"baseline leaf envelope clears a nearby wall")
	details._scenery.clear(); details.interaction = Pressure.new(); details._index_scenery_box(wall,Transform3D.IDENTITY)
	check(not details.scenery_clear(Vector2(7.2,9),0.0),"bent envelope excludes a wall across the chunk boundary")
	details.free()

func location(details: TerrainDetails) -> Vector2:
	var size := details.terrain.size_ei(); var best := Vector2.INF; var score := INF
	for y in range(16,int(size.y)-16,4):
		for x in range(16,int(size.x)-16,4):
			var p := Vector2(x+0.5,y+0.5)
			if not details.grass_allowed(p): continue
			var valid := true
			for offset: Vector2 in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2)]:
				if not details.grass_allowed(p+offset): valid = false; break
			if not valid: continue
			var distance := p.distance_squared_to(size*0.5)
			if distance < score: score = distance; best = p
	return best

func build(details: TerrainDetails,centre: Vector2) -> void:
	details._ensure_grass_resources(); details.set_process(false)
	var key := Vector2i((centre/TerrainDetails.CHUNK).floor()); details._focus = key
	for y in range(key.y-1,key.y+2):
		for x in range(key.x-1,key.x+2):
			var chunk := Vector2i(x,y)
			if not details._chunks.has(chunk): details._install_chunk(chunk,details.instances(chunk))
	details._material.set_shader_parameter("view_position",Vector3(centre.x,details.terrain.height_at(centre.x,centre.y),-centre.y))

func actor(world: GameWorld,point: Vector3,id := 1) -> GameUnit:
	var u := GameUnit.new()
	check(u.setup(world,{"prototype":"Human Hero","nid":id}),"authored human figure loads")
	world.add_child(u); world.set_unit(id,u)
	u.set_process(false); u.set_physics_process(false); u.model.set_process(false)
	u.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	u.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	u.model.player.play("ei/cidle01",0.0); u.model.player.seek(0.3,true)
	u.position = point
	return u

func distribution(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)],"samples":values.size()} if not values.is_empty() else {}

func timing(view: SubViewport,details: TerrainDetails,world: GameWorld,camera: Camera3D,p: Vector2,hero: GameUnit) -> void:
	var actors: Array[GameUnit] = [hero]
	for i in 31:
		var point := p+Vector2((i%6-2.5)*0.9,(i/6-2.0)*0.9)
		actors.append(actor(world,Vector3(point.x,world.terrain.height_at(point.x,point.y),-point.y),100+i))
	var poses := actors.map(func(u: GameUnit): return u.position)
	var focus := Vector3(p.x,world.terrain.height_at(p.x,p.y),-p.y)
	camera.position = focus+Vector3(5,6,7); camera.look_at(focus)
	var old_size := view.size; view.size = Vector2i(1280,720)
	Engine.max_fps = 0; GameData.options["fps_limit"] = 0; GameData.options["vsync"] = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport := view.get_viewport_rid(); RenderingServer.viewport_set_measure_render_time(viewport,true)
	for enabled: bool in [false,true,true,false]:
		GameData.options["gfx_vegetation_interaction"] = int(enabled); details.apply_options(); build(details,p)
		await frames(20)
		var wall := []; var update := []; var sampled := []; var cpu := []; var gpu := []; var draws := []; var contacts := []; var cells := []
		var previous := Time.get_ticks_usec(); var uploads_before := details.interaction.updates if details.interaction else 0
		for frame in 160:
			for i in actors.size(): actors[i].position = poses[i]+Vector3(sin(frame/60.0*4.0)*0.35,0,0)
			world.terrain._waves.advance(1.0/60.0)
			var updates_before := details.interaction.updates if details.interaction else 0
			var started := Time.get_ticks_usec(); details._update_motion(focus); var cost := (Time.get_ticks_usec()-started)/1000.0
			await RenderingServer.frame_post_draw; await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if frame >= 40:
				wall.append((now-previous)/1000.0); update.append(cost)
				if details.interaction and details.interaction.updates != updates_before: sampled.append(cost)
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport)); gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
				draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
				if details.interaction: contacts.append(details.interaction.last_contacts); cells.append(details.interaction._cells.size())
			previous = now
		check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,"vegetation timing stays uncapped")
		rows.append({"case":"timing","enabled":enabled,"actors":actors.size(),"contacts":distribution(contacts),"cells":distribution(cells),
			"frame_ms":distribution(wall),"update_per_frame_ms":distribution(update),"sampled_update_ms":distribution(sampled),
			"viewport_cpu_ms":distribution(cpu),"viewport_gpu_ms":distribution(gpu),"draws":distribution(draws),"size":str(view.size),
			"uploaded_bytes":(details.interaction.updates-uploads_before)*65536 if details.interaction else 0,"game_seconds":160.0/60.0})
	view.size = old_size; Engine.max_fps = 120; GameData.options["fps_limit"] = 3

func fixture() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	var view := SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var map := EIMapScene.new(); world.add_child(map); world.map = map
	var t := EITerrain.load_map("zone1"); map.add_child(t); map.terrain = t; world.terrain = t; t.set_process(false)
	var details := t.details; details.set_process(false); details.prepare_grass()
	var p := location(details)
	check(p.is_finite(),"authored broad grass patch exists")
	if not p.is_finite(): view.free(); return
	var focus := Vector3(p.x,t.height_at(p.x,p.y),-p.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = focus+Vector3(4,3.5,5); camera.look_at(focus); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.14,0.24,0.34); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); sun.shadow_enabled = true; view.add_child(sun)
	var lamp := OmniLight3D.new(); lamp.position = focus+Vector3(1,2,1); lamp.omni_range = 10.0
	lamp.light_energy = 2.0; lamp.shadow_enabled = true; view.add_child(lamp)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var u := actor(world,focus)
	build(details,p)
	var off: Image
	if rendered:
		var initial := await snap(view,"off-initial")
		# Local shadow-atlas resolution can settle after the first few draws.
		# Record the unchanged scene first, then wait beyond that initial work.
		await frames(160); off = await snap(view,"off")
		rows.append({"case":"baseline-settling","difference":difference(initial,off)})
		var delta := difference(off,await snap(view,"off-stable"))
		rows.append({"case":"baseline-stable","difference":delta})
		check(delta.changed_pixels == 0,"baseline grass and figure settle before comparison")
	check(details.interaction == null and not details._material.shader.code.contains("vegetation_pressure"),"default off keeps the field and shader work absent")
	GameData.options["gfx_vegetation_interaction"] = 1; details.apply_options(); build(details,p)
	var field := details.interaction; field.focus = Vector2(focus.x,focus.z)
	details._material.set_shader_parameter("vegetation_focus",field.focus)
	check(field != null,"option creates the bounded pressure owner")
	if rendered:
		var empty_image := await snap(view,"empty")
		var delta := difference(off,empty_image); rows.append({"case":"empty","difference":delta})
		check(delta.changed_pixels == 0,"empty pressure preserves the baseline grass image")
		for node: MultiMeshInstance3D in details._chunks.values(): details.remove_child(node); details.add_child(node)
		delta = difference(empty_image,await snap(view,"empty-refreshed"))
		rows.append({"case":"empty-refresh","difference":delta})
		check(delta.changed_pixels == 0,"unchanged empty grass survives the refresh control")
	var admitted := field.contacts(details,world)
	check(admitted.size() == 1,"visible planted human is admitted")
	rows.append({"case":"admission","point":str(focus),"bounds":str(Pressure.posed_bounds(u)),"contacts":admitted.size()})
	for i in 8: t._waves.advance(0.05); details._update_motion(focus)
	check(not field._cells.is_empty(),"game-clock updates press grass under the figure")
	if rendered:
		var standing_image := await snap(view,"standing")
		var delta := difference(off,standing_image); rows.append({"case":"standing","difference":delta})
		check(delta.pixels_over_2 > 20,"standing pressure visibly parts grass")
		for node: MultiMeshInstance3D in details._chunks.values(): details.remove_child(node); details.add_child(node)
		delta = difference(standing_image,await snap(view,"shadow-refreshed"))
		rows.append({"case":"shadow-refresh","difference":delta})
		check(delta.changed_pixels == 0,"pressure shadows match forced instance refresh")
	for flag: String in ["hidden","fogged","dead"]:
		u.set(flag,true); check(field.contacts(details,world).is_empty(),flag+" actor supplies no pressure"); u.set(flag,false)
	u.position.y += 2.0; check(field.contacts(details,world).is_empty(),"airborne/bridge figure supplies no ground pressure"); u.position.y -= 2.0
	var standing: Vector2 = admitted[0].extent if not admitted.is_empty() else Vector2.ZERO
	u.stance = GameUnit.STANCE_CRAWL
	var clip := u.model.resolve("crawl")
	check(not clip.is_empty() and u.model.player.has_animation("ei/"+clip),"authored crawl pose is available")
	if not clip.is_empty(): u.model.player.play("ei/"+clip,0.0); u.model.player.seek(0.3,true)
	admitted = field.contacts(details,world)
	check(admitted.size() == 1 and (admitted[0].extent as Vector2).x > standing.x,"crawling uses the longer presented contact envelope")
	for i in 12:
		u.position.x += 0.06; t._waves.advance(0.05); details._update_motion(focus)
	if rendered: await snap(view,"crawl")
	check(field._cells.size() <= Pressure.MAX_CELLS,"pressure history remains bounded")
	var held := field.updates; var pixels := field.texture.get_image().get_data()
	for i in 5: details._update_motion(focus)
	check(field.updates == held and field.texture.get_image().get_data() == pixels,"frozen terrain time holds interaction exactly")
	var session := Session.new(); world.session = session
	for flag: String in ["loading_game","_zone_holding","_remote_loading"]:
		session.set(flag,true); t._waves.advance(0.1); details._update_motion(focus)
		check(field.updates == held,"world hold stops pressure: "+flag); session.set(flag,false)
	session.lmp_travel = preload("res://src/game/lmp_travel.gd").new(session)
	t._waves.advance(0.1); details._update_motion(focus)
	check(field.updates == held,"unregistered LMP world cannot advance pressure")
	session.lmp_travel = null; world.session = null; session.free()
	GameData.options["gfx_wind"] = 1; details.apply_options()
	t._waves.advance(0.25); details._update_motion(focus)
	var phase: float = details._material.get_shader_parameter("wind_phase")
	check(is_equal_approx(phase,fposmod(t._waves.time_ticks()*EIWaterWaves.TICK*1.6,TAU)),"grass wind uses the terrain game clock")
	await frames()
	check(is_equal_approx(phase,details._material.get_shader_parameter("wind_phase")),"wall time alone does not move grass wind")
	if rendered:
		# TIME still marks a dynamic shadow caster, but contributes zero to
		# vertex position. Real wall time may advance during a scene-tree pause.
		process_mode = Node.PROCESS_MODE_ALWAYS; get_tree().paused = true; Engine.time_scale = 1.0
		var paused := await snap(view,"wind-paused")
		var delta := difference(paused,await snap(view,"wind-paused-later"))
		rows.append({"case":"paused-wind","difference":delta})
		check(delta.changed_pixels == 0,"paused wind and pressure stay visually fixed while shadow time advances")
		Engine.time_scale = 0; get_tree().paused = false; process_mode = Node.PROCESS_MODE_INHERIT
	GameData.options["gfx_wind"] = 0; details.apply_options()
	# Flooding invalidates geometry and all pressure history before rebuilding.
	details.water_changed(); check(field._cells.is_empty() and details._chunks.is_empty(),"water change discards pressure and resident grass")
	var ref := weakref(field); field = null
	GameData.options["gfx_vegetation_interaction"] = 0; details.apply_options(); build(details,p)
	check(ref.get_ref() == null and details.interaction == null,"disable releases the pressure field")
	u.position = focus; u.stance = GameUnit.STANCE_NONE; u.model.player.play("ei/cidle01",0.0); u.model.player.seek(0.3,true)
	if rendered:
		var delta := difference(off,await snap(view,"restored")); rows.append({"case":"restored","difference":delta})
		check(delta.changed_pixels == 0,"off-on-off restores authored grass")
	GameData.options["gfx_vegetation_interaction"] = 1; details.apply_options(); build(details,p)
	var owner_ref := weakref(details.interaction); var texture_ref := weakref(details.interaction.texture)
	GameData.options["gfx_grass"] = 0; details.apply_options()
	check(owner_ref.get_ref() == null and texture_ref.get_ref() == null and details._chunks.is_empty(),"disabling grass releases interaction texture and geometry")
	GameData.options["gfx_grass"] = 1; GameData.options["gfx_vegetation_interaction"] = 0; details.apply_options(); build(details,p)
	if rendered and OS.get_cmdline_user_args().has("--vegetation-timing"): await timing(view,details,world,camera,p,u)
	view.free(); await frames()

func _ready() -> void:
	for key: String in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_vegetation_interaction","gfx_water","gfx_water_caustics","gfx_water_interaction","gfx_wind","confine_mouse","vsync","gfx_volumetric","gfx_ssao","gfx_bloom"]: GameData.options[key] = 0
	GameData.options["gfx_grass"] = 1
	Engine.max_fps = 120; Engine.time_scale = 0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	field_rules(); await fixture()
	TexUpscale.shutdown(); await frames(16)
	FileAccess.open("user://vegetation-interaction.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")+"\n")
	get_tree().quit(1 if failures else 0)
