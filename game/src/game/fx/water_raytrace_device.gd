extends RefCounted
## Shared hardware RT pipeline for DX12 and Vulkan. Resources belong to the
## render thread; dispatch explicitly retains this owner until queued work ends.
signal prepared(ok: bool)
signal rendered(preparation: int, ok: bool)

const FRAME_BYTES := 352
const SHADERS := "res://src/game/fx/shaders/water_raytrace_"
const STAGES := {RenderingDevice.SHADER_STAGE_RAYGEN:"raygen", RenderingDevice.SHADER_STAGE_MISS:"miss",
	RenderingDevice.SHADER_STAGE_CLOSEST_HIT:"closest_hit", RenderingDevice.SHADER_STAGE_ANY_HIT:"any_hit"}

var output := Texture2DRD.new()
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _shader := RID()
var _pipeline := RID()
var _tlas := RID()
var _sbt := RID()
var _vertices := RID()
var _materials := RID()
var _blases: Array[RID] = []
var _geometry: Array = []
var _instances: Array[RDAccelerationStructureInstance] = []
# Keep stable scene indices while omitting masked instances from GPU builds.
var _active_instances := {}
var _placement_geometry := PackedInt32Array()
var _colours := RID()
var _sampler := RID()
var _samplers: Array[RID] = []
var _frame := RID()
var _target := RID()
var _set := RID()
var _size := Vector2i.ZERO
var _ready := false
var _closed := false
# Written on the render thread, observed there by one-off preparation work.
var completed_renders := 0
const Programs = preload("res://src/game/fx/raytrace_programs.gd")
var programs: Programs
var incremental_build := false
var _building := false
var _build_cursor := 0
var _pending_images: Array[Image] = []
var _texture_cursor := 0
var build_timings := {}
const RESOURCE_PHASES := ["program","vertices","materials","placements","textures","extra"]
var _build_resource_stage := -1
var _build_resource_cpu_us := 0
var _build_started := 0
var _build_data := PackedByteArray()
var _build_placements: Array = []
var _build_material_data := PackedByteArray()
var _build_material_cursor := 0
var _build_hit_range := 0
var initial_poses: Array = []
var _opaque_fast_path := not OS.get_cmdline_user_args().has("--ei-water-rt-force-anyhit")

func shader_prefix() -> String: return SHADERS
func shader_stage_path(stage: int) -> String: return shader_prefix()+STAGES[stage]
func frame_bytes() -> int: return FRAME_BYTES
func instance_id(geometry_index: int, _placement_index: int) -> int: return geometry_index
func build_extra(_data: PackedByteArray, _placements: Array) -> bool: return true

func reflection_output() -> Texture2DRD: return output

func output_ready() -> bool:
	return not _closed and _ready and output.texture_rd_rid.is_valid()

## A settings request must complete its own render, not reuse an older image's
## readiness. Notify once after pipeline creation and command recording; the
## screen then remains through the real post-draw settling frames.
func render_preparation(preparation: int, size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	var before := completed_renders
	render(size, frame, changes, texture_filter)
	_notify(&"rendered", [preparation, completed_renders > before and output_ready()])

## A method Callable stores only its target's ObjectID. Bind the RefCounted
## owner as data so cancellation cannot destroy it during queued GPU work.
static func dispatch(target: RefCounted, method: StringName, arguments: Array = []) -> void:
	RenderingServer.call_on_render_thread(_dispatch.bind(target,method,arguments))

static func _dispatch(target: RefCounted, method: StringName, arguments: Array) -> void:
	target.callv(method,arguments)

## Deferred Signal values are also weak. Keep a canceled device alive until
## the main thread has consumed notifications emitted by its queued work.
func _notify(signal_name: StringName, arguments: Array) -> void:
	_emit_retained.call_deferred(self,signal_name,arguments)

static func _emit_retained(target: RefCounted, signal_name: StringName, arguments: Array) -> void:
	target.emit_signal.callv([signal_name]+arguments)

## Ray-tracing support cannot change while the process runs; the first
## positive answer is kept instead of six engine queries per frame.
static var _supported_known := false

static func supported() -> bool:
	if _supported_known: return true
	var result := _query_supported()
	if result: _supported_known = true
	return result

static func _query_supported() -> bool:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus": return false
	var driver := RenderingServer.get_current_rendering_driver_name()
	if driver == "vulkan":
		if not OS.has_feature("ei_raytracing_uniform_stages"): return false
	elif driver == "d3d12":
		if not OS.has_feature("ei_d3d12_raytracing"): return false
	else: return false
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE)

