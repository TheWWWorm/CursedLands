extends "local_shadow_cache.gd"
## Opportunity probe, NOT a shadow-cache implementation. The diagnostic lower
## bound removes static casters' shadows while retaining their visible meshes.
## It does not include static depth restoration/copies or new cache management.
const PERIOD := 120
const MeshScreenRect = preload("res://src/ui/mesh_screen_rect.gd")
var actor: GameUnit
var clip := ""
var clip_length := 0.0
var path: Array[Vector2] = []
var static_meshes: Array[GeometryInstance3D] = []
var static_shadow_modes: Array[int] = []
var sample_count := 240
var switch_warmup := 96
var target: OmniLight3D
var static_overlap := 0
var selected_lights := []
var controls := {}
var poses := []
var held_rows := []

func difference(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var changed := 0; var over := 0; var sum := 0
	for p in range(0,aa.size(),4):
		var delta := 0
		for c in 3:
			var d := absi(aa[p+c]-bb[p+c]); delta = maxi(delta,d); sum += d
		peak = maxi(peak,delta); changed += int(delta>0); over += int(delta>2)
	return {"changed_pixels":changed,"pixels_over_2":over,"peak_delta":peak,
		"mean_rgb_delta":float(sum)/(a.get_width()*a.get_height()*3)}

func set_static_shadows(enabled: bool) -> void:
	for i in static_meshes.size():
		static_meshes[i].cast_shadow = static_shadow_modes[i] if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func place(step: int) -> void:
	var k := posmod(step,PERIOD)
	actor.pos = path[k]
	var velocity := path[posmod(k+1,PERIOD)]-path[posmod(k-1,PERIOD)]
	if velocity.length_squared() > 0.0000001: actor.facing = velocity.angle()
	actor.resync_drawn()
	EIAnimPart.batch = true
	actor.model.player.seek(clip_length*fposmod(0.17+float(k)/PERIOD*2.0,1.0),true)
	EIAnimPart.batch = false
	for root: EIAnimPart in actor.model._animation_roots: root._apply_key()

func image_at(label: String, step := 0) -> Image:
	place(step)
	await settle(16)
	var image := view.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	check(image.save_png("user://local-shadow-overlay-"+label+".png") == OK,"capture "+label)
	return image

func held_sample(label: String) -> void:
	# Identical pixels alone cannot prove that static shadow depth was reused:
	# a frozen TIME-dependent caster could keep redrawing the same depth.
	await settle(16)
	var shadows := []
	for i in 24:
		await tick()
		shadows.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	held_rows.append({"label":label,"shadow_primitives":distribution(shadows)})
	check(shadows.max() == 0,label+": held actor permits native shadow reuse")

func moving_sample(label: String, static_enabled: bool) -> void:
	set_static_shadows(static_enabled)
	for i in switch_warmup:
		place(i-switch_warmup)
		await tick()
	var clock := Engine.get_frames_drawn()
	var wall := []; var cpu := []; var gpu := []; var shadows := []; var draws := []; var visible_primitives := []
	var advance := []; var zero_shadow_frames := 0; var invalid_gpu_samples := 0
	for i in sample_count:
		var begin := Time.get_ticks_usec()
		place(i)
		advance.append((Time.get_ticks_usec()-begin)/1000.0)
		await tick()
		wall.append((Time.get_ticks_usec()-begin)/1000.0)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		invalid_gpu_samples += int(not is_finite(gpu_ms) or gpu_ms <= 0.0)
		gpu.append(gpu_ms)
		var n := view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		shadows.append(n); zero_shadow_frames += int(n == 0)
		# GLES counts shadow draws in VISIBLE/DRAW_CALLS, not SHADOW/DRAW_CALLS.
		draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		visible_primitives.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	check(Engine.get_frames_drawn() >= clock+sample_count,label+": normal render clock advances")
	check(zero_shadow_frames == 0,label+": moving unit keeps shadow depth updating")
	check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,label+": uncapped and VSync off")
	check(invalid_gpu_samples == 0,label+": every retained native viewport GPU timestamp is finite and positive")
	rows.append({"label":label,"static_casters_enabled":static_enabled,"samples":sample_count,
		"shadow_primitives":distribution(shadows),"visible_draws_including_gles_shadows":distribution(draws),
		"visible_primitives":distribution(visible_primitives),"viewport_cpu_ms":distribution(cpu),
		"viewport_gpu_ms":distribution(gpu),"frame_wall_ms":distribution(wall),"pose_update_ms":distribution(advance),
		"zero_shadow_frames":zero_shadow_frames,"invalid_gpu_samples":invalid_gpu_samples,
		"drawn_frames":Engine.get_frames_drawn()-clock})
	print("LOCAL_SHADOW_OVERLAY_ROW ",JSON.stringify(rows.back()))

