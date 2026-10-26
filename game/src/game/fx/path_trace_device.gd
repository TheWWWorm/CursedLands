extends "res://src/game/fx/scene_raytrace_device.gd"
## Same scene and stable texture lifetime as RT lighting. Channels become
## diffuse illumination, normal/depth, glossy radiance and albedo/roughness.
const PATH_FILTER = preload("res://src/game/fx/shaders/path_trace_filter.glsl")
const Emitters = preload("res://src/game/fx/path_trace_emitters.gd")
const Terrain = preload("res://src/game/fx/path_trace_terrain.gd")
const Nrd = preload("res://src/game/fx/path_trace_nrd.gd")
const DIRECT_COMPOSITE = preload("res://src/game/fx/shaders/path_trace_direct_composite.glsl")
const Sharc = preload("res://src/game/fx/path_trace_sharc.gd")
const Rtxdi = preload("res://src/game/fx/path_trace_rtxdi.gd")
const Transmission = preload("res://src/game/fx/path_trace_transmission.gd")
var transmission := Transmission.new()
var transmission_enabled := false
var transmission_failed := false
var _transmission_dirty := true
var rtxdi := Rtxdi.new()
var rtxdi_enabled := false
var rtxdi_failed := false
var _rtxdi_mode := false
var sharc := Sharc.new()
var sharc_enabled := false
var sharc_failed := false
var _sharc_requested := false
var _sharc_mode := 0 # 0 reference, 1 query, 2 update
var _sharc_sbts := {}
var nrd := Nrd.new()
var nrd_active := false
var ray_reconstruction := false
var raw_reconstruction_frames := 0
var presentation_handoffs := 0
var direct_sun := Texture2DRD.new()
var _direct_images: Array[RID] = []
var _direct_auxiliary: Array[RID] = []
var _direct_set := RID()
var _direct_frame := RID()
var _direct_composite_set := RID()
var _direct_composite_shader := RID()
var _direct_composite_pipeline := RID()
var _direct_valid := false
var _nrd_failed := false
var defer_nrd := false
var history_handoffs := 0
var history_matched_surfaces := 0
var _history_reject := PackedInt32Array()
const SPATIAL = preload("res://src/game/fx/shaders/path_trace_spatial.glsl")
var _spatial_shader := RID()
var _spatial_pipeline := RID()
var _spatial_images: Array[RID] = []
var _spatial_sets: Array[RID] = []
var _spatial_source := RID()
# Same-build diagnostic, for matched camera/noise comparisons.
var _spatial_enabled := not OS.get_cmdline_user_args().has("--ei-pt-no-spatial")
var terrain := Terrain.new()
var _terrain_data := RID()
var _terrain_atlas := RID()
var _cloud_texture: Texture2D
var _cloud_image := RID()
var _clear_cloud := RID()
var _cloud_sampler := RID()
signal emitter_stats(count: int, candidates: int)
var emitters := Emitters.new()
var _instance_geometry := RID()
var _lighting_offsets := RID()
var _lighting_offset_data := PackedByteArray()
var _lighting_offset_values: Array[Vector3] = []
var _emitters := RID()
var _emitter_lookup := RID()
var _uses_emitters := false
var _deep_paths := false
# Diagnostic full-path reference; normal play uses the compensated deep tail.
var _full_paths_reference := OS.get_cmdline_user_args().has("--ei-full-paths")
var _variants := {}
var _prepared_path_modes := {}
# Each record maps the current rigid surface and shading normal to their
# previous rendered positions. Unchanged placements take the identity fast path.
const MOTION_STRIDE := 96
# Keep small gaps in one transfer, but do not copy a whole city's static
# records just because two animated objects have distant stable IDs.
const RECORD_UPLOAD_GAP := 32768
const RECORD_UPLOAD_LIMIT := 8
const OFFSET_SPARSE_LIMIT := 128
var _motion := RID()
var _motion_data := PackedByteArray()
var _motion_pending := {}
var _geometry_placements: Array[Array] = []
var _build_extra_phase := 0
# Same-build reconstruction reference; normal play follows articulated meshes.
var _rigid_history := not OS.get_cmdline_user_args().has("--ei-camera-only-history")
func shader_prefix() -> String: return "res://src/game/fx/shaders/path_trace_"
func shader_stage_path(stage: int) -> String:
	if stage==RenderingDevice.SHADER_STAGE_CLOSEST_HIT and terrain.data.size()>=Terrain.HEADER and terrain.data.decode_u32(0)>0:
		return shader_prefix()+("closest_hit_transitions" if terrain.data.decode_u32(56)>0 else "closest_hit_terrain")
	if stage==RenderingDevice.SHADER_STAGE_RAYGEN:
		return shader_prefix()+"raygen"+("_rtxdi" if _rtxdi_mode else "")+("_sharc" if _sharc_mode>0 else "")+("_update" if _sharc_mode==2 else "")+("_deep" if _deep_paths and _sharc_mode!=2 else "")+("_no_emitters" if not _uses_emitters else "")
	return super.shader_stage_path(stage)
