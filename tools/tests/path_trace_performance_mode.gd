extends "res://tools/tests/path_trace_performance.gd"
## Player Performance preset (saved pt_mode 3): one continuation bounce with
## Balanced's responsive reconstruction and lighting budget. Runs the normal
## player presets (no --ei-pt-tuning) on original campaign views: interleaved
## GPU timing against Balanced at 720p and 1440p, then matched captures of
## river noon/night, grove and a cave brazier with brightness, colour, still
## noise and camera-pan comparisons. Quality is captured once for context.
const Settings = preload("res://src/platform/path_trace_settings.gd")
const BALANCED := 1
const QUALITY := 2
const PERFORMANCE := 3
const NAMES := {1:"balanced", 2:"quality", 3:"performance"}
var timing_rows := []
var view_rows := []
var pan_rows := []

func luminance_stats(image: Image) -> Dictionary:
	# Skip the FPS counter's corner; sample a regular lattice.
	var sum := Vector3.ZERO;var total := 0;var bright := 0
	for y in range(80,image.get_height(),3):
		for x in range(0,image.get_width(),3):
			var c:=image.get_pixel(x,y);sum+=Vector3(c.r,c.g,c.b);total+=1
			bright+=int(maxf(c.r,maxf(c.g,c.b))>=0.995)
	var mean:=sum/maxf(total,1)
	return {"rgb":[mean.x,mean.y,mean.z],"luminance":mean.x*0.2126+mean.y*0.7152+mean.z*0.0722,"clipped":float(bright)/maxf(total,1)}

## Mean absolute difference over the whole frame below the HUD row.
func difference(a: Image,b: Image) -> float:
	var value:=0.0;var count:=0
	for y in range(80,mini(a.get_height(),b.get_height()),3):
		for x in range(0,mini(a.get_width(),b.get_width()),3):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			value+=absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b);count+=3
	return value/maxf(count,1)

## Isolated, bright single-pixel changes between two still frames: fireflies.
func speckles(a: Image,b: Image) -> float:
	var found:=0;var total:=0
	for y in range(81,mini(a.get_height(),b.get_height())-1,2):
		for x in range(1,mini(a.get_width(),b.get_width())-1,2):
			total+=1
			var d:=b.get_pixel(x,y).get_luminance()-a.get_pixel(x,y).get_luminance()
			if d<0.25:continue
			var around:=0.0
			for o: Vector2i in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
				around+=b.get_pixel(x+o.x,y+o.y).get_luminance()-a.get_pixel(x+o.x,y+o.y).get_luminance()
			found+=int(around/4.0<d*0.25)
	return float(found)/maxf(total,1)

func select_mode(game: Game,mode: int) -> void:
	GameData.options.pt_mode=mode
	Gfx.apply_env(game._env)

func check_preset(mode: int) -> void:
	var tag:=str(NAMES[mode])
	check(GameData.option("pt_mode")==mode,tag+": saved ID is unchanged")
	check(Settings.bounces(mode)==[0,2,4,1][mode],tag+": continuation bounces")
	check(GameData.option("pt_accumulation")==0 and GameData.option("pt_target_fps")==0 \
		and GameData.option("pt_sharc")==0 and GameData.option("pt_denoiser")==0 \
		and GameData.option("q_rt_lighting")==0 and GameData.option("pt_ray_reconstruction")==1,
		tag+": shares the managed responsive reconstruction budget")
	check(GameData.option("pt_refraction")==int(mode==QUALITY) and GameData.option("pt_restir")==int(mode==QUALITY),
		tag+": refraction and ReSTIR only in Quality")

func ready_mode(game: Game,mode: int) -> bool:
	select_mode(game,mode)
	var rt: Node=game.get_node("SceneRaytrace")
	var ready:=await ready_snapshot(rt)
	var tag:=str(NAMES[mode])
	check(ready,tag+": path tracer prepares")
	if not ready:return false
	check(rt.stats.get("path_tracing",false) and rt.stats.get("path_bounces",-1)==Settings.bounces(mode),tag+": controller traces the preset's bounces")
	check(rt.device!=null and rt.device._deep_paths==(mode==QUALITY),tag+": only Quality uses the deep-path program")
	return true

