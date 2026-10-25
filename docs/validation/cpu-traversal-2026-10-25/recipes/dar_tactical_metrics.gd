extends "dar_tactical_route.gd"
var measuring := false
var render_rows := []
var render_phases := []
func _process(dt: float) -> void:
	super._process(dt)
	if not measuring:return
	var vp:=get_viewport().get_viewport_rid()
	render_rows.append({"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
func phase(label: String,seconds: float,goal:=Vector2.INF,pan:=false)->void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	render_rows=[];measuring=true
	await super.phase(label,seconds,goal,pan)
	measuring=false;render_phases.append({"phase":label,"rows":render_rows})
	write_file("render-metrics.json",JSON.stringify(render_phases))
