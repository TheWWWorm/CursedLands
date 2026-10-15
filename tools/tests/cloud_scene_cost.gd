extends Node
## Matched 4K full-scene cloud consumers, with presentation excluded.
var s: Session
var g: Game
var t: EITerrain
var rows := []
var cfg := {"seconds":5.0,"samples":240,"settle":5.0,"angles":["overhead","low"],"width":3840,"height":2160}
var scene_view: SubViewport
var render_camera: Camera3D
var camera_pose: Transform3D
var view_angle := ""
var live := false
var cloud_clock := 0.0
var clouds: RefCounted
const Clouds = preload("res://src/game/fx/clouds.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	run.call_deferred()

func _process(_dt: float) -> void:
	if scene_view == null: RenderingServer.force_draw(false)

func frames(n := 1) -> void:
	for i in n:
		if live and t:
			if cfg.has("sweep"):
				var phase:=(cloud_clock-420.0)*TAU/float(cfg.get("sweep_seconds",8.0))
				render_camera.global_position=camera_pose.origin-Vector3.RIGHT*(.5-.5*cos(phase))*float(cfg.sweep)
				if view_angle=="first":render_camera.global_position.y=t.height_at(render_camera.global_position.x,-render_camera.global_position.z)+1.6
			t._waves.advance(1.0 / 60.0)
			t._update_wave_parameters()
			g._sky_spin+=EISky.SPIN_PER_SECOND/60.0
			g._update_daylight(false)
			cloud_clock+=1.0/60.0
			publish_clouds()
		await get_tree().process_frame

func publish_clouds() -> void:
	if Clouds.mode()>0:
		Gfx.set_cloud_frame(t.get_instance_id(),clouds.sample(cloud_clock,t.map_name,String(g.world.zone.get("allod","Gipat")),Vector4(.8,.6,.8,1),float(cfg.get("rain",0.0)),0,12,false))

func distribution(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for v: float in values: total += v
	return {"mean":total/values.size(),"p50":values[values.size()/2],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back()}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--config="): cfg.merge(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--config="))),true)
	GameData.options.merge(GfxPresets.values(7),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"control_mode":0},true)
	GameData.options.merge(cfg.get("options",{}),true)
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	s=Session.new();get_parent().add_child(s)
	g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	if cfg.has("save"):
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		var file:=FileAccess.open(SaveInfo.path("cloud-cost"),FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(cfg.save));file.close()
		if not await s.load_game_shown("cloud-cost"):printerr("LOAD FAILED");get_tree().quit(1);return
	else:
		s.state.ensure_hero(0,s._hero_proto(0))
		await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);g.set_process(false);g.world.set_process(false);g.world.set_physics_process(false)
	g.world.vm.briefings._check=INF;g.hud.process_mode=Node.PROCESS_MODE_DISABLED;g.hud.hide();g.rig.set_process(false)
	g.direct.set_process(false)
	t=g.world.terrain;t.set_process(false)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(800,450)
	get_viewport().disable_3d=true
	scene_view=SubViewport.new();scene_view.size=Vector2i(cfg.width,cfg.height)
	scene_view.own_world_3d=true;scene_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	scene_view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(scene_view)
	if s.local_host and s.local_host.frontend:await s.local_host.stop()
	s.reparent(scene_view);g.reparent(scene_view)
	render_camera=g.rig.camera;render_camera.current=true
	Gfx.apply_quality(scene_view)
	RenderingServer.set_render_loop_enabled(true)
	Engine.max_fps=0
	s.state.world_time=12;g._update_daylight(false)
	RenderingServer.viewport_set_measure_render_time(scene_view.get_viewport_rid(),true)
	Engine.time_scale=1.0 if cfg.get("live_effects",false) else 0.0
	var camera:=g.rig.camera
	var at:=Vector2(159.5,12.5)
	if cfg.has("save"): at=s.party_units(0)[0].pos
	if cfg.has("at"): at=Vector2(cfg.at[0],cfg.at[1])
	var level:=t.water_at(at.x,at.y)
	if not is_finite(level):level=t.height_at(at.x,at.y)
	var focus:=Vector3(at.x,level,-at.y)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	var base:=GameData.options.duplicate(true)
	var profiler=load("res://pan_profile.gd") if ResourceLoader.exists("res://pan_profile.gd") else null
	for angle: String in cfg.angles:
		camera.global_position=focus+(Vector3(-8,16,-12) if angle=="overhead" else Vector3(4,5,8))
		camera.look_at(focus)
		if angle=="first":
			camera.global_position=focus+Vector3(0,1.6,0);camera.look_at(focus+Vector3(-30,1.6,0))
		view_angle=angle;camera_pose=camera.global_transform
		var pose:=camera.global_transform
		for effects: Array in cfg.get("cases",[[0,0,0],[3,0,0],[3,1,0],[3,0,1],[3,1,1],[0,0,0]]):
			live=false
			t._waves.ticks=1;t._waves.acc=0.0;t._waves.phase=6.2831854820251465;t._waves.set_wind(Vector3(0,0,1),0.4)
			cloud_clock=420.0;clouds=Clouds.new();g._sky_spin=0.0
			GameData.options=base.duplicate(true)
			GameData.options.merge({"gfx_clouds":effects[0],"gfx_cloud_shadows":effects[1],"gfx_cloud_reflections":effects[2]},true)
			g._apply_options();t.apply_gfx();t._update_cloud_parameters();g._update_daylight(false)
			camera.global_transform=pose
			render_camera.global_transform=pose
			Engine.max_fps=0
			await frames(4)
			t._update_cloud_parameters();g._update_daylight(false)
			publish_clouds()
			var field_view=Gfx._cloud_shadow_field.view if Gfx._cloud_shadow_field else null
			var reflection=t.get("_cloud_reflection")
			if field_view:RenderingServer.viewport_set_measure_render_time(field_view.get_viewport_rid(),true)
			if reflection and reflection.viewport:RenderingServer.viewport_set_measure_render_time(reflection.viewport.get_viewport_rid(),true)
			var deadline:=Time.get_ticks_msec()+int(float(cfg.settle)*1000)
			while Time.get_ticks_msec()<deadline:await frames()
			live=true
			if profiler:profiler.clear()
			var drawn_before:=Engine.get_frames_drawn()
			var before:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
			var wall:=[];var stalls:=[];var start:=Time.get_ticks_usec();var previous:=start
			while wall.size()<int(cfg.samples):
				await frames()
				var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				if wall.back()>20.0:stalls.append({"frame":Engine.get_process_frames(),"ms":wall.back(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
			live=false
			var cache: Node=t.get("_cloud_reflection")
			var field=Gfx._cloud_shadow_field
			var drawn:=Engine.get_frames_drawn()-drawn_before
			var root_gpu:=[];var shadow_gpu:=[];var reflection_gpu:=[]
			live=true
			for i in 40:
				await frames()
				root_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(scene_view.get_viewport_rid()))
				if field:shadow_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(field.view.get_viewport_rid()))
				if cache and cache.viewport:reflection_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(cache.viewport.get_viewport_rid()))
			live=false
			var row:={"gpu_samples":distribution(root_gpu),"shadow_gpu_samples":distribution(shadow_gpu) if not shadow_gpu.is_empty() else {},"reflection_gpu_samples":distribution(reflection_gpu) if not reflection_gpu.is_empty() else {},"angle":angle,"effects":effects,"fps_limit":Engine.max_fps,"drawn":drawn,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(scene_view.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(scene_view.get_viewport_rid()),"frame_ms":distribution(wall),"frames":wall.size(),"pipelines":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)-before,"cloud_frame":str(Gfx._cloud_frame),"sun":str(Gfx._cloud_sun_direction),"camera":str(camera.global_transform),"size":str(scene_view.size),"cache_ready":bool(t._water_mat.get_shader_parameter("cloud_reflection_ready")) if effects[2] else false,"field_ready":field!=null and field._published,"field_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(field.view.get_viewport_rid()) if field else 0.0,"reflection_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(cache.viewport.get_viewport_rid()) if cache and cache.viewport else 0.0,"cache_size":str(cache.viewport.size) if cache and cache.viewport else "none"}
			row.stalls=stalls
			if profiler:row.profile=profiler.snapshot()
			rows.append(row);print("CLOUD_COST ",JSON.stringify(row))
			scene_view.get_texture().get_image().save_png("user://cloud-cost-%02d.png"%rows.size())
			if cache and cache.viewport: cache.viewport.get_texture().get_image().save_png("user://cloud-cache-%02d.png"%rows.size())
	FileAccess.open("user://cloud-cost.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"config":cfg,"adapter":RenderingServer.get_video_adapter_name(),"options":base},"\t"))
	if s.local_host and s.local_host.frontend:await s.local_host.stop()
	g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown();get_tree().quit()
