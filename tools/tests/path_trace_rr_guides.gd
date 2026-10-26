extends "res://tools/tests/scene_raytrace_device.gd"
## Real production compute dispatch on D3D12 and Vulkan, independently of the
## Streamline SDK. Analytical surfaces supply binary16 PT guides, real float
## depth and quantized raster normals. No image comparison or source matching.
const GUIDES=preload("res://src/game/fx/shaders/path_trace_rr_guides.glsl")
const EXTENT:=Vector2i(8,8)
const ALBEDO:=Color(.17,.29,.41,63)
const EPSILON:=.001
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var sampler:=RID()
var result: Image
var all_finite:=false
var released:=false
var dispatch_error:=""
var rows: Array[Dictionary]=[]
signal dispatched

func binding(type: int,index: int,ids: Array) -> RDUniform:
	var uniform:=RDUniform.new();uniform.uniform_type=type;uniform.binding=index
	for rid: RID in ids:uniform.add_id(rid)
	return uniform

func texture(format: int,bytes:=PackedByteArray()) -> RID:
	var info:=RDTextureFormat.new();info.width=EXTENT.x;info.height=EXTENT.y;info.format=format
	info.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(info,RDTextureView.new(),[] if bytes.is_empty() else [bytes])

func prepare() -> void:
	rd=RenderingServer.get_rendering_device()
	if rd!=null:
		shader=rd.shader_create_from_spirv(GUIDES.get_spirv(),"RR guide contract regression")
		if shader.is_valid():pipeline=rd.compute_pipeline_create(shader)
		sampler=rd.sampler_create(RDSamplerState.new())
	dispatched.emit.call_deferred()

func execute(images: Array[Image],frame_data: PackedByteArray) -> void:
	result=null;all_finite=false;dispatch_error=""
	var formats: Array[int]=[RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM]
	var inputs: Array[RID]=[];var outputs: Array[RID]=[]
	for i in 6:inputs.append(texture(formats[i],images[i].get_data()))
	for i in 4:outputs.append(texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT if i==3 else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT))
	var frame_buffer:=rd.uniform_buffer_create(frame_data.size(),frame_data)
	var uniforms: Array[RDUniform]=[]
	for i in 4:uniforms.append(binding(RenderingDevice.UNIFORM_TYPE_IMAGE,i,[inputs[i]]))
	for i in range(4,6):uniforms.append(binding(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,i,[sampler,inputs[i]]))
	for i in 4:uniforms.append(binding(RenderingDevice.UNIFORM_TYPE_IMAGE,6+i,[outputs[i]]))
	uniforms.append(binding(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,10,[frame_buffer]))
	var set:=rd.uniform_set_create(uniforms,shader,0)
	if set.is_valid() and inputs.all(func(rid: RID):return rid.is_valid()) and outputs.all(func(rid: RID):return rid.is_valid()):
		var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,set,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
		result=Image.create_from_data(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(outputs[0],0))
		all_finite=true
		for i in 4:
			var image:=Image.create_from_data(EXTENT.x,EXTENT.y,false,Image.FORMAT_RH if i==3 else Image.FORMAT_RGBAH,rd.texture_get_data(outputs[i],0))
			for y in EXTENT.y:
				for x in EXTENT.x:
					var c:=image.get_pixel(x,y);all_finite=all_finite and is_finite(c.r+c.g+c.b+c.a)
	else:dispatch_error="compute input or uniform allocation failed"
	for rid: RID in [set,frame_buffer]+inputs+outputs:
		if rid.is_valid():rd.free_rid(rid)
	released=(inputs+outputs).all(func(rid: RID):return not rd.texture_is_valid(rid))
	dispatched.emit.call_deferred()

func finish_compute() -> void:
	if rd!=null:
		for rid in [pipeline,shader,sampler]:
			if rid.is_valid():rd.free_rid(rid)
	dispatched.emit.call_deferred()

func half_spacing(depth: float) -> float:
	# Decode the actual storage representation instead of duplicating the
	# production logarithm or geometric matching calculation.
	var sample:=Image.create(1,1,false,Image.FORMAT_RF);sample.set_pixel(0,0,Color(depth,0,0))
	sample.convert(Image.FORMAT_RH)
	var exponent: int=(sample.get_data().decode_u16(0)>>10)&31
	return pow(2.0,maxi(exponent,1)-25)

