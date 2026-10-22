extends "res://tools/tests/path_trace_performance.gd"
## Alternate a saved/current hit library or filter in one
## scene and process. The raygen, ray counts and scene resources are shared.
signal hit_selected(ok: bool)
var hit_reference := ""
var filter_reference := ""
var reference_variants := {}
var selected_shader := RID()
var optimized_filter := RID()

func select_filter(device: Object,reference: bool) -> bool:
	var rd: RenderingDevice=device._rd
	if not optimized_filter.is_valid():optimized_filter=device._filter_pipeline
	if reference and not reference_variants.has("filter"):
		var spirv:=RDShaderSPIRV.new()
		if filter_reference.ends_with(".spv"):
			var bytes:=FileAccess.get_file_as_bytes(filter_reference)
			if bytes.is_empty():return false
			spirv.set_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE,bytes)
		else:
			var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string(filter_reference).trim_prefix("#[compute]\n")
			spirv=rd.shader_compile_spirv_from_source(source)
		if not spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():return false
		var shader: RID=device._own(rd.shader_create_from_spirv(spirv,"PT filter reference"))
		var pipeline: RID=device._own(rd.compute_pipeline_create(shader))
		if not pipeline.is_valid():return false
		reference_variants["filter"]=pipeline
	device._filter_pipeline=reference_variants["filter"] if reference else optimized_filter
	selected_shader=device._shader;device._history_valid=false
	return true

func select_hit(device: Object,reference: bool) -> void:
	if not filter_reference.is_empty():
		if not select_filter(device,reference):hit_selected.emit.call_deferred(false);return
		if hit_reference.is_empty():hit_selected.emit.call_deferred(true);return
	var key: int=int(device._uses_emitters)|(int(device._deep_paths)<<1)
	var rd: RenderingDevice=device._rd
	if reference and not reference_variants.has(key):
		var spirv:=RDShaderSPIRV.new();var dxil:={}
		var directx:=RenderingServer.get_current_rendering_driver_name()=="d3d12"
		for stage in device.STAGES:
			var path: String=device.shader_stage_path(stage)
			if stage==RenderingDevice.SHADER_STAGE_CLOSEST_HIT:path=hit_reference.path_join(path.get_file())
			var bytes:=FileAccess.get_file_as_bytes(path+".spv")
			if bytes.is_empty():hit_selected.emit.call_deferred(false);return
			spirv.set_stage_bytecode(stage,bytes)
			if directx:
				dxil[stage]=FileAccess.get_file_as_bytes(path+".dxil")
				if dxil[stage].is_empty():hit_selected.emit.call_deferred(false);return
		var shader: RID=rd.call("shader_create_from_spirv_and_dxil",spirv,dxil,"PT material reference") if directx else rd.shader_create_from_spirv(spirv,"PT material reference")
		device._own(shader)
		if not shader.is_valid():hit_selected.emit.call_deferred(false);return
		var program:=RDPipelineShader.new();program.shader=shader
		var group:=RDHitGroup.new();group.closest_hit_shader=program;group.any_hit_shader=program
		var pipeline: RID=device._own(rd.raytracing_pipeline_create([program],[program],[group],1))
		if not pipeline.is_valid():hit_selected.emit.call_deferred(false);return
		reference_variants[key]={"shader":shader,"pipeline":pipeline}
	var variant: Dictionary=reference_variants[key] if reference else device._variants[key]
	device._shader=variant.shader;device._pipeline=variant.pipeline;selected_shader=variant.shader
	if rd.hit_sbt_set_pipeline(device._sbt,device._pipeline)!=OK:hit_selected.emit.call_deferred(false);return
	if device._set.is_valid():rd.free_rid(device._set);device._set=RID()
	device._history_valid=false
	hit_selected.emit.call_deferred(true)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-hit-reference="):hit_reference=arg.trim_prefix("--pt-hit-reference=")
		if arg.begins_with("--pt-filter-reference="):filter_reference=arg.trim_prefix("--pt-filter-reference=")
	var quick:=OS.get_cmdline_user_args().has("--pt-bench-quick")
	var context:=await setup();var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"rt_shadows":0,"rt_gi":0,
		"pt_mode":2,"pt_accumulation":0,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"material benchmark prepares the campaign snapshot")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var device: Object=rt.device;var scene_handle: RID=device._tlas
	var hit_path: String=hit_reference.path_join(device.shader_stage_path(RenderingDevice.SHADER_STAGE_CLOSEST_HIT).get_file())
	var reference_files:={}
	if not hit_reference.is_empty():reference_files.merge({"library":hit_path.get_file(),"spirv":FileAccess.get_sha256(hit_path+".spv"),"dxil":FileAccess.get_sha256(hit_path+".dxil")})
	if not filter_reference.is_empty():reference_files["filter"]=FileAccess.get_sha256(filter_reference)
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	var cases:=[[2,1,true],[2,1,false],[2,2,false],[2,2,true]] if quick else [[1,1,true],[1,1,false],[1,2,false],[1,2,true],[2,1,true],[2,1,false],[2,2,false],[2,2,true]]
	for round_index in (2 if quick else 4):
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.pt_mode=choice[0];GameData.options.q_rt_lighting=choice[1]
			await frames(4)
			RenderingServer.call_on_render_thread(select_hit.bind(device,choice[2]))
			check(await hit_selected,"bind requested reference/current program")
			if not failures.is_empty():get_tree().quit(1);return
			await frames(40)
			check(rt.device==device and device._tlas==scene_handle and device._shader==selected_shader,"hit switch retains acceleration structures and requested shader")
			if not filter_reference.is_empty():check(device._filter_pipeline==(reference_variants["filter"] if choice[2] else optimized_filter),"requested reconstruction pipeline is active")
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var previous:=Time.get_ticks_usec()
			for i in 120:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			sampling=false
			var row:={"mode":choice[0],"quality":choice[1],"reference":choice[2],"round":round_index,
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),"controller_cpu_ms":summary(cpu_samples.duplicate()),
				"frame_ms":summary(wall),"stats":rt.stats.duplicate()}
			runs.append(row);print("PATH_MATERIAL_BENCH ",JSON.stringify(row))
			FileAccess.open(out.path_join("path-material-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":runs,
				"checks":checks,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"viewport":[1280,720],
				"reference_files":reference_files,
				"note":"Frozen river, detailed materials, identical raygen, controller, scene and images. Alternating saved/current program identified by reference_files, 120 samples after 40 warmup frames."},"\t"))
	set_process(false);before.queue_free()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
