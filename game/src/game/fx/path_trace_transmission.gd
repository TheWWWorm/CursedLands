extends RefCounted
## Independent transparent radiance. Reuses the opaque scene's TLAS, materials
## and lighting; never writes the opaque NRD/RR guides or reservoir history.
const Programs = preload("res://src/game/fx/raytrace_programs.gd")
var colour := Texture2DRD.new()
var guide := Texture2DRD.new()
var active := false
var frames := 0
var resets := 0
var bytes := 0
var history := 0
var _rd: RenderingDevice
var _programs: RefCounted
var _own_programs := false
var _images: Array[RID]=[]
var _size := Vector2i.ZERO
var _metadata := RID()
var _empty := false
var _control := RID()
var _set := RID()
var _sbt := RID()
var _shader := RID()
var _pipeline := RID()
var _signature := PackedByteArray()
var _sampler := RID()
var _cloud := RID()

func _setup(owner: RefCounted) -> bool:
	_rd=owner._rd
	if _metadata.is_valid() or _empty:return true
	var data:=PackedByteArray();data.resize(owner._geometry.size()*32)
	var count:=0
	for i in owner._geometry.size():
		var optical: PackedFloat32Array=owner._geometry[i].get("dielectric",PackedFloat32Array())
		if optical.size()!=8:continue
		for c in 8:data.encode_float(i*32+c*4,optical[c])
		count+=1
	if count==0:_empty=true;return true
	_metadata=_rd.storage_buffer_create(data.size(),data)
	_control=_rd.uniform_buffer_create(16)
	_programs=owner.programs
	if _programs==null:_programs=Programs.new();_own_programs=true
	return _metadata.is_valid() and _control.is_valid()

func _program(owner: RefCounted) -> bool:
	var paths: Dictionary={}
	for stage in [RenderingDevice.SHADER_STAGE_RAYGEN,RenderingDevice.SHADER_STAGE_MISS,RenderingDevice.SHADER_STAGE_CLOSEST_HIT,RenderingDevice.SHADER_STAGE_ANY_HIT]:
		paths[stage]=owner.shader_stage_path(stage)
	paths[RenderingDevice.SHADER_STAGE_RAYGEN]=owner.shader_prefix()+"raygen_transmission"+("_no_emitters" if not owner._uses_emitters else "")
	paths[RenderingDevice.SHADER_STAGE_CLOSEST_HIT]+="_transmission"
	var directx:=RenderingServer.get_current_rendering_driver_name()=="d3d12"
	var shader: RID=_programs.program(_rd,paths,directx)
	if not shader.is_valid():return false
	if shader==_shader:return true
	_release_set()
	if _sbt.is_valid():_rd.free_rid(_sbt)
	_shader=shader
	var program:=RDPipelineShader.new();program.shader=_shader
	_pipeline=_programs.pipeline(program)
	if not _pipeline.is_valid():return false
	_sbt=_rd.hit_sbt_create(_pipeline,1)
	if not _sbt.is_valid():return false
	var hit_range:=_rd.hit_sbt_range_alloc(_sbt,1)
	_rd.hit_sbt_range_update(_sbt,hit_range,0,[0])
	history=0
	return true

func _release_set(release: Callable=Callable()) -> void:
	if _set.is_valid() and _rd.uniform_set_is_valid(_set):
		if release.is_valid():release.call(_set)
		else:_rd.free_rid(_set)
	_set=RID()

func _uniform(kind: int,binding: int,ids: Array[RID]) -> RDUniform:
	var result:=RDUniform.new();result.uniform_type=kind;result.binding=binding
	for id in ids:result.add_id(id)
	return result

func _bindings(owner: RefCounted,images: Array[RID]) -> Array[RDUniform]:
	var bindings: Array[RDUniform]=[
		_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,[owner._tlas]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[images[0]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[owner._vertices]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,3,[owner._colours]),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[owner._frame]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,[owner._materials]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,6,[owner._sampler]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,7,[images[1]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,8,[images[2]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,10,[owner._instance_geometry]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,13,[owner._terrain_data]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,14,[owner._terrain_atlas]),
		_uniform(RenderingDevice.UNIFORM_TYPE_TEXTURE,15,[owner._cloud_image]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER,16,[owner._cloud_sampler]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,21,[owner._lighting_offsets]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,39,[_metadata]),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,40,[_control])]
	if owner._uses_emitters:
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,11,[owner._emitters]))
		bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,12,[owner._emitter_lookup]))
	return bindings

