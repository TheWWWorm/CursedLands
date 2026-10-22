extends "res://tools/tests/path_trace_performance.gd"
## Matched campaign captures or interleaved timings of the previous/current
## display and flame-size profiles. Geometry, materials and ray budgets agree.
var history_control := OS.get_cmdline_user_args().has("--pt-history-bench")
var benchmark := OS.get_cmdline_user_args().has("--pt-lighting-bench") or history_control
func image_stats(image: Image) -> Dictionary:
	var clipped:=0;var dark:=0;var total:=0;var luminance:=0.0
	for y in range(80,image.get_height(),3):
		for x in range(0,image.get_width(),3):
			var c:=image.get_pixel(x,y);var high:=maxf(c.r,maxf(c.g,c.b))
			clipped+=int(high>=0.995);dark+=int(high<0.03);total+=1
			luminance+=c.r*0.2126+c.g*0.7152+c.b*0.0722
	return {"clipped":float(clipped)/total,"dark":float(dark)/total,"display_luminance":luminance/total}

func compare_view(game: Game, label: String) -> void:
	if benchmark and label not in ["river-12","brazier"]:return
	if history_control and label!="brazier":return
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"lighting comparison prepares "+label)
	if not rt.stats.get("active",false):return
	var sources:=[]
	for node: Node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		if node.has_meta(LocalLighting.PATH_SOURCE_RADIUS):sources.append([node,node.get_meta(LocalLighting.PATH_SOURCE_RADIUS)])
	if benchmark:
		await measure_view(game,label,sources)
		return
	var images:=[];var metrics:=[]
	for current in [false,true]:
		select_profile(game,sources,current)
		rt._history_key="";rt._path_signature=PackedByteArray();rt._frame_number=300
		await frames(160)
		var image:=await capture(label+("-current" if current else "-previous"));var row:=image_stats(image)
		images.append(image);metrics.append(row)
		row.merge({"view":label,"current":current,"camera":str(camera.global_transform),
			"sun":str(Gfx.sun),"ambient":str(Gfx.ambient),"sky":str(Gfx.fog_sky),"history":rt.stats.accumulation_frames,
			"ui_pixel":str(image.get_pixel(25,25))});rows.append(row)
	check(images[0].get_size()==Vector2i(1280,720) and images[1].get_size()==Vector2i(1280,720),label+": matched 720p output")
	check(images[0].get_pixel(25,25)==images[1].get_pixel(25,25),label+": Canvas UI remains unchanged")
	check(metrics[1].display_luminance>metrics[0].display_luminance*0.9 and metrics[1].display_luminance<metrics[0].display_luminance*1.25,
		label+": display brightness remains within the calibrated palette envelope")
	if label=="brazier":
		check(metrics[0].clipped>0.001 and metrics[1].clipped<metrics[0].clipped*0.25,"flame highlight clipping is reduced")
		check(mean_difference(images[0],images[1])>0.002,"authored lighting visibly changes the original cave")

func select_profile(game: Game,sources: Array,current: bool) -> void:
	if history_control:
		game.get_node("SceneRaytrace")._strict_light_history=not current
		Gfx.apply_env(game._env)
		return
	for source: Array in sources:source[0].set_meta(LocalLighting.PATH_SOURCE_RADIUS,source[1] if current else 0.0)
	Gfx.apply_env(game._env)
	if not current:
		game._env.tonemap_mode=Environment.TONE_MAPPER_LINEAR;game._env.tonemap_exposure=1.0

