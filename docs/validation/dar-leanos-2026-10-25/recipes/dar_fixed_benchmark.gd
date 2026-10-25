extends "dar_leanos_route.gd"
var samples := []
var current_label := ""
var profile_rows := []
func _process(dt: float) -> void:
	super._process(dt)
	if current_label.is_empty():return
	var vp:=get_viewport().get_viewport_rid()
	var row:={"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"raster_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"raster_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rt":rt.stats.duplicate(true),"gather_instances":rt._gather.instances.size() if rt._gather else 0,
		"gather_textures":rt._gather.images.size() if rt._gather else 0,
		"gather_triangles":rt._gather.triangles if rt._gather else 0,
		"source_cache":{"hits":rt._source_cache.hits,"misses":rt._source_cache.misses,"bytes":rt._source_cache._bytes,"entries":rt._source_cache._entries.size()}}
	samples.append(row)
func phase(label: String, seconds: float, goal:=Vector2.INF, pan:=false) -> void:
	Engine.max_fps=0
	rt._profile_cpu=true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	current_label=label;samples=[]
	await super.phase(label,seconds,goal,pan)
	current_label=""
	profile_rows.append({"phase":label,"samples":samples})
	write_file("cpu-profile.json",JSON.stringify(profile_rows))
