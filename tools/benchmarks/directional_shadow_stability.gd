extends "local_shadow_cache.gd"
## Diagnostic only: existing continuous desktop sun, fitted native cascades.
## No held/snapped candidate, projection change, cache, or production mutation.
const BASE_HOUR := 10.0
const TRACE_STEPS := 31
const TRACE_DT := 1.0 / 15.0
const PAN_SPEED := 0.3
var sun: DirectionalLight3D
var lights: EILights
var camera_start := Transform3D.IDENTITY
var trace_rows := []
var captured := []
var sample_frames := 240
var initial_image: Image
var final_exact := false
var held_exact := false

func image_now(label: String) -> Image:
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var filename := "directional-stability-"+label+".png"
	check(image.save_png("user://"+filename) == OK,"capture "+label)
	captured.append(filename)
	return image

func scene_at(mode: String, seconds: float) -> void:
	camera.transform = camera_start
	if mode == "pan":
		camera.position += camera_start.basis.x*seconds*PAN_SPEED
	var hour := BASE_HOUR+seconds/CampaignState.HOUR_SECONDS if mode == "clock" else BASE_HOUR
	var direction := EISpace.vec(EISky.light_dir_ei(hour)).normalized()
	game._aim_sun(direction,false)
	Gfx.update_original(game._env,sun,lights,hour,false)

func shadow_state(enabled: bool) -> void:
	sun.shadow_enabled = enabled
	Gfx.sync_sun_pass(sun)

func frame_counters() -> Dictionary:
	return {"shadow_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"visible_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}

func timed(label: String, enabled: bool, mode := "held") -> void:
	shadow_state(enabled)
	scene_at(mode,0)
	await settle(64)
	var cpu := []; var gpu := []; var wall := []; var primitives := []; var draws := []
	var visible_primitives := []; var visible_draws := []; var invalid := 0
	var start := Engine.get_frames_drawn()
	for i in sample_frames:
		var begin := Time.get_ticks_usec()
		if mode != "held": scene_at(mode,float(i)/60.0)
		await tick()
		wall.append((Time.get_ticks_usec()-begin)/1000.0)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		var ms := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		invalid += int(not is_finite(ms) or ms <= 0)
		gpu.append(ms)
		var counters := frame_counters()
		primitives.append(counters.shadow_primitives); draws.append(counters.shadow_draws)
		visible_primitives.append(counters.visible_primitives); visible_draws.append(counters.visible_draws)
	check(Engine.get_frames_drawn() >= start+sample_frames,label+": normal frame clock advances")
	check(invalid == 0,label+": every retained native GPU timestamp is finite and positive")
	check(primitives.min() > 0 if enabled else primitives.max() == 0,label+": expected directional shadow submission")
	check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,label+": uncapped and VSync off")
	rows.append({"label":label,"mode":mode,"shadows":enabled,"sample_frames":sample_frames,"warmup_frames":64,
		"shadow_primitives":distribution(primitives),"shadow_draws":distribution(draws),
		"visible_primitives":distribution(visible_primitives),"visible_draws":distribution(visible_draws),
		"viewport_cpu_ms":distribution(cpu),"viewport_gpu_ms":distribution(gpu),"frame_wall_ms":distribution(wall),
		"invalid_gpu_samples":invalid,"drawn_frames":Engine.get_frames_drawn()-start})
	print("DIRECTIONAL_STABILITY_ROW ",JSON.stringify(rows.back()))

func trace(mode: String, enabled: bool) -> void:
	shadow_state(enabled); scene_at(mode,0)
	await settle(32)
	var frames := []
	for i in TRACE_STEPS:
		var seconds := i*TRACE_DT
		scene_at(mode,seconds)
		await settle(2)
		var label := "%s-%s-%02d" % [mode,"on" if enabled else "off",i]
		image_now(label)
		var counters := frame_counters()
		frames.append({"filename":captured.back(),"trace_seconds":seconds,
			"hour":BASE_HOUR+seconds/CampaignState.HOUR_SECONDS if mode == "clock" else BASE_HOUR,
			"camera_transform":str(camera.transform),"sun_basis":str(sun.basis),"counters":counters})
	trace_rows.append({"mode":mode,"shadows":enabled,"frames":frames})
	check(frames.size() == TRACE_STEPS,"complete "+mode+(" on" if enabled else " off")+" image trace")