func measure_view(game: Game,label: String,sources: Array) -> void:
	var rt: Node=game.get_node("SceneRaytrace");var device: Object=rt.device
	GameData.options.pt_accumulation=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	# Let the real flame controller run in both cases, including its bounded
	# responsive history. Particle motion stays frozen for matched workloads.
	var local: LocalLighting=game.get_node("LocalLighting");local.set_process(label=="brazier")
	var cases:=[[1,false],[1,true],[2,true],[2,false]]
	for round_index in 4:
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.q_rt_lighting=choice[0];select_profile(game,sources,choice[1]);local._time=0
			await frames(40)
			check(rt.device==device,"profile comparison retains scene and path tracer")
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec();var started:=Time.get_unix_time_from_system()
			for i in 120:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var row:={"view":label,"round":round_index,"quality":choice[0],"current":choice[1],"frame_ms":summary(wall),
				"main_gpu_ms":summary(main_gpu),"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
				"controller_cpu_ms":summary(cpu_samples.duplicate()),"start_unix":started,"end_unix":Time.get_unix_time_from_system(),"stats":rt.stats.duplicate()}
			rows.append(row);print("LIGHTING_BENCH ",JSON.stringify(row));save_report()
	before.queue_free();local.set_process(false);select_profile(game,sources,true)

func save_report() -> void:
	FileAccess.open(out.path_join("path-lighting-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,
		"benchmark":benchmark,"history_control":history_control,"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"viewport":[1280,720],
		"note":"Original campaign geometry/materials and cave fill retained. Static particles; flame flutter enabled in both benchmark profiles. Four bounces, identical quality within each pair; no readbacks while timing. Main viewport GPU excludes the separate RT dispatch."},"\t"))

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	get_window().min_size=Vector2i(1,1);get_window().borderless=true;get_window().size=Vector2i(1280,720);await frames(4)
	game.set_process_input(false);game.set_process_unhandled_input(false)
	for child in game.get_children():
		if child is FxRainSnow:child.process_mode=Node.PROCESS_MODE_DISABLED;child.hide()
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"gfx_firelight":1,"character_light":1,"pt_mode":2,"pt_accumulation":1,"q_rt_lighting":1},true)
	var layer:=CanvasLayer.new();layer.layer=300;add_child(layer)
	var swatch:=ColorRect.new();swatch.position=Vector2(10,10);swatch.size=Vector2(32,32);swatch.color=Color(0.5,0.3,0.2);layer.add_child(swatch)
	game.get_node("LocalLighting").set_process(false)
	game.get_node("LocalLighting").apply_options();game.get_node("LocalLighting")._process(0)
	t.apply_gfx();Gfx.apply_env(game._env)
	for hour in [12.0,18.0,0.0]:
		session.state.world_time=hour;game._update_daylight(false)
		await compare_view(game,"river-"+str(int(hour)))
	var tree: Node3D=session.world.objects[4442]
	camera.global_position=tree.global_position+Vector3(5,1.7,8);camera.look_at(tree.global_position+Vector3.UP*4.5)
	session.state.world_time=12.0;game._update_daylight(false)
	await compare_view(game,"grove")
	session._enter_zone("gz14k",1,false);t=session.world.terrain
	session.set_physics_process(false);session.world.set_process(false);session.world.set_physics_process(false);session.world.vm.instances.clear()
	game.set_process(false);game._update_daylight(false);game.rig.set_process(false);game.direct.set_process(false)
	for unit: GameUnit in session.world.units.values():unit.hide();unit.set_process(false);unit.set_physics_process(false)
	var local: LocalLighting=game.get_node("LocalLighting");local.apply_options();local._process(0)
	var fx:=session.world.get_node("ParticleFx") as ParticleFx;fx.set_process(false)
	var lights:=fx.lights.filter(func(d: Dictionary)->bool:return d.get("kind","")=="fire")
	lights.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return Vector2(a.light.global_position.x-179.9853,a.light.global_position.z+43.2999).length_squared()<Vector2(b.light.global_position.x-179.9853,b.light.global_position.z+43.2999).length_squared())
	check(not lights.is_empty(),"comparison uses an original cave brazier")
	if not lights.is_empty():
		var center: Vector3=lights[0].light.global_position
		camera.global_position=center+Vector3(3.5,2,4.5);camera.look_at(center-Vector3.UP*0.7);camera.fov=55
		for i in 60:fx._process(1.0/60.0)
		get_window().borderless=true;get_window().size=Vector2i(1280,720)
		t.apply_gfx();Gfx.apply_env(game._env)
		await compare_view(game,"brazier")
	save_report()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
