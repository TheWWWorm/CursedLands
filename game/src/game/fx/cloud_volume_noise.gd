extends RefCounted
## Periodic Perlin/Worley fields from pinned R1 sky_clouds.h, generated once
## on the main RenderingDevice. No texture readback, original asset or worker
## owns these resources. The owner detaches shared views before freeing RIDs.
const SHADER := """
#version 450
layout(local_size_x=4,local_size_y=4,local_size_z=4) in;
layout(set=0,binding=0,r8) uniform writeonly image3D output_noise;
layout(push_constant,std430) uniform Params { int size; int detail; int pad0; int pad1; } pc;
uint hash3(ivec3 p){uint h=uint(p.x)*73856093u^uint(p.y)*19349663u^uint(p.z)*83492791u;h^=h>>13;h*=0x5bd1e995u;h^=h>>15;return h;}
vec3 grad3(ivec3 p){uint h=hash3(p);return normalize(vec3(h&1023u,(h>>10)&1023u,(h>>20)&1023u)/511.5-1.0+1e-4);}
float perlin3(vec3 p,int period){
 ivec3 i=ivec3(floor(p));vec3 f=fract(p),u=f*f*f*(f*(f*6.0-15.0)+10.0);float r=0.0;
 for(int k=0;k<8;k++){ivec3 o=ivec3(k&1,(k>>1)&1,k>>2),c=((i+o)%period+period)%period;
 vec3 w=mix(1.0-u,u,vec3(o));r+=w.x*w.y*w.z*dot(grad3(c),f-vec3(o));}return r*.5+.5;
}
float worley3(vec3 p,int period){
 ivec3 i=ivec3(floor(p));vec3 f=fract(p);float d=1.0;
 for(int k=0;k<27;k++){ivec3 o=ivec3(k%3,(k/3)%3,k/9)-1,c=((i+o)%period+period)%period;
 uint h=hash3(c+7);vec3 j=vec3(h&255u,(h>>8)&255u,(h>>16)&255u)/255.0;d=min(d,length(vec3(o)+j-f));}return 1.0-clamp(d,0.0,1.0);
}
void main(){
 ivec3 id=ivec3(gl_GlobalInvocationID);if(any(greaterThanEqual(id,ivec3(pc.size))))return;
 vec3 p=(vec3(id)+.5)/float(pc.size);float n;
 if(pc.detail!=0){n=worley3(p*2.0+vec3(.31,.73,1.17),2)*.625+worley3(p.yzx*4.0+vec3(1.59,2.37,.43),4)*.25+worley3(p.zxy*8.0+vec3(3.13,5.71,1.89),8)*.125;}
 else {
 float pf=perlin3(p*4.0+vec3(.17,.43,.71),4)*.625+perlin3(p.yzx*8.0+vec3(2.31,5.17,1.73),8)*.25+perlin3(p.zxy*16.0+vec3(7.13,3.61,11.29),16)*.125;
 float wf=worley3(p*4.0+vec3(1.37,.59,2.11),4)*.625+worley3(p.zxy*8.0+vec3(3.71,1.23,5.47),8)*.25+worley3(p.yzx*16.0+vec3(9.19,7.43,2.89),16)*.125;
 n=clamp((pf-(wf-1.0))/(2.0-wf),0.0,1.0);
 }imageStore(output_noise,id,vec4(n));
}
"""
var shape: Texture3DRD
var detail: Texture3DRD
var setup_ms := 0.0
var _backings: Array[RID] = []


static func supported() -> bool:
	return not Portability.constrained() and not Portability.compatibility() \
		and DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null \
		and (RenderingServer.get_current_rendering_method() != "mobile" or OS.has_feature("ei_sky_subpass_alpha"))


func prepare() -> bool:
	if shape and detail: return true
	if not supported(): return false
	var job := {"done":Semaphore.new(),"shape":null,"detail":null,"backings":[]}
	var start := Time.get_ticks_usec()
	RenderingServer.call_on_render_thread(_create.bind(job))
	job.done.wait() # CPU setup only; the normal render graph executes GPU work.
	setup_ms=(Time.get_ticks_usec()-start)/1000.0
	shape=job.shape; detail=job.detail; _backings.assign(job.backings)
	return shape != null and detail != null


func release() -> void:
	# RenderingServer globals must be detached by the caller first.
	if shape: shape.texture_rd_rid=RID()
	if detail: detail.texture_rd_rid=RID()
	shape=null; detail=null
	var resources := _backings.duplicate(); _backings.clear()
	if not resources.is_empty(): RenderingServer.call_on_render_thread(_free.bind(resources))


func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		# Do not call release() through a dying RefCounted.
		if shape: shape.texture_rd_rid=RID()
		if detail: detail.texture_rd_rid=RID()
		var resources := _backings.duplicate(); _backings.clear()
		if not resources.is_empty(): RenderingServer.call_on_render_thread(_free.bind(resources))


static func _free(resources: Array) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd:
		for rid: RID in resources:
			if rd.texture_is_valid(rid): rd.free_rid(rid)


static func _create(job: Dictionary) -> void:
	_create_inner(job)
	job.done.post()


static func _create_inner(job: Dictionary) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd==null: return
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if not rd.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R8_UNORM,usage): return
	var source := RDShaderSource.new(); source.source_compute=SHADER
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty(): push_warning("CloudVolumeNoise: "+spirv.compile_error_compute); return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader) if shader.is_valid() else RID()
	if not pipeline.is_valid():
		if shader.is_valid(): rd.free_rid(shader)
		return
	var textures: Array[RID]=[]; var sets: Array[RID]=[]
	for size in [128,32]:
		var fmt := RDTextureFormat.new();fmt.texture_type=RenderingDevice.TEXTURE_TYPE_3D
		fmt.width=size;fmt.height=size;fmt.depth=size;fmt.format=RenderingDevice.DATA_FORMAT_R8_UNORM;fmt.usage_bits=usage
		var texture := rd.texture_create(fmt,RDTextureView.new())
		if not texture.is_valid(): break
		textures.append(texture)
		var u := RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.binding=0;u.add_id(texture)
		var set_ := rd.uniform_set_create([u],shader,0)
		if not set_.is_valid(): break
		sets.append(set_)
	if sets.size()==2:
		var commands := rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline)
		for i in 2:
			var size := 128 if i==0 else 32
			var pc := PackedByteArray();pc.resize(16);pc.encode_s32(0,size);pc.encode_s32(4,i)
			rd.compute_list_bind_uniform_set(commands,sets[i],0);rd.compute_list_set_push_constant(commands,pc,16)
			rd.compute_list_dispatch(commands,size/4,size/4,size/4)
		rd.compute_list_end()
		job.shape=Texture3DRD.new();job.shape.texture_rd_rid=textures[0]
		job.detail=Texture3DRD.new();job.detail.texture_rd_rid=textures[1]
		job.backings=textures
	else:
		for texture: RID in textures: rd.free_rid(texture)
	for set_: RID in sets: rd.free_rid(set_)
	rd.free_rid(pipeline);rd.free_rid(shader)
