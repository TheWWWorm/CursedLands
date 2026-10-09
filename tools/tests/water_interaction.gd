extends Node
## Real map/water/unit materials with controlled presented poses. The fixture
## tests the visual controller, not navigation or a complete gameplay route.
const Interaction = preload("res://src/game/fx/water_interaction.gd")
const Surface = preload("res://src/game/fx/water_surface.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 8) -> void:
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

func centre(terrain: EITerrain) -> Vector3:
	var best := Vector3.INF; var distance := INF; var width := terrain.sectors_x*32
	for i in terrain.water.size():
		if not is_finite(terrain.water[i]) or terrain.liquid_ground[i] in [13,14,255]: continue
		var p := Vector2(i%width+0.5,i/width+0.5)
		if terrain.water[i] < terrain.height_at(p.x,p.y)+0.15: continue
		var open := true
		for offset: Vector2 in [Vector2(-1.0,0),Vector2(1.0,0),Vector2(0,-1.0),Vector2(0,1.0)]:
			var q := p+offset; var height := terrain.water_at(q.x,q.y)
			if not is_finite(height) or height < terrain.height_at(q.x,q.y)+0.15: open = false; break
		if not open: continue
		var score := p.distance_squared_to(terrain.size_ei()*0.5)
		if score < distance: distance = score; best = Vector3(p.x,terrain.water[i],-p.y)
	return best

func unit(world: GameWorld, uid: int, location: Vector3) -> GameUnit:
	var u := GameUnit.new()
	check(u.setup(world,{"prototype":"Human Hero","nid":uid}),"real human figure is created")
	world.add_child(u); world.set_unit(uid,u)
	u.set_process(false); u.set_physics_process(false)
	u.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	u.model.set_process(false)
	u.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	u.model.player.play("ei/cidle01",0.0); u.model.player.seek(0.3,true)
	u.position = location
	return u

func snap(view: SubViewport, label: String) -> Image:
	await frames()
	var im := view.get_texture().get_image()
	im.save_png("user://water-interaction-"+label+".png")
	return im

func motion_rules() -> void:
	var first := Interaction.Contact.new(); var second := Interaction.Contact.new()
	first.heading = Vector2.RIGHT; second.heading = Vector2.RIGHT
	for i in 60: Interaction.advance(first,Vector3((i+1)*0.05,0,0),0.5,1.0/60.0)
	for i in 30: Interaction.advance(second,Vector3((i+1)*0.1,0,0),0.5,1.0/30.0)
	check(is_equal_approx(first.motion,1.0) and is_equal_approx(first.presence,1.0),"movement/presence fade reaches full strength")
	check(is_equal_approx(first.speed,3.0) and is_equal_approx(second.speed,3.0),"motion speed uses game seconds at both sample rates")
	check(first.position.is_equal_approx(second.position) and first.heading.is_equal_approx(second.heading),"same route is independent of 30/60 Hz sampling")
	for i in 60: Interaction.advance(first,Vector3(3,0,0),0.5,1.0/60.0)
	check(first.motion == 0.0 and is_equal_approx(first.speed,3.0),"stopped wake fades while retaining its last travel shape")
	Interaction.advance(second,Vector3(3,0,-0.05),0.5,1.0/60.0)
	check(second.heading.x > 0.8 and second.heading.y < 0.0,"wake turns gradually rather than rotating with the body")
	Interaction.advance(second,Vector3(20,0,0),0.5,1.0/60.0)
	check(second.motion == 0.0 and second.speed == 0.0 and second.presence < 0.1,"teleport does not drag a wake across the map")
	var edge := EITerrain.new(); edge.sectors_x = 1; edge.sectors_y = 1
	edge.water.resize(32*32); edge.water.fill(-INF); edge.water[3*32+3] = 1.0
	check(Interaction.near_water(edge,Vector3(4.02,1.0,-4.02)),"diagonally deformed water edge remains a broad-phase candidate")
	edge.free()

func scheduling(owner: Interaction, world: GameWorld, camera: Camera3D) -> void:
	# Real process callbacks under an always-processing parent, as in Game.
	# Keep the fixture's map/actors frozen and use an unattached Session so this
	# test starts no multiplayer services or gameplay scripts.
	var g := Game.new(); g.world = world; g.rig = CameraRig.new(); g.rig.camera = camera
	var session := Session.new(); world.session = session; owner.game = g
	var parent := Node.new(); parent.process_mode = Node.PROCESS_MODE_ALWAYS; add_child(parent)
	owner.reparent(parent)
	var original_mode := world.process_mode; world.process_mode = Node.PROCESS_MODE_DISABLED
	var held_clock := owner._clock; owner._process(0.1)
	check(owner._clock == held_clock,"disabled world behind the travel map holds contacts")
	world.process_mode = original_mode
	session.lmp_travel = preload("res://src/game/lmp_travel.gd").new(session)
	owner._process(0.1)
	check(owner._clock == held_clock,"unregistered LMP world holds contacts")
	session.lmp_travel = null
	for key: String in ["loading_game","_zone_holding","_remote_loading"]:
		session.set(key,true); var before := owner._clock; owner._process(0.1)
		check(owner._clock == before,"contact clock holds during "+key); session.set(key,false)
	session._movie_ev = {"serial":1}
	var before := owner._clock; owner._process(0.1)
	check(owner._clock == before,"contact clock holds during a movie"); session._movie_ev.clear()
	world.authority = false
	owner._process(0.1)
	check(is_equal_approx(owner._clock,before+0.1),"remote presentation advances without authority draw_time")
	world.authority = true
	process_mode = Node.PROCESS_MODE_ALWAYS; owner.set_process(true)
	get_tree().paused = true; before = owner._clock; await frames()
	check(owner._clock == before,"SceneTree pause freezes contacts under an always-processing parent")
	get_tree().paused = false
	var elapsed := []
	for scale: float in [1.0,2.0]:
		Engine.time_scale = scale
		await frames(4); before = owner._clock
		# Thirty capped render frames provide a bounded real callback sample;
		# the game-time delta, not wall-clock shader TIME, drives the effect.
		await frames(30); elapsed.append(owner._clock-before)
	check(elapsed[0] > 0.15 and elapsed[1]/elapsed[0] > 1.7 and elapsed[1]/elapsed[0] < 2.3,"2x game speed doubles the contact clock")
	rows.append({"case":"game-clock","elapsed_1x":elapsed[0],"elapsed_2x":elapsed[1]})
	Engine.time_scale = 0; owner.set_process(false); owner.game = null
	world.session = null; owner.reparent(self); parent.free(); g.rig.free(); g.free(); session.free()
	process_mode = Node.PROCESS_MODE_INHERIT

func distribution(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)],"samples":values.size()}

