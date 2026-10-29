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
# A live replacement has no public output yet. Allocate its native RR image
# pool over bounded steps, keeping partial work separate from render targets.
var _staged_raw: Array[RID] = []
var _staged_history: Array[RID] = []
var _staged_size := Vector2i.ZERO
const Retirement = preload("res://src/game/fx/raytrace_retirement.gd")
var _retirement_cpu: Retirement
var _retirement_owned: Array[RID] = []
var _retirement_resources: Array[RID] = []
var _retirement_pending := false
var _defer_retirement_release := false
var retirement_steps := 0
var retirement_step_ms := 0.0

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
func extra_filter_uniforms(_raw_targets: Array[RID]) -> Array[RDUniform]: return []
## Native reconstruction consumes current AOVs and four public images only.
## The custom denoiser needs another history pair plus its auxiliary guides.
func uses_filter_targets() -> bool: return true
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
	_release_staged_targets()
	for rid in _filter_sets:
		if rid.is_valid(): _release_rid(rid)
	_filter_sets.clear()
	if _set.is_valid(): _release_rid(_set); _set = RID()
	for rid in _raw+_history+_filter_auxiliary+_retired_outputs:
		if rid.is_valid(): _release_rid(rid)
	_raw.clear(); _history.clear(); _filter_auxiliary.clear()
	_retired_outputs.clear()
	_history_valid = false
	_published_valid = false

func _target_set(bindings: Array[RDUniform],shader: RID) -> RID:
	return _rd.uniform_set_create(bindings,shader,0)

## The images the ray programs write. The base reconstruction traces into the
## raw images and filters into the published ones; a derived device may trace
## straight into the published images when nothing filters in between.
func _ray_targets(raw: Array[RID],_history_targets: Array[RID]) -> Array[RID]: return raw

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
		if rid.is_valid(): _release_rid(rid)

func _release_rid(rid: RID) -> void:
	if _defer_retirement_release:_retirement_resources.append(rid)
	else:_rd.free_rid(rid)

func _release_staged_targets() -> void:
	_free_targets(_staged_raw+_staged_history)
	_staged_raw.clear();_staged_history.clear();_staged_size=Vector2i.ZERO

func _raw_targets_staged(size: Vector2i) -> bool:
	return size==_staged_size and _staged_raw.size()==raw_formats().size() and _staged_history.size()==4

func _stage_raw_targets(size: Vector2i) -> void:
	if _closed or not _ready or _published_valid or size.x<2 or size.y<2:return
	if size!=_staged_size:_release_staged_targets();_staged_size=size
	var started:=Time.get_ticks_usec();var count:=0
	var formats:=raw_formats()
	while not _raw_targets_staged(size):
		var raw:=_staged_raw.size()<formats.size()
		var format: int=formats[_staged_raw.size()] if raw else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		var rid:=_lighting_texture(size,format)
		if not rid.is_valid():
			_release_staged_targets();_render_failed();return
		if raw:_staged_raw.append(rid)
		else:_staged_history.append(rid)
		count+=1
		if count>=3 or Time.get_ticks_usec()-started>=1500:break
	var elapsed:=(Time.get_ticks_usec()-started)/1000.0
	build_timings["target_allocation_ms"]=build_timings.get("target_allocation_ms",0.0)+elapsed
	build_timings["target_allocation_step_ms"]=maxf(build_timings.get("target_allocation_step_ms",0.0),elapsed)

func _filter_target_set(raw: Array[RID],history: Array[RID],auxiliary: Array[RID]) -> RID:
	var bindings: Array[RDUniform] = []
	for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[raw[i]]))
	for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+4,[history[i+4]]))
	for i in 4: bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+8,[history[i]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,12,[_frame]))
	for i in auxiliary.size(): bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,13+i,[auxiliary[i]]))
	bindings.append_array(extra_filter_uniforms(raw))
	return _target_set(bindings,_filter_shader)

