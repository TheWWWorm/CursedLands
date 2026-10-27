extends RefCounted
## NRD owns its temporal history. The application supplies unfiltered signals,
## motion and guides, then publishes remodulated light through stable textures.
const CONFIG := "res://src/native/path_nrd.cfg"
const SHADERS := "res://src/game/fx/shaders/nrd/"
const FORMATS := {0:RenderingDevice.DATA_FORMAT_R8_UNORM,4:RenderingDevice.DATA_FORMAT_R8G8_UNORM,
	15:RenderingDevice.DATA_FORMAT_R16_UINT,17:RenderingDevice.DATA_FORMAT_R16_SFLOAT,
	22:RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,27:RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	28:RenderingDevice.DATA_FORMAT_R32_UINT,30:RenderingDevice.DATA_FORMAT_R32_SFLOAT}
var available := false
var directional := not OS.get_cmdline_user_args().has("--ei-pt-nrd-radiance")
var _mode := ""
var rendered_frames := 0
var last_dispatch_count := 0
var _rd: RenderingDevice
var _native: RefCounted
var _description := {}
var _layouts := {}
var _size := Vector2i.ZERO
var _programs := {}
# Borrow immutable programs only; temporal pools and descriptors stay private.
var program_cache: RefCounted
var _sets := {}
var _owned: Array[RID] = []
var _textures: Array[RID] = []
var _buffers: Array[RID] = []
var _permanent: Array[RID] = []
var _transient: Array[RID] = []
var _external := {}
var _samplers: Array[RID] = []
var _pack := RID()
var _resolve := RID()
var _last_time := 0
var _restart := true
var _input_frame := RID()

func _init() -> void:
	# Device construction is on the main thread; load once before render-thread
	# work. A cfg descriptor keeps unsupported platforms free of loader errors.
	if OS.get_cmdline_user_args().has("--ei-pt-custom-denoiser"):return
	if not OS.has_feature("x86_64") or not (OS.has_feature("linux") or OS.has_feature("windows")):return
	var suffix := "dll" if OS.has_feature("windows") else "so"
	if not FileAccess.file_exists("res://src/native/bin/libpath_nrd."+suffix):return
	if not ClassDB.class_exists("PathNrd"):
		var status := GDExtensionManager.load_extension(CONFIG)
		if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]:return
	available=ClassDB.class_exists("PathNrd") and FileAccess.file_exists(SHADERS+"build.json")

func _uniform(type: int,binding: int,rid: RID) -> RDUniform:
	var result := RDUniform.new();result.uniform_type=type;result.binding=binding;result.add_id(rid);return result

func _texture(size: Vector2i,format: int) -> RID:
	var desc := RDTextureFormat.new();desc.width=size.x;desc.height=size.y;desc.format=format
	desc.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var rid := _rd.texture_create(desc,RDTextureView.new());_textures.append(rid);return rid

func _program(name: String) -> Dictionary:
	if _programs.has(name):return _programs[name]
	if not _layouts.has(name):return {}
	var bytes := FileAccess.get_file_as_bytes(SHADERS+name+".spv")
	if bytes.is_empty():return {}
	var spirv := RDShaderSPIRV.new();spirv.bytecode_compute=bytes
	var shader := RID();var pipeline := RID()
	if program_cache!=null:
		var pair: Array=program_cache.compute(_rd,spirv,"NRD "+name)
		shader=pair[0];pipeline=pair[1]
	else:
		shader=_rd.shader_create_from_spirv(spirv,"NRD "+name)
		if not shader.is_valid():return {}
		_owned.append(shader)
		pipeline=_rd.compute_pipeline_create(shader)
		if pipeline.is_valid():_owned.append(pipeline)
	if not shader.is_valid() or not pipeline.is_valid():return {}
	var result := {"shader":shader,"pipeline":pipeline,"layout":_layouts[name]}
	_programs[name]=result;return result

func _descriptor(program: Dictionary,index: int,uniforms: Array[RDUniform]) -> RID:
	# JSON numbers are floats. Array.has uses strict Variant types, so convert
	# reflected bindings before comparing them with RD's integer bindings.
	var bindings := PackedInt32Array(program.layout.get(str(index),[]))
	if bindings.is_empty():return RID()
	var selected: Array[RDUniform]=[]
	var key := str(program.shader.get_id())+":"+str(index)
	for uniform in uniforms:
		if not bindings.has(uniform.binding):continue
		selected.append(uniform);key+=":"+str(uniform.binding)+"="+str(uniform.get_ids()[0].get_id())
	if _sets.has(key):return _sets[key]
	if selected.size()!=bindings.size():return RID()
	var set := _rd.uniform_set_create(selected,program.shader,index)
	if set.is_valid():_sets[key]=set
	return set

