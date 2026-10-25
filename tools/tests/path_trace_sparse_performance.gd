extends "res://tools/tests/path_trace_sparse_updates.gd"
## Same-device ABBA comparison of the previous full-span upload and sparse
## uploads. GPU Lab heavy only; report update CPU cost, never whole-game FPS.
var observation := {}

func stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value: float in values:total+=value
	return {"count":values.size(),"mean_us":total/values.size(),"median_us":values[values.size()/2],
		"p95_us":values[int(values.size()*0.95)]}

func initialize() -> void:
	check(setup_device(),"build sparse-upload benchmark")
	done.emit.call_deferred()

func measure(indices: Array,full: bool,iteration: int) -> void:
	d.full_span=full
	var changes := []
	var direction := 0.1 if iteration%2 else -0.1
	for index: int in indices:changes.append(change(index,Vector3(0,direction,0),-1,Vector3(0,direction,0)))
	d.reset_counts()
	var started := Time.get_ticks_usec()
	var ok := d._update_motion({"instances":changes}) and d._update_lighting_offsets({"instances":changes})
	var elapsed := Time.get_ticks_usec()-started
	observation={"ok":ok,"us":elapsed,"motion_bytes":d.bytes(true),"offset_bytes":d.bytes(false),
		"motion_calls":d.calls(true),"offset_calls":d.calls(false)}
	done.emit.call_deferred()

func retire() -> void:
	gpu_matches("benchmark final")
	d.dispose();done.emit.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified benchmark GPU")
	if not PathDevice.supported():get_tree().quit(1);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	RenderingServer.call_on_render_thread(initialize);await done
	if not d._ready:get_tree().quit(1);return
	var cases := {"two_distant":[0,COUNT-1],"dense_1024":range(1024),"sixteen_groups":[]}
	for i in 16:cases.sixteen_groups.append(i*500)
	for label: String in cases:
		for block in 4:
			var full := block in [0,3]
			var timings := [];var valid := true
			for i in 140:
				RenderingServer.call_on_render_thread(measure.bind(cases[label],full,i));await done
				valid=valid and observation.ok
				if i>=40:timings.append(float(observation.us))
				await get_tree().process_frame
			check(valid,"all "+label+" uploads succeed in block "+str(block))
			var row := observation.duplicate();row.erase("us");row.erase("ok")
			row.merge({"case":label,"full_span":full,"block":block,"cpu":stats(timings)})
			rows.append(row);print("SPARSE_BENCH ",JSON.stringify(row))
	RenderingServer.call_on_render_thread(retire);await done
	FileAccess.open(out.path_join("path-sparse-performance.json"),FileAccess.WRITE).store_string(JSON.stringify(
		{"checks":checks,"failures":failures,"rows":rows,"device":RenderingServer.get_video_adapter_name(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"scope":"Render-thread motion packing and GPU record uploads; no whole-game FPS claim."},"\t"))
	TexUpscale.shutdown()
	print("PT_SPARSE_PERFORMANCE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