func setup() -> bool:
	map_name = "bz13h"
	view = SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	Gfx.apply_quality(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	world = GameWorld.new(); world.process_mode = Node.PROCESS_MODE_DISABLED; view.add_child(world)
	check(world.load_map(map_name,map_name,false),"original map loads")
	if world.map == null: return false
	world.zone = CampaignMap.load_from(GameData.texts).zone_by_map(map_name)
	check(not world.zone.is_empty() and String(world.zone.get("sky","")) != "cave","authored outdoor zone metadata")
	if world.zone.is_empty() or String(world.zone.get("sky","")) == "cave": return false
	var focus := Vector3(88,world.terrain.height_at(88,56),-56)
	camera = Camera3D.new(); camera.near = Gfx.NEAR_CLIP; camera.far = Gfx.far_clip(); camera.fov = CameraRig.MODERN_FOV
	view.add_child(camera); camera.position = focus+Vector3(24,22,28); camera.look_at(focus+Vector3.UP*2); camera.current = true
	camera_start = camera.transform
	game = Game.new()
	game._setup_env() # The actual desktop bias, blend, blur, caster mask and aiming policy.
	# The dummy Game is deliberately not in the tree; preserve local state.
	for child: Node in game.get_children(): child.reparent(view,false)
	sun = game._sun
	game._env.background_mode = Environment.BG_COLOR
	game._env.background_color = Color(0.15,0.15,0.15)
	game._env.sky = null
	Gfx.fit_shadows(sun,world.terrain.size_ei())
	lights = EILights.load_for(String(world.zone.get("allod",EILights.allod_of(map_name))).capitalize(),false)
	check(lights != null,"authored allod light data loads")
	check(game.sun_aim_mode == 1,"desktop sun remains continuous")
	check(sun.shadow_enabled,"production sun casts shadows")
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector3.ZERO)
	scene_at("held",0)
	return lights != null

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("DIRECTIONAL_STABILITY requires a desktop renderer"); get_tree().quit(2); return
	for key: String in GameData.options:
		if key.begins_with("gfx_"): GameData.options[key] = 0
	GameData.options.merge({"q_shadows":1,"q_shadow_fit":1,"q_aa":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"auto_graphics":0},true)
	Gfx.ensure_globals(); EIFigure.set_wind(false)
	Engine.max_fps = 0; Engine.time_scale = 0.0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true)
	if not setup(): get_tree().quit(1); return
	await settle(180)
	initial_image = image_now("held-first")
	await settle(32)
	held_exact = initial_image.get_data() == image_now("held-last").get_data()
	check(held_exact,"stationary camera/clock produces exact held pixels")
	for enabled: bool in [true,false,false,true]:
		await timed("held-"+("on" if enabled else "off")+"-"+str(rows.size()),enabled)
	await timed("slow-pan-on",true,"pan")
	await timed("clock-on",true,"clock")
	for mode: String in ["pan","clock"]:
		for enabled: bool in [true,false]: await trace(mode,enabled)
	shadow_state(true); scene_at("held",0)
	await settle(64)
	final_exact = initial_image.get_data() == image_now("restored").get_data()
	check(final_exact,"returning camera/clock/shadow state restores exact pixels")
	var report := {"checks":checks,"failures":failures,"map":map_name,"zone":world.zone.get("id",""),
		"zone_sky":world.zone.get("sky",""),"allod":world.zone.get("allod",""),
		"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),
		"viewport":str(view.size),"camera_start":str(camera_start),"fov":camera.fov,"near":camera.near,"far":camera.far,
		"base_hour":BASE_HOUR,"hour_seconds":CampaignState.HOUR_SECONDS,"continuous_aim":game.sun_aim_mode,
		"grid_roll":game.sun_grid_lock,"atlas":4096,"depth_bits":16,"q_shadows":1,"shadow_fit":1,
		"shadow_distance":sun.directional_shadow_max_distance,
		"splits":[sun.directional_shadow_split_1,sun.directional_shadow_split_2,sun.directional_shadow_split_3],
		"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"blur":sun.shadow_blur,"blend":sun.directional_shadow_blend_splits,
		"caster_mask":sun.shadow_caster_mask,"wind":false,"units":false,"optional_fx":false,"simulation":false,
		"normal_loop":true,"held_exact":held_exact,"restored_exact":final_exact,"timed_rows":rows,"traces":trace_rows,
		"trace_steps":TRACE_STEPS,"trace_dt":TRACE_DT,"pan_m_per_second":PAN_SPEED,"timed_motion_dt":1.0/60.0,
		"captures":captured,"production_changed":false,"cache_implemented":false,
		"limits":"Whole-viewport enabled/disabled timing is not isolated depth-map cost or measured cache savings. Logical camera/clock steps are replayed through normal rendered frames; screenshot capture time is excluded from timing rows. Camera motion and legitimate sunlight changes also change pixels; temporal deltas alone do not prove objectionable shimmer. No held/snapped policy comparison, target-device result, or projection change."}
	FileAccess.open("user://directional-shadow-stability.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("DIRECTIONAL_STABILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"held_exact":held_exact,"restored_exact":final_exact,"captures":captured.size()}))
	game.free(); view.free(); TexUpscale.shutdown()
	await settle(12)
	get_tree().quit(1 if failures else 0)
