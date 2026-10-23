extends Node
## Matched live settings, camera and clock for cloud-reflection visibility
## and GPU cost. Uses a complete original scene, not a standalone shader.
var rows := []
var failures := 0
var moving_terrain: EITerrain
var update_times := []
var live := "--live-clouds" in OS.get_cmdline_user_args()

func frames(n := 12) -> void:
	for i in n:
		if live and is_instance_valid(moving_terrain):
			moving_terrain._waves.advance(1.0/60.0);moving_terrain._update_wave_parameters()
			var begin:=Time.get_ticks_usec()
			moving_terrain._update_cloud_parameters()
			update_times.append((Time.get_ticks_usec()-begin)/1000.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func stats(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*.95)],"max":values[-1]}

func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",label)

func cache_lifecycle(t: EITerrain, camera: Camera3D, game: Game) -> void:
	live=false
	GameData.options.gfx_cloud_reflections=1;game._apply_options();t.apply_gfx();t._update_cloud_parameters();game._update_daylight(false)
	await frames(8)
	var cache: Node=t.get("_cloud_reflection")
	check(cache!=null and cache.viewport!=null,"cached reflection allocated")
	if cache==null or cache.viewport==null:return
	check(cache.camera.environment.sky!=game._env.sky,"reflection owns a separate sky history")
	check(cache.camera.environment.sky.radiance_size==Sky.RADIANCE_SIZE_32,"unused reflection radiance stays at minimum size")
	var reflected_sky:ShaderMaterial=cache.camera.environment.sky.sky_material
	check(not reflected_sky.get_shader_parameter("sky_radiance") and not reflected_sky.get_shader_parameter("cloud_radiance"),"reflection sky excludes unused radiance")
	var aim_mode:=game.sun_aim_mode
	game.sun_aim_mode=0;game._update_daylight(false)
	check(Gfx._cloud_sun_direction.is_equal_approx(game.sun_light_dir),"held game shadow aiming publishes the actual clock direction to cloud caches")
	game.sun_aim_mode=aim_mode;game._update_daylight(false);await frames(4)
	var held: Image=cache.viewport.get_texture().get_image()
	await frames(8)
	# The Node getter retains UPDATE_ONCE after the render server consumes it.
	# An unannounced shader-global change must not redraw the cached image.
	RenderingServer.global_shader_parameter_set(&"ei_flash",Vector3(1,0,0));await frames(3)
	check(cache.viewport.get_texture().get_image().get_data()==held.get_data(),"held sky is reused without rendering")
	check(cache.viewport.get_texture().get_image().get_data()==held.get_data(),"held reflection pixels are stable")
	Gfx.set_lightning_flash(1);await frames(4)
	check(cache.viewport.get_texture().get_image().get_data()!=held.get_data(),"lightning refreshes reflection during held time")
	Gfx.set_lightning_flash(0);await frames(4)
	check(cache.viewport.get_texture().get_image().get_data()==held.get_data(),"lightning removal restores reflection")
	var pose:=camera.global_transform
	camera.rotate_y(.12);await frames(4)
	check(cache.viewport.get_texture().get_image().get_data()!=held.get_data(),"paused camera rotation refreshes reflection")
	camera.global_transform=pose;await frames(4)
	check(cache.viewport.get_texture().get_image().get_data()==held.get_data(),"restored camera restores reflection")
	t.hide();await frames(3)
	check(not t._water_mat.get_shader_parameter("cloud_reflection_ready") and cache.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"hidden terrain suspends reflection")
	t.show();await frames(3)
	check(bool(t._water_mat.get_shader_parameter("cloud_reflection_ready")),"visible terrain resumes reflection")
	Gfx._cloud_owner=game.get_instance_id();await frames(3)
	check(not t._water_mat.get_shader_parameter("cloud_reflection_ready"),"inactive world does not render cached sky")
	t._update_cloud_parameters();await frames(3)
	check(bool(t._water_mat.get_shader_parameter("cloud_reflection_ready")),"active world resumes cached sky")
	camera.global_position+=Vector3(5000,0,5000)
	var until:=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<until:await frames(1)
	check(not t._water_mat.get_shader_parameter("cloud_reflection_ready"),"no visible water suspends sky view")
	camera.global_transform=pose
	until=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<until:await frames(1)
	check(bool(t._water_mat.get_shader_parameter("cloud_reflection_ready")),"return to water resumes sky view")
	var gone: WeakRef = weakref(cache.viewport)
	GameData.options.gfx_cloud_reflections=0;game._apply_options();t.apply_gfx();await frames(4)
	check(t.get("_cloud_reflection")==null and gone.get_ref()==null,"option disable releases the reflection viewport")

