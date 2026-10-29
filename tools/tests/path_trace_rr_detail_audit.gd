extends CompositorEffect
## Diagnostic only. Samples the real opaque depth/normal and the production PT
## guide after RR has prepared its material inputs; it never changes those inputs.
const SOURCE := """
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D raster_depth;
layout(set=0,binding=1) uniform sampler2D raster_normal;
layout(rgba16f,set=0,binding=2) uniform readonly image2D traced_guide;
layout(rgba32f,set=0,binding=3) uniform writeonly image2D diagnostics;
layout(std140,set=0,binding=4) uniform Frame { mat4 inv_projection; mat4 camera_world; vec4 plane; } frame;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(diagnostics);
    if(any(greaterThanEqual(p,size)))return;
    vec2 uv=(vec2(p)+.5)/vec2(size);
    float z=texelFetch(raster_depth,p,0).r;
    vec4 view=frame.inv_projection*vec4(uv.x*2.-1.,1.-uv.y*2.,1.-2.*z,1.);view/=view.w;
    vec4 guide=imageLoad(traced_guide,p);
    bool ortho=abs(frame.inv_projection[3][3]-1.)<1e-5;
    vec3 traced=ortho?vec3(view.xy,-guide.w):view.xyz*(guide.w/max(-view.z,1e-6));
    vec3 world=(frame.camera_world*vec4(view.xyz,1.)).xyz;
    vec3 delta=mat3(frame.camera_world)*(view.xyz-traced);
    vec3 normal=normalize(mat3(frame.camera_world)*(texelFetch(raster_normal,p,0).xyz*2.-1.));
    // R is an independent analytic detail mask: signed distance to the known plane.
    // G is the existing match's signed depth residual. B tests the proposed
    // tangent-plane metric without changing production. A checks normal parity.
    imageStore(diagnostics,p,(z>0. && guide.w>0.) ?
        vec4(dot(world,frame.plane.xyz)+frame.plane.w,guide.w+view.z,abs(dot(delta,normalize(guide.xyz))),dot(normal,normalize(guide.xyz))):vec4(-999.));
}
"""
var target: RefCounted
var rr: RefCounted
var armed:=false
var result: Image
var diffuse: Image
var raw_albedo: Image
var raw_guide: Image
var plane:=Vector4(0,1,0,0)
var error:=""
var projection:=Projection()
var camera_world:=Transform3D.IDENTITY
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var sampler:=RID()
var output:=RID()
var uniform_buffer:=RID()
var output_size:=Vector2i.ZERO
var raster_size:=Vector2i.ZERO
var raster_has_normal:=false
signal inspected

func _init() -> void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_OPAQUE
	access_resolved_depth=true
	needs_normal_roughness=true

func uniform(type: int,binding: int,ids: Array) -> RDUniform:
	var u:=RDUniform.new();u.uniform_type=type;u.binding=binding
	for rid: RID in ids:u.add_id(rid)
	return u

func _render_callback(kind: int,data: RenderData) -> void:
	if kind!=EFFECT_CALLBACK_TYPE_POST_OPAQUE or not armed:return
	armed=false;error="";result=null;diffuse=null;raw_albedo=null;raw_guide=null
	var buffers: RenderSceneBuffersRD=data.get_render_scene_buffers()
	var scene: RenderSceneData=data.get_render_scene_data()
	if buffers!=null:
		raster_size=buffers.get_internal_size()
		raster_has_normal=buffers.has_texture(&"forward_clustered",&"normal_roughness")
	if target==null or target._raw.size()<4 or buffers==null or scene==null:
		error="missing current render targets (raw=%d raster=%s)"%[target._raw.size() if target!=null else -1,raster_size];inspected.emit.call_deferred();return
	if rd==null:rd=RenderingServer.get_rendering_device()
	var size:=buffers.get_internal_size()
	if size!=target._size or not buffers.has_texture(&"forward_clustered",&"normal_roughness"):
		error="raster/PT dimensions or normal mismatch: raster=%s PT=%s normal=%s"%[size,target._size,buffers.has_texture(&"forward_clustered",&"normal_roughness")];inspected.emit.call_deferred();return
	if not shader.is_valid():
		var source:=RDShaderSource.new();source.source_compute=SOURCE
		var spirv:=rd.shader_compile_spirv_from_source(source)
		error=spirv.compile_error_compute
		if not error.is_empty():inspected.emit.call_deferred();return
		shader=rd.shader_create_from_spirv(spirv,"raster detail diagnostic")
		pipeline=rd.compute_pipeline_create(shader);sampler=rd.sampler_create(RDSamplerState.new())
		uniform_buffer=rd.uniform_buffer_create(144)
	if output_size!=size:
		if output.is_valid():rd.free_rid(output)
		var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
		format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		output=rd.texture_create(format,RDTextureView.new());output_size=size
	projection=scene.call("get_ray_projection")
	camera_world=scene.get_cam_transform()
	var numbers:=PackedFloat32Array()
	for matrix: Projection in [projection.inverse(),Projection(camera_world)]:
		for column in 4:
			var v: Vector4=matrix[column];numbers.append_array([v.x,v.y,v.z,v.w])
	numbers.append_array([plane.x,plane.y,plane.z,plane.w])
	rd.buffer_update(uniform_buffer,0,144,numbers.to_byte_array())
	var bindings: Array[RDUniform]=[
		uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,0,[sampler,buffers.get_depth_layer(0)]),
		uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,1,[sampler,buffers.get_texture_slice(&"forward_clustered",&"normal_roughness",0,0,1,1)]),
		uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,2,[target.ray_targets()[1]]),
		uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,3,[output]),
		uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[uniform_buffer])]
	var set:=rd.uniform_set_create(bindings,shader,0)
	if not set.is_valid():error="diagnostic uniform creation failed";inspected.emit.call_deferred();return
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1);rd.compute_list_end()
	result=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,rd.texture_get_data(output,0))
	# The ray targets are the published images under RR and the raw images
	# under the denoiser; read whichever the ray programs wrote.
	var targets: Array[RID]=target.ray_targets()
	raw_guide=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(targets[1],0))
	raw_albedo=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(targets[3],0))
	if rr!=null and rr._images.size()==4:
		diffuse=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(rr._images[0],0))
	rd.free_rid(set);inspected.emit.call_deferred()

func dispose() -> void:
	enabled=false;armed=false;target=null;rr=null
	if rd!=null:
		for rid in [output,uniform_buffer,pipeline,shader,sampler]:
			if rid.is_valid():rd.free_rid(rid)
	output=RID();uniform_buffer=RID();pipeline=RID();shader=RID();sampler=RID()
