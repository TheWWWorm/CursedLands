extends RefCounted
## Shared hardware RT pipeline for DX12 and Vulkan. Resources belong to the
## render thread; queued callables retain this owner until disposal finishes.
signal prepared(ok: bool)

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
var _opaque_fast_path := not OS.get_cmdline_user_args().has("--ei-water-rt-force-anyhit")

func shader_prefix() -> String: return SHADERS
func shader_stage_path(stage: int) -> String: return shader_prefix()+STAGES[stage]
func frame_bytes() -> int: return FRAME_BYTES
func instance_id(geometry_index: int, _placement_index: int) -> int: return geometry_index
func build_extra(_data: PackedByteArray, _placements: Array) -> bool: return true

static func supported() -> bool:
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

## data contains a non-indexed triangle list, 64 bytes per vertex. Images are
## private CPU snapshots; the render thread never reads scene nodes.
func build(data: PackedByteArray, images: Array[Image], geometry_data: Array = [], placements: Array = []) -> void:
	if _closed: return
	_rd = RenderingServer.get_rendering_device()
	if _rd == null or not _rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE) or data.is_empty() or images.is_empty():
		prepared.emit.call_deferred(false)
		return
	var program := _compile()
	if program == null:
		prepared.emit.call_deferred(false)
		return
	var group := RDHitGroup.new()
	group.closest_hit_shader = program
	group.any_hit_shader = program
	_pipeline = _own(_rd.raytracing_pipeline_create([program],[program],[group],1))
	if not _pipeline.is_valid():
		prepared.emit.call_deferred(false)
		return
	_vertices = _own(_rd.vertex_buffer_create(data.size(),data,
		RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT |
		RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT | RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT))
	if not _vertices.is_valid():
		prepared.emit.call_deferred(false)
		return
	# Own the descriptors: teardown must not clear the caller's scene array.
	_geometry = geometry_data.duplicate(true) if not geometry_data.is_empty() else [{"offset":0,"count":data.size()/64}]
	var material_data := PackedByteArray(); material_data.resize(_geometry.size()*16)
	for i in _geometry.size():
		var description: Dictionary = _geometry[i]
		material_data.encode_u32(i*16,description.offset)
		material_data.encode_u32(i*16+4,1 if description.get("standard",false) else 0)
		material_data.encode_float(i*16+8,description.get("cutoff",0.5))
		# The final word was reserved. Water/one-bounce shaders ignore it;
		# path tracing uses a compact roughness/metalness/specular profile.
		var surface: Vector3 = description.get("surface",Vector3(1.0,0.0,0.5))
		material_data.encode_u32(i*16+12,0x80000000 | roundi(clampf(surface.x,0.0,1.0)*255.0) \
			| (roundi(clampf(surface.y,0.0,1.0)*255.0)<<8) | (roundi(clampf(surface.z,0.0,1.0)*255.0)<<16))
	_materials = _own(_rd.storage_buffer_create(material_data.size(),material_data))
	if not _materials.is_valid(): prepared.emit.call_deferred(false); return
	_blases.resize(_geometry.size())
	if placements.is_empty(): placements = [{"geometry":0,"transform":Transform3D.IDENTITY,"mask":255}]
	_tlas = _own(_rd.tlas_create(placements.size(),RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT))
	_sbt = _own(_rd.hit_sbt_create(_pipeline,1))
	if not _tlas.is_valid() or not _sbt.is_valid():
		prepared.emit.call_deferred(false); return
	var hit_range := _rd.hit_sbt_range_alloc(_sbt,1)
	_rd.hit_sbt_range_update(_sbt,hit_range,0,[0])
	for placement: Dictionary in placements:
		var instance := RDAccelerationStructureInstance.new()
		_placement_geometry.append(placement.geometry)
		if placement.get("mask",255) != 0:
			instance.blas = _geometry_blas(placement.geometry)
			if not instance.blas.is_valid(): prepared.emit.call_deferred(false); return
		instance.id = instance_id(placement.geometry,_instances.size())
		instance.transform = placement.transform
		instance.mask = placement.get("mask",255)
		instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
		instance.hit_sbt_range = hit_range
		if instance.mask != 0: _active_instances[_instances.size()] = instance
		_instances.append(instance)
	if _rd.tlas_build(_tlas,_active_instances.values()) != OK:
		prepared.emit.call_deferred(false); return
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = images[0].get_width()
	format.height = images[0].get_height()
	format.array_layers = images.size()
	format.mipmaps = images[0].get_mipmap_count()+1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var layers: Array[PackedByteArray] = []
	for im in images: layers.append(im.get_data())
	_colours = _own(_rd.texture_create(format,RDTextureView.new(),layers))
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
	_ready = _colours.is_valid() and _frame.is_valid() and _samplers.all(func(rid: RID): return rid.is_valid())
	if _ready: _ready = build_extra(data,placements)
	prepared.emit.call_deferred(_ready)

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

func update_scene(changes: Dictionary) -> bool:
	if _closed or not _ready: return false
	var changed := false
	for pose: Dictionary in changes.get("poses",[]):
		_rd.buffer_update(_vertices,_geometry[pose.geometry].offset*64,pose.data.size(),pose.data)
		if _blases[pose.geometry].is_valid() and _rd.blas_build(_blases[pose.geometry]) != OK:
			_ready = false; prepared.emit.call_deferred(false); return false
		changed = true
	for placement: Dictionary in changes.get("instances",[]):
		_instances[placement.index].transform = placement.transform
		_instances[placement.index].mask = placement.mask
		if placement.mask != 0:
			var instance := _instances[placement.index]
			instance.blas = _geometry_blas(_placement_geometry[placement.index])
			if not instance.blas.is_valid(): _ready = false; prepared.emit.call_deferred(false); return false
			_active_instances[placement.index] = instance
		else: _active_instances.erase(placement.index)
		changed = true
	if changed and _rd.tlas_build(_tlas,_active_instances.values()) != OK:
		_ready = false; prepared.emit.call_deferred(false); return false
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
			prepared.emit.call_deferred(false)
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
			prepared.emit.call_deferred(false)
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
	_rd.buffer_update(_frame,0,frame.size(),frame)
	var list := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(list,_pipeline)
	_rd.raytracing_list_bind_uniform_set(list,_set,0)
	_rd.raytracing_list_trace_rays(list,0,_sbt,size.x,size.y,1)
	_rd.raytracing_list_end()

func dispose() -> void:
	_closed = true
	_ready = false
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
