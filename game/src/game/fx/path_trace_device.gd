extends "res://src/game/fx/scene_raytrace_device.gd"
## Same scene and stable texture lifetime as RT lighting. Channels become
## diffuse illumination, normal/depth, glossy radiance and albedo/roughness.
const PATH_FILTER = preload("res://src/game/fx/shaders/path_trace_filter.glsl")
const Emitters = preload("res://src/game/fx/path_trace_emitters.gd")
const Terrain = preload("res://src/game/fx/path_trace_terrain.gd")
var terrain := Terrain.new()
var _terrain_data := RID()
var _terrain_atlas := RID()
signal emitter_stats(count: int, candidates: int)
var emitters := Emitters.new()
var _instance_geometry := RID()
var _emitters := RID()
var _emitter_lookup := RID()
var _uses_emitters := false
var _deep_paths := false
# Diagnostic full-path reference; normal play uses the compensated deep tail.
var _full_paths_reference := OS.get_cmdline_user_args().has("--ei-full-paths")
var _variants := {}
# Each record maps the current rigid surface and shading normal to their
# previous rendered positions. Unchanged placements take the identity fast path.
const MOTION_STRIDE := 96
var _motion := RID()
var _motion_data := PackedByteArray()
var _motion_pending := {}
var _geometry_placements: Array[Array] = []
# Same-build reconstruction reference; normal play follows articulated meshes.
var _rigid_history := not OS.get_cmdline_user_args().has("--ei-camera-only-history")
func shader_prefix() -> String: return "res://src/game/fx/shaders/path_trace_"
func shader_stage_path(stage: int) -> String:
	if stage==RenderingDevice.SHADER_STAGE_CLOSEST_HIT and terrain.data.size()>=Terrain.HEADER and terrain.data.decode_u32(0)>0:
		return shader_prefix()+("closest_hit_transitions" if terrain.data.decode_u32(56)>0 else "closest_hit_terrain")
	if stage==RenderingDevice.SHADER_STAGE_RAYGEN:
		return shader_prefix()+"raygen"+("_deep" if _deep_paths else "")+("_no_emitters" if not _uses_emitters else "")
	return super.shader_stage_path(stage)
func frame_bytes() -> int: return 704
func filter_spirv() -> RDShaderSPIRV: return PATH_FILTER.get_spirv()
func filter_auxiliary_formats() -> Array[int]:
	return [RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT]
func extra_filter_uniforms() -> Array[RDUniform]:
	return [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,17,[_motion])]

# Geometry is shared by several placements. Lights need their unique, stable
# placement ID, including when hidden instances are removed from the TLAS.
func instance_id(_geometry_index: int, placement_index: int) -> int: return placement_index

func build_extra(data: PackedByteArray, placements: Array) -> bool:
	if terrain.data.is_empty(): terrain.data.resize(Terrain.HEADER)
	_terrain_data = _own(_rd.storage_buffer_create(terrain.data.size(),terrain.data))
	# Borrow the immutable raster atlas, with a retained TextureLayered owner.
	# Synthetic/non-terrain scenes bind the existing array as an unused dummy.
	_terrain_atlas = RenderingServer.texture_get_rd_texture(terrain.atlas.get_rid(),true) if terrain.atlas else _colours
	if not _terrain_data.is_valid() or not _terrain_atlas.is_valid(): return false
	_variants[0] = {"shader":_shader,"pipeline":_pipeline}
	var mapping := _placement_geometry.to_byte_array()
	_instance_geometry = _own(_rd.storage_buffer_create(mapping.size(),mapping))
	_motion_data.resize(placements.size()*MOTION_STRIDE)
	for i in _geometry.size(): _geometry_placements.append([])
	for i in placements.size():
		_geometry_placements[placements[i].geometry].append(i)
		_write_motion(i,Transform3D.IDENTITY,Basis.IDENTITY,true,false)
	_motion = _own(_rd.storage_buffer_create(_motion_data.size(),_motion_data))
	emitters.setup(data,_geometry,placements,_opaque_fast_path)
	_emitters = _own(_rd.storage_buffer_create(Emitters.HEADER+Emitters.LIMIT*Emitters.STRIDE))
	_emitter_lookup = _own(_rd.storage_buffer_create(Emitters.HASH_SLOTS*16))
	return _instance_geometry.is_valid() and _motion.is_valid() and _emitters.is_valid() and _emitter_lookup.is_valid() \
		and _upload_emitters() and _select_pipeline(emitters.count>0,_deep_paths)