func configure(rd: RenderingDevice,size: Vector2i,raw: Array[RID],outputs: Array[RID],frame: RID,motion: RID) -> bool:
	if not available:return false
	_rd=rd
	if _size==size and _description.get("directional",false)==directional:
		return true if _input_frame==frame else rebind(raw,outputs,frame,motion)
	release_targets()
	_native=ClassDB.instantiate("PathNrd")
	_description=_native.describe(directional)
	if _description.is_empty():return false
	_mode="_sh" if directional else ""
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(SHADERS+"build.json"))
	if not manifest is Dictionary or manifest.get("version")!=_description.version:return false
	_layouts=manifest.layouts
	if _samplers.is_empty():
		for linear in [false,true]:
			var state := RDSamplerState.new()
			state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR if linear else RenderingDevice.SAMPLER_FILTER_NEAREST
			state.mag_filter=state.min_filter
			state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;state.repeat_v=state.repeat_u;state.repeat_w=state.repeat_u
			var sampler := _rd.sampler_create(state);_samplers.append(sampler);_owned.append(sampler)
	var types: Dictionary=_description.resources
	for entry in [["motion",27],["normal",27],["depth",30],["diffuse",27],["specular",27],
		["confidence_diffuse",17],["out_diffuse",27],["out_specular",27]]:
		_external[types[entry[0]]]=_texture(size,FORMATS[entry[1]])
	_external[types.confidence_specular]=_external[types.confidence_diffuse]
	if directional:
		for name in ["diffuse_sh1","specular_sh1","out_diffuse_sh1","out_specular_sh1"]:
			_external[types[name]]=_texture(size,FORMATS[27])
	for pool_name in ["permanent","transient"]:
		var target: Array[RID]=_permanent if pool_name=="permanent" else _transient
		for desc: Dictionary in _description[pool_name]:
			if not FORMATS.has(desc.format):return false
			var dimensions := Vector2i(ceili(float(size.x)/desc.scale),ceili(float(size.y)/desc.scale))
			target.append(_texture(dimensions,FORMATS[desc.format]))
	if not _textures.all(func(rid: RID):return rid.is_valid()):return false
	var pack := _program("pack"+_mode);var resolve := _program("resolve"+_mode)
	if pack.is_empty() or resolve.is_empty():return false
	_size=size;_restart=true
	return rebind(raw,outputs,frame,motion)

## Only the application boundary changes when a region is replaced. Keep
## NRD's native frame index, permanent pools and internal descriptors alive.
func rebind(raw: Array[RID],outputs: Array[RID],frame: RID,motion: RID) -> bool:
	for rid in [_pack,_resolve]:
		if rid.is_valid():
			for key in _sets.keys():
				if _sets[key]==rid:_sets.erase(key)
			if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
	var types: Dictionary=_description.resources
	var pack: Dictionary=_programs["pack"+_mode];var resolve: Dictionary=_programs["resolve"+_mode]
	var inputs: Array[RDUniform]=[]
	for i in 5:inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,i,raw[i]))
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,motion))
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,6,frame))
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,13,raw[5]))
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,14,raw[6]))
	if _description.directional:
		if raw.size()<9:return false
		inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,15,raw[7]))
		inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,16,raw[8]))
	var packed: Array[RDUniform]=inputs.duplicate()
	var names := ["motion","normal","depth","diffuse","specular","confidence_diffuse"]
	for i in names.size():packed.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i+7,_external[types[names[i]]]))
	if _description.directional:
		packed.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,17,_external[types.diffuse_sh1]))
		packed.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,18,_external[types.specular_sh1]))
	_pack=_descriptor(pack,0,packed)
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,7,_external[types.out_diffuse]))
	inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,8,_external[types.out_specular]))
	if _description.directional:
		inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,17,_external[types.out_diffuse_sh1]))
		inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,18,_external[types.out_specular_sh1]))
	for i in 4:inputs.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,9+i,outputs[i]))
	_resolve=_descriptor(resolve,0,inputs)
	if not _pack.is_valid() or not _resolve.is_valid():return false
	_input_frame=frame;return true

func _matrix(data: PackedByteArray,start: int) -> Projection:
	var result := Projection()
	for column in 4:
		var offset := (start+column*4)*4
		result[column]=Vector4(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8),data.decode_float(offset+12))
	return result