func _own(rid: RID) -> RID:
	if rid.is_valid(): _owned.append(rid)
	return rid

func _compile() -> RDPipelineShader:
	if programs!=null:
		var paths := {}
		for stage in STAGES:paths[stage]=shader_stage_path(stage)
		_shader=programs.program(_rd,paths,RenderingServer.get_current_rendering_driver_name()=="d3d12")
		if not _shader.is_valid():return null
		var cached := RDPipelineShader.new();cached.shader=_shader;return cached
	var spirv := RDShaderSPIRV.new()
	var dxil := {}
	var directx := RenderingServer.get_current_rendering_driver_name() == "d3d12"
	for stage in STAGES:
		var path: String = shader_stage_path(stage)
		var bytes := FileAccess.get_file_as_bytes(path + ".spv")
		if bytes.is_empty():
			push_error("Water RT shader is missing: " + path)
			return null
		spirv.set_stage_bytecode(stage, bytes)
		if directx:
			dxil[stage] = FileAccess.get_file_as_bytes(path + ".dxil")
			if dxil[stage].is_empty(): return null
	var shader: RID
	if directx:
		shader = _rd.call("shader_create_from_spirv_and_dxil", spirv, dxil, "Water RT")
	else:
		shader = _rd.shader_create_from_spirv(spirv, "Water RT")
	_own(shader)
	if not shader.is_valid(): return null
	_shader = shader
	var wrapped := RDPipelineShader.new()
	wrapped.shader = shader
	return wrapped

func _compute_program(spirv: RDShaderSPIRV,label: String) -> Array[RID]:
	if programs!=null:return programs.compute(_rd,spirv,label)
	var shader:=_own(_rd.shader_create_from_spirv(spirv,label))
	return [shader,_own(_rd.compute_pipeline_create(shader)) if shader.is_valid() else RID()]

func instance_mask(_geometry_index: int, mask: int) -> int: return mask

func _create_pipeline(program: RDPipelineShader) -> RID:
	if programs!=null:return programs.pipeline(program)
	var group := RDHitGroup.new();group.closest_hit_shader=program;group.any_hit_shader=program
	return _own(_rd.raytracing_pipeline_create([program],[program],[group],1))

## data contains a non-indexed triangle list, 64 bytes per vertex. Images are
## private CPU snapshots; the render thread never reads scene nodes.
func build(data: PackedByteArray, images: Array[Image], geometry_data: Array = [], placements: Array = []) -> void:
	if _closed:return
	_build_started=Time.get_ticks_usec()
	_rd=RenderingServer.get_rendering_device()
	if _rd==null or not _rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE) or data.is_empty() or images.is_empty():
		_notify(&"prepared",[false]);return
	# Capture the same private descriptors at enqueue time. A caller editing
	# its arrays after build returns cannot alter this candidate's contents.
	_build_data=data
	_geometry=geometry_data.duplicate(true) if not geometry_data.is_empty() else [{"offset":0,"count":data.size()/64}]
	_build_placements=placements.duplicate(true) if not placements.is_empty() else [{"geometry":0,"transform":Transform3D.IDENTITY,"mask":255}]
	_pending_images.assign(images)
	_build_resource_stage=0;_building=incremental_build;_ready=false
	_build_resource_cpu_us=Time.get_ticks_usec()-_build_started
	build_timings["input_copy_ms"]=_build_resource_cpu_us/1000.0
	if incremental_build:return
	# Initial/loading construction retains its synchronous completion contract.
	while _build_resource_stage>=0:
		if not _advance_resource_build():return
	_ready=true;_notify(&"prepared",[true])

