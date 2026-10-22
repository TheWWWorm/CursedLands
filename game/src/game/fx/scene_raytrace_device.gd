extends "res://src/game/fx/water_raytrace_device.gd"
## Main-view lighting uses the same native scene/AS backend as reflections.
## All GPU allocation, reconstruction and destruction stay on the render thread.
const FILTER = preload("res://src/game/fx/shaders/scene_raytrace_filter.glsl")
var guide := Texture2DRD.new()
var shadow0 := Texture2DRD.new()
var shadow1 := Texture2DRD.new()
var _raw: Array[RID] = []
var _history: Array[RID] = []
var _filter_sets: Array[RID] = []
var _filter_shader := RID()
var _filter_pipeline := RID()
var _history_valid := false

func shader_prefix() -> String: return "res://src/game/fx/shaders/scene_raytrace_"
func frame_bytes() -> int: return 576

func _lighting_texture(size: Vector2i) -> RID:
	var format := RDTextureFormat.new()
	format.width = size.x; format.height = size.y
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(format,RDTextureView.new())

func _release_targets() -> void:
	for rid in _filter_sets:
		if rid.is_valid(): _rd.free_rid(rid)
	_filter_sets.clear()
	if _set.is_valid(): _rd.free_rid(_set); _set = RID()
	for rid in _raw+_history:
		if rid.is_valid(): _rd.free_rid(rid)
	_raw.clear(); _history.clear()
	_history_valid = false

func _targets(size: Vector2i, sampler: RID) -> bool:
	if not _filter_shader.is_valid():
		_filter_shader = _own(_rd.shader_create_from_spirv(FILTER.get_spirv(),"Scene RT reconstruction"))
		if not _filter_shader.is_valid(): return false
		_filter_pipeline = _own(_rd.compute_pipeline_create(_filter_shader))
		if not _filter_pipeline.is_valid(): return false
	if size != _size:
		# Keep the RS handles alive while replacing their backing RD textures.
		var old_raw := _raw; var old_history := _history; var old_sets := _filter_sets
		_raw = []; _history = []; _filter_sets = []
		for i in 4: _raw.append(_lighting_texture(size))
		for i in 8: _history.append(_lighting_texture(size))
		if not (_raw+_history).all(func(rid: RID): return rid.is_valid()):
			_raw.append_array(old_raw); _history.append_array(old_history); _filter_sets = old_sets
			return false
		var bindings: Array[RDUniform] = []
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[_raw[i]]))
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+4,[_history[i+4]]))
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+8,[_history[i]]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,12,[_frame]))
		_filter_sets.append(_rd.uniform_set_create(bindings,_filter_shader,0))
		output.texture_rd_rid = _history[0]; guide.texture_rd_rid = _history[1]
		shadow0.texture_rd_rid = _history[2]; shadow1.texture_rd_rid = _history[3]
		if _set.is_valid(): _rd.free_rid(_set); _set = RID()
		for rid in old_sets+old_raw+old_history:
			if rid.is_valid(): _rd.free_rid(rid)
		_size = size; _history_valid = false
	if not _set.is_valid() or sampler != _sampler:
		if _set.is_valid(): _rd.free_rid(_set)
		_set = _rd.uniform_set_create([
			_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,[_tlas]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[_raw[0]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[_vertices]),
			_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,3,[_colours]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[_frame]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,[_materials]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,6,[sampler]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,7,[_raw[1]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,8,[_raw[2]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,9,[_raw[3]])],_shader,0)
		_sampler = sampler
	return _set.is_valid() and _filter_sets.all(func(rid: RID): return rid.is_valid())

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if not update_scene(changes): return
	if size.x < 2 or size.y < 2 or frame.size() != frame_bytes(): return
	if not _targets(size,_samplers[clampi(texture_filter,0,_samplers.size()-1)]):
		_ready = false; prepared.emit.call_deferred(false); return
	if not _history_valid: frame.encode_float(82*4,0.0)
	_rd.buffer_update(_frame,0,frame.size(),frame)
	_rd.capture_timestamp("Scene RT begin")
	var rays := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(rays,_pipeline)
	_rd.raytracing_list_bind_uniform_set(rays,_set,0)
	_rd.raytracing_list_trace_rays(rays,0,_sbt,size.x,size.y,1)
	_rd.raytracing_list_end()
	var filter := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(filter,_filter_pipeline)
	_rd.compute_list_bind_uniform_set(filter,_filter_sets[0],0)
	_rd.compute_list_dispatch(filter,ceili(size.x/8.0),ceili(size.y/8.0),1)
	_rd.compute_list_end()
	# Texture2DRD replacement invalidates every material sampling that RS
	# texture. Keep four stable outputs instead of swapping them every frame;
	# a small GPU copy supplies next frame's history without descriptor churn.
	for i in 4:
		_rd.texture_copy(_history[i],_history[i+4],Vector3.ZERO,Vector3.ZERO,Vector3(size.x,size.y,1),0,0,0,0)
	_rd.capture_timestamp("Scene RT end")
	_history_valid = true

func dispose() -> void:
	guide.texture_rd_rid = RID(); shadow0.texture_rd_rid = RID(); shadow1.texture_rd_rid = RID()
	output.texture_rd_rid = RID()
	if _rd != null: _release_targets()
	super.dispose()
