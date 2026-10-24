extends "res://src/game/fx/water_raytrace_device.gd"
## Main-view lighting uses the same native scene/AS backend as reflections.
## All GPU allocation, reconstruction and destruction stay on the render thread.
const FILTER = preload("res://src/game/fx/shaders/scene_raytrace_filter.glsl")
# Extra timestamp boundaries are diagnostic only; normal frames retain the
# existing whole-pass bracket without intermediate query overhead.
var _profile_stages := OS.get_cmdline_user_args().has("--ei-profile-rt")
var measure_budget := false
var gpu_frame := -1
var gpu_ms := 0.0

func _measure_budget() -> void:
	var current := _rd.get_captured_timestamps_frame()
	if current==gpu_frame:return
	var begin := -1;var elapsed := 0
	for i in _rd.get_captured_timestamps_count():
		var label := _rd.get_captured_timestamp_name(i)
		if label=="Scene RT begin":begin=_rd.get_captured_timestamp_gpu_time(i)
		elif label=="Scene RT end" and begin>=0:
			elapsed+=_rd.get_captured_timestamp_gpu_time(i)-begin;begin=-1
	if elapsed>0:gpu_frame=current;gpu_ms=elapsed/1000000.0

var guide := Texture2DRD.new()
var shadow0 := Texture2DRD.new()
var shadow1 := Texture2DRD.new()
var _raw: Array[RID] = []
var _history: Array[RID] = []
var _filter_auxiliary: Array[RID] = []
var _filter_sets: Array[RID] = []
var _filter_shader := RID()
var _filter_pipeline := RID()
var _history_valid := false
# Readiness describes the last complete public image, independently of the
# next render's temporal confidence. The main thread may query it mid-render.
var _published_valid := false
# A resize can succeed before the next frame upload fails. Keep the last
# published images alive until the replacement has produced complete output.
var _retired_outputs: Array[RID] = []

func shader_prefix() -> String: return "res://src/game/fx/shaders/scene_raytrace_"
func frame_bytes() -> int: return 576
func filter_spirv() -> RDShaderSPIRV: return FILTER.get_spirv()
func extra_ray_uniforms() -> Array[RDUniform]: return []
func raw_formats() -> Array[int]:
	return [RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT]
## Optional reconstruction-only textures, in previous/result pairs. They use
## bindings 13 onward and are copied together with the stable lighting outputs.
func filter_auxiliary_formats() -> Array[int]: return []
func extra_filter_uniforms() -> Array[RDUniform]: return []
func published_targets() -> Array[RID]:
	return [output.texture_rd_rid,guide.texture_rd_rid,shadow0.texture_rd_rid,shadow1.texture_rd_rid]
## A new device becomes display-ready only after a complete successful render.
## History resets and private resizes keep its prior published image ready.
func output_ready() -> bool:
	return not _closed and _ready and _published_valid and output.texture_rd_rid.is_valid()

func _lighting_texture(size: Vector2i, data_format:=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT) -> RID:
	var format := RDTextureFormat.new()
	format.width = size.x; format.height = size.y
	format.format = data_format
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(format,RDTextureView.new())

func _release_targets() -> void:
	for rid in _filter_sets:
		if rid.is_valid(): _rd.free_rid(rid)
	_filter_sets.clear()
	if _set.is_valid(): _rd.free_rid(_set); _set = RID()
	for rid in _raw+_history+_filter_auxiliary+_retired_outputs:
		if rid.is_valid(): _rd.free_rid(rid)
	_raw.clear(); _history.clear(); _filter_auxiliary.clear()
	_retired_outputs.clear()
	_history_valid = false
	_published_valid = false

func _target_set(bindings: Array[RDUniform],shader: RID) -> RID:
	return _rd.uniform_set_create(bindings,shader,0)

func _ray_bindings(raw: Array[RID],sampler: RID) -> Array[RDUniform]:
	var bindings: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,[_tlas]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[raw[0]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[_vertices]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,3,[_colours]),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[_frame]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,[_materials]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,6,[sampler]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,7,[raw[1]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,8,[raw[2]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,9,[raw[3]])]
	bindings.append_array(extra_ray_uniforms())
	return bindings

func _free_targets(resources: Array[RID]) -> void:
	for rid in resources:
		if rid.is_valid(): _rd.free_rid(rid)