func _clear_build_inputs() -> void:
	_build_data=PackedByteArray();_build_placements=[];_build_material_data=PackedByteArray()
	initial_poses.clear()

func _advance_resource_build() -> bool:
	var phase:=_build_resource_stage;var started:=Time.get_ticks_usec()
	var result:=_build_resource_phase(phase)
	var elapsed:=Time.get_ticks_usec()-started
	_build_resource_cpu_us+=elapsed
	var label: String=RESOURCE_PHASES[phase]+"_ms"
	build_timings[label]=build_timings.get(label,0.0)+elapsed/1000.0
	build_timings["resource_steps"]=int(build_timings.get("resource_steps",0))+1
	build_timings["resource_stage"]=RESOURCE_PHASES[phase]
	build_timings["resources_ms"]=_build_resource_cpu_us/1000.0
	build_timings["largest_resource_step_ms"]=maxf(build_timings.get("largest_resource_step_ms",0.0),elapsed/1000.0)
	build_timings["largest_step_ms"]=maxf(build_timings.get("largest_step_ms",0.0),elapsed/1000.0)
	if result!=OK and result!=ERR_BUSY:
		_building=false;_ready=false;_build_resource_stage=-1
		_clear_build_inputs();_pending_images.clear();_notify(&"prepared",[false]);return false
	if result==OK:_build_resource_stage+=1
	if _build_resource_stage==RESOURCE_PHASES.size():
		_build_resource_stage=-1;_clear_build_inputs()
		build_timings["resource_prepare_ms"]=(Time.get_ticks_usec()-_build_started)/1000.0
		build_timings["resource_stage"]="complete"
	return true

func _build_resource_phase(phase: int) -> int:
	match phase:
		0:return _build_program()
		1:return _build_vertices()
		2:return _build_materials()
		3:return _build_placement_batch()
		4:return _build_textures()
		5:return build_extra_step(_build_data,_build_placements)
	return ERR_INVALID_PARAMETER

func build_extra_ready() -> bool:return true

func build_extra_step(data: PackedByteArray,placements: Array) -> int:
	return OK if build_extra(data,placements) else ERR_CANT_CREATE

func _build_program() -> int:
	var program := _compile()
	if program == null:
		return ERR_CANT_CREATE
	_pipeline = _create_pipeline(program)
	if not _pipeline.is_valid():
		return ERR_CANT_CREATE
	return OK

func _build_vertices() -> int:
	_vertices = _own(_rd.vertex_buffer_create(_build_data.size(),_build_data,
		RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT |
		RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT | RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT))
	if not _vertices.is_valid():
		return ERR_CANT_CREATE
	for pose: Dictionary in initial_poses:
		if not _upload_pose(pose):return ERR_CANT_CREATE
	initial_poses.clear()
	return OK

func _build_materials() -> int:
	if _build_material_data.is_empty():_build_material_data.resize(_geometry.size()*16)
	var started:=Time.get_ticks_usec();var processed:=0
	while _build_material_cursor<_geometry.size():
		var i:=_build_material_cursor
		var description: Dictionary = _geometry[i]
		_build_material_data.encode_u32(i*16,description.offset)
		# Independent flags preserve the legacy standard-emission bit. Mask
		# layers are raw data in the existing array; zero means no plant mask.
		var flags := int(description.get("standard",false)) | (int(description.get("terrain",false))<<1)
		if description.get("foliage_layer",-1)>=0:
			flags |= ((description.foliage_layer+1)<<8) | (int(description.get("leaf_light",false))<<2) | (int(description.get("bark_relief",false))<<3)
		# Bits 16..23 identify an optional linear surface map in the same
		# array. Zero keeps the scalar profile and the old shader fast path.
		if description.get("surface_layer",-1)>=0:
			flags |= (description.surface_layer+1)<<16
		if description.get("detail_layer",-1)>=0:
			flags |= (description.detail_layer+1)<<24
		_build_material_data.encode_u32(i*16+4,flags)
		_build_material_data.encode_float(i*16+8,description.get("cutoff",0.5))
		# The final word was reserved. Water/one-bounce shaders ignore it;
		# path tracing uses a compact roughness/metalness/specular profile.
		var surface: Vector3 = description.get("surface",Vector3(1.0,0.0,0.5))
		var relief := roundi(clampf(description.get("relief",0.0),0.0,1.0)*127.0)
		_build_material_data.encode_u32(i*16+12,0x80000000 | roundi(clampf(surface.x,0.0,1.0)*255.0) \
			| (roundi(clampf(surface.y,0.0,1.0)*255.0)<<8) | (roundi(clampf(surface.z,0.0,1.0)*255.0)<<16) | (relief<<24))
		_build_material_cursor+=1;processed+=1
		if incremental_build and _build_material_cursor<_geometry.size() and (processed>=1024 or Time.get_ticks_usec()-started>=1500):return ERR_BUSY
	_materials = _own(_rd.storage_buffer_create(_build_material_data.size(),_build_material_data))
	if not _materials.is_valid():return ERR_CANT_CREATE
	_build_material_data=PackedByteArray()
	return OK

