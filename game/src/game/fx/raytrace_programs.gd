extends RefCounted
## Immutable shader/pipeline pairs shared by consecutive scene snapshots.
## All access and final disposal run on the render thread, after their SBTs.
var _rd: RenderingDevice
var _programs := {}
var _pipelines := {}
var _compute := {}
var compute_compilations := 0
var compute_hits := 0
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

## Reconstruction and cache resolve programs are immutable too. DX12 may
## translate SPIR-V and compile a PSO here; repeat scene buffers must not
## repeat that work while the player is moving. Descriptor sets stay private.
func compute(rd: RenderingDevice,spirv: RDShaderSPIRV,label: String) -> Array[RID]:
	_rd=rd
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update(spirv.bytecode_compute)
	var key:=digest.finish().hex_encode()
	if _compute.has(key):compute_hits+=1;return _compute[key]
	var shader:=rd.shader_create_from_spirv(spirv,label)
	if not shader.is_valid():return [RID(),RID()]
	var pipeline:=rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():rd.free_rid(shader);return [RID(),RID()]
	_owned.append(shader);_owned.append(pipeline)
	var pair:Array[RID]=[shader,pipeline]
	_compute[key]=pair;compute_compilations+=1
	return pair

func dispose() -> void:
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):_rd.free_rid(_owned[i])
	_owned.clear();_programs.clear();_pipelines.clear();_compute.clear();_rd=null
