extends "/home/llm2x/Documents/EI/local/scratchpad/cpu-traversal-20261025/traversal.gd"
var phases := []
var phase_origin := 0
var added := []
var admitted := []
func ei_profile_begin()->void:
	phase_origin=Time.get_ticks_usec()
	get_tree().node_added.connect(_added)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	get_tree().process_frame.connect(_phase.bind("process_frame"))
	RenderingServer.frame_pre_draw.connect(_phase.bind("pre_draw"))
	RenderingServer.frame_post_draw.connect(_phase.bind("post_draw"))
func _phase(kind: String)->void:
	var now:=Time.get_ticks_usec()-phase_origin
	if now>6000000:return
	var row:={"phase":kind,"usec":now,"frame":Engine.get_process_frames()}
	if kind=="pre_draw":
		for ref: WeakRef in added:
			var node=ref.get_ref()
			if node==null:continue
			var material: Material=node.material_override
			var mesh: Mesh=node.mesh if node is MeshInstance3D else node.multimesh.mesh if node.multimesh else null
			var details:={"usec":now,"frame":Engine.get_process_frames(),"path":String(node.get_path()),"class":node.get_class(),"visible":node.is_visible_in_tree(),"material_class":material.get_class() if material else "", "mesh_surfaces":mesh.get_surface_count() if mesh else 0}
			if material is ShaderMaterial:
				details["shader_code_hash"]=hash(material.shader.code)
				details["shader_path"]=material.shader.resource_path
			admitted.append(details)
		added.clear()
	if kind=="post_draw":
		var counts:=[]
		for key in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
			counts.append(RenderingServer.get_rendering_info(key))
		row["pipelines"]=counts
		row["render_cpu_ms"]=RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		row["render_gpu_ms"]=RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	phases.append(row)
func _added(node: Node)->void:
	if node is MeshInstance3D or node is MultiMeshInstance3D: added.append(weakref(node))
func ei_profile_end()->void:
	FileAccess.open("user://admitted-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(admitted,"\t"))
	FileAccess.open("user://frame-phases.json",FileAccess.WRITE).store_string(JSON.stringify(phases,"\t"))