func _build_placement_batch() -> int:
	if _instances.is_empty():
		_blases.resize(_geometry.size())
		_tlas = _own(_rd.tlas_create(_build_placements.size(),RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT))
		_sbt = _own(_rd.hit_sbt_create(_pipeline,1))
		if not _tlas.is_valid() or not _sbt.is_valid():
			return ERR_CANT_CREATE
		_build_hit_range = _rd.hit_sbt_range_alloc(_sbt,1)
		_rd.hit_sbt_range_update(_sbt,_build_hit_range,0,[0])
	var started:=Time.get_ticks_usec();var processed:=0
	while _instances.size()<_build_placements.size():
		var placement: Dictionary=_build_placements[_instances.size()]
		var instance := RDAccelerationStructureInstance.new()
		_placement_geometry.append(placement.geometry)
		if placement.get("mask",255) != 0 and not incremental_build:
			instance.blas = _geometry_blas(placement.geometry)
			if not instance.blas.is_valid():return ERR_CANT_CREATE
		instance.id = instance_id(placement.geometry,_instances.size())
		instance.transform = placement.transform
		instance.mask = instance_mask(placement.geometry,placement.get("mask",255))
		instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
		instance.hit_sbt_range = _build_hit_range
		if instance.mask != 0: _active_instances[_instances.size()] = instance
		_instances.append(instance)
		processed+=1
		if incremental_build and _instances.size()<_build_placements.size() and (processed>=1024 or Time.get_ticks_usec()-started>=1500):return ERR_BUSY
	if not incremental_build and not _build_tlas():return ERR_CANT_CREATE
	return OK

func _build_textures() -> int:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = _pending_images[0].get_width()
	format.height = _pending_images[0].get_height()
	format.array_layers = _pending_images.size()
	format.mipmaps = _pending_images[0].get_mipmap_count()+1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var layers: Array[PackedByteArray] = []
	if incremental_build:
		format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	else:
		for im in _pending_images: layers.append(im.get_data())
	_colours = _own(_create_colour_array(format,layers))
	# Small immutable samplers let the existing Texture filtering option
	# change live without rebuilding the RT scene or reallocating its image.
	for quality in 5:
		var sampler := RDSamplerState.new()
		sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.use_anisotropy = quality > 0
		sampler.anisotropy_max = 1 << quality
		sampler.max_lod = 20.0
		sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		_samplers.append(_own(_rd.sampler_create(sampler)))
	_frame = _own(_rd.uniform_buffer_create(frame_bytes()))
	if not incremental_build:_pending_images.clear()
	return OK if _colours.is_valid() and _frame.is_valid() and _samplers.all(func(rid: RID): return rid.is_valid()) else ERR_CANT_CREATE