func _matrices(frame: PackedByteArray) -> PackedFloat32Array:
	var projection := _matrix(frame,0).inverse()
	var view := _matrix(frame,16).inverse()
	var previous_view := _matrix(frame,48)
	var previous_projection := _matrix(frame,32)*previous_view.inverse()
	if frame.decode_float(82*4)<0.5:
		previous_projection=projection;previous_view=view
	# Godot Camera3D matrices use -1..1 clip depth. NRD expects D3D 0..1,
	# supports right-handed views and performs its own camera-relative transform.
	for column in 4:
		projection[column].z=(projection[column].z+projection[column].w)*0.5
		previous_projection[column].z=(previous_projection[column].z+previous_projection[column].w)*0.5
	var result := PackedFloat32Array()
	for matrix: Projection in [projection,previous_projection,view,previous_view]:
		for column in 4:
			var v: Vector4=matrix[column];result.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	return result

func _dispatch(program: Dictionary,sets: Array[RID],grid: Vector2i) -> void:
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,program.pipeline)
	for i in sets.size():
		if sets[i].is_valid():_rd.compute_list_bind_uniform_set(list,sets[i],i)
	_rd.compute_list_dispatch(list,grid.x,grid.y,1)
	# A list boundary lets RD track UAV -> SRV hazards between every NRD pass.
	_rd.compute_list_end()

func render(frame: PackedByteArray) -> bool:
	var now := Time.get_ticks_usec()
	var elapsed := float(now-_last_time)/1000.0 if _last_time>0 else 16.667
	_last_time=now
	var dispatches: Array=_native.dispatches(_matrices(frame),_size,rendered_frames,
		_restart or frame.decode_float(82*4)<0.5,elapsed,frame.decode_float(145*4))
	if dispatches.is_empty():return false
	# Prepare all pipelines/descriptors before recording anything. Any setup
	# failure leaves the custom fallback a complete set of unfiltered inputs.
	var jobs: Array=[]
	var types: Dictionary=_description.resources
	for i in dispatches.size():
		var dispatch: Dictionary=dispatches[i]
		var pipeline: Dictionary=_description.pipelines[dispatch.pipeline]
		var program := _program(String(pipeline.shader).sha256_text())
		if program.is_empty():return false
		var uniforms: Array[RDUniform]=[]
		var sampled := 20;var storage := 3
		for resource: Dictionary in dispatch.resources:
			var rid: RID
			if resource.type==types.permanent:rid=_permanent[resource.pool]
			elif resource.type==types.transient:rid=_transient[resource.pool]
			else:rid=_external.get(resource.type,RID())
			if not rid.is_valid():return false
			uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE if resource.storage else RenderingDevice.UNIFORM_TYPE_TEXTURE,
				storage if resource.storage else sampled,rid))
			if resource.storage:storage+=1
			else:sampled+=1
		var resources := _descriptor(program,0,uniforms)
		if not resources.is_valid():return false
		var constants := RID()
		if program.layout.has("1"):
			while _buffers.size()<=i:_buffers.append(_rd.uniform_buffer_create(_description.constant_bytes))
			if not _buffers[i].is_valid():return false
			var data: PackedByteArray=dispatch.constants
			if not data.is_empty() and _rd.buffer_update(_buffers[i],0,data.size(),data)!=OK:return false
			constants=_descriptor(program,1,[_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,0,_samplers[0]),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,1,_samplers[1]),
				_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,2,_buffers[i])])
			if not constants.is_valid():return false
		jobs.append({"program":program,"sets":[resources,constants],"grid":dispatch.grid})
	var grid := Vector2i(ceili(_size.x/8.0),ceili(_size.y/8.0))
	_dispatch(_programs["pack"+_mode],[_pack],grid)
	for job: Dictionary in jobs:
		var sets: Array[RID]=[];sets.assign(job.sets)
		_dispatch(job.program,sets,job.grid)
	_dispatch(_programs["resolve"+_mode],[_resolve],grid)
	_restart=false;rendered_frames+=1;last_dispatch_count=jobs.size()
	return true

func reset() -> void:
	_restart=true

func release_targets(release: Callable=Callable()) -> void:
	if _rd==null:return
	for rid: RID in _sets.values():
		if _rd.uniform_set_is_valid(rid):
			if release.is_valid():release.call(rid)
			else:_rd.free_rid(rid)
	_sets.clear()
	for rid in _textures+_buffers:
		if rid.is_valid():
			if release.is_valid():release.call(rid)
			else:_rd.free_rid(rid)
	_textures.clear();_buffers.clear();_external.clear();_permanent.clear();_transient.clear()
	_native=null;_size=Vector2i.ZERO;_pack=RID();_resolve=RID();_input_frame=RID();_restart=true;_last_time=0

func dispose(release: Callable=Callable()) -> void:
	release_targets(release)
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):
			var rid := _owned[i]
			if rid.is_valid():
				if release.is_valid():release.call(rid)
				else:_rd.free_rid(rid)
	_owned.clear();_programs.clear();_samplers.clear();_rd=null