func material_branches(view: SubViewport, owner: Interaction, world: GameWorld, camera: Camera3D) -> void:
	var t := world.terrain; var material := t._water_mat
	var base := EITerrain._water_fx_shader; var contact := material.shader
	var saved_cells: Texture2D = material.get_shader_parameter("terrain_cells")
	var lava: PackedFloat32Array = material.get_shader_parameter("lava")
	var forced_lava := lava.duplicate(); forced_lava.fill(1.0)
	var image := saved_cells.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var cell := image.get_pixel(x,y); cell.b = 14.0; image.set_pixel(x,y,cell)
	var swamp := ImageTexture.create_from_image(image)
	owner.step(world,camera,0.1)
	check(not owner._contacts.is_empty(),"branch guard is exercised with a live contact")
	for branch: String in ["lava","swamp"]:
		material.set_shader_parameter("lava",forced_lava if branch == "lava" else lava)
		material.set_shader_parameter("terrain_cells",swamp if branch == "swamp" else saved_cells)
		material.shader = base; var original := await snap(view,branch+"-control")
		material.shader = contact; owner._bind(); var candidate := await snap(view,branch)
		var delta := difference(original,candidate)
		check(delta.changed_pixels == 0,"contact program preserves the "+branch+" branch")
		rows.append({"case":"forced-material-"+branch,"difference":delta})
	material.set_shader_parameter("lava",lava); material.set_shader_parameter("terrain_cells",saved_cells)
	var saved_cover := t._rain_cover
	GameData.options["gfx_weather_surfaces"] = 1; Gfx.apply_surface_options(); Gfx.set_surface_weather(0.6,0.8)
	material.set_shader_parameter("reflections",true); material.set_shader_parameter("mirror",1.0)
	for roof: bool in [false,true]:
		var cover := Image.create(1,1,false,Image.FORMAT_RF); cover.fill(Color(10000.0 if roof else -10000.0,0,0))
		t.set_rain_cover(cover)
		check(material.get_shader_parameter("rain_cover") == t._rain_cover,"contact material receives the new roof map")
		material.set_shader_parameter("water_contact_count",0)
		material.shader = base; var initial := await snap(view,"rain-"+str(roof)+"-initial")
		await frames(24)
		var original := await snap(view,"rain-"+str(roof)+"-control")
		var stable := await snap(view,"rain-"+str(roof)+"-stable")
		check(difference(original,stable).changed_pixels == 0,"unchanged rain program settles before comparison")
		material.shader = contact; var candidate := await snap(view,"rain-"+str(roof))
		var delta := difference(original,candidate)
		check(delta.changed_pixels == 0,"empty contact shader preserves rain/SSR under roof="+str(roof))
		material.shader = base; var restored := await snap(view,"rain-"+str(roof)+"-restored")
		check(difference(original,restored).changed_pixels == 0,"rain control remains unchanged across shader switch")
		rows.append({"case":"rain-reflection-roof-"+str(roof),"difference":delta,
			"initial_to_stable":difference(initial,stable),"restoration":difference(original,restored)})
		material.shader = contact
	GameData.options["gfx_weather_surfaces"] = 0; Gfx.apply_surface_options(); Gfx.set_surface_weather(0.0,0.0)
	t._rain_cover = saved_cover; t.apply_gfx(); owner._bind()
	GameData.options["gfx_water"] = 0; t.apply_gfx(); owner.refresh(); owner.set_process(false)
	check(material.shader == EITerrain._water_shader and owner._contacts.is_empty() and not owner._enabled,"original-water option also disables contact work")
	GameData.options["gfx_water"] = 1; t.apply_gfx(); owner.refresh(); owner.set_process(false)

