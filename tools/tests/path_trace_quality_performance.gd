extends "res://tools/tests/path_trace_spatial_performance.gd"
## Matched first-person route; run old/new packs in ABBA order on one heavy GPU job.
func run() -> void:
	map_name="zone1";resolution=Vector2i(1920,1080)
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1];var rt: Node=game.get_node("SceneRaytrace")
	var diagnostic:=camera;camera=game.rig.camera;camera.make_current();diagnostic.queue_free()
	game.direct._set_view_mode(3);game.direct.tilt=-0.12;game.direct.apply_camera()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(await ready_scene(rt),"matched first-person benchmark prepares")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	await frames(80);gpu_samples.clear();sampling=true
	var wall:=[];var previous:=Time.get_ticks_usec()
	for i in 240:
		await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
	sampling=false
	var result:={"rt_gpu_ms":summary(gpu_samples.duplicate()),"frame_ms":summary(wall)}
	check(rt.stats.get("active",false),"benchmark retains path tracing")
	print("QUALITY_PERFORMANCE ",result)
	FileAccess.open(out.path_join("quality-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"runs":[result],
		"resolution":[resolution.x,resolution.y],"stats":rt.stats},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