func frame_bytes() -> int: return 2816
func filter_spirv() -> RDShaderSPIRV: return PATH_FILTER.get_spirv()
func raw_formats() -> Array[int]:
	var formats := super.raw_formats();formats.append(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT)
	formats.append(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	formats.append(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	# Radiance-weighted first angular moments for directional NRD.
	for i in 2:formats.append(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	return formats
func _ray_bindings(raw: Array[RID],sampler: RID) -> Array[RDUniform]:
	var bindings := super._ray_bindings(raw,sampler)
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,18,[raw[4]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,19,[raw[5]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,20,[raw[6]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,28,[raw[7]]))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,29,[raw[8]]));return bindings
func published_targets() -> Array[RID]:
	var result := super.published_targets();result.append(direct_sun.texture_rd_rid);return result
func _publish_targets() -> void:
	# The base transaction retains the previous published raw AOV on resize
	# until this complete frame has safely replaced every public image.
	var sunlight := _direct_images[0] if _direct_valid else _raw[6]
	if direct_sun.texture_rd_rid!=sunlight:direct_sun.texture_rd_rid=sunlight
	super._publish_targets()

## Called only on the render thread, before queueing the replacement's first
## visible RR frame. Keep the physical global sampler images and RS wrappers;
## rebinding them invalidates every dependent raster material/surface cache.
## No image copies or additional resident images are needed for this handoff.
func adopt_presentation(previous: RefCounted) -> bool:
	if previous==null or previous==self or _rd==null or _rd!=previous._rd \
		or not output_ready() or not previous.output_ready() \
		or not ray_reconstruction or not previous.ray_reconstruction or _size!=previous._size \
		or _history.size()!=4 or previous._history.size()!=4 or _raw.size()!=9 or previous._raw.size()!=9 \
		or _direct_valid or previous._direct_valid or transmission_enabled!=previous.transmission_enabled \
		or not transmission.presentation_compatible(previous.transmission):return false
	if published_targets()!=_history+[_raw[6]] or previous.published_targets()!=previous._history+[previous._raw[6]]:return false
	var raw: Array[RID]=_raw.duplicate();raw[6]=previous._raw[6]
	var replacement_set:=_target_set(_ray_bindings(raw,_sampler),_shader)
	if not replacement_set.is_valid():return false
	var transmission_set:=RID()
	if transmission.active:
		transmission_set=transmission.prepare_presentation(self,previous.transmission)
		if not transmission_set.is_valid():_rd.free_rid(replacement_set);return false
	# All fallible work is complete. Swap whole owners, never mutate a public
	# Texture2DRD's backing. The prior owner retires only after queued work.
	var spare_history:=_history;_history=previous._history;previous._history=spare_history
	var spare_sun:=_raw[6];_raw[6]=previous._raw[6];previous._raw[6]=spare_sun
	for name in ["output","guide","shadow0","shadow1","direct_sun"]:
		var spare: Texture2DRD=get(name);set(name,previous.get(name));previous.set(name,spare)
	sharc.release_update_set()
	if _set.is_valid():_rd.free_rid(_set)
	_set=replacement_set
	transmission.commit_presentation(previous.transmission,transmission_set)
	_transmission_dirty=true
	presentation_handoffs=previous.presentation_handoffs+1
	return true
func filter_auxiliary_formats() -> Array[int]:
	return [RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT]
func uses_filter_targets() -> bool: return not ray_reconstruction
func extra_filter_uniforms(raw_targets: Array[RID]) -> Array[RDUniform]:
	return [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,17,[_motion]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,18,[raw_targets[0]])]

# Geometry is shared by several placements. Lights need their unique, stable
# placement ID, including when hidden instances are removed from the TLAS.
func instance_id(_geometry_index: int, placement_index: int) -> int: return placement_index

func instance_mask(geometry_index: int, mask: int) -> int:
	return (8 if (mask&1)!=0 else 0) if not _geometry[geometry_index].get("dielectric",PackedFloat32Array()).is_empty() else mask

func build_extra(data: PackedByteArray, placements: Array) -> bool:
	return _build_environment() and _build_placement_data(placements) and _build_emitters(data,placements)

func build_extra_step(data: PackedByteArray,placements: Array) -> int:
	if not incremental_build:return super.build_extra_step(data,placements)
	var started:=Time.get_ticks_usec();var ok:=false
	var label: String=["environment","motion","emitters"][_build_extra_phase]
	match _build_extra_phase:
		0:ok=_build_environment()
		1:ok=_build_placement_data(placements)
		2:ok=_build_emitters(data,placements)
	build_timings["extra_stage"]=label
	build_timings["extra_"+label+"_ms"]=(Time.get_ticks_usec()-started)/1000.0
	if not ok:return ERR_CANT_CREATE
	_build_extra_phase+=1
	return OK if _build_extra_phase==3 else ERR_BUSY

func _build_environment() -> bool:
	if terrain.data.is_empty(): terrain.data.resize(Terrain.HEADER)
	_terrain_data = _own(_rd.storage_buffer_create(terrain.data.size(),terrain.data))
	# Borrow the immutable raster atlas, with a retained TextureLayered owner.
	# Synthetic/non-terrain scenes bind the existing array as an unused dummy.
	_terrain_atlas = RenderingServer.texture_get_rd_texture(terrain.atlas.get_rid(),true) if terrain.atlas else _colours
	if not _terrain_data.is_valid() or not _terrain_atlas.is_valid(): return false
	var cloud_format := RDTextureFormat.new()
	cloud_format.width=1;cloud_format.height=1
	cloud_format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	cloud_format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_clear_cloud=_own(_rd.texture_create(cloud_format,RDTextureView.new(),[PackedByteArray([255,255,255,255])]))
	var cloud_sampler := RDSamplerState.new()
	cloud_sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR;cloud_sampler.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	cloud_sampler.mip_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	cloud_sampler.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT;cloud_sampler.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_cloud_sampler=_own(_rd.sampler_create(cloud_sampler))
	if not _clear_cloud.is_valid() or not _cloud_sampler.is_valid():return false
	_cloud_image=_clear_cloud
	_variants[0] = {"shader":_shader,"pipeline":_pipeline}
	return true

func _build_placement_data(placements: Array) -> bool:
	var mapping := _placement_geometry.to_byte_array()
	_instance_geometry = _own(_rd.storage_buffer_create(mapping.size(),mapping))
	_lighting_offset_data.resize(placements.size()*16)
	_lighting_offset_values.resize(placements.size())
	for i in placements.size():
		_write_lighting_offset(i,placements[i].get("lighting_offset",Vector3.ZERO))
	_lighting_offsets = _own(_rd.storage_buffer_create(_lighting_offset_data.size(),_lighting_offset_data))
	_motion_data=_initial_motion(placements.size())
	for i in _geometry.size(): _geometry_placements.append([])
	for i in placements.size():
		_geometry_placements[placements[i].geometry].append(i)
	_motion = _own(_rd.storage_buffer_create(_motion_data.size(),_motion_data))
	return _instance_geometry.is_valid() and _lighting_offsets.is_valid() and _motion.is_valid()

## The initial transform, normal and validity record is identical for every
## placement. Copy its exact bytes instead of encoding 24 scalar fields per
## object; later motion updates keep their existing per-record path.
static func _initial_motion(count: int) -> PackedByteArray:
	var neutral:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0,1,0,0,1,0,1,0,0,0,0,1,0]).to_byte_array()
	var data:=PackedByteArray()
	for i in count:data.append_array(neutral)
	return data