func _targets(size: Vector2i, sampler: RID) -> bool:
	if _closed or not _ready or size.x<2 or size.y<2: return false
	var filtered := uses_filter_targets()
	if filtered or size!=_staged_size:_release_staged_targets()
	if filtered and not _filter_shader.is_valid():
		var pair:=_compute_program(filter_spirv(),"Scene RT reconstruction")
		_filter_shader=pair[0];_filter_pipeline=pair[1]
		if not _filter_shader.is_valid() or not _filter_pipeline.is_valid():return false
	# A same-size switch between the filtered and direct modes changes which
	# images the ray programs write, so their descriptor set is rebuilt too.
	var rebind := false
	if size != _size:
		# Stage the entire replacement. A failed image or descriptor allocation
		# must leave the previous complete output and its resource indices intact.
		var raw: Array[RID] = [];var history: Array[RID] = [];var auxiliary: Array[RID] = []
		if not filtered and _raw_targets_staged(size):
			raw=_staged_raw;history=_staged_history
			_staged_raw=[];_staged_history=[];_staged_size=Vector2i.ZERO
		else:
			_release_staged_targets()
			for format: int in raw_formats(): raw.append(_lighting_texture(size,format))
			for i in (8 if filtered else 4): history.append(_lighting_texture(size))
		if filtered:
			for format: int in filter_auxiliary_formats(): auxiliary.append(_lighting_texture(size,format))
		if not (raw+history+auxiliary).all(func(rid: RID): return rid.is_valid()):
			_free_targets(raw+history+auxiliary);return false
		var filter_set := _filter_target_set(raw,history,auxiliary) if filtered else RID()
		if filtered and not filter_set.is_valid():
			_free_targets(raw+history+auxiliary);return false
		var ray_set := _target_set(_ray_bindings(_ray_targets(raw,history),sampler),_shader)
		if not ray_set.is_valid():
			if filter_set.is_valid(): _rd.free_rid(filter_set)
			_free_targets(raw+history+auxiliary);return false
		var old_targets := _filter_sets+_raw+_history+_filter_auxiliary
		if _set.is_valid(): old_targets.push_front(_set)
		var published := published_targets()
		for rid in published:
			if rid.is_valid() and old_targets.has(rid):
				old_targets.erase(rid);_retired_outputs.append(rid)
		_raw=raw;_history=history;_filter_auxiliary=auxiliary
		_filter_sets.clear()
		if filtered: _filter_sets.append(filter_set)
		_set=ray_set;_sampler=sampler;_size=size
		_history_valid=false
		# Unpublished work images and descriptors are no longer needed. The
		# public images stay valid through upload/dispatch/copy failures.
		_free_targets(old_targets)
	elif filtered and _history.size()==4:
		# A same-size RR -> denoiser switch keeps all four published images.
		# Stage only the missing histories and guides; allocation failure must
		# leave the current public image and raw ray descriptors intact.
		var extra: Array[RID] = [];var auxiliary: Array[RID] = []
		for i in 4: extra.append(_lighting_texture(size))
		for format: int in filter_auxiliary_formats(): auxiliary.append(_lighting_texture(size,format))
		if not (extra+auxiliary).all(func(rid: RID): return rid.is_valid()):
			_free_targets(extra+auxiliary);return false
		var filter_set := _filter_target_set(_raw,_history+extra,auxiliary)
		if not filter_set.is_valid(): _free_targets(extra+auxiliary);return false
		_history.append_array(extra);_filter_auxiliary=auxiliary;_filter_sets=[filter_set]
		_history_valid=false;rebind=true
	elif not filtered and _history.size()>4:
		_free_targets(_filter_sets+_history.slice(4)+_filter_auxiliary)
		_filter_sets.clear();_filter_auxiliary.clear();_history.resize(4)
		_history_valid=false;rebind=true
	if not _set.is_valid() or sampler != _sampler or rebind:
		var ray_set := _target_set(_ray_bindings(_ray_targets(_raw,_history),sampler),_shader)
		if not ray_set.is_valid(): return false
		if _set.is_valid(): _rd.free_rid(_set)
		_set=ray_set;_sampler=sampler
		_history_valid=false
	return _set.is_valid() and (not filtered or (_filter_sets.size()==1 and _filter_sets[0].is_valid()))

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
	_release_staged_targets()
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