func presentation_compatible(previous: RefCounted) -> bool:
	if previous==null or active!=previous.active:return false
	if not active:return _images.is_empty() and previous._images.is_empty()
	return _rd==previous._rd and _size==previous._size and _images.size()==3 and previous._images.size()==3 \
		and colour.texture_rd_rid==_images[0] and guide.texture_rd_rid==_images[1] \
		and previous.colour.texture_rd_rid==previous._images[0] and previous.guide.texture_rd_rid==previous._images[1]

## Stage descriptors before any image/wrapper ownership changes. The opaque
## owner commits both transactions only once every allocation has succeeded.
func prepare_presentation(owner: RefCounted,previous: RefCounted) -> RID:
	return owner._target_set(_bindings(owner,previous._images),_shader)

func commit_presentation(previous: RefCounted,replacement_set: RID) -> void:
	var spare_colour:=colour;colour=previous.colour;previous.colour=spare_colour
	var spare_guide:=guide;guide=previous.guide;previous.guide=spare_guide
	if not active:return
	var spare:=_images;_images=previous._images;previous._images=spare
	_release_set();_set=replacement_set
	# The physical targets contain the previously visible view. The next trace
	# writes all channels without reusing a different generation's refraction.
	history=0

func render(owner: RefCounted,frame: PackedByteArray,dirty: bool) -> bool:
	if not _setup(owner):return false
	if not _metadata.is_valid():return true # Scene has no declared dielectric.
	if not _program(owner):return false
	var size: Vector2i=owner._size
	if size!=_size:
		var images: Array[RID]=[]
		for i in 3:images.append(owner._lighting_texture(size))
		if not images.all(func(r: RID):return r.is_valid()):
			for r in images:
				if r.is_valid():_rd.free_rid(r)
			return false
		_release_set();colour.texture_rd_rid=RID();guide.texture_rd_rid=RID()
		for r in _images:_rd.free_rid(r)
		_images=images;_size=size;history=0
		bytes=size.x*size.y*24+owner._geometry.size()*32+16
	if _sampler!=owner._sampler or _cloud!=owner._cloud_image:_release_set();history=0
	_sampler=owner._sampler;_cloud=owner._cloud_image
	if not _set.is_valid() or not _rd.uniform_set_is_valid(_set):
		var bindings:=_bindings(owner,_images)
		for i in bindings.size():
			if bindings[i]==null:push_error("Null transmission binding "+str(i));return false
		_set=_rd.uniform_set_create(bindings,_shader,0)
	if not _set.is_valid():return false
	# Refraction does not have an ordinary primary-surface motion vector.
	# Reuse only a truly stationary, unchanged view. No opaque history guesses
	# through moving glass, camera cuts, animated actors, lighting or RR jitter.
	var signature:=frame.slice(0,2816)
	for index in range(32,64):signature.encode_float(index*4,0)
	for index in range(148,164):signature.encode_float(index*4,0)
	for index in [76,82,145,146]:signature.encode_float(index*4,0)
	if dirty or signature!=_signature or frame.decode_float(82*4)<.5:
		history=0;resets+=1
	_signature=signature
	var control:=PackedFloat32Array([history,0,0,0]).to_byte_array()
	if _rd.buffer_update(_control,0,16,control)!=OK:return false
	var rays:=_rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(rays,_pipeline)
	_rd.raytracing_list_bind_uniform_set(rays,_set,0)
	_rd.raytracing_list_trace_rays(rays,0,_sbt,size.x,size.y,1)
	_rd.raytracing_list_end()
	# Assigning even the same RD RID replaces the RenderingServer texture and
	# invalidates prepared material descriptors. RR calls this at PRE_OPAQUE;
	# publish only on allocation (queue_frame prepares resizes before the view).
	if colour.texture_rd_rid!=_images[0]:colour.texture_rd_rid=_images[0]
	if guide.texture_rd_rid!=_images[1]:guide.texture_rd_rid=_images[1]
	active=true;frames+=1;history=mini(history+1,31)
	return true

func dispose(release: Callable=Callable()) -> void:
	colour.texture_rd_rid=RID();guide.texture_rd_rid=RID();active=false
	if _rd!=null:
		_release_set(release)
		for r in _images+[_sbt,_metadata,_control]:
			if r.is_valid():
				if release.is_valid():release.call(r)
				else:_rd.free_rid(r)
	if _own_programs and _programs!=null:_programs.dispose(release)
	_images.clear();_sbt=RID();_metadata=RID();_control=RID();_shader=RID();_pipeline=RID()
	_programs=null;_own_programs=false;_rd=null;_size=Vector2i.ZERO;_sampler=RID();_cloud=RID()
	_signature=PackedByteArray();history=0;bytes=0;_empty=false