func _build_emitters(data: PackedByteArray,placements: Array) -> bool:
	emitters.setup(data,_geometry,placements,_opaque_fast_path)
	_emitters = _own(_rd.storage_buffer_create(Emitters.HEADER+Emitters.LIMIT*Emitters.STRIDE))
	_emitter_lookup = _own(_rd.storage_buffer_create(Emitters.HASH_SLOTS*16))
	return _emitters.is_valid() and _emitter_lookup.is_valid() \
		and _upload_emitters() and _select_pipeline(emitters.count>0,_deep_paths,_sharc_mode)

## Every variant shares hit stages, TLAS, SBT ranges and stable output images.
func _pipeline_variant(enabled: bool,deep: bool,sharc_mode: int,di := false) -> Dictionary:
	var key := int(enabled)|(int(deep)<<1)|(sharc_mode<<2)|(int(di)<<4)
	if not _variants.has(key):
		var old_enabled := _uses_emitters;var old_deep := _deep_paths;var old_shader := _shader;var old_sharc := _sharc_mode
		var old_di:=_rtxdi_mode
		_uses_emitters=enabled;_deep_paths=deep;_sharc_mode=sharc_mode;_rtxdi_mode=di
		var program := _compile();var shader := _shader
		_uses_emitters=old_enabled;_deep_paths=old_deep;_shader=old_shader;_sharc_mode=old_sharc;_rtxdi_mode=old_di
		if program==null:return {}
		var pipeline := _create_pipeline(program)
		if not pipeline.is_valid():return {}
		_variants[key]={"shader":shader,"pipeline":pipeline}
	return _variants[key]

