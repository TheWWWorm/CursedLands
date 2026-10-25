extends "res://tools/tests/scene_raytrace_performance.gd"
## Run only through GPU Lab with workload=heavy. Same live-location setup,
## then freeze simulation and camera so paired exports measure the same work.
func run() -> void:
	pass

func measure(a: Node) -> void:
	a.s.set_physics_process(false);a.s.world.set_physics_process(false);a.s.world.set_process(false)
	a.g.set_process(false);a.t.set_process(false);a.t.details.set_process(false)
	a.s.world.get_node("ParticleFx").set_process(false)
	for unit: GameUnit in a.s.world.units.values():unit.process_mode=Node.PROCESS_MODE_DISABLED
	# LocalLighting stays live: gentle flames must exercise the changed NRD
	# response. No screenshot or texture readback is taken inside the samples.
	GameData.options.fps_limit=0;Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before)
	process_priority=102
	RenderingServer.viewport_set_measure_render_time(a.get_viewport().get_viewport_rid(),true)
	for round_index in 3:
		for view: String in (["forward","ground"] if round_index%2==0 else ["ground","forward"]):
			a.g.direct._set_view_mode(3);a.g.direct.tilt=-0.85 if view=="ground" else -0.12;a.g.direct.apply_camera()
			await a.frames(60)
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec()
			for i in 180:
				await a.frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(a.get_viewport().get_viewport_rid()))
			sampling=false
			var row:={"view":view,"round":round_index,"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":a.rt.stats.duplicate()}
			runs.append(row);print("LOCATION_BENCH ",JSON.stringify(row))
			a.check(gpu_samples.size()>100 and a.rt.device.nrd_active,"benchmark samples active NRD: "+view+" "+str(round_index))
	FileAccess.open(a.out.path_join("location-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":runs,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"zone":a.zone,"dlss":a.dlss,"display":[3840,2160],"raster":[1920,1080],"trace":[960,540],
		"note":"Uncapped, vsync off; fixed scene with live flame-light intensity; 3 rounds per view, no image readbacks during timing. GPU Lab heavy job required. Main viewport GPU excludes RT dispatch; frame time includes both."},"\t"))
	before.queue_free();set_process(false)
