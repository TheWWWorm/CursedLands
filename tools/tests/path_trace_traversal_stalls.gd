extends "res://tools/tests/path_trace_recording_route.gd"
## Record slow real campaign frames with their immediately preceding scene
## state. Readbacks and loading remain outside the sampled stages.
var slow_frames: Array = []
var observing := false
var observed_phase := ""
var previous_state := {}

func frames(count := 4) -> void:
	for i in count:
		var start := Time.get_ticks_usec()
		await super.frames(1)
		if not observing or not is_instance_valid(rt):continue
		var elapsed := (Time.get_ticks_usec()-start)/1000.0
		var state := {"phase":observed_phase,"ms":elapsed,"scene":rt.stats.duplicate(true),
			"render_pipelines":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
			"specialized_pipelines":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
			"mesh_pipelines":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			"pos":[h.pos.x,h.pos.y]}
		if elapsed>45.0:
			state["before"]=previous_state
			slow_frames.append(state)
			print("TRAVERSAL_STALL ",JSON.stringify(state))
		previous_state=state.duplicate(true);previous_state.erase("before")

func stage(label: String,seconds: float,predicate:=Callable()) -> void:
	observing=true;observed_phase=label
	await super.stage(label,seconds,predicate)
	observing=false
	FileAccess.open(out.path_join("traversal-stalls.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"slow_frames":slow_frames,"stages":route_results},"\t"))