func timing(view: SubViewport, owner: Interaction, world: GameWorld, camera: Camera3D, actors: Array[GameUnit]) -> void:
	var old_size := view.size; view.size = Vector2i(1280,720)
	var poses := actors.map(func(u: GameUnit): return u.position)
	GameData.options["fps_limit"] = 0; GameData.options["vsync"] = 0
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport := view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	for enabled: bool in [false,true,true,false]:
		GameData.options["gfx_water_interaction"] = int(enabled)
		world.terrain.apply_gfx(); owner.refresh(); owner.set_process(false)
		await frames(16)
		var wall := []; var update := []; var cpu := []; var gpu := []; var draws := []
		var previous := Time.get_ticks_usec()
		for frame in 224:
			for i in actors.size(): actors[i].position = poses[i]+Vector3(sin(frame/60.0*4.0)*0.4,0,0)
			var started := Time.get_ticks_usec(); owner.step(world,camera,1.0/60.0)
			var cost := Time.get_ticks_usec()-started
			await RenderingServer.frame_post_draw; await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if frame >= 64:
				wall.append((now-previous)/1000.0); update.append(cost/1000.0)
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
				draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
			previous = now
		check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,"water timing stays uncapped")
		rows.append({"case":"timing","enabled":enabled,"units":actors.size(),"contacts":owner._contacts.size(),
			"frame_ms":distribution(wall),"update_ms":distribution(update),"viewport_cpu_ms":distribution(cpu),
			"viewport_gpu_ms":distribution(gpu),"draws":distribution(draws),"size":str(view.size)})
	for i in actors.size(): actors[i].position = poses[i]
	view.size = old_size; Engine.max_fps = 120; GameData.options["fps_limit"] = 3
	GameData.options["gfx_water_interaction"] = 1; world.terrain.apply_gfx(); owner.refresh(); owner.set_process(false)
	await frames()