func _ready() -> void: run.call_deferred()
func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"q_aa":0,"vsync":0,"fps_limit":0,"gfx_water_reflections":0,"gfx_clouds":3,"gfx_cloud_reflections":0,"gfx_cloud_shadows":0},true)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(1920,1080)
	Engine.max_fps=0;RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0))
	var interior := "--interior" in OS.get_cmdline_user_args()
	await s.enter_zone("gz2g" if interior else "gz1g",1,false)
	s.set_physics_process(false);g.set_process(false);g.world.set_process(false);g.world.set_physics_process(false)
	g.world.vm.briefings._check=INF;g.hud.process_mode=Node.PROCESS_MODE_DISABLED;g.hud.hide();g.rig.set_process(false)
	var t:=g.world.terrain;t.set_process(false);moving_terrain=t
	t._waves.advance(120);t._update_wave_parameters();t._update_cloud_parameters()
	s.state.world_time=12;g._update_daylight(false)
	Engine.time_scale=0.0
	var camera:=g.rig.camera
	var at:=Vector2(87.5,83.5) if interior else Vector2(159.5,12.5)
	var focus:=Vector3(at.x,t.water_at(at.x,at.y),-at.y)
	camera.global_position=focus+Vector3(4,5,8);camera.look_at(focus)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	for angle: String in ([] if "--lifecycle-only" in OS.get_cmdline_user_args() else ["overhead","low"]):
		camera.global_position=focus+(Vector3(-8,16,-12) if angle=="overhead" else Vector3(4,5,8));camera.look_at(focus)
		g._update_daylight(false)
		var off: Image
		for effects: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(0,0)]:
			GameData.options.gfx_cloud_reflections=effects.x;GameData.options.gfx_cloud_shadows=effects.y
			g._apply_options();t.apply_gfx();t._update_cloud_parameters();g._update_daylight(false)
			# The field attaches deferred during option changes, then publishes on the next update.
			await frames(4)
			t._update_cloud_parameters();g._update_daylight(false)
			var shadow_times:=[];var reflection_times:=[]
			var field: SubViewport=Gfx._cloud_shadow_field.view if Gfx._cloud_shadow_field else null
			if field:RenderingServer.viewport_set_measure_render_time(field.get_viewport_rid(),true)
			var cache: Node=t.get("_cloud_reflection") if "--inspect-cache" in OS.get_cmdline_user_args() else null
			if cache and cache.viewport:RenderingServer.viewport_set_measure_render_time(cache.viewport.get_viewport_rid(),true)
			# Full-scene shader toggles compile many driver variants asynchronously.
			# Exclude that transient work from steady-state cloud timing.
			var moving := live;live=false
			var warm_until:=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<warm_until:await frames(1)
			live=moving
			await frames(90)
			var pipelines_before:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
			var gpu:=[];var wall:=[];var render_cpu:=[];update_times.clear();var previous:=Time.get_ticks_usec()
			var first_frame:=Engine.get_frames_drawn()
			for i in 240:
				if live:
					t._waves.advance(1.0/60.0);t._update_wave_parameters()
					var begin:=Time.get_ticks_usec();t._update_cloud_parameters();update_times.append((Time.get_ticks_usec()-begin)/1000.0)
				await get_tree().process_frame
				var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			# Render-server getters synchronize a separate rendering thread. Query
			# only after the wall-time sample, never serially inside its frame loop.
			var drawn:=Engine.get_frames_drawn()-first_frame
			await RenderingServer.frame_post_draw
			if field:shadow_times.append(RenderingServer.viewport_get_measured_render_time_gpu(field.get_viewport_rid()))
			if cache and cache.viewport:reflection_times.append(RenderingServer.viewport_get_measured_render_time_gpu(cache.viewport.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			var picture:=get_viewport().get_texture().get_image()
			if effects.y and (Gfx._cloud_shadow_field==null or not Gfx._cloud_shadow_field._published): failures+=1
			if "--inspect-cache" in OS.get_cmdline_user_args() and effects.x:
				if cache==null or cache.viewport==null or not t._water_mat.get_shader_parameter("cloud_reflection_ready"):
					failures+=1
				else:
					if maxi(cache.viewport.size.x,cache.viewport.size.y)>256:failures+=1
					cache.viewport.get_texture().get_image().save_png("user://cache-"+angle+"-"+str(rows.size())+".png")
			var label:="cloud-water-"+angle+"-"+str(rows.size())+"-"+str(effects)
			picture.save_png("user://"+label+".png")
			var changed:=0;var peak:=0.0
			if off:
				for y in picture.get_height():
					for x in picture.get_width():
						var a:=picture.get_pixel(x,y);var b:=off.get_pixel(x,y)
						var d:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))*255
						changed+=int(d>2);peak=maxf(peak,d)
			else:off=picture
			rows.append({"frames_drawn":drawn,"gpu_timing_scope":"last completed frame, queried outside pacing sample","new_pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)-pipelines_before,"live_clouds":live,"angle":angle,"cloud_reflections":effects.x,"cloud_shadows":effects.y,"gpu_ms":stats(gpu),"shadow_gpu_ms":stats(shadow_times) if not shadow_times.is_empty() else {},"reflection_gpu_ms":stats(reflection_times) if not reflection_times.is_empty() else {},"frame_ms":stats(wall),"update_ms":stats(update_times) if not update_times.is_empty() else {},"render_cpu_ms":stats(render_cpu),"pixels_over_2":changed,"peak_bytes":peak,"size":str(picture.get_size()),"cloud_state":str(Gfx._cloud_frame.state),"renderer":RenderingServer.get_current_rendering_method()})
			print("CLOUD_REFLECTION_SCENE ",JSON.stringify(rows[-1]))
	if "--lifecycle" in OS.get_cmdline_user_args(): await cache_lifecycle(t,camera,g)
	FileAccess.open("user://cloud-reflection-scene.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"\t"))
	g.queue_free();s.queue_free();await frames(2);TexUpscale.shutdown();get_tree().quit(int(failures>0))
