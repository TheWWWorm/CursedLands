extends "res://tools/tests/path_trace_performance.gd"
## Alternate the original full-path and optimized shaders inside one campaign
## snapshot. CPU tracking, scene buffers, image size and samples stay identical.
signal reference_selected
func select_reference(device: Object,enabled: bool) -> void:
	device._full_paths_reference=enabled
	reference_selected.emit.call_deferred()

func run() -> void:
	var context:=await setup();var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"rt_shadows":0,"rt_gi":0,
		"pt_mode":2,"pt_accumulation":0,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"alternating benchmark prepares the campaign snapshot")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var device: Object=rt.device;var scene_handle: RID=device._tlas
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var cases:=[[1,true],[1,false],[2,false],[2,true]]
	for round_index in 4:
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.q_rt_lighting=choice[0]
			RenderingServer.call_on_render_thread(select_reference.bind(device,choice[1]));await reference_selected
			await frames(40)
			check(rt.device==device and device._tlas==scene_handle,"reference switch retains the same acceleration structures")
			check(device._deep_paths!=choice[1],"requested full-path or roulette shader is bound")
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var previous:=Time.get_ticks_usec()
			for i in 120:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			sampling=false
			var row:={"quality":choice[0],"full_paths":choice[1],"round":round_index,
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"controller_cpu_ms":summary(cpu_samples.duplicate()),
				"frame_ms":summary(wall),"stats":rt.stats.duplicate()}
			runs.append(row);print("PATH_TAIL_BENCH ",JSON.stringify(row))
			FileAccess.open(out.path_join("path-tail-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":runs,
				"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"viewport":[1280,720],
				"note":"Four continuation bounces, frozen river, detailed materials, same native controller and scene resources. Four alternating rounds of 120 frames after 40 warmup frames. Full-path reference binds the unchanged original raygen with the same four-bounce frame constants."},"\t"))
	set_process(false);before.queue_free()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