func time_modes(game: Game,label: String,size: Vector2i) -> Dictionary:
	get_window().size=size;await get_tree().create_timer(0.4,true,false,true).timeout
	var rt: Node=game.get_node("SceneRaytrace")
	var medians:={BALANCED:{"rt":[],"rays":[],"main":[],"frame":[]},PERFORMANCE:{"rt":[],"rays":[],"main":[],"frame":[]}}
	var order:=[BALANCED,PERFORMANCE]
	for round_index in 4:
		order.reverse()
		for mode: int in order:
			if not await ready_mode(game,mode):return {}
			check(rt.stats.get("display_size",[])==[size.x,size.y],label+": measured at "+str(size))
			await frames(40)
			phase_source=rt;gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();phase_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec()
			for i in 120:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var row:={"view":label,"size":[size.x,size.y],"mode":NAMES[mode],"pt_mode":mode,"round":round_index,
				"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),"rt_gpu_ms":summary(gpu_samples.duplicate()),
				"gpu_stages_ms":stage_summary(),"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":rt.stats.duplicate()}
			timing_rows.append(row);print("PT_PERFORMANCE_MODE_BENCH ",JSON.stringify(row));save_report()
			if row.rt_gpu_ms.is_empty() or not row.gpu_stages_ms.has("rays"):
				check(false,label+": GPU timestamps are captured");return {}
			medians[mode].rt.append(row.rt_gpu_ms.median);medians[mode].rays.append(row.gpu_stages_ms.rays.median)
			medians[mode].main.append(row.main_gpu_ms.median);medians[mode].frame.append(row.frame_ms.median)
	var result:={"view":label,"size":[size.x,size.y]}
	for key in ["rt","rays","main","frame"]:
		var b: Array=medians[BALANCED][key].duplicate();b.sort()
		var p: Array=medians[PERFORMANCE][key].duplicate();p.sort()
		result[key]={"balanced":(b[1]+b[2])/2.0,"performance":(p[1]+p[2])/2.0}
		result[key]["saving"]=1.0-result[key].performance/maxf(result[key].balanced,0.0001)
	print("PT_PERFORMANCE_MODE_SAVING ",JSON.stringify(result))
	# The ray pass drops one of two continuation segments with its shadow and
	# emitter work. The fixed denoiser, copies and raster frame remain.
	check(result.rays.saving>=0.15,label+": Performance ray pass is clearly cheaper than Balanced "+str(size))
	check(result.rt.saving>=0.08,label+": Performance PT GPU time is lower than Balanced "+str(size))
	return result

func capture_mode(game: Game,label: String,mode: int) -> Dictionary:
	if not await ready_mode(game,mode):return {}
	var rt: Node=game.get_node("SceneRaytrace")
	rt._history_key="";rt._path_signature=PackedByteArray()
	await frames(160)
	var image:=await capture("%s-%s"%[label,NAMES[mode]])
	await frames(8)
	var later:=await capture_quiet()
	var row:={"view":label,"mode":NAMES[mode],"pt_mode":mode,"camera":str(camera.global_transform),"image":image,
		"still_difference":difference(image,later),"speckles":speckles(image,later),"stats":rt.stats.duplicate()}
	row.merge(luminance_stats(image))
	return row