func inputs_for(ortho: bool,depth: float,slope: float,kind: String) -> Dictionary:
	var projection:=Projection.create_orthogonal(-.7,.7,-.7,.7,.05,200) if ortho else Projection.create_perspective(12,1,.05,200)
	var inverse:=projection.inverse()
	var transform:=Transform3D(Basis(Vector3.UP,.37)*Basis(Vector3.BACK,-.2),Vector3(17,12,-5))
	var frame_data:=PackedFloat32Array()
	for matrix: Projection in [inverse,Projection(transform),Projection(),Projection()]:
		for i in 4:
			var v: Vector4=matrix[i];frame_data.append_array([v.x,v.y,v.z,v.w])
	frame_data.resize(704)
	var guide:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBAF)
	var material:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBAF);material.fill(ALBEDO)
	var distance:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGF);distance.fill(Color(2,3,0))
	var specular:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBAF);specular.fill(Color(0,0,0,.5))
	var depth_image:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RF)
	var raster_normal:=Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBA8)
	var plane_normal:=Vector3(0,sin(deg_to_rad(slope)),cos(deg_to_rad(slope)))
	for y in EXTENT.y:
		for x in EXTENT.x:
			var uv:=(Vector2(x,y)+Vector2(.5,.5))/Vector2(EXTENT)
			var near:=inverse*Vector4(uv.x*2-1,1-uv.y*2,-1,1);near/=near.w
			var origin:=Vector3(near.x,near.y,0) if ortho else Vector3.ZERO
			var ray:=Vector3(0,0,-1) if ortho else Vector3(near.x,near.y,near.z)/(-near.z)
			var normal:=plane_normal
			var traced_depth: float=(normal.dot(Vector3(0,0,-depth))-normal.dot(origin))/normal.dot(ray)
			if kind=="curved":
				# The front of an actual sphere, not a screen-space normal field.
				var centre:=Vector3(0,0,-depth);var radius:=depth*.25
				var delta:=origin-centre;var a:=ray.length_squared();var b:=2.0*ray.dot(delta)
				traced_depth=(-b-sqrt(b*b-4.0*a*(delta.length_squared()-radius*radius)))/(2.0*a)
				normal=(origin+ray*traced_depth-centre).normalized()
			var world_normal:=transform.basis*normal
			var raster_depth:=traced_depth
			if kind=="raised":raster_depth-=3.0*half_spacing(traced_depth)
			elif kind=="opposed":raster_depth-=.008
			elif kind=="ambiguous":raster_depth-=.25*half_spacing(traced_depth)
			var traced_store:=traced_depth*.5 if kind=="foreground" else traced_depth
			guide.set_pixel(x,y,Color(world_normal.x,world_normal.y,world_normal.z,0.0 if kind=="missing" else traced_store))
			var point:=origin+ray*raster_depth
			var clip:=projection*Vector4(point.x,point.y,point.z,1)
			depth_image.set_pixel(x,y,Color(0 if kind=="sky" else (1.0-clip.z/clip.w)*.5,0,0))
			var actual_normal: Vector3=-normal if kind=="opposed" else normal.rotated(Vector3.RIGHT,deg_to_rad(50.0)) if kind=="relief" else normal
			raster_normal.set_pixel(x,y,Color(actual_normal.x*.5+.5,actual_normal.y*.5+.5,actual_normal.z*.5+.5,127.0/255.0))
	guide.convert(Image.FORMAT_RGBAH);material.convert(Image.FORMAT_RGBAH)
	distance.convert(Image.FORMAT_RGH);specular.convert(Image.FORMAT_RGBAH)
	var images: Array[Image]=[guide,material,distance,specular,depth_image,raster_normal]
	return {"images":images,"frame":frame_data.to_byte_array(),"expected":material.get_pixel(0,0)}

func exercise(ortho: bool,depth: float,slope: float,kind: String) -> void:
	var label:="%s %s depth %.1f slope %.1f"%["ortho" if ortho else "perspective",kind,depth,slope]
	var input:=inputs_for(ortho,depth,slope,kind)
	RenderingServer.call_on_render_thread(execute.bind(input.images,input.frame));await dispatched
	check(dispatch_error.is_empty() and result!=null and all_finite,label+" produces finite actual GPU guides")
	var matched:=0;var neutral:=0;var black:=0;var other:=0
	if result!=null:
		var expected: Color=input.expected
		for y in EXTENT.y:
			for x in EXTENT.x:
				var c:=result.get_pixel(x,y)
				if Vector3(c.r-expected.r,c.g-expected.g,c.b-expected.b).length()<EPSILON:matched+=1
				elif Vector3(c.r-1,c.g-1,c.b-1).length()<EPSILON:neutral+=1
				elif Vector3(c.r,c.g,c.b).length()<EPSILON:black+=1
				else:other+=1
	var count:=EXTENT.x*EXTENT.y
	var good:=matched==count if kind in ["matching","curved","relief"] else black==count if kind=="sky" else matched+neutral==count if kind=="ambiguous" else neutral==count
	check(result!=null and good,label+" preserves the analytical material contract")
	rows.append({"label":label,"matched":matched,"neutral":neutral,"black":black,"other":other,"error":dispatch_error})
	if not good and result!=null:result.save_png(out.path_join(label.replace(" ","-")+".png"))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.call_on_render_thread(prepare);await dispatched
	check(rd!=null,"real RenderingDevice is available")
	check(shader.is_valid() and pipeline.is_valid() and sampler.is_valid(),"production RR compute program prepares")
	if not pipeline.is_valid():finish();return
	for ortho: bool in [false,true]:
		for depth: float in [2.0,20.0,65.0]:
			for kind: String in ["matching","raised","opposed","ambiguous"]:await exercise(ortho,depth,0,kind)
		for slope: float in [-50.0,50.0]:
			for kind: String in ["matching","raised","relief"]:await exercise(ortho,20,slope,kind)
		for depth: float in [8.0,20.0]:await exercise(ortho,depth,0,"curved")
		for kind: String in ["foreground","missing","sky"]:await exercise(ortho,20,0,kind)
	check(released,"compute cases release every private input and output texture")
	RenderingServer.call_on_render_thread(finish_compute);await dispatched
	FileAccess.open(out.path_join("rr-guide-contract.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,
		"driver":RenderingServer.get_current_rendering_driver_name(),"native_sdk_required":false},"\t"))
	finish()