func choose_path() -> bool:
	var center := Vector2(target.global_position.x,-target.global_position.z)
	var toward := Vector2(10,-12).normalized()
	var tangent := Vector2(-toward.y,toward.x)
	# Search only genuinely walkable original AI-map cells, with the entire
	# actor-height route inside this authored lamp's unchanged radius.
	for radius: float in [2.4,1.8,3.0,1.2]:
		for turn in 32:
			var angle := float(turn)*TAU/32.0
			var middle := center+toward.rotated(angle)*radius
			var candidate: Array[Vector2] = []
			var valid := true
			for i in PERIOD:
				var p := middle+tangent*0.7*sin(float(i)*TAU/PERIOD)
				if not world.nav.is_walkable(p,3): valid = false; break
				var top := EISpace.pos(p.x,p.y,world._stand_z(p)+1.0)
				if top.distance_to(target.global_position) > target.omni_range*0.9: valid = false; break
				candidate.append(p)
			if valid:
				path = candidate
				return true
	return false

func setup_scene() -> bool:
	view = SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	view.positional_shadow_atlas_size = 2048; view.positional_shadow_atlas_16_bits = true
	# Same 4-shadow subdivision as default quadrants 0/1. Use only those two
	# so this single lamp has a known 256x256 cube face on Compatibility.
	for q in 4:
		view.set_positional_shadow_atlas_quadrant_subdiv(q,Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4 if q<2 else Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED)
	add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	world = GameWorld.new(); world.process_mode = Node.PROCESS_MODE_DISABLED; view.add_child(world)
	check(world.load_map(map_name,map_name,false),"authored map loads")
	if world.map == null: return false
	fx = ParticleFx.of(world); fx.setup_zone()
	check(not fx.lights.is_empty(),"authored lights present")
	if fx.lights.is_empty(): return false
	var overlap := -1
	for d: Dictionary in fx.lights:
		var n := nearby_foliage(d.light)
		if n > overlap: overlap = n; target = d.light
	var focus := target.global_position
	camera = Camera3D.new(); camera.far = 90; camera.fov = CameraRig.MODERN_FOV
	view.add_child(camera); camera.position = focus+Vector3(10,10,12); camera.look_at(focus); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.1,0.1,0.1)
	view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.12,0.12,0.12),Color(0.35,0.35,0.35))
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(80,90,0))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	game = Game.new(); game.world = world
	manager = LocalLighting.new(game); view.add_child(manager); manager.set_process(false); manager._world = world
	manager._assign_shadows(fx,camera,focus); manager._advance_shadows(0.4); manager._advance_shadows(0.4)
	for d: Dictionary in fx.lights:
		if d.light.shadow_enabled: selected_lights.append({"position":str(d.light.global_position),"range":d.light.omni_range,
			"energy":d.light.light_energy,"opacity":d.light.shadow_opacity,"mode":d.light.omni_shadow_mode})
	check(target.shadow_enabled and selected_lights.size() == 1,"one authored target selected by production manager")
	if selected_lights.size() != 1: return false
	for n: Node in world.map.find_children("*","GeometryInstance3D",true,false):
		var geometry := n as GeometryInstance3D
		if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		static_meshes.append(geometry); static_shadow_modes.append(geometry.cast_shadow)
		var box := geometry.global_transform*geometry.get_aabb()
		if target.global_position.distance_to(target.global_position.clamp(box.position,box.end)) <= target.omni_range:
			static_overlap += 1
	check(static_overlap > 0,"original static casters overlap the light")
	check(choose_path(),"walkable actor route inside authored light")
	if path.is_empty(): return false
	actor = world.spawn_unit({"prototype":"Human Hero","position":Vector3(path[0].x,path[0].y,0)})
	check(actor != null and actor.model != null,"actual GameUnit from original Human Hero data")
	if actor == null or actor.model == null: return false
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	actor.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	clip = actor.model.resolve("walk",1)
	check(not clip.is_empty(),"authored walk animation available")
	if clip.is_empty(): return false
	clip_length = actor.model.player.get_animation("ei/"+clip).length
	actor.model.player.play("ei/"+clip,0.0)
	place(0)
	return true

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or not Portability.compatibility():
		printerr("LOCAL_SHADOW_OVERLAY requires desktop Compatibility"); get_tree().quit(2); return
	map_name = "zone3obr"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--overlay-samples="): sample_count = maxi(120,int(arg.trim_prefix("--overlay-samples=")))
	seed(417)
	for key: String in GameData.options:
		if key.begins_with("gfx_"): GameData.options[key] = 0
	GameData.options.merge({"gfx_firelight":1,"confine_mouse":0,"vsync":0,"fps_limit":0,"auto_graphics":0},true)
	Gfx.ensure_globals(); EIFigure.set_wind(false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0; Engine.time_scale = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true)
	if not setup_scene(): get_tree().quit(1); return
	await settle(180)
	var all := await image_at("full")
	var held := await image_at("full-held")
	controls["held"] = difference(all,held)
	check(all.get_data() == held.get_data(),"held scene image is exact")
	await held_sample("full")
	var moved := await image_at("full-moved",30)
	controls["moving_actor"] = difference(all,moved)
	check(controls.moving_actor.pixels_over_2 > 0,"actual actor movement is visible")
	var context := MeshScreenRect.camera_context(camera)
	for mesh: MeshInstance3D in actor.model.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree(): continue
		var rect := MeshScreenRect.of_context(mesh,camera,context)
		if rect.has_area(): poses.append({"part":str(actor.model.get_path_to(mesh)),"screen_rect":str(rect)})
	check(not poses.is_empty(),"original unit geometry projects into the viewport")
	set_static_shadows(false)
	var excluded := await image_at("static-excluded")
	controls["removed_static_shadows"] = difference(all,excluded)
	check(controls.removed_static_shadows.pixels_over_2 > 0,"diagnostic changes the image and cannot count as implementation")
	await held_sample("static-excluded")
	var actor_modes := []
	for geometry: GeometryInstance3D in actor._geoms:
		actor_modes.append(geometry.cast_shadow); geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var no_actor_shadow := await image_at("static-excluded-unit-shadow-off")
	controls["unit_shadow"] = difference(excluded,no_actor_shadow)
	check(controls.unit_shadow.pixels_over_2 > 0,"actual unit casts a visible local shadow")
	for i in actor._geoms.size(): actor._geoms[i].cast_shadow = actor_modes[i]
	set_static_shadows(true)
	var restored := await image_at("restored")
	controls["restored"] = difference(all,restored)
	check(all.get_data() == restored.get_data(),"restoring all caster flags restores the exact image")
	# ABBA exposes order/thermal drift; it does not eliminate it. Each block
	# repeats the identical poses, camera, light, color meshes and viewport.
	for enabled: bool in [true,false,false,true]:
		await moving_sample(("full" if enabled else "static-excluded")+"-"+str(rows.size()),enabled)
	for i in [0,3]:
		for j in [1,2]:
			check(rows[i].shadow_primitives.median > rows[j].shadow_primitives.median,"arms %d/%d: static geometry contributes resubmitted shadow work" % [i,j])
	for i in [1,2,3]:
		check(rows[0].visible_primitives == rows[i].visible_primitives,"arm %d: color-pass primitive distribution unchanged" % i)
	var drift := {}
	for metric: String in ["viewport_cpu_ms","viewport_gpu_ms","frame_wall_ms"]:
		drift[metric] = {"full_a2_minus_a1":rows[3][metric].median-rows[0][metric].median,
			"excluded_b2_minus_b1":rows[2][metric].median-rows[1][metric].median,
			"first_full_minus_excluded":rows[0][metric].median-rows[1][metric].median,
			"second_full_minus_excluded":rows[3][metric].median-rows[2][metric].median}
	var report := {"checks":checks,"failures":failures,"map":map_name,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"viewport":str(view.size),
		"camera_transform":str(camera.transform),"camera_fov":camera.fov,"selected_lights":selected_lights,
		"static_caster_nodes":static_meshes.size(),"static_caster_nodes_in_sphere":static_overlap,
		"unit_prototype":"Human Hero","animation":clip,"clip_length":clip_length,"actor_route":path.map(func(p): return [p.x,p.y]),
		"actor_screen_parts":poses,"manual_animation_and_placement":true,"gameplay_simulation":false,
		"period_frames":PERIOD,"sample_frames":sample_count,"warmup_frames":switch_warmup,"initial_warmup":180,
		"normal_render_loop":true,"wind":false,"directional_shadows":false,"cache_implemented":false,
		"shadow_atlas_size":2048,"shadow_depth_bits":16,"shadow_quadrant_subdivisions":[4,4,0,0],
		"derived_cube_face_size":256,"extra_static_cube_payload_bytes":6*256*256*2,
		"six_depth_copies_read_plus_write_bytes_per_dynamic_frame":2*6*256*256*2,
		"copy_time_measured":false,"rows":rows,"held_rows":held_rows,"median_drift_and_deltas":drift,"controls":controls,
		"limits":"Static-excluded images deliberately lose scenery shadows. Timing is the observed whole-viewport full-minus-excluded difference, including changed depth occlusion and color shadow values; it is not isolated static-shadow GPU time. The work reduction omits six depth copies, extra memory, classification and invalidation costs. No implementation gain or gameplay FPS result is claimed."}
	FileAccess.open("user://local-shadow-overlay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("LOCAL_SHADOW_OVERLAY ",JSON.stringify(report))
	manager.free(); game.free(); view.free(); UnitWounds.shutdown(); TexUpscale.shutdown()
	await settle(12)
	get_tree().quit(1 if failures else 0)