## A spell or changing figure can introduce the first emissive triangles
## long after loading. Preparing both emission states before the first
## displayed frame avoids a synchronous ray-pipeline build in combat.
## Only the selected path depth/cache mode is prepared; settings changes
## already own a preparation cover. Replacement scenes share these programs.
func _prepare_live_variants(deep: bool,cached: bool,di := false) -> bool:
	var key := int(deep)|(int(cached)<<1)|(int(di)<<2)
	if _prepared_path_modes.has(key):return true
	for emission in [false,true]:
		# SHaRC can fall back to ordinary PT without opening another cover.
		if _pipeline_variant(emission,deep,0,di).is_empty():return false
		if cached and (_pipeline_variant(emission,deep,1,di).is_empty() \
			or _pipeline_variant(emission,false,2).is_empty()):return false
	_prepared_path_modes[key]=true
	return true

func _select_pipeline(enabled: bool,deep: bool,sharc_mode := 0,di := false) -> bool:
	if enabled==_uses_emitters and deep==_deep_paths and sharc_mode==_sharc_mode and di==_rtxdi_mode:return true
	var variant := _pipeline_variant(enabled,deep,sharc_mode,di)
	if variant.is_empty() or _rd.hit_sbt_set_pipeline(_sbt,variant.pipeline)!=OK:return false
	_shader=variant.shader;_pipeline=variant.pipeline
	_uses_emitters=enabled;_deep_paths=deep;_sharc_mode=sharc_mode;_rtxdi_mode=di
	_release_ray_set();_history_valid=false
	return true

func _upload_emitters() -> bool:
	if _rd.buffer_update(_emitters,0,emitters.records.size(),emitters.records) != OK \
		or _rd.buffer_update(_emitter_lookup,0,emitters.lookup.size(),emitters.lookup) != OK: return false
	_notify(&"emitter_stats",[emitters.count,emitters.candidates])
	return true

## Runs on the render thread before the frame. Retain the RS texture owner
## while its view is bound; all scene generations may share the cloud field.
func set_cloud_texture(texture: Texture2D) -> void:
	if _rd==null or _closed:return
	# Deleting a cloud viewport also invalidates its dependent RD uniform
	# sets. A nonzero RID alone does not mean the descriptor still exists.
	if _set.is_valid() and not _rd.uniform_set_is_valid(_set):_set=RID()
	var rid := RenderingServer.texture_get_rd_texture(texture.get_rid()) if texture!=null else RID()
	if not rid.is_valid():rid=_clear_cloud
	_cloud_texture=texture
	if rid==_cloud_image:return
	_release_ray_set()
	_cloud_image=rid

func _release_ray_set() -> void:
	sharc.release_update_set(_release_rid if _defer_retirement_release else Callable())
	if _set.is_valid() and _rd.uniform_set_is_valid(_set):_release_rid(_set)
	_set=RID()

func extra_ray_uniforms() -> Array[RDUniform]:
	var uniforms: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,10,[_instance_geometry]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,13,[_terrain_data]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,14,[_terrain_atlas]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,15,[_cloud_image]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,16,[_cloud_sampler]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,21,[_lighting_offsets])]
	if _uses_emitters:
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,11,[_emitters]))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,12,[_emitter_lookup]))
	if _sharc_mode>0:uniforms.append_array(sharc.uniforms())
	if _rtxdi_mode:uniforms.append_array(rtxdi.uniforms(_motion))
	return uniforms

func update_scene(changes: Dictionary) -> bool:
	if not changes.get("instances",[]).is_empty() or not changes.get("poses",[]).is_empty():_transmission_dirty=true
	if changes.has("ray_reconstruction") and ray_reconstruction!=bool(changes.ray_reconstruction):
		ray_reconstruction=changes.ray_reconstruction
		_history_valid=false;_direct_valid=false;nrd.reset()
	if changes.has("nrd_directional"):nrd.directional=changes.nrd_directional
	if _closed or not _ready: return false
	if sharc.active:
		# Conservative invalidation: moving/deformed blockers and emissive
		# surfaces must not leave old light in otherwise static cache cells.
		if not changes.get("poses",[]).is_empty():sharc.invalidate()
		for placement: Dictionary in changes.get("instances",[]):
			var old: RDAccelerationStructureInstance=_instances[placement.index]
			if old.transform!=placement.transform or old.mask!=placement.mask:
				sharc.invalidate();break
	if not _update_motion(changes) or not _update_lighting_offsets(changes):
		_render_failed();return false
	if not super.update_scene(changes): return false
	if emitters.update(changes):
		_history_valid = false
		rtxdi.invalidate()
		if not _upload_emitters() or not _select_pipeline(emitters.count>0,_deep_paths,_sharc_mode,_rtxdi_mode):
			_render_failed();return false
	return true

