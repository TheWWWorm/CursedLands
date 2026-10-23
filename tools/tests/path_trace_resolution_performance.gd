extends "res://tools/tests/path_trace_resolution.gd"
## Same-process A/B: retain the raster upscaler, view, scene and sample counts;
## alternate only the old window-relative and applied-render-resolution grids.
func run() -> void:
	var context:=await configure_resolution_game();var game: Game=context[1]
	var owner: Node=game.get_node("SceneRaytrace")
	if not owner.stats.get("active",false):get_tree().quit(1);return
	var device: Object=owner.device;var scene_handle: RID=device._tlas
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var sdk:=FsrGraphics.facts();var use_sdk: bool=sdk.api and sdk.sr3
	apply_resolution_settings(0 if use_sdk else 5,4,1 if use_sdk else 0,1)
	# quality, reference. Two and four bounce modes share the same reduction.
	GameData.options.pt_mode=2
	if use_sdk and not await wait_for_sdk("benchmark-upscaler"):
		get_tree().quit(1);return
	var cases:=[[0,true],[0,false],[1,false],[1,true]]
	var captures:={};var comparisons:={}
	for round_index in 2:
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.q_rt_lighting=choice[0];owner._window_resolution_reference=choice[1]
			await frames(45)
			check(owner.device==device and device._tlas==scene_handle,"resolution A/B retains the same acceleration structures")
			var display:=camera.get_viewport().get_visible_rect().size
			var expected:=Controller.target_size(display,choice[0]) if choice[1] else expected_trace_size(choice[0])
			check(owner.stats.size==[expected.x,expected.y] and device.output.get_size()==Vector2(expected),"resolution A/B binds the requested real GPU image size")
			var sdk_before:=upscaler_snapshot()
			if use_sdk and not sdk_status_ready(sdk_before):
				check(false,"SDK readiness changed before a benchmark block");get_tree().quit(1);return
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec()
			for i in 120:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var sdk_after:=upscaler_snapshot()
			if use_sdk:check_sdk_measurement("benchmark quality %d round %d"%[choice[0],round_index],sdk_before,sdk_after,110)
			var row:={"quality":choice[0],"window_reference":choice[1],"round":round_index,
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
				"controller_cpu_ms":summary(cpu_samples.duplicate()),"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),
				"stats":owner.stats.duplicate(),"upscaler_before":sdk_before,"upscaler_after":sdk_after,
				"upscale_evaluations":int(sdk_after.get("upscale_evaluations",0))-int(sdk_before.get("upscale_evaluations",0))}
			runs.append(row);print("PATH_RESOLUTION_BENCH ",JSON.stringify(row))
			if round_index==0:
				var label:="quality-%d-%s"%[choice[0],"window-reference" if choice[1] else "render-resolution"]
				captures["%d:%s"%[choice[0],choice[1]]]=await capture(label)
				var reference_key:="%d:true"%choice[0];var scaled_key:="%d:false"%choice[0]
				if captures.has(reference_key) and captures.has(scaled_key):
					comparisons[choice[0]]=image_comparison(captures[reference_key],captures[scaled_key])
			FileAccess.open(out.path_join("path-resolution-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
				"checks":checks,"failures":failures,"runs":runs,"image_comparisons":comparisons,
				"sdk_readiness":sdk_readiness,
				"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
				"upscaler":"FSR 3.1 Quality" if use_sdk else "FSR 2 Quality","viewport":[int(display.x),int(display.y)],
				"note":"Same frozen detailed river, four bounce PT, responsive history, water reflection and frame generation off. Only PT grid changes. Two alternating rounds, 120 samples after 45 warmup frames. Main GPU excludes the separate PT pass."},"\t"))
	set_process(false);before.queue_free()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