## The controller queues at most one step per frame. A canceled owner cannot
## schedule more work, and its previous scene remains visible throughout.
func build_step(budget_us := 1500) -> void:
	if _closed or not _building:return
	# A moving main view can spend a larger, still bounded slice preparing its
	# next region. Do not turn tiny completed phases into mandatory idle frames.
	var deadline:=Time.get_ticks_usec()+clampi(budget_us,1500,6000)
	while _build_resource_stage>=0:
		# Pending CPU work is polled once per frame, never spun to the deadline.
		if _build_resource_stage==5 and not build_extra_ready():return
		if not _advance_resource_build():return
		if budget_us<=1500 or Time.get_ticks_usec()>=deadline:return
	var started := Time.get_ticks_usec();var built := 0
	# Retain the private CPU snapshots until each array layer and all its mips
	# have been uploaded. The controller keeps displaying the old scene and
	# cannot promote this candidate before both uploads and AS builds finish.
	if not _pending_images.is_empty():
		while _texture_cursor < _pending_images.size():
			if not _upload_colour_layer(_texture_cursor,_pending_images[_texture_cursor].get_data()):
				_building=false;_pending_images.clear();_notify(&"prepared",[false]);return
			_pending_images[_texture_cursor]=null
			_texture_cursor+=1;built+=1
			if built>=(4 if budget_us<=1500 else 64) or Time.get_ticks_usec()>=deadline:break
		if _texture_cursor==_pending_images.size():_pending_images.clear()
		var elapsed := (Time.get_ticks_usec()-started)/1000.0
		build_timings["texture_upload_ms"]=build_timings.get("texture_upload_ms",0.0)+elapsed
		build_timings["texture_upload_step_ms"]=maxf(build_timings.get("texture_upload_step_ms",0.0),elapsed)
		build_timings["largest_step_ms"]=maxf(build_timings.get("largest_step_ms",0.0),elapsed)
		if not _pending_images.is_empty() or budget_us<=1500 or Time.get_ticks_usec()>=deadline:return
		built=0
	while _build_cursor<_instances.size():
		var instance := _instances[_build_cursor]
		if instance.mask!=0:
			var geometry := _placement_geometry[_build_cursor]
			if not _blases[geometry].is_valid():built+=1
			instance.blas=_geometry_blas(geometry)
			if not instance.blas.is_valid():_building=false;_notify(&"prepared",[false]);return
		_build_cursor+=1
		if built>=(16 if budget_us<=1500 else 4096) or Time.get_ticks_usec()>=deadline:break
	if _build_cursor==_instances.size():
		_building=false
		_ready=_build_tlas()
		_notify(&"prepared",[_ready])
	build_timings["largest_step_ms"]=maxf(build_timings.get("largest_step_ms",0.0),(Time.get_ticks_usec()-started)/1000.0)

func _upload_colour_layer(layer: int, data: PackedByteArray) -> bool:
	return _rd.texture_update(_colours,layer,data)==OK

func _create_colour_array(format: RDTextureFormat, layers: Array[PackedByteArray]) -> RID:
	return _rd.texture_create(format,RDTextureView.new(),layers)

## Hidden meshes keep CPU/vertex data, but acquire a BLAS only when first
## revealed. Reuse it afterward; movement needs only a compact TLAS rebuild.
func _geometry_blas(index: int) -> RID:
	if _blases[index].is_valid(): return _blases[index]
	var description: Dictionary = _geometry[index]
	var geometry := RDAccelerationStructureGeometry.new()
	if _opaque_fast_path and description.get("opaque",false):
		geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	geometry.vertex_buffer = _vertices
	geometry.vertex_offset = description.offset*64
	geometry.vertex_count = description.count
	geometry.vertex_stride = 64
	geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	var blas := _own(_rd.blas_create([geometry],RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT))
	if not blas.is_valid() or _rd.blas_build(blas) != OK: return RID()
	_blases[index] = blas
	return blas

func _uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = kind
	uniform.binding = binding
	for rid in ids: uniform.add_id(rid)
	return uniform

func _upload_pose(pose: Dictionary) -> bool:
	return _rd.buffer_update(_vertices,_geometry[pose.geometry].offset*64,pose.data.size(),pose.data)==OK

func _build_tlas() -> bool:
	return _rd.tlas_build(_tlas,_active_instances.values())==OK

