extends "/home/llm2x/Documents/EI/local/scratchpad/cpu-traversal-20261025/traversal.gd"
var phases := []
var phase_origin := 0
func ei_profile_begin()->void:
	phase_origin=Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	get_tree().process_frame.connect(_phase.bind("process_frame"))
	RenderingServer.frame_pre_draw.connect(_phase.bind("pre_draw"))
	RenderingServer.frame_post_draw.connect(_phase.bind("post_draw"))
func _phase(kind: String)->void:
	var now:=Time.get_ticks_usec()-phase_origin
	if now>6000000:return
	var row:={"phase":kind,"usec":now,"frame":Engine.get_process_frames()}
	if kind=="post_draw":
		var counts:=[]
		for key in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
			counts.append(RenderingServer.get_rendering_info(key))
		row["pipelines"]=counts
		row["render_cpu_ms"]=RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		row["render_gpu_ms"]=RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	phases.append(row)
func ei_profile_end()->void:
	FileAccess.open("user://frame-phases.json",FileAccess.WRITE).store_string(JSON.stringify(phases,"\t"))