func adopt_history(previous: RefCounted,matches: PackedInt32Array) -> void:
	defer_nrd=false
	if _closed or previous==null or previous._closed or not previous.nrd_active \
		or _size!=previous._size or _uses_emitters!=previous._uses_emitters or _deep_paths!=previous._deep_paths \
		or nrd.directional!=previous.nrd.directional:return
	if matches.size()!=_instances.size():return
	var unused := nrd
	nrd=previous.nrd;previous.nrd=unused;previous.nrd_active=false
	if not nrd.rebind(_raw,_history,_frame,_motion):
		_nrd_failed=true;nrd.dispose();return
	for i in matches.size():
		var old := matches[i]
		if old>=0 and old<previous._instances.size() and (previous._instances[old].mask&1)!=0:
			# The first update now computes motion from the actual last visible
			# frame, not from the replacement's private preparation frame.
			_instances[i].transform=previous._instances[old].transform
			_instances[i].mask=previous._instances[old].mask
			history_matched_surfaces+=1
		else:_history_reject.append(i)
	nrd_active=true;_history_valid=true
	# NRD remaps the old scene's history; the separate direct history still
	# belongs to the candidate's private frame and different placement IDs.
	_direct_valid=false
	history_handoffs=previous.history_handoffs+1

func _write_lighting_offset(index: int,offset: Vector3) -> void:
	_lighting_offset_values[index]=offset
	for axis in 3:_lighting_offset_data.encode_float(index*16+axis*4,offset[axis])

func _update_lighting_offsets(changes: Dictionary) -> bool:
	var placements: Array=changes.get("instances",[])
	# Offset records are only 16 bytes. For bulk scene updates, collecting
	# and sorting every changed ID costs more than one bounded span upload.
	# Keep the original min/max path; small first-person groups use sparsity.
	if placements.size()>=OFFSET_SPARSE_LIMIT:
		var first := _lighting_offset_values.size();var last := -1
		for placement: Dictionary in placements:
			var index: int=placement.index
			var offset: Vector3=placement.get("lighting_offset",Vector3.ZERO)
			if offset==_lighting_offset_values[index]:continue
			_write_lighting_offset(index,offset)
			first=mini(first,index);last=maxi(last,index)
		return true if last<first else _upload_record_range(_lighting_offsets,_lighting_offset_data,first*16,(last+1)*16)
	var dirty: Array[int]=[]
	for placement: Dictionary in placements:
		var index: int=placement.index
		var offset: Vector3=placement.get("lighting_offset",Vector3.ZERO)
		if offset==_lighting_offset_values[index]:continue
		_write_lighting_offset(index,offset)
		dirty.append(index)
	return _upload_records(_lighting_offsets,_lighting_offset_data,dirty,16)

func _upload_records(buffer: RID,data: PackedByteArray,indices: Array,stride: int) -> bool:
	if indices.is_empty():return true
	indices.sort()
	if (indices.back()-indices.front()+1-indices.size())*stride<=RECORD_UPLOAD_GAP:
		return _upload_record_range(buffer,data,indices.front()*stride,(indices.back()+1)*stride)
	# Splitting at the largest gaps minimizes bytes within a bounded call
	# budget. Dense articulated figures retain their single-upload fast path.
	var gaps: Array[Vector2i]=[]
	for i in range(1,indices.size()):
		var gap: int=(indices[i]-indices[i-1]-1)*stride
		if gap>RECORD_UPLOAD_GAP:gaps.append(Vector2i(gap,i))
	gaps.sort_custom(func(a: Vector2i,b: Vector2i):return a.x>b.x if a.x!=b.x else a.y<b.y)
	var cuts: Array[int]=[]
	for i in mini(gaps.size(),RECORD_UPLOAD_LIMIT-1):cuts.append(gaps[i].y)
	cuts.sort();cuts.append(indices.size())
	var first := 0
	for cut in cuts:
		if not _upload_record_range(buffer,data,indices[first]*stride,(indices[cut-1]+1)*stride):return false
		first=cut
	return true

func _upload_record_range(buffer: RID,data: PackedByteArray,begin: int,end: int) -> bool:
	return _rd.buffer_update(buffer,begin,end-begin,data.slice(begin,end))==OK

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
	# A moving part already receives its final record below. Clearing it first
	# doubled packing work for every articulated limb in crowded scenes.
	var rejected := {}
	for index in _history_reject:rejected[index]=true
	var deformed := {}
	for pose: Dictionary in changes.get("poses",[]):
		for index: int in _geometry_placements[pose.geometry]:
			deformed[index] = true
	for placement: Dictionary in changes.get("instances",[]):
		var index: int = placement.index
		if rejected.has(index):continue
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
	for index in deformed:
		if _motion_pending.has(index) or rejected.has(index):continue
		_write_motion(index,Transform3D.IDENTITY,Basis.IDENTITY,false,false)
		dirty[index]=true;_motion_pending[index]=true
	for index in rejected:
		_write_motion(index,Transform3D.IDENTITY,Basis.IDENTITY,false,false)
		dirty[index]=true;_motion_pending[index]=true
	_history_reject.clear()
	for index: int in dirty:
		if not _motion_pending.has(index):
			_write_motion(index,Transform3D.IDENTITY,Basis.IDENTITY,true,false)
	return _upload_records(_motion,_motion_data,dirty.keys(),MOTION_STRIDE)

