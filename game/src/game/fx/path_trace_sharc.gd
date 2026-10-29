extends RefCounted
## Render-thread SHaRC resources. Each scene generation owns its cache; it
## never borrows another scene's radiance or the denoiser's image history.
const PREFIX := "res://src/game/fx/shaders/path_trace_sharc_resolve"
const CAPACITY := 1 << 20
const STRIDES := [8,16,16,4]
# Godot 4.7's RenderingDevice::SUPPORTS_HALF_FLOAT is not script-bound.
# The engine feature checks native fp16 arithmetic AND 16-bit buffer storage.
const HALF_FLOAT_FEATURE := 1
var diagnostics := false
var active := false
var frames := 0
var resets := 0
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _buffers: Array[RID] = []
var _constants := RID()
var _stats := RID()
var _resolve_shader := RID()
var _resolve_pipeline := RID()
var _resolve_set := RID()
var _update_set := RID()
var _source_set := RID()
var _update_shader := RID()
var _reset := true
var _previous_camera := Vector3.ZERO

static func supported() -> bool:
	var rd := RenderingServer.get_rendering_device()
	return rd!=null and rd.has_feature(HALF_FLOAT_FEATURE)

func _own(rid: RID) -> RID:
	if rid.is_valid():_owned.append(rid)
	return rid

func allocate(bytes: int) -> RID:
	return _own(_rd.storage_buffer_create(bytes))

func setup(rd: RenderingDevice,programs: RefCounted=null) -> bool:
	if active:return true
	_rd=rd
	if not supported():return false
	for stride: int in STRIDES:
		var buffer := allocate(CAPACITY*stride)
		if not buffer.is_valid():dispose();return false
		_buffers.append(buffer)
	_constants=_own(_rd.uniform_buffer_create(64))
	_stats=allocate(16)
	var spirv := RDShaderSPIRV.new()
	spirv.bytecode_compute=FileAccess.get_file_as_bytes(PREFIX+".spv")
	if spirv.bytecode_compute.is_empty():dispose();return false
	# Compute follows the existing NRD path on both drivers. The engine's
	# direct DXIL entry point only accepts ray-tracing library stages.
	if programs!=null:
		var pair:Array[RID]=programs.compute(_rd,spirv,"SHaRC resolve")
		_resolve_shader=pair[0];_resolve_pipeline=pair[1]
	else:
		_resolve_shader=_own(_rd.shader_create_from_spirv(spirv,"SHaRC resolve"))
		if _resolve_shader.is_valid():_resolve_pipeline=_own(_rd.compute_pipeline_create(_resolve_shader))
	if not _resolve_shader.is_valid() or not _constants.is_valid() or not _stats.is_valid():dispose();return false
	_resolve_set=_own(_rd.uniform_set_create(uniforms(),_resolve_shader,0))
	if not _resolve_pipeline.is_valid() or not _resolve_set.is_valid():dispose();return false
	if _rd.buffer_clear(_stats,0,16)!=OK:dispose();return false
	active=true;_reset=true
	return true

func uniforms() -> Array[RDUniform]:
	var result: Array[RDUniform]=[]
	for i in _buffers.size():
		var uniform := RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding=22+i;uniform.add_id(_buffers[i]);result.append(uniform)
	var uniform := RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding=26;uniform.add_id(_constants);result.append(uniform)
	uniform=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding=27;uniform.add_id(_stats);result.append(uniform)
	return result

func invalidate() -> void:
	_reset=true

func prepare(frame: PackedByteArray,size: Vector2i) -> bool:
	if not active:return false
	var position := Vector3(frame.decode_float(28*4),frame.decode_float(29*4),frame.decode_float(30*4))
	if _reset or frame.decode_float(82*4)<0.5:
		for i in _buffers.size():
			if _rd.buffer_clear(_buffers[i],0,CAPACITY*STRIDES[i])!=OK:return false
		_reset=false;_previous_camera=position;resets+=1
	var data := PackedFloat32Array([position.x,position.y,position.z,128,
		_previous_camera.x,_previous_camera.y,_previous_camera.z,0]).to_byte_array()
	data.append_array(PackedInt32Array([CAPACITY,frames,size.x,size.y]).to_byte_array())
	data.append_array(PackedFloat32Array([minf(8.0,frame.decode_float(145*4)),8,float(diagnostics),0]).to_byte_array())
	if _rd.buffer_update(_constants,0,data.size(),data)!=OK:return false
	_previous_camera=position
	return true

func update_set(host: RefCounted,shader: RID) -> RID:
	if _source_set!=host.get("_set") or _update_shader!=shader or not _rd.uniform_set_is_valid(_update_set):
		release_update_set()
		_update_set=_rd.uniform_set_create(host._ray_bindings(host.ray_targets() if host.has_method("ray_targets") else host._raw,host._sampler),shader,0)
		_source_set=host.get("_set");_update_shader=shader
	return _update_set

func resolve() -> void:
	# RenderingDevice's command graph tracks the shared storage buffers across
	# ray/compute lists and inserts write->read/write barriers on both APIs.
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_resolve_pipeline)
	_rd.compute_list_bind_uniform_set(list,_resolve_set,0)
	_rd.compute_list_dispatch(list,CAPACITY/256,1,1)
	_rd.compute_list_end()
	frames+=1

func counters() -> PackedInt32Array:
	return _rd.buffer_get_data(_stats).to_int32_array() if active else PackedInt32Array()

func release_update_set(release: Callable=Callable()) -> void:
	if _rd!=null and _update_set.is_valid() and _rd.uniform_set_is_valid(_update_set):
		if release.is_valid():release.call(_update_set)
		else:_rd.free_rid(_update_set)
	_update_set=RID();_source_set=RID();_update_shader=RID()

func dispose(release: Callable=Callable()) -> void:
	release_update_set(release)
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):
			if release.is_valid():release.call(_owned[i])
			else:_rd.free_rid(_owned[i])
	_owned.clear();_buffers.clear();_constants=RID();_stats=RID()
	_resolve_set=RID();_resolve_pipeline=RID();_resolve_shader=RID()
	active=false;_reset=true
