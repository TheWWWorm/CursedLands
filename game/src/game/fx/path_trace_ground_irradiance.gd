extends RefCounted
## Small raster-only ground details sample one planted point. RR cannot recover
## the independently noisy path sample coherently repeated over an entire plant.
## Reconstruct that receiver's indirect and direct irradiance independently,
## leaving RR's AOVs raw and retaining native detailed shadow attenuation.
const PROGRAM=preload("res://src/game/fx/shaders/path_trace_ground_irradiance.glsl")
var output:=Texture2DRD.new()
var sun_output:=Texture2DRD.new()
var rendered_frames:=0
var _rd: RenderingDevice
var _size:=Vector2i.ZERO
var _shader:=RID()
var _pipeline:=RID()
var _frame:=RID()
var _set:=RID()
var _sources: Array[RID]=[]
var _images: Array[RID]=[]
var _history:=false
var _published:=false
var _previous_projection:=Projection()
var _previous_transform:=Transform3D.IDENTITY

func prepare(rd: RenderingDevice,size: Vector2i,publish:=true) -> bool:
	# Called before the view prepares material descriptors, never from its
	# compositor callback. Ordinary frames and compatible region handoffs keep
	# both the physical output and the global texture binding unchanged.
	if rd==null or size.x<2 or size.y<2:invalidate();return false
	_rd=rd
	if not _shader.is_valid():
		_shader=_rd.shader_create_from_spirv(PROGRAM.get_spirv(),"Ground detail irradiance")
		if not _shader.is_valid():return false
		_pipeline=_rd.compute_pipeline_create(_shader)
		_frame=_rd.uniform_buffer_create(336)
	if not _pipeline.is_valid() or not _frame.is_valid():return false
	if _size!=size:
		_release_images();_size=size
		for i in 5:
			var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
			format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
			format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
			_images.append(_rd.texture_create(format,RDTextureView.new()))
		if not _images.all(func(rid: RID):return rid.is_valid()):_release_images();return false
		for rid in _images:_rd.texture_clear(rid,Color(0,0,0,0),0,1,0,1)
		output.texture_rd_rid=_images[0]
		sun_output.texture_rd_rid=_images[3]
		if publish:
			RenderingServer.global_shader_parameter_set(&"ei_pt_ground_indirect",output)
			RenderingServer.global_shader_parameter_set(&"ei_pt_ground_sun",sun_output)
			RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",1.0)
			_published=true
	return true

func render(raw: Array[RID],packet: PackedByteArray,projection: Projection,transform: Transform3D,reset: bool) -> bool:
	if _images.size()!=5 or raw.size()<7 or packet.size()<146*4:invalidate();return false
	var sources: Array[RID]=[raw[0],raw[1],raw[6]]
	if not sources.all(func(rid: RID):return _rd.texture_is_valid(rid)):
		invalidate();return false
	if sources!=_sources or not _rd.uniform_set_is_valid(_set):
		if _rd.uniform_set_is_valid(_set):_rd.free_rid(_set)
		var bindings: Array[RDUniform]=[]
		for i in 3:bindings.append(_binding(RenderingDevice.UNIFORM_TYPE_IMAGE,i,sources[i]))
		for i in 3:bindings.append(_binding(RenderingDevice.UNIFORM_TYPE_IMAGE,3+i,_images[(i+1)%3]))
		bindings.append(_binding(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,6,_frame))
		bindings.append(_binding(RenderingDevice.UNIFORM_TYPE_IMAGE,7,_images[4]))
		bindings.append(_binding(RenderingDevice.UNIFORM_TYPE_IMAGE,8,_images[3]))
		_set=_rd.uniform_set_create(bindings,_shader,0);_sources=sources
	if not _set.is_valid():invalidate();return false
	var view:=Projection(_previous_transform.affine_inverse())
	var previous_vp:=_previous_projection*view
	var values:=PackedFloat32Array()
	for matrix: Projection in [projection.inverse(),Projection(transform),previous_vp,view,previous_vp.inverse()]:
		for axis in 4:
			var v: Vector4=matrix[axis];values.append_array([v.x,v.y,v.z,v.w])
	# The controller already distinguishes gradual daylight from fast torch /
	# weather changes and strict lighting discontinuities. Respect its policy.
	var limit:=packet.decode_float(145*4)
	limit=minf(limit,3.0) if limit<8.0 else 32.0
	# Strict cache freshness also changes for a moving local light. The main
	# RR reset separately identifies camera/global-light discontinuities. A
	# local update gets the short response rather than flashing every plant
	# back to a fresh noisy sample, including distant unaffected receivers.
	if packet.decode_float(82*4)<.5:limit=minf(limit,3.0)
	# Direct visibility must respond faster than indirect irradiance. Both
	# channels share geometric rejection, but never share their colour history.
	values.append_array([float(_history and not reset),limit,float(absf(projection[3][3]-1.0)<.00001),minf(limit,8.0)])
	var bytes:=values.to_byte_array();_rd.buffer_update(_frame,0,bytes.size(),bytes)
	var list:=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline)
	_rd.compute_list_bind_uniform_set(list,_set,0)
	_rd.compute_list_dispatch(list,ceili(_size.x/8.0),ceili(_size.y/8.0),1);_rd.compute_list_end()
	var extent:=Vector3(_size.x,_size.y,1)
	if _rd.texture_copy(_images[0],_images[1],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK \
		or _rd.texture_copy(_images[3],_images[4],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK \
		or _rd.texture_copy(raw[1],_images[2],Vector3.ZERO,Vector3.ZERO,extent,0,0,0,0)!=OK:
		invalidate();return false
	_history=true;_previous_projection=projection;_previous_transform=transform;rendered_frames+=1
	return true

func invalidate() -> void:
	_history=false
	if _images.size()==5:
		for i in [0,3]:_rd.texture_clear(_images[i],Color(0,0,0,0),0,1,0,1)

func memory_bytes() -> int:return _size.x*_size.y*8*_images.size()

func _binding(type: int,index: int,rid: RID) -> RDUniform:
	var uniform:=RDUniform.new();uniform.uniform_type=type;uniform.binding=index;uniform.add_id(rid);return uniform

func _release_images() -> void:
	if _rd==null:return
	if _published:
		RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",0.0)
		RenderingServer.global_shader_parameter_set(&"ei_pt_ground_indirect",null)
		RenderingServer.global_shader_parameter_set(&"ei_pt_ground_sun",null)
		_published=false
	output.texture_rd_rid=RID()
	sun_output.texture_rd_rid=RID()
	if _rd.uniform_set_is_valid(_set):_rd.free_rid(_set)
	_set=RID();_sources.clear()
	for rid in _images:
		if rid.is_valid():_rd.free_rid(rid)
	_images.clear();_size=Vector2i.ZERO;_history=false

func dispose() -> void:
	_release_images()
	if _rd!=null:
		for rid in [_frame,_pipeline,_shader]:
			if rid.is_valid():_rd.free_rid(rid)
	_frame=RID();_pipeline=RID();_shader=RID()
