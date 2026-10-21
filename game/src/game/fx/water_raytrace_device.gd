extends RefCounted
## Experimental Vulkan RT pipeline. All RD resources belong to the render
## thread. Queued callables retain this owner even after its scene is freed.
signal prepared(ok: bool)

const COMMON := """#version 460
#extension GL_EXT_ray_tracing : require
layout(set=0,binding=0) uniform accelerationStructureEXT scene;
layout(set=0,binding=1,rgba16f) uniform image2D output_image;
struct Vertex { vec4 position_u; vec4 normal_v; vec4 diffuse; vec4 emission_layer; };
layout(set=0,binding=2,std430) readonly buffer Vertices { Vertex vertices[]; };
layout(set=0,binding=3) uniform sampler2DArray colours;
layout(set=0,binding=4,std140) uniform Frame {
 mat4 inv_projection;
 mat4 camera_world;
 vec4 ambient;
 vec4 sun;
 vec4 sun_plane;
 vec4 fog; // near, far, trace reach, unused
 vec4 sky;
} frame;
vec3 linear_colour(vec3 c) {
 c=clamp(c,0.0,1.0);
 return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
"""
const RAYGEN := COMMON + """
layout(location=0) rayPayloadEXT vec4 result;
void main() {
 ivec2 pixel=ivec2(gl_LaunchIDEXT.xy);
 vec2 uv=(vec2(pixel)+0.5)/vec2(gl_LaunchSizeEXT.xy);
 vec4 p=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,1.0,1.0);
 p/=p.w;
 vec3 origin=frame.camera_world[3].xyz;
 vec3 direction=normalize((frame.camera_world*vec4(p.xyz,0.0)).xyz);
 result=vec4(0.0);
 // The virtual camera is below water. Start at the water plane, so banks
 // below the surface cannot occlude the scenery being reflected.
 if(direction.y>0.00001) {
  float entry=(frame.sun_plane.w-origin.y)/direction.y;
  if(entry>0.0 && entry<frame.fog.z) {
   traceRayEXT(scene,gl_RayFlagsNoneEXT,255,0,0,0,
       origin+direction*(entry+0.025),0.001,direction,frame.fog.z-entry,0);
  }
 }
 imageStore(output_image,pixel,result);
}
"""
const MISS := COMMON + """
layout(location=0) rayPayloadInEXT vec4 result;
void main() { result=vec4(0.0); }
"""
const HIT_COMMON := COMMON + """
hitAttributeEXT vec2 bary;
vec4 albedo_at_hit() {
 uint i=3u*uint(gl_PrimitiveID);
 vec3 b=vec3(1.0-bary.x-bary.y,bary);
 vec2 uv=vec2(dot(b,vec3(vertices[i].position_u.w,vertices[i+1].position_u.w,vertices[i+2].position_u.w)),
              dot(b,vec3(vertices[i].normal_v.w,vertices[i+1].normal_v.w,vertices[i+2].normal_v.w)));
 return textureLod(colours,vec3(uv,vertices[i].emission_layer.w),0.0);
}
"""
const ANY_HIT := HIT_COMMON + """
void main() {
 if(albedo_at_hit().a*vertices[3u*uint(gl_PrimitiveID)].diffuse.a<0.5) { ignoreIntersectionEXT; }
}
"""
const CLOSEST_HIT := HIT_COMMON + """
layout(location=0) rayPayloadInEXT vec4 result;
void main() {
 uint i=3u*uint(gl_PrimitiveID);
 vec3 b=vec3(1.0-bary.x-bary.y,bary);
 vec3 n=normalize(vertices[i].normal_v.xyz*b.x+vertices[i+1].normal_v.xyz*b.y+vertices[i+2].normal_v.xyz*b.z);
 vec3 light=max(frame.ambient.rgb,min(vec3(1.0),vertices[i].emission_layer.rgb+
     frame.sun.rgb*max(dot(n,frame.sun_plane.xyz),0.0)*vertices[i].diffuse.rgb));
 vec3 colour=linear_colour(albedo_at_hit().rgb*light);
 vec3 point=gl_WorldRayOriginEXT+gl_WorldRayDirectionEXT*gl_HitTEXT;
 float depth=dot(point-frame.camera_world[3].xyz,-frame.camera_world[2].xyz);
 float fog=clamp((depth-frame.fog.x)/max(frame.fog.y-frame.fog.x,0.001),0.0,1.0);
 result=vec4(mix(colour,linear_colour(frame.sky.rgb),fog),1.0);
}
"""

var output := Texture2DRD.new()
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _shader := RID()
var _pipeline := RID()
var _tlas := RID()
var _sbt := RID()
var _vertices := RID()
var _colours := RID()
var _sampler := RID()
var _frame := RID()
var _target := RID()
var _set := RID()
var _size := Vector2i.ZERO
var _ready := false
var _closed := false

