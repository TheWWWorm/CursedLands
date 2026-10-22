extends "res://src/game/fx/scene_raytrace_device.gd"
## Same scene and stable texture lifetime as RT lighting. Channels become
## diffuse illumination, normal/depth, glossy radiance and albedo/roughness.
const PATH_FILTER = preload("res://src/game/fx/shaders/path_trace_filter.glsl")
const Emitters = preload("res://src/game/fx/path_trace_emitters.gd")
signal emitter_stats(count: int, candidates: int)
var emitters := Emitters.new()
var _instance_geometry := RID()
var _emitters := RID()
var _emitter_lookup := RID()
var _uses_emitters := false
var _variants := {}
func shader_prefix() -> String: return "res://src/game/fx/shaders/path_trace_"
func shader_stage_path(stage: int) -> String:
	if stage==RenderingDevice.SHADER_STAGE_RAYGEN and not _uses_emitters: return shader_prefix()+"raygen_no_emitters"
	return super.shader_stage_path(stage)
func frame_bytes() -> int: return 704
func filter_spirv() -> RDShaderSPIRV: return PATH_FILTER.get_spirv()
func filter_auxiliary_formats() -> Array[int]:
	return [RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16_SFLOAT]

# Geometry is shared by several placements. Lights need their unique, stable
# placement ID, including when hidden instances are removed from the TLAS.
func instance_id(_geometry_index: int, placement_index: int) -> int: return placement_index

func build_extra(data: PackedByteArray, placements: Array) -> bool:
	_variants[false] = {"shader":_shader,"pipeline":_pipeline}
	var mapping := _placement_geometry.to_byte_array()
	_instance_geometry = _own(_rd.storage_buffer_create(mapping.size(),mapping))
	emitters.setup(data,_geometry,placements,_opaque_fast_path)
	_emitters = _own(_rd.storage_buffer_create(Emitters.HEADER+Emitters.LIMIT*Emitters.STRIDE))
	_emitter_lookup = _own(_rd.storage_buffer_create(Emitters.HASH_SLOTS*16))
	return _instance_geometry.is_valid() and _emitters.is_valid() and _emitter_lookup.is_valid() \
		and _upload_emitters() and _select_pipeline(emitters.count>0)

## Compile the larger raygen only for scenes with eligible emissive surfaces.
## Both variants share the same hit stages, TLAS, SBT ranges and stable images.
func _select_pipeline(enabled: bool) -> bool:
	if enabled==_uses_emitters: return true
	_uses_emitters = enabled
	if not _variants.has(enabled):
		var program := _compile()
		if program==null: return false
		var group := RDHitGroup.new();group.closest_hit_shader=program;group.any_hit_shader=program
		var pipeline := _own(_rd.raytracing_pipeline_create([program],[program],[group],1))
		if not pipeline.is_valid(): return false
		_variants[enabled] = {"shader":_shader,"pipeline":pipeline}
	_shader = _variants[enabled].shader;_pipeline = _variants[enabled].pipeline
	if _rd.hit_sbt_set_pipeline(_sbt,_pipeline)!=OK: return false
	if _set.is_valid(): _rd.free_rid(_set);_set=RID()
	_history_valid = false
	return true

func _upload_emitters() -> bool:
	if _rd.buffer_update(_emitters,0,emitters.records.size(),emitters.records) != OK \
		or _rd.buffer_update(_emitter_lookup,0,emitters.lookup.size(),emitters.lookup) != OK: return false
	emitter_stats.emit.call_deferred(emitters.count,emitters.candidates)
	return true

func extra_ray_uniforms() -> Array[RDUniform]:
	var uniforms: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,10,[_instance_geometry])]
	if _uses_emitters:
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,11,[_emitters]))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,12,[_emitter_lookup]))
	return uniforms

func update_scene(changes: Dictionary) -> bool:
	if not super.update_scene(changes): return false
	if emitters.update(changes):
		_history_valid = false
		if not _upload_emitters() or not _select_pipeline(emitters.count>0):
			_ready = false; prepared.emit.call_deferred(false); return false
	return true

func dispose() -> void:
	super.dispose()
	emitters = Emitters.new()
	_variants.clear()