func update_scene(changes: Dictionary) -> bool:
	if _closed or not _ready: return false
	var changed := false
	for pose: Dictionary in changes.get("poses",[]):
		if not _upload_pose(pose):
			_ready=false;_notify(&"prepared",[false]);return false
		if _blases[pose.geometry].is_valid() and _rd.blas_build(_blases[pose.geometry]) != OK:
			_ready = false; _notify(&"prepared",[false]); return false
		changed = true
	for placement: Dictionary in changes.get("instances",[]):
		var instance := _instances[placement.index]
		# PT may update only a lighting-origin offset. It does not move the
		# traced geometry, so neither it nor a duplicate needs another TLAS.
		var mask := instance_mask(_placement_geometry[placement.index],placement.mask)
		if instance.transform==placement.transform and instance.mask==mask:continue
		var was_visible := instance.mask!=0
		instance.transform = placement.transform
		instance.mask = mask
		if mask != 0:
			instance.blas = _geometry_blas(_placement_geometry[placement.index])
			if not instance.blas.is_valid(): _ready = false; _notify(&"prepared",[false]); return false
			_active_instances[placement.index] = instance
		else: _active_instances.erase(placement.index)
		# Hidden transforms are retained for their next reveal, but there is
		# no active descriptor to update until visibility changes.
		changed = changed or was_visible or mask!=0
	if changed and not _build_tlas():
		_ready = false; _notify(&"prepared",[false]); return false
	return true

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if not update_scene(changes): return
	var sampler := _samplers[clampi(texture_filter,0,_samplers.size()-1)]
	if size != _size or sampler != _sampler:
		var resized := size != _size
		var target := _target
		if resized:
			var format := RDTextureFormat.new()
			format.width = size.x
			format.height = size.y
			format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
			format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			target = _rd.texture_create(format,RDTextureView.new())
		if not target.is_valid():
			_ready = false
			_notify(&"prepared",[false])
			return
		var uniforms := _rd.uniform_set_create([
			_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,[_tlas]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[target]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[_vertices]),
			_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,3,[_colours]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,6,[sampler]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[_frame]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,[_materials])],_shader,0)
		if not uniforms.is_valid():
			if resized: _rd.free_rid(target)
			_ready = false
			_notify(&"prepared",[false])
			return
		# Replace the backing texture while the old one is still alive so
		# Texture2DRD preserves the RS RID already bound by the water material.
		var old_target := _target
		var old_set := _set
		_target = target
		_set = uniforms
		_sampler = sampler
		_size = size
		if resized: output.texture_rd_rid = target
		if old_set.is_valid(): _rd.free_rid(old_set)
		if resized and old_target.is_valid(): _rd.free_rid(old_target)
	if frame.size() < FRAME_BYTES: frame.resize(FRAME_BYTES)
	if _rd.buffer_update(_frame,0,frame.size(),frame) != OK:
		_ready = false
		_notify(&"prepared", [false])
		return
	var list := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(list,_pipeline)
	_rd.raytracing_list_bind_uniform_set(list,_set,0)
	_rd.raytracing_list_trace_rays(list,0,_sbt,size.x,size.y,1)
	_rd.raytracing_list_end()
	completed_renders += 1

func dispose() -> void:
	_build_resource_stage=-1;_clear_build_inputs()
	_closed = true
	_building = false
	_ready = false
	_pending_images.clear()
	output.texture_rd_rid = RID()
	_samplers.clear()
	if _rd == null: return
	if _set.is_valid(): _rd.free_rid(_set)
	if _target.is_valid(): _rd.free_rid(_target)
	# Lazily created BLAS objects can be newer than their TLAS. Release the
	# TLAS explicitly before reversing the remaining dependency order.
	if _tlas.is_valid():
		_rd.free_rid(_tlas); _owned.erase(_tlas); _tlas = RID()
	# A derived device may lazily switch the SBT to a newer pipeline. Release
	# it before either pipeline, regardless of their allocation order.
	if _sbt.is_valid():
		_rd.free_rid(_sbt); _owned.erase(_sbt); _sbt = RID()
	_owned.reverse()
	for rid in _owned: _rd.free_rid(rid)
	_owned.clear()
	_blases.clear(); _instances.clear(); _active_instances.clear(); _geometry.clear(); _placement_geometry.clear()
	_set = RID()
	_target = RID()