static func supported() -> bool:
	if not OS.has_feature("ei_raytracing_uniform_stages"): return false
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus": return false
	if RenderingServer.get_current_rendering_driver_name() != "vulkan": return false
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE)

func _own(rid: RID) -> RID:
	if rid.is_valid(): _owned.append(rid)
	return rid

func _compile() -> RDPipelineShader:
	var source := RDShaderSource.new()
	var stages := {RenderingDevice.SHADER_STAGE_RAYGEN:RAYGEN,RenderingDevice.SHADER_STAGE_MISS:MISS,
		RenderingDevice.SHADER_STAGE_CLOSEST_HIT:CLOSEST_HIT,RenderingDevice.SHADER_STAGE_ANY_HIT:ANY_HIT}
	for stage in stages: source.set_stage_source(stage,stages[stage])
	var spirv := _rd.shader_compile_spirv_from_source(source)
	for stage in stages:
		var error := spirv.get_stage_compile_error(stage)
		if not error.is_empty():
			push_error("Water RT shader: " + error)
			return null
	var shader := _own(_rd.shader_create_from_spirv(spirv))
	if not shader.is_valid(): return null
	_shader = shader
	var wrapped := RDPipelineShader.new()
	wrapped.shader = shader
	return wrapped

## data contains a non-indexed triangle list, 64 bytes per vertex. Images are
## private CPU snapshots; the render thread never reads scene nodes.
func build(data: PackedByteArray, images: Array[Image]) -> void:
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
		RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT | RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT))
	if not _vertices.is_valid():
		prepared.emit.call_deferred(false)
		return
	var geometry := RDAccelerationStructureGeometry.new()
	geometry.vertex_buffer = _vertices
	geometry.vertex_count = data.size()/64
	geometry.vertex_stride = 64
	geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	var blas := _own(_rd.blas_create([geometry],RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT))
	_tlas = _own(_rd.tlas_create(1,0))
	_sbt = _own(_rd.hit_sbt_create(_pipeline,1))
	if not blas.is_valid() or not _tlas.is_valid() or not _sbt.is_valid():
		prepared.emit.call_deferred(false)
		return
	if _rd.blas_build(blas) != OK:
		prepared.emit.call_deferred(false)
		return
	var instance := RDAccelerationStructureInstance.new()
	instance.blas = blas
	instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
	instance.hit_sbt_range = _rd.hit_sbt_range_alloc(_sbt,1)
	_rd.hit_sbt_range_update(_sbt,instance.hit_sbt_range,0,[0])
	if _rd.tlas_build(_tlas,[instance]) != OK:
		prepared.emit.call_deferred(false)
		return
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = images[0].get_width()
	format.height = images[0].get_height()
	format.array_layers = images.size()
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var layers: Array[PackedByteArray] = []
	for im in images: layers.append(im.get_data())
	_colours = _own(_rd.texture_create(format,RDTextureView.new(),layers))
	var sampler := RDSamplerState.new()
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = _own(_rd.sampler_create(sampler))
	_frame = _own(_rd.uniform_buffer_create(208))
	_ready = _colours.is_valid() and _sampler.is_valid() and _frame.is_valid()
	prepared.emit.call_deferred(_ready)

func _uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = kind
	uniform.binding = binding
	for rid in ids: uniform.add_id(rid)
	return uniform

func render(size: Vector2i, frame: PackedByteArray) -> void:
	if _closed or not _ready: return
	if size != _size:
		if _set.is_valid(): _rd.free_rid(_set)
		_set = RID()
		output.texture_rd_rid = RID()
		if _target.is_valid(): _rd.free_rid(_target)
		var format := RDTextureFormat.new()
		format.width = size.x
		format.height = size.y
		format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		_target = _rd.texture_create(format,RDTextureView.new())
		if not _target.is_valid():
			_ready = false
			prepared.emit.call_deferred(false)
			return
		_set = _rd.uniform_set_create([
			_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,[_tlas]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[_target]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[_vertices]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,3,[_sampler,_colours]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[_frame])],_shader,0)
		if not _set.is_valid():
			_ready = false
			prepared.emit.call_deferred(false)
			return
		_size = size
		output.texture_rd_rid = _target
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
	if _rd == null: return
	if _set.is_valid(): _rd.free_rid(_set)
	if _target.is_valid(): _rd.free_rid(_target)
	# Uniform sets and TLAS must go before their underlying resources.
	_owned.reverse()
	for rid in _owned: _rd.free_rid(rid)
	_owned.clear()
	_set = RID()
	_target = RID()
