extends "res://src/game/fx/path_trace_device.gd"
## A virtual reflected camera uses the main PT integrator and material ABI.
## Only camera rays clip to the water plane; transport and blockers retain
## the complete scene. HDR composition owns a stable, separate public texture.
const COMPOSE = preload("res://src/game/fx/shaders/path_trace_water_composite.glsl")
var reflection := Texture2DRD.new()
var _reflection_image := RID()
var _reflection_set := RID()
var _reflection_shader := RID()
var _reflection_pipeline := RID()
var _water_frame := RID()

func frame_bytes() -> int: return 2848
func reflection_output() -> Texture2DRD: return reflection

func shader_stage_path(stage: int) -> String:
	if stage==RenderingDevice.SHADER_STAGE_RAYGEN:
		return shader_prefix()+"raygen_water"+("_deep" if _deep_paths else "")+("_no_emitters" if not _uses_emitters else "")
	return super.shader_stage_path(stage)

func raw_formats() -> Array[int]:
	var formats:=super.raw_formats()
	for i in 2:formats.append(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	return formats

func build_extra(data: PackedByteArray,placements: Array) -> bool:
	_water_frame=_own(_rd.uniform_buffer_create(32))
	return _water_frame.is_valid() and super.build_extra(data,placements)

func extra_ray_uniforms() -> Array[RDUniform]:
	var bindings:=super.extra_ray_uniforms()
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,32,[_water_frame]))
	return bindings

func _upload_frame(frame: PackedByteArray) -> bool:
	return _rd.buffer_update(_water_frame,0,32,frame.slice(2816,2848))==OK and super._upload_frame(frame)

func _ray_bindings(raw: Array[RID],sampler: RID) -> Array[RDUniform]:
	var bindings:=super._ray_bindings(raw,sampler)
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,30,[raw[9]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,31,[raw[10]]))
	return bindings

func render(size: Vector2i,frame: PackedByteArray,changes: Dictionary={},texture_filter:=4) -> void:
	if frame.size()!=frame_bytes():return
	# The reflected view has independent history. Do not query the main view's
	# SHARC cells or create another cache per water plane.
	frame=frame.duplicate();frame.encode_float(190*4,0.0);frame.encode_float(191*4,1.0)
	super.render(size,frame,changes,texture_filter)

func _release_reflection(retain_output:=false) -> void:
	if _reflection_set.is_valid() and _rd.uniform_set_is_valid(_reflection_set):_rd.free_rid(_reflection_set)
	_reflection_set=RID()
	if _reflection_image.is_valid():
		if retain_output and _reflection_image==reflection.texture_rd_rid:_retired_outputs.append(_reflection_image)
		else:_rd.free_rid(_reflection_image)
	_reflection_image=RID()

func _targets(size: Vector2i,sampler: RID) -> bool:
	if size!=_size:_release_reflection(true)
	return super._targets(size,sampler)

func reconstruct(frame: PackedByteArray) -> bool:
	if not super.reconstruct(frame):return false
	if not _reflection_shader.is_valid():
		_reflection_shader=_own(_rd.shader_create_from_spirv(COMPOSE.get_spirv(),"PT water HDR composition"))
		if not _reflection_shader.is_valid():return false
		_reflection_pipeline=_own(_rd.compute_pipeline_create(_reflection_shader))
	if not _reflection_pipeline.is_valid():return false
	if not _reflection_set.is_valid():
		if not _reflection_image.is_valid():_reflection_image=_lighting_texture(_size)
		if not _reflection_image.is_valid():return false
		var inputs: Array[RID]=[_history[0],_history[2],_raw[3],_raw[1],_raw[9],_raw[10],_reflection_image]
		var bindings: Array[RDUniform]=[]
		for i in inputs.size():bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[inputs[i]]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,7,[_frame]))
		_reflection_set=_target_set(bindings,_reflection_shader)
	if not _reflection_set.is_valid():return false
	var list:=_rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_reflection_pipeline)
	_rd.compute_list_bind_uniform_set(list,_reflection_set,0)
	_rd.compute_list_dispatch(list,ceili(_size.x/8.0),ceili(_size.y/8.0),1)
	_rd.compute_list_end()
	return true

func _publish_targets() -> void:
	if reflection.texture_rd_rid!=_reflection_image:reflection.texture_rd_rid=_reflection_image
	super._publish_targets()

func output_ready() -> bool:
	return super.output_ready() and reflection.texture_rd_rid.is_valid()

func dispose() -> void:
	reflection.texture_rd_rid=RID()
	if _rd!=null:_release_reflection()
	super.dispose()
	_reflection_shader=RID();_reflection_pipeline=RID()
	_water_frame=RID()