## Only private live replacements use this entry point. Preparing targets is
## not a render: readiness and public Texture2DRD bindings remain untouched.
func render_candidate(size: Vector2i,frame: PackedByteArray,changes: Dictionary = {},texture_filter := 4) -> void:
	if _closed or not _ready:return
	if not _published_valid and _raw.is_empty() and bool(changes.get("ray_reconstruction",false)):
		if not _raw_targets_staged(size):
			# The collector consumes pose/visibility deltas every frame. Keep
			# applying them while targets prepare so no live changes are lost.
			if not update_scene(changes):return
			_stage_raw_targets(size);return
		# Keep the final allocation step separate from the first trace. The
		# normal transactional _targets path consumes this complete pool.
	render(size,frame,changes,texture_filter)

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}, texture_filter := 4) -> void:
	if _closed or not _ready or size.x<2 or size.y<2 or frame.size()!=frame_bytes(): return
	if _profile_stages:_rd.capture_timestamp("PT preflight %d:%d"%[get_instance_id(),completed_renders])
	if changes.has("transmission") and transmission_enabled!=bool(changes.transmission):
		transmission_enabled=changes.transmission;transmission_failed=false;_transmission_dirty=true
	if not transmission_enabled and transmission.active:transmission.dispose()
	if changes.has("rtxdi") and rtxdi_enabled!=bool(changes.rtxdi):
		rtxdi_enabled=changes.rtxdi;rtxdi_failed=false;rtxdi.invalidate()
	var di:=rtxdi_enabled and frame.decode_float(145*4)<=8.0 and not rtxdi_failed
	var enabled := frame.decode_float(190*4)>0.5 if frame.decode_float(191*4)>0.5 else sharc_enabled
	if enabled!=_sharc_requested:sharc_failed=false;_sharc_requested=enabled
	var requested := enabled and frame.decode_float(145*4)<=8.0 and not sharc_failed
	if requested and not sharc.setup(_rd,programs):sharc_failed=true;requested=false
	var deep := frame.decode_float(144*4)>2.0 and not _full_paths_reference
	if not _prepare_live_variants(deep,requested):
		if not requested or not _prepare_live_variants(deep,false):_render_failed();return
		sharc_failed=true;requested=false
	if di and rtxdi._size!=size:_release_ray_set()
	if di and not rtxdi.prepare_targets(_rd,size):rtxdi_failed=true;di=false
	if di and not _prepare_live_variants(deep,requested,true):rtxdi_failed=true;di=false
	if di and not _select_pipeline(_uses_emitters,deep,1 if requested else 0,true):
		rtxdi_failed=true;di=false
	if not _select_pipeline(_uses_emitters,deep,1 if requested else 0,di):
		if not requested or not _select_pipeline(_uses_emitters,deep,0,di):_render_failed();return
		sharc_failed=true;requested=false
	if not di and rtxdi.active:_release_ray_set();rtxdi.dispose()
	if not requested and sharc.active:sharc.dispose()
	super.render(size,frame,changes,texture_filter)

func trace_frame(frame: PackedByteArray) -> bool:
	if _sharc_mode==1:
		if not _trace_sharc(frame):
			# A failed optional pass must leave a usable ordinary PT frame.
			sharc_failed=true
			if not _select_pipeline(_uses_emitters,_deep_paths,0,_rtxdi_mode):return false
			sharc.dispose()
			if not _targets(_size,_sampler):return false
			frame.encode_float(82*4,0)
			if not _upload_frame(frame):return false
	if _rtxdi_mode and not rtxdi.prepare(frame,ray_reconstruction):
		rtxdi_failed=true
		if not _select_pipeline(_uses_emitters,_deep_paths,_sharc_mode,false):return false
		rtxdi.dispose()
		if not _targets(_size,_sampler):return false
		frame.encode_float(82*4,0)
		if not _upload_frame(frame):return false
	var ok:=super.trace_frame(frame)
	if ok and _rtxdi_mode:rtxdi.finish(frame)
	if ok and transmission_enabled and not transmission_failed:
		if not transmission.render(self,frame,_transmission_dirty):
			transmission_failed=true;transmission.dispose()
		_transmission_dirty=false
	return ok

