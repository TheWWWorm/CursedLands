extends "res://tools/tests/path_trace_camera_routes.gd"
## Same 4K scene, alternating presentation filter on/off; GPU Lab heavy job.
signal selected
var sampling := false
var gpu_samples := []
var last_gpu_frame := -1

func select(device: Object,enabled: bool) -> void:
	device._spatial_enabled=enabled
	selected.emit.call_deferred()

func _process(_dt: float) -> void:
	if sampling:RenderingServer.call_on_render_thread(timestamps)

func timestamps() -> void:
	var rd:=RenderingServer.get_rendering_device()
	var frame:=rd.get_captured_timestamps_frame()
	if frame==last_gpu_frame:return
	last_gpu_frame=frame
	var start: int=-1
	for i in rd.get_captured_timestamps_count():
		var label:=rd.get_captured_timestamp_name(i)
		var time:=rd.get_captured_timestamp_gpu_time(i)
		if label=="Scene RT begin":start=time
		elif label=="Scene RT end" and start>=0:accept.call_deferred((time-start)/1000000.0)

func accept(ms: float) -> void:
	if sampling:gpu_samples.append(ms)

func summary(values: Array) -> Dictionary:
	values.sort()
	return {} if values.is_empty() else {"n":values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}

func run() -> void:
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"benchmark prepares actual 4K scene")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var device: Object=rt.device;var results:=[]
	for enabled: bool in [false,true,true,false]:
		RenderingServer.call_on_render_thread(select.bind(device,enabled));await selected
		await frames(40)
		gpu_samples.clear();sampling=true
		var wall:=[];var previous:=Time.get_ticks_usec()
		for i in 120:
			await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
		sampling=false
		check(rt.device==device and device.output_ready(),"measurement keeps the same ready scene")
		results.append({"spatial":enabled,"rt_gpu_ms":summary(gpu_samples.duplicate()),"frame_ms":summary(wall)})
		print("SPATIAL_PERFORMANCE ",results[-1])
	FileAccess.open(out.path_join("spatial-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"runs":results,
		"resolution":[resolution.x,resolution.y],"stats":rt.stats},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