func world_cases() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	var view := SubViewport.new(); view.size = Vector2i(640,480); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.terrain = EITerrain.load_map("zone1"); world.add_child(world.terrain); world.terrain.set_process(false)
	var t := world.terrain; var focus := centre(t); check(focus.is_finite(),"exposed water found")
	var camera := Camera3D.new(); view.add_child(camera)
	camera.position = focus+Vector3(3.2,3.5,5.0); camera.look_at(focus+Vector3.UP*0.2); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.14,0.24,0.34); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var original_position := focus-Vector3.UP*0.6
	var u := unit(world,1,original_position)
	var owner := Interaction.new(); add_child(owner); owner.set_process(false)
	check(owner.process_mode == Node.PROCESS_MODE_PAUSABLE,"effect explicitly pauses despite Game's always-processing mode")
	GameData.options["gfx_water_interaction"] = 0; t.apply_gfx(); owner.refresh(); owner.set_process(false)
	var off: Image
	if rendered:
		var initial := await snap(view,"off-initial")
		await frames(24)
		var warm := await snap(view,"off-warm")
		off = await snap(view,"off")
		var stable := difference(warm,off)
		check(stable.changed_pixels == 0,"unchanged original water settles before comparison")
		rows.append({"case":"original-stabilization","initial_to_warm":difference(initial,warm),"warm_to_final":stable})
	var base_shader := t._water_mat.shader
	GameData.options["gfx_water_interaction"] = 1; t.apply_gfx(); owner.refresh(); owner.set_process(false)
	check(t._water_mat.shader != base_shader,"enabled water gets a dedicated contact shader")
	if rendered:
		var empty := await snap(view,"empty")
		var delta := difference(off,empty)
		check(delta.changed_pixels == 0,"enabled shader with no contacts preserves the original image")
		rows.append({"case":"empty","difference":delta})
	for i in 30: owner.step(world,camera,1.0/60.0)
	check(owner._contacts.size() == 1,"standing wader admitted")
	var id := u.get_instance_id()
	if owner._contacts.has(id):
		var contact: Interaction.Contact = owner._contacts[id]
		rows.append({"case":"placement","focus":str(focus),"root":str(u.position),"figure_radius":u.figure_radius,
			"bounds":str(Interaction.vertical_bounds(u)),"surface":owner._surface.sample(Vector2(u.position.x,u.position.z)),
			"contact_position":str(contact.position),"radius":contact.radius})
	check(owner._contacts.has(id) and owner._contacts[id].motion == 0.0,"standing contact has no running wake")
	var before := owner._clock; owner.step(world,camera,0.0)
	check(owner._clock == before,"zero game delta holds phase and contact history")
	var standing: Image
	if rendered:
		standing = await snap(view,"standing")
		var delta := difference(off,standing)
		check(delta.pixels_over_2 > 5,"standing contact is visible")
		rows.append({"case":"standing","difference":delta})
	for i in 30:
		u.position.x += 0.04; owner.step(world,camera,1.0/60.0)
	check(owner._contacts.has(id) and owner._contacts[id].motion > 0.95,"running wake eases in")
	if rendered:
		var moving := await snap(view,"moving")
		t._water_mat.set_shader_parameter("water_contact_count",0)
		var control := await snap(view,"moving-control")
		owner._bind()
		var delta := difference(control,moving)
		check(delta.pixels_over_2 > 20,"moving contact/wake is visible against the same posed scene")
		rows.append({"case":"moving","difference":delta})
	for i in 12:
		u.position.z -= 0.04; owner.step(world,camera,1.0/60.0)
	if rendered: await snap(view,"turning")
	for i in 60: owner.step(world,camera,1.0/60.0)
	check(owner._contacts.has(id) and owner._contacts[id].motion == 0.0,"standing again removes movement wake")
	u.position.y += 3.0
	owner.step(world,camera,0.1)
	check(owner._contacts.has(id) and owner._contacts[id].presence < 1.0,"leaving water fades at the last contact")
	for i in 8: owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"bridge/high root leaves no permanent contact")
	u.position = original_position; u.model.position.y = 3.0
	owner.step(world,camera,0.1); check(owner._contacts.is_empty(),"hovering posed model is rejected even with a low root")
	u.model.position.y = 0.0; u.position.y = focus.y-4.0
	owner.step(world,camera,0.1); check(owner._contacts.is_empty(),"fully submerged figure has no surface contact")
	u.position = original_position
	owner.step(world,camera,0.1); check(owner._contacts.size() == 1,"re-entry creates a new contact")
	u.hidden = true; owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"script-hidden unit cannot leave a revealing wake")
	u.hidden = false; u.fogged = true; owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"fog-hidden unit cannot enter the water list")
	u.fogged = false; u.dead = true; owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"dead unit is excluded")
	u.dead = false
	var material := int(t.water_mat[floori(-focus.z)*t.sectors_x*32+floori(focus.x)])
	t.set_water_offset(material,3.0); owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"scripted flooding above the whole figure rejects surface contact")
	t.set_water_offset(material,0.0); owner.step(world,camera,0.1)
	check(owner._contacts.size() == 1,"restoring water level admits contact again")
	owner.clear()
	var actors: Array[GameUnit] = [u]
	for i in range(2,19): actors.append(unit(world,i,original_position+Vector3((i%3)*0.06,0,(i/3)*0.04)))
	# VisibleOnScreenNotifier3D reports the last rendered frame, not the pose
	# just constructed in this synchronous fixture.
	await frames()
	var costs := []
	for i in 12:
		owner.step(world,camera,1.0/60.0); costs.append(owner.last_update_us)
	check(owner._contacts.size() == Interaction.MAX_UNITS,"contact list respects its sixteen-unit cap")
	check(owner._surface._sectors.size() <= Surface.CACHE_SECTORS,"surface cache stays bounded")
	rows.append({"case":"18-candidates","update_us":costs,"contacts":owner._contacts.size(),"surface_sectors":owner._surface._sectors.size()})
	if rendered and "--water-timing" in OS.get_cmdline_user_args(): await timing(view,owner,world,camera,actors)
	GameData.options["gfx_water_interaction"] = 0; t.apply_gfx(); owner.refresh(); owner.set_process(false)
	check(owner._contacts.is_empty() and owner._surface == null,"option off releases world contact history and surface cache")
	check(t._water_mat.shader == base_shader,"option off restores the exact original water program")
	for other in actors:
		if other != u: world.erase_unit(other.uid); other.free()
	u.position = original_position; u.model.player.play("ei/cidle01",0.0); u.model.player.seek(0.3,true)
	if rendered:
		var restored := await snap(view,"restored")
		var delta := difference(off,restored)
		check(delta.changed_pixels == 0,"off/on/off restores the original image")
		rows.append({"case":"restored","difference":delta})
	GameData.options["gfx_water_interaction"] = 1; t.apply_gfx(); owner.refresh(); owner.set_process(false)
	if rendered: await material_branches(view,owner,world,camera)
	await scheduling(owner,world,camera)
	owner.step(world,camera,0.1); world.erase_unit(u.uid); u.free(); owner.step(world,camera,0.1)
	check(owner._contacts.is_empty(),"removed unit releases its weak contact")
	var second := GameWorld.new(); view.add_child(second); second.set_process(false); second.set_physics_process(false)
	second.terrain = EITerrain.new(); second.terrain._water_mat = ShaderMaterial.new(); second.add_child(second.terrain)
	owner.step(second,camera,0.0)
	check(owner._contacts.is_empty() and owner._clock == 0.0 and owner._surface == null,"world change resets contact clock/cache")
	owner.free(); view.free(); await frames(16)

func _ready() -> void:
	for key: String in ["gfx_hd_textures","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_terrain","confine_mouse","gfx_volumetric","gfx_ssao","gfx_bloom","gfx_water_reflections","gfx_weather_surfaces","vsync"]:
		GameData.options[key] = 0
	GameData.options["gfx_water"] = 1; Gfx.ensure_globals()
	GameData.options["fps_limit"] = 3 # option index: 120 Hz, also used by deferred window setup
	Engine.time_scale = 0; Engine.max_fps = 120
	if DisplayServer.get_name() != "headless":
		RenderingServer.set_render_loop_enabled(true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	motion_rules(); await world_cases()
	UnitWounds.shutdown(); TexUpscale.shutdown(); await frames(16)
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	FileAccess.open("user://water-interaction.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WATER_INTERACTION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