func _trace_sharc(frame: PackedByteArray) -> bool:
	if not sharc.prepare(frame,_size):return false
	var variant := _pipeline_variant(_uses_emitters,false,2)
	if variant.is_empty():return false
	var key: int=variant.pipeline.get_id()
	if not _sharc_sbts.has(key):
		var sbt := _own(_rd.hit_sbt_create(variant.pipeline,1))
		if not sbt.is_valid():return false
		var hit_range := _rd.hit_sbt_range_alloc(sbt,1)
		_rd.hit_sbt_range_update(sbt,hit_range,0,[0]);_sharc_sbts[key]=sbt
	var di:=_rtxdi_mode;_rtxdi_mode=false
	var descriptor := sharc.update_set(self,variant.shader)
	_rtxdi_mode=di
	if not descriptor.is_valid():return false
	var rays := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(rays,variant.pipeline)
	_rd.raytracing_list_bind_uniform_set(rays,descriptor,0)
	_rd.raytracing_list_trace_rays(rays,0,_sharc_sbts[key],ceili(_size.x/4.0),ceili(_size.y/4.0),1)
	_rd.raytracing_list_end()
	if _profile_stages:_rd.capture_timestamp("SHaRC update")
	sharc.resolve()
	if _profile_stages:_rd.capture_timestamp("SHaRC resolve")
	return true

func _release_spatial() -> void:
	for rid in _spatial_sets+_spatial_images:
		if rid.is_valid():_release_rid(rid)
	_spatial_sets.clear();_spatial_images.clear();_spatial_source=RID()

func _targets(size: Vector2i,sampler: RID) -> bool:
	# Descriptors must retire before the textures they refer to during resize.
	if size!=_size or (ray_reconstruction and _history.size()>4):
		_release_spatial();nrd.release_targets();_release_direct(true)
	return super._targets(size,sampler)

func _release_direct(retain_output := false) -> void:
	for rid in [_direct_set,_direct_composite_set]:
		if rid.is_valid() and _rd.uniform_set_is_valid(rid):_release_rid(rid)
	_direct_set=RID();_direct_composite_set=RID()
	for rid in _direct_images+_direct_auxiliary:
		if retain_output and rid==direct_sun.texture_rd_rid:_retired_outputs.append(rid)
		elif rid.is_valid():_release_rid(rid)
	_direct_images.clear();_direct_auxiliary.clear();_direct_valid=false

## Analytic BRDF evaluation still uses random area-light/shadow samples.
## NRD excludes this direct glossy term, so reconstruct it independently with
## the same geometric, material, motion and disocclusion checks as PT history.
## The sunlight AOV used by terrain/grass must follow the same reconstruction.
func _reconstruct_direct(frame: PackedByteArray) -> bool:
	if not _direct_set.is_valid():
		if not _direct_frame.is_valid():_direct_frame=_own(_rd.uniform_buffer_create(frame_bytes()))
		if not _direct_frame.is_valid():return false
		for i in 8:_direct_images.append(_lighting_texture(_size))
		for format: int in filter_auxiliary_formats():_direct_auxiliary.append(_lighting_texture(_size,format))
		if not (_direct_images+_direct_auxiliary).all(func(rid: RID):return rid.is_valid()):return false
		var bindings: Array[RDUniform]=[]
		var inputs: Array[RID]=[_raw[6],_raw[1],_raw[5],_raw[3]]
		for i in 4:
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[inputs[i]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+4,[_direct_images[i+4]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+8,[_direct_images[i]]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,12,[_direct_frame]))
		for i in _direct_auxiliary.size():bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,13+i,[_direct_auxiliary[i]]))
		bindings.append_array(extra_filter_uniforms(_raw))
		_direct_set=_target_set(bindings,_filter_shader)
		if not _direct_set.is_valid():return false
	# The filter-only frame selects a compact direct-light kernel. Keep this
	# buffer separate so the ray and NRD passes retain their original frame.
	var direct_frame:=frame.duplicate();direct_frame.encode_float(147*4,2.0)
	if not _direct_valid:direct_frame.encode_float(82*4,0.0)
	if _rd.buffer_update(_direct_frame,0,direct_frame.size(),direct_frame)!=OK:return false
	var list:=_rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_filter_pipeline)
	_rd.compute_list_bind_uniform_set(list,_direct_set,0)
	_rd.compute_list_dispatch(list,ceili(_size.x/8.0),ceili(_size.y/8.0),1)
	_rd.compute_list_end()
	var extent:=Vector3(_size.x,_size.y,1)
	for i in 4:
		if _rd.texture_copy(_direct_images[i],_direct_images[i+4],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK:return false
	for i in range(0,_direct_auxiliary.size(),2):
		if _rd.texture_copy(_direct_auxiliary[i+1],_direct_auxiliary[i],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK:return false
	_direct_valid=true
	return true

func _composite_direct() -> bool:
	if not _direct_composite_shader.is_valid():
		var pair:=_compute_program(DIRECT_COMPOSITE.get_spirv(),"PT direct light composite")
		_direct_composite_shader=pair[0];_direct_composite_pipeline=pair[1]
		if not _direct_composite_shader.is_valid():return false
	if not _direct_composite_pipeline.is_valid():return false
	if not _direct_composite_set.is_valid():
		var bindings: Array[RDUniform]=[]
		var inputs: Array[RID]=[_raw[5],_direct_images[2],_history[2],_direct_images[0],_history[0]]
		for i in inputs.size():bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[inputs[i]]))
		_direct_composite_set=_target_set(bindings,_direct_composite_shader)
	if not _direct_composite_set.is_valid():return false
	var list:=_rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_direct_composite_pipeline)
	_rd.compute_list_bind_uniform_set(list,_direct_composite_set,0)
	_rd.compute_list_dispatch(list,ceili(_size.x/8.0),ceili(_size.y/8.0),1)
	_rd.compute_list_end()
	return true

