extends "res://tools/tests/path_trace_sharc_live.gd"
## Same camera and scene, ABBA order at each bounce budget. GPU Lab heavy only.
var sampling := false
var timings := []
var last_gpu_frame := -1
func _process(_dt: float) -> void:
	if sampling:RenderingServer.call_on_render_thread(timestamps)
func profile(target: Object) -> void:
	target._profile_stages=true;target.sharc.diagnostics=false
	cache_inspected.emit.call_deferred()
func timestamps() -> void:
	var rd := RenderingServer.get_rendering_device()
	var frame := rd.get_captured_timestamps_frame()
	if frame==last_gpu_frame:return
	last_gpu_frame=frame
	var times := {}
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if name.begins_with("Scene RT ") or name.begins_with("SHaRC "):times[name]=rd.get_captured_timestamp_gpu_time(i)/1000000.0
	if not times.has("Scene RT begin") or not times.has("Scene RT end"):return
	var begin: float=times["Scene RT begin"]
	var update: float=times.get("SHaRC update",begin)
	var resolve: float=times.get("SHaRC resolve",update)
	var rays: float=times.get("Scene RT rays",resolve)
	accept.call_deferred({"total":times["Scene RT end"]-begin,"update":update-begin,"resolve":resolve-update,"trace":rays-resolve})
func accept(row: Dictionary) -> void:
	if sampling:timings.append(row)
func summary(values: Array) -> Dictionary:
	values.sort()
	return {} if values.is_empty() else {"n":values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}
func run() -> void:
	var context := await setup_sharc()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1];var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"benchmark has a settled campaign scene")
	if rt.device==null:await finish_live(context,rt);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var device: Object=rt.device;var results := []
	RenderingServer.call_on_render_thread(profile.bind(device));await cache_inspected
	for mode in [1,2]:
		GameData.options.pt_mode=mode
		for enabled: bool in [false,true,true,false]:
			check(await select_sharc(rt,enabled),"benchmark selects requested cache state")
			await frames(40)
			var resets: int=device.sharc.resets
			timings.clear();sampling=true
			var wall := [];var previous := Time.get_ticks_usec()
			for i in 120:
				await frames(1);var now := Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			sampling=false
			check(rt.device==device and device.output_ready() and device.nrd_active and device.sharc.active==enabled,"measurement retains the selected PT/NRD path")
			check(timings.size()>=110,"measurement has fresh GPU timestamps")
			var row := {"sharc":enabled,"bounces":mode*2,"frame_ms":summary(wall),"cache_resets":device.sharc.resets-resets}
			for key in ["total","update","resolve","trace"]:
				var values := []
				for sample: Dictionary in timings:values.append(sample[key])
				row[key+"_gpu_ms"]=summary(values)
			results.append(row);print("SHARC_PERFORMANCE ",row)
	FileAccess.open(out.path_join("sharc-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"cave":cave,"quality":GameData.option("q_rt_lighting"),"runs":results,"resolution":[resolution.x,resolution.y],
		"device":RenderingServer.get_video_adapter_name(),"stats":rt.stats},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("SHARC_PERFORMANCE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
