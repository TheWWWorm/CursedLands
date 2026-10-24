extends RefCounted
## Immutable shader/pipeline pairs shared by consecutive scene snapshots.
## All access and final disposal run on the render thread, after their SBTs.
var _rd: RenderingDevice
var _programs := {}
var _pipelines := {}
var _owned: Array[RID] = []
var compilations := 0
var hits := 0

func program(rd: RenderingDevice,paths: Dictionary,directx: bool) -> RID:
	_rd=rd
	var key := str(paths)+str(directx)
	if _programs.has(key):hits+=1;return _programs[key]
	var spirv := RDShaderSPIRV.new();var dxil := {}
	for stage: int in paths:
		var bytes := FileAccess.get_file_as_bytes(paths[stage]+".spv")
		if bytes.is_empty():return RID()
		spirv.set_stage_bytecode(stage,bytes)
		if directx:
			dxil[stage]=FileAccess.get_file_as_bytes(paths[stage]+".dxil")
			if dxil[stage].is_empty():return RID()
	var shader: RID=rd.call("shader_create_from_spirv_and_dxil",spirv,dxil,"Scene RT") if directx else rd.shader_create_from_spirv(spirv,"Scene RT")
	if shader.is_valid():_owned.append(shader);_programs[key]=shader;compilations+=1
	return shader

func pipeline(program: RDPipelineShader) -> RID:
	var key := program.shader.get_id()
	if _pipelines.has(key):return _pipelines[key]
	var group := RDHitGroup.new();group.closest_hit_shader=program;group.any_hit_shader=program
	var result := _rd.raytracing_pipeline_create([program],[program],[group],1)
	if result.is_valid():_owned.append(result);_pipelines[key]=result
	return result

func dispose() -> void:
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):_rd.free_rid(_owned[i])
	_owned.clear();_programs.clear();_pipelines.clear();_rd=null