func reconstruct(frame: PackedByteArray) -> bool:
	if ray_reconstruction:
		nrd_active=false;_direct_valid=false
		var extent:=Vector3(_size.x,_size.y,1)
		for i in 4:
			if _rd.texture_copy(_raw[i],_history[i],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK:return false
		raw_reconstruction_frames+=1
		return true
	if not _reconstruct_direct(frame):return false
	var previous := nrd_active
	var failed_now := false
	nrd_active=false
	if not defer_nrd and nrd.available and not _nrd_failed and frame.decode_float(145*4)<=8.0:
		if not previous:nrd.reset()
		if nrd.configure(_rd,_size,_raw,_history,_frame,_motion) and nrd.render(frame):
			nrd_active=true
			if _profile_stages:_rd.capture_timestamp("Scene RT reconstruct")
			return _composite_direct()
		# Disable only this device's NRD session. Reset the custom history before
		# using its output; never interpret NRD's private history as custom history.
		_nrd_failed=true;failed_now=true;nrd.dispose()
		print("PT NRD unavailable; using custom reconstruction")
	if previous or failed_now:
		frame.encode_float(82*4,0.0)
		if not _upload_frame(frame):return false
	return super.reconstruct(frame)

func filter_presented(frame_data: PackedByteArray) -> bool:
	# Still-scene convergence uses the exact temporal estimate. Responsive
	# play filters diffuse and glossy separately, after saving temporal history.
	if not _spatial_enabled or frame_data.decode_float(145*4)>8.0:return true
	if not _spatial_shader.is_valid():
		var pair:=_compute_program(SPATIAL.get_spirv(),"PT spatial reconstruction")
		_spatial_shader=pair[0];_spatial_pipeline=pair[1]
		if not _spatial_shader.is_valid():return false
		if not _spatial_pipeline.is_valid():return false
	if _spatial_source!=_history[0]:
		_release_spatial()
		for i in 2:_spatial_images.append(_lighting_texture(_size))
		if not _spatial_images.all(func(rid: RID):return rid.is_valid()):return false
		var current: Array[RID]=[_history[0],_history[2]]
		for pass_index in 2:
			var inputs: Array[RID]=current if pass_index==0 else _spatial_images
			var outputs: Array[RID]=_spatial_images if pass_index==0 else current
			var bindings: Array[RDUniform]=[]
			for i in 2:bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[inputs[i]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,2,[_history[1]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,3,[_history[3]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,4,[_filter_auxiliary[1]]))
			for i in 2:bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,5+i,[outputs[i]]))
			bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,7,[_frame]))
			var descriptor:=_target_set(bindings,_spatial_shader)
			if not descriptor.is_valid():return false
			_spatial_sets.append(descriptor)
		_spatial_source=_history[0]
	for pass_index in 2:
		var push:=PackedInt32Array([1<<pass_index,0,0,0]).to_byte_array()
		var list:=_rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list,_spatial_pipeline)
		_rd.compute_list_bind_uniform_set(list,_spatial_sets[pass_index],0)
		_rd.compute_list_set_push_constant(list,push,push.size())
		_rd.compute_list_dispatch(list,ceili(_size.x/8.0),ceili(_size.y/8.0),1)
		_rd.compute_list_end()
	return true

func dispose() -> void:
	var release:=_release_rid if _defer_retirement_release else Callable()
	transmission.dispose(release)
	direct_sun.texture_rd_rid=RID()
	if _rd!=null:_release_ray_set();_release_spatial();_release_direct();nrd.dispose(release);sharc.dispose(release);rtxdi.dispose(release)
	super.dispose()
	_spatial_shader=RID();_spatial_pipeline=RID()
	_direct_composite_shader=RID();_direct_composite_pipeline=RID()
	_direct_frame=RID()
	emitters = Emitters.new()
	terrain = Terrain.new();_terrain_atlas=RID()
	_cloud_texture=null;_cloud_image=RID();_clear_cloud=RID();_cloud_sampler=RID()
	_variants.clear();_prepared_path_modes.clear();_sharc_sbts.clear()
	_motion=RID();_motion_data.clear();_motion_pending.clear();_geometry_placements.clear()
	_lighting_offsets=RID();_lighting_offset_data.clear();_lighting_offset_values.clear()