## Compile only the needed emitter/deep-path combinations. Every variant
## shares hit stages, TLAS, SBT ranges and stable output images.
func _select_pipeline(enabled: bool,deep: bool) -> bool:
	if enabled==_uses_emitters and deep==_deep_paths: return true
	var key := int(enabled)|(int(deep)<<1)
	if not _variants.has(key):
		# Compilation reads these flags and replaces _shader. Do not publish a
		# requested mode until both its pipeline and SBT transition succeed.
		var old_enabled := _uses_emitters;var old_deep := _deep_paths;var old_shader := _shader
		_uses_emitters=enabled;_deep_paths=deep
		var program := _compile()
		var shader := _shader
		_uses_emitters=old_enabled;_deep_paths=old_deep;_shader=old_shader
		if program==null: return false
		var group := RDHitGroup.new();group.closest_hit_shader=program;group.any_hit_shader=program
		var pipeline := _own(_rd.raytracing_pipeline_create([program],[program],[group],1))
		if not pipeline.is_valid(): return false
		_variants[key] = {"shader":shader,"pipeline":pipeline}
	if _rd.hit_sbt_set_pipeline(_sbt,_variants[key].pipeline)!=OK: return false
	_shader=_variants[key].shader;_pipeline=_variants[key].pipeline
	_uses_emitters=enabled;_deep_paths=deep
	if _set.is_valid(): _rd.free_rid(_set);_set=RID()
	_history_valid = false
	return true

func _upload_emitters() -> bool:
	if _rd.buffer_update(_emitters,0,emitters.records.size(),emitters.records) != OK \
		or _rd.buffer_update(_emitter_lookup,0,emitters.lookup.size(),emitters.lookup) != OK: return false
	_notify(&"emitter_stats",[emitters.count,emitters.candidates])
	return true

func extra_ray_uniforms() -> Array[RDUniform]:
	var uniforms: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,10,[_instance_geometry]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,13,[_terrain_data]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,14,[_terrain_atlas])]
	if _uses_emitters:
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,11,[_emitters]))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,12,[_emitter_lookup]))
	return uniforms

func update_scene(changes: Dictionary) -> bool:
	if _closed or not _ready: return false
	if not _update_motion(changes):
		_render_failed();return false
	if not super.update_scene(changes): return false
	if emitters.update(changes):
		_history_valid = false
		if not _upload_emitters() or not _select_pipeline(emitters.count>0,_deep_paths):
			_render_failed();return false
	return true

func _write_motion(index: int,position: Transform3D,normal: Basis,valid: bool,moving: bool) -> void:
	var offset := index*MOTION_STRIDE
	for row in 3:
		for column in 3:
			_motion_data.encode_float(offset+(row*4+column)*4,position.basis[column][row])
			_motion_data.encode_float(offset+48+(row*4+column)*4,normal[column][row])
		_motion_data.encode_float(offset+(row*4+3)*4,position.origin[row])
	_motion_data.encode_float(offset+60,float(valid))
	_motion_data.encode_float(offset+76,float(moving and _rigid_history))
	_motion_data.encode_float(offset+92,0.0)

func _update_motion(changes: Dictionary) -> bool:
	# Retire last frame's movement even when no transform changes this frame.
	# Otherwise a stopped actor keeps walking backwards through stale history.
	var dirty := _motion_pending
	_motion_pending = {}
	for index: int in dirty:
		_write_motion(index,Transform3D.IDENTITY,Basis.IDENTITY,true,false)
	var deformed := {}
	for pose: Dictionary in changes.get("poses",[]):
		for index: int in _geometry_placements[pose.geometry]:
			deformed[index] = true
			_write_motion(index,Transform3D.IDENTITY,Basis.IDENTITY,false,false)
			dirty[index] = true;_motion_pending[index] = true
	for placement: Dictionary in changes.get("instances",[]):
		var index: int = placement.index
		var previous: Transform3D = _instances[index].transform
		var current: Transform3D = placement.transform
		var valid: bool = (_instances[index].mask&1)!=0 and (placement.mask&1)!=0 and not deformed.has(index)
		var moving := previous!=current
		var position := Transform3D.IDENTITY
		var normal := Basis.IDENTITY
		if moving and valid:
			# Singular transforms have no corresponding previous surface.
			valid = absf(previous.basis.determinant())>0.00000001 and absf(current.basis.determinant())>0.00000001
			if valid:
				position = previous*current.affine_inverse()
				normal = (current*previous.affine_inverse()).basis.transposed()
		_write_motion(index,position,normal,valid,moving)
		dirty[index] = true;_motion_pending[index] = true
	if dirty.is_empty(): return true
	# One bounded upload avoids an API call for every articulated body part.
	var indices := dirty.keys();indices.sort()
	var begin: int = indices.front()*MOTION_STRIDE
	var end: int = (indices.back()+1)*MOTION_STRIDE
	return _rd.buffer_update(_motion,begin,end-begin,_motion_data.slice(begin,end))==OK

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if _closed or not _ready or size.x<2 or size.y<2 or frame.size()!=frame_bytes(): return
	if not _select_pipeline(_uses_emitters,frame.decode_float(144*4)>2.0 and not _full_paths_reference):
		_render_failed();return
	super.render(size,frame,changes,texture_filter)

func dispose() -> void:
	super.dispose()
	emitters = Emitters.new()
	terrain = Terrain.new();_terrain_atlas=RID()
	_variants.clear()
	_motion=RID();_motion_data.clear();_motion_pending.clear();_geometry_placements.clear()
