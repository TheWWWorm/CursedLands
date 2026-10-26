extends CompositorEffect
## Main-view RR input transaction. Geometry packets arrive on the render thread;
## tracing happens at PRE_OPAQUE with this view's actual jittered camera.
const GUIDES = preload("res://src/game/fx/shaders/path_trace_rr_guides.glsl")
var _rd: RenderingDevice
var _target: RefCounted
var _frame := PackedByteArray()
var _changes := {}
var _filter := 4
var _token := -1
var _shader := RID()
var _pipeline := RID()
var _set := RID()
var _sampler := RID()
var _images: Array[RID]=[]
var _size := Vector2i.ZERO
var _source := []
var _last_target := 0
var _samples := 0
var submitted_frames := 0
var failed := false
var last_projection := Projection()
var last_size := Vector2i.ZERO

func _init() -> void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	access_resolved_depth=true
	needs_normal_roughness=true
	needs_motion_vectors=true

func queue_frame(target: RefCounted,size: Vector2i,frame: PackedByteArray,changes: Dictionary,filter: int,token: int) -> void:
	# Material descriptor sets are prepared before PRE_OPAQUE. Replace public
	# textures here, before that preparation, never inside the active view.
	if not target.ray_reconstruction or target._size!=size:
		changes["ray_reconstruction"]=true
		target.render(size,frame.duplicate(),changes,filter)
		changes={"ray_reconstruction":true}
	_target=target;_frame=frame;_changes=changes;_filter=filter
	if token>=0:_token=token

func _render_callback(kind: int,data: RenderData) -> void:
	if kind!=EFFECT_CALLBACK_TYPE_PRE_OPAQUE or failed or _target==null or _target._closed or _frame.is_empty():return
	var buffers: RenderSceneBuffersRD=data.get_render_scene_buffers()
	var scene: RenderSceneData=data.get_render_scene_data()
	if buffers==null or scene==null or buffers.get_view_count()!=1 or not buffers.has_method("set_dlss_ray_reconstruction") or not scene.has_method("get_ray_projection"):return
	var size:=buffers.get_internal_size()
	if size.x<2 or size.y<2 or _target._size!=size:return
	# No camera-node reads on this thread; these are the renderer's exact values.
	var projection: Projection=scene.call("get_ray_projection")
	var transform:=scene.get_cam_transform()
	var frame:=_frame.duplicate()
	var matrices: Array[Projection]=[projection.inverse(),Projection(transform)]
	for m in matrices.size():
		for c in 4:
			for r in 4:frame.encode_float((m*16+c*4+r)*4,matrices[m][c][r])
	frame.encode_float(76*4,_samples);_samples=(_samples+1)%1000000
	frame.encode_float(77*4,1.0) # RR receives one unfiltered path sample per input pixel.
	var reset:=_last_target!=_target.get_instance_id() or size!=_size or frame.decode_float(82*4)<0.5
	_changes["ray_reconstruction"]=true
	var before: int=_target.completed_renders
	_target.render(size,frame,_changes,_filter)
	_changes={"ray_reconstruction":true}
	if _token>=0:
		_target._notify(&"rendered",[_token,_target.completed_renders>before and _target.output_ready()]);_token=-1
	if not _target.output_ready():return
	if _rd==null:_rd=RenderingServer.get_rendering_device()
	if not _prepare(size,buffers):failed=true;return
	var list:=_rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_pipeline)
	_rd.compute_list_bind_uniform_set(list,_set,0)
	_rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)
	_rd.compute_list_end()
	if not buffers.call("set_dlss_ray_reconstruction",_images[0],_images[1],_images[2],_images[3],reset):failed=true;return
	_last_target=_target.get_instance_id();submitted_frames+=1
	last_projection=projection;last_size=size

func _prepare(size: Vector2i,buffers: RenderSceneBuffersRD) -> bool:
	if not buffers.has_texture(&"forward_clustered",&"normal_roughness"):return false
	if not _shader.is_valid():
		_shader=_rd.shader_create_from_spirv(GUIDES.get_spirv(),"DLSS RR material guides")
		if not _shader.is_valid():return false
		_pipeline=_rd.compute_pipeline_create(_shader)
		_sampler=_rd.sampler_create(RDSamplerState.new())
	if not _pipeline.is_valid() or not _sampler.is_valid():return false
	if size!=_size:
		_release_images();_size=size
		for i in 4:
			var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
			format.format=RenderingDevice.DATA_FORMAT_R16_SFLOAT if i==3 else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
			format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			_images.append(_rd.texture_create(format,RDTextureView.new()))
		if not _images.all(func(rid: RID):return rid.is_valid()):return false
	var sources: Array=[_target._raw[1],_target._raw[3],_target._raw[4],_target._raw[5],buffers.get_depth_layer(0),buffers.get_texture_slice(&"forward_clustered",&"normal_roughness",0,0,1,1),_target._frame]
	if sources!=_source or not _rd.uniform_set_is_valid(_set):
		if _rd.uniform_set_is_valid(_set):_rd.free_rid(_set)
		var bindings: Array[RDUniform]=[]
		for i in 4:bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[sources[i]]))
		for i in range(4,6):bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,i,[_sampler,sources[i]]))
		for i in 4:bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,6+i,[_images[i]]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,10,[sources[6]]))
		_set=_rd.uniform_set_create(bindings,_shader,0);_source=sources
	return _set.is_valid()

func _uniform(type: int,binding: int,rids: Array) -> RDUniform:
	var uniform:=RDUniform.new();uniform.uniform_type=type;uniform.binding=binding
	for rid: RID in rids:uniform.add_id(rid)
	return uniform

func _release_images() -> void:
	if _rd==null:return
	if _rd.uniform_set_is_valid(_set):_rd.free_rid(_set)
	_set=RID();_source.clear()
	for rid in _images:
		if rid.is_valid():_rd.free_rid(rid)
	_images.clear();_size=Vector2i.ZERO

func dispose() -> void:
	enabled=false;_target=null;_frame.clear();_changes.clear();_token=-1
	_release_images()
	if _rd!=null:
		for rid in [_pipeline,_shader,_sampler]:
			if rid.is_valid():_rd.free_rid(rid)
	_shader=RID();_pipeline=RID();_sampler=RID()