func _targets(size: Vector2i, sampler: RID) -> bool:
	if _closed or not _ready or size.x<2 or size.y<2: return false
	if not _filter_shader.is_valid():
		_filter_shader = _own(_rd.shader_create_from_spirv(filter_spirv(),"Scene RT reconstruction"))
		if not _filter_shader.is_valid(): return false
	if not _filter_pipeline.is_valid():
		_filter_pipeline = _own(_rd.compute_pipeline_create(_filter_shader))
		if not _filter_pipeline.is_valid(): return false
	if size != _size:
		# Stage the entire replacement. A failed image or descriptor allocation
		# must leave the previous complete output and its resource indices intact.
		var raw: Array[RID] = [];var history: Array[RID] = [];var auxiliary: Array[RID] = []
		for format: int in raw_formats(): raw.append(_lighting_texture(size,format))
		for i in 8: history.append(_lighting_texture(size))
		for format: int in filter_auxiliary_formats(): auxiliary.append(_lighting_texture(size,format))
		if not (raw+history+auxiliary).all(func(rid: RID): return rid.is_valid()):
			_free_targets(raw+history+auxiliary);return false
		var bindings: Array[RDUniform] = []
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[raw[i]]))
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+4,[history[i+4]]))
		for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+8,[history[i]]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,12,[_frame]))
		for i in auxiliary.size(): bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,13+i,[auxiliary[i]]))
		bindings.append_array(extra_filter_uniforms())
		var filter_set := _target_set(bindings,_filter_shader)
		if not filter_set.is_valid():
			_free_targets(raw+history+auxiliary);return false
		var ray_set := _target_set(_ray_bindings(raw,sampler),_shader)
		if not ray_set.is_valid():
			_rd.free_rid(filter_set);_free_targets(raw+history+auxiliary);return false
		var old_targets := _filter_sets+_raw+_history+_filter_auxiliary
		if _set.is_valid(): old_targets.push_front(_set)
		var published := published_targets()
		for rid in published:
			if rid.is_valid() and old_targets.has(rid):
				old_targets.erase(rid);_retired_outputs.append(rid)
		_raw=raw;_history=history;_filter_auxiliary=auxiliary
		_filter_sets=[filter_set];_set=ray_set;_sampler=sampler;_size=size
		_history_valid=false
		# Unpublished work images and descriptors are no longer needed. The
		# public images stay valid through upload/dispatch/copy failures.
		_free_targets(old_targets)
	elif not _set.is_valid() or sampler != _sampler:
		var ray_set := _target_set(_ray_bindings(_raw,sampler),_shader)
		if not ray_set.is_valid(): return false
		if _set.is_valid(): _rd.free_rid(_set)
		_set=ray_set;_sampler=sampler
		_history_valid=false
	return _set.is_valid() and _filter_sets.size()==1 and _filter_sets[0].is_valid()

func _publish_targets() -> void:
	if output.texture_rd_rid!=_history[0]:
		# Keep the RS handles stable, and change their backing only once the
		# replacement render is complete. Ordinary frames avoid this churn.
		output.texture_rd_rid=_history[0];guide.texture_rd_rid=_history[1]
		shadow0.texture_rd_rid=_history[2];shadow1.texture_rd_rid=_history[3]
	_free_targets(_retired_outputs);_retired_outputs.clear()

func _upload_frame(frame: PackedByteArray) -> bool:
	return _rd.buffer_update(_frame,0,frame.size(),frame)==OK

func _copy_history() -> bool:
	var extent := Vector3(_size.x,_size.y,1)
	for i in 4:
		if _rd.texture_copy(_history[i],_history[i+4],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK: return false
	for i in range(0,_filter_auxiliary.size(),2):
		if _rd.texture_copy(_filter_auxiliary[i+1],_filter_auxiliary[i],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK: return false
	return true

func _render_failed() -> void:
	_history_valid=false;_published_valid=false;_ready=false;_notify(&"prepared",[false])

func filter_presented(_frame_data: PackedByteArray) -> bool:
	return true

func reconstruct(frame: PackedByteArray) -> bool:
	var filter := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(filter,_filter_pipeline)
	_rd.compute_list_bind_uniform_set(filter,_filter_sets[0],0)
	_rd.compute_list_dispatch(filter,ceili(_size.x/8.0),ceili(_size.y/8.0),1)
	_rd.compute_list_end()
	if _profile_stages: _rd.capture_timestamp("Scene RT reconstruct")
	# The custom presentation filter must not feed its broader blur into history.
	return _copy_history() and filter_presented(frame)

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if _closed or not _ready or size.x<2 or size.y<2 or frame.size()!=frame_bytes(): return
	if measure_budget:_measure_budget()
	if not update_scene(changes): _history_valid=false;_published_valid=false;return
	if not _targets(size,_samplers[clampi(texture_filter,0,_samplers.size()-1)]):
		_render_failed();return
	if not _history_valid: frame.encode_float(82*4,0.0)
	if not _upload_frame(frame): _render_failed();return
	_rd.capture_timestamp("Scene RT begin")
	var rays := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(rays,_pipeline)
	_rd.raytracing_list_bind_uniform_set(rays,_set,0)
	_rd.raytracing_list_trace_rays(rays,0,_sbt,size.x,size.y,1)
	_rd.raytracing_list_end()
	if _profile_stages: _rd.capture_timestamp("Scene RT rays")
	# Texture2DRD replacement invalidates every material sampling that RS
	# texture. Keep four stable outputs instead of swapping them every frame;
	# a small GPU copy supplies next frame's history without descriptor churn.
	# Presentation-only filtering must not feed its broader blur back into the
	# temporal history. Retain the current surface guides and history first.
	var copied := reconstruct(frame)
	_rd.capture_timestamp("Scene RT end")
	if not copied: _render_failed();return
	_publish_targets()
	_history_valid = true
	_published_valid = true
	completed_renders += 1

func dispose() -> void:
	_published_valid=false
	guide.texture_rd_rid = RID(); shadow0.texture_rd_rid = RID(); shadow1.texture_rd_rid = RID()
	output.texture_rd_rid = RID()
	if _rd != null: _release_targets()
	super.dispose()
	_filter_shader=RID();_filter_pipeline=RID()