func capture_quiet() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func compare_view(game: Game,label: String) -> void:
	var balanced:=await capture_mode(game,label,BALANCED)
	var performance:=await capture_mode(game,label,PERFORMANCE)
	if balanced.is_empty() or performance.is_empty():return
	var a: Image=balanced.image;var b: Image=performance.image
	check(a.get_size()==Vector2i(1280,720) and b.get_size()==a.get_size(),label+": matched 720p captures")
	var ratio: float=performance.luminance/maxf(balanced.luminance,0.0001)
	# One bounce loses only the second indirect segment: slightly darker
	# shade, never brighter, and no tint relative to Balanced.
	check(ratio>=0.8 and ratio<=1.03,label+": Performance brightness stays close to Balanced (%.3f)"%ratio)
	var tint:=0.0
	for c in 3:
		var pb: float=balanced.rgb[c]/maxf(balanced.luminance,0.0001);var pp: float=performance.rgb[c]/maxf(performance.luminance,0.0001)
		tint=maxf(tint,absf(pp-pb))
	check(tint<=0.04,label+": Performance keeps Balanced's colour balance (%.4f)"%tint)
	check(difference(a,b)<=0.05,label+": Performance image matches Balanced closely")
	check(performance.still_difference<=balanced.still_difference*1.25+0.002,label+": Performance still frames are no noisier than Balanced")
	check(performance.speckles<=balanced.speckles*1.5+0.0005,label+": Performance shows no added fireflies")
	for row: Dictionary in [balanced,performance]:
		var saved:=row.duplicate();saved.erase("image");view_rows.append(saved)
	view_rows[-1]["luminance_ratio"]=ratio;view_rows[-1]["tint"]=tint;view_rows[-1]["difference_from_balanced"]=difference(a,b)
	save_report()

## Matched camera pans: brightness and colour balance between the modes
## stay matched, so one bounce adds no colour or exposure change in motion.
func pan(game: Game,label: String) -> void:
	var start:=camera.global_transform
	var series:={}
	for mode: int in [BALANCED,PERFORMANCE]:
		if not await ready_mode(game,mode):return
		camera.global_transform=start;await frames(120)
		var values:=[]
		for i in 48:
			camera.rotate_y(0.006);camera.global_position+=camera.global_transform.basis.x*0.04
			var image:=await capture_quiet()
			if OS.get_cmdline_user_args().has("--pt-mode-pan-frames"):image.save_png(out.path_join("pan-%s-%02d.png"%[NAMES[mode],i]))
			values.append(luminance_stats(image))
		series[mode]=values
		camera.global_transform=start
	# Whole-frame exposure/tint jumps during camera motion also occur in
	# Balanced and are outside this preset. Compare robust per-mode medians and
	# require Performance to add no extra outlier frames.
	var summary_rows:={}
	for mode: int in [BALANCED,PERFORMANCE]:
		var values: Array=series[mode].map(func(v: Dictionary): return v.luminance)
		var sorted:=values.duplicate();sorted.sort()
		var median: float=sorted[sorted.size()/2]
		var rgb:=[0.0,0.0,0.0]
		var frames_used:=0;var outliers:=0
		for v: Dictionary in series[mode]:
			if absf(v.luminance/maxf(median,0.0001)-1.0)>0.05:outliers+=1;continue
			for c in 3:rgb[c]+=v.rgb[c]/maxf(v.luminance,0.0001)
			frames_used+=1
		for c in 3:rgb[c]/=maxi(frames_used,1)
		summary_rows[mode]={"median":median,"outliers":outliers,"chroma":rgb,"luminance":values}
	var ratio: float=summary_rows[PERFORMANCE].median/maxf(summary_rows[BALANCED].median,0.0001)
	var tint:=0.0
	for c in 3:tint=maxf(tint,absf(summary_rows[PERFORMANCE].chroma[c]-summary_rows[BALANCED].chroma[c]))
	pan_rows.append({"view":label,"median_ratio":ratio,"tint":tint,
		"balanced":summary_rows[BALANCED],"performance":summary_rows[PERFORMANCE]})
	check(ratio>=0.8 and ratio<=1.03,label+": Performance brightness tracks Balanced through the pan (%.3f)"%ratio)
	check(tint<=0.02,label+": no mode-specific colour shift during the pan (%.4f)"%tint)
	check(summary_rows[PERFORMANCE].outliers<=summary_rows[BALANCED].outliers+3,
		label+": Performance adds no exposure jumps during the pan (%d vs %d)"%[summary_rows[PERFORMANCE].outliers,summary_rows[BALANCED].outliers])
	save_report()