func trace_frame(_frame_data: PackedByteArray) -> bool:
	var rays := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(rays,_pipeline)
	_rd.raytracing_list_bind_uniform_set(rays,_set,0)
	_rd.raytracing_list_trace_rays(rays,0,_sbt,_size.x,_size.y,1)
	_rd.raytracing_list_end()
	return true

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if _closed or not _ready or size.x<2 or size.y<2 or frame.size()!=frame_bytes(): return
	if _profile_stages:_rd.capture_timestamp("PT submit %d:%d"%[get_instance_id(),completed_renders])
	if measure_budget:_measure_budget()
	if not update_scene(changes): _history_valid=false;_published_valid=false;return
	if _profile_stages:_rd.capture_timestamp("PT scene updated")
	if not _targets(size,_samplers[clampi(texture_filter,0,_samplers.size()-1)]):
		_render_failed();return
	if _profile_stages:_rd.capture_timestamp("PT targets ready")
	if not _history_valid: frame.encode_float(82*4,0.0)
	if not _upload_frame(frame): _render_failed();return
	_rd.capture_timestamp("Scene RT begin")
	if not trace_frame(frame): _render_failed();return
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
	if _profile_stages:_rd.capture_timestamp("PT published %d:%d"%[get_instance_id(),completed_renders])
	_history_valid = true
	_published_valid = true
	completed_renders += 1

## Stop queued rendering immediately, then let the controller retire this
## unbound generation across later frames. Ordinary dispose remains immediate.
func begin_retirement() -> void:
	if _closed:return
	_closed=true;_ready=false;_building=false;_published_valid=false
	_retirement_pending=true

func retirement_complete() -> bool: return _closed and not _retirement_pending
func retirement_resources_pending() -> int:
	return _retirement_resources.size()+_retirement_owned.size()+_owned.size()

func _free_retired_rid(rid: RID) -> void:
	_rd.free_rid(rid)

func retire_step() -> void:
	if not _retirement_pending:return
	var started:=Time.get_ticks_usec()
	if _retirement_cpu==null:
		_retirement_owned=_owned;_owned=[]
		_retirement_cpu=Retirement.new()
		_retirement_cpu.parts=[_geometry,_instances,_active_instances]
		_geometry=[];_instances=[];_active_instances={}
		_defer_retirement_release=true
		dispose()
		_defer_retirement_release=false
		# The virtual disposal path appends descriptors before their images,
		# buffers and AS dependencies. Pop in that same order across frames.
		_retirement_resources.reverse()
	var freed:=0
	while not _retirement_resources.is_empty() or not _retirement_owned.is_empty():
		var resources:=_retirement_owned if _retirement_resources.is_empty() else _retirement_resources
		_free_retired_rid(resources.pop_back());freed+=1
		if freed>=16 or Time.get_ticks_usec()-started>=1000:break
	var cpu_done:=_retirement_cpu.step(1000)
	retirement_steps+=1;retirement_step_ms=(Time.get_ticks_usec()-started)/1000.0
	if _retirement_resources.is_empty() and _retirement_owned.is_empty() and cpu_done:
		_retirement_cpu=null;_retirement_pending=false

func dispose() -> void:
	_published_valid=false
	guide.texture_rd_rid = RID(); shadow0.texture_rd_rid = RID(); shadow1.texture_rd_rid = RID()
	output.texture_rd_rid = RID()
	if _rd != null: _release_targets()
	if _defer_retirement_release:
		# Water's immediate teardown normally frees these dependency roots.
		# Detach them here so the bounded queue also covers their destruction.
		for rid in [_target,_tlas,_sbt]:
			if rid.is_valid():_retirement_owned.erase(rid);_release_rid(rid)
		_target=RID();_tlas=RID();_sbt=RID()
	super.dispose()
	_filter_shader=RID();_filter_pipeline=RID()
	if not _defer_retirement_release:
		while not _retirement_resources.is_empty():_free_retired_rid(_retirement_resources.pop_back())
		while not _retirement_owned.is_empty():_free_retired_rid(_retirement_owned.pop_back())
		if _retirement_cpu!=null:_retirement_cpu.finish();_retirement_cpu=null
		_retirement_pending=false