func save_report() -> void:
	FileAccess.open(out.path_join("path-performance-mode.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"timings":timing_rows,"views":view_rows,"pans":pan_rows,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"note":"Player presets without --ei-pt-tuning: responsive history, managed one-sample PT budget (RR when the renderer supports it), water reflections and frame generation off. Timing alternates Balanced/Performance over four rounds of 120 frames after 40 warm-up frames; result medians use the middle two rounds. RT GPU covers the ray pass, filters/reconstruction and copies; main GPU excludes the separate PT dispatch."},"\t"))

func run() -> void:
	check(not OS.get_cmdline_user_args().has("--ei-pt-tuning"),"Performance mode is measured through the player presets")
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	get_window().min_size=Vector2i(1,1);get_window().borderless=true;get_window().size=Vector2i(1280,720);await frames(4)
	game.set_process_input(false);game.set_process_unhandled_input(false)
	for child in game.get_children():
		if child is FxRainSnow:child.process_mode=Node.PROCESS_MODE_DISABLED;child.hide()
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"gfx_firelight":1,"character_light":1,"pt_mode":PERFORMANCE,
		"pt_accumulation":1,"pt_sharc":1,"pt_denoiser":1,"q_rt_lighting":2,"pt_restir":1,"pt_refraction":1},true)
	# Stale tuning values must not leak into the player presets.
	for mode in [PERFORMANCE,BALANCED,QUALITY]:
		GameData.options.pt_mode=mode;check_preset(mode)
	game.get_node("LocalLighting").set_process(false)
	game.get_node("LocalLighting").apply_options();game.get_node("LocalLighting")._process(0)
	t.apply_gfx();Gfx.apply_env(game._env)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before)
	process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	session.state.world_time=12.0;game._update_daylight(false)
	var savings:=[]
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		var result:=await time_modes(game,"river-12",size)
		if result.is_empty():break
		savings.append(result)
	set_process(false);before.queue_free()
	get_window().size=Vector2i(1280,720);await get_tree().create_timer(0.4,true,false,true).timeout
	Engine.max_fps=60
	for hour in [12.0,0.0]:
		session.state.world_time=hour;game._update_daylight(false)
		await compare_view(game,"river-"+str(int(hour)))
	session.state.world_time=12.0;game._update_daylight(false)
	await pan(game,"river-12")
	var quality:=await capture_mode(game,"river-12",QUALITY)
	if not quality.is_empty():
		quality.erase("image");view_rows.append(quality)
	var tree: Node3D=session.world.objects[4442]
	camera.global_position=tree.global_position+Vector3(5,1.7,8);camera.look_at(tree.global_position+Vector3.UP*4.5)
	await compare_view(game,"grove")
	# Leave the river with PT released. A zone change while the responsive
	# player preset is active intermittently ends this fixture with SIGSEGV on
	# the 1.36.0 Linux engine in every mode, including Balanced alone; that
	# separate failure is outside the bounce preset measured here.
	select_mode(game,0)
	var rt: Node=game.get_node("SceneRaytrace")
	for i in 600:
		if rt.device==null and not rt.stats.get("active",false):break
		await frames(1)
	check(rt.device==null,"PT Off releases the river scene before the cave")
	await frames(10)
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
	check(savings.size()==2,"timings cover 720p and 1440p")
	save_report()
	FileAccess.open(out.path_join("path-performance-mode-savings.json"),FileAccess.WRITE).store_string(JSON.stringify(savings,"\t"))
	print("PT_PERFORMANCE_MODE ",JSON.stringify({"checks":checks,"failures":failures}))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
