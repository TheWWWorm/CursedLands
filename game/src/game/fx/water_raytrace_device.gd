extends RefCounted
## Experimental Vulkan RT pipeline. All RD resources belong to the render
## thread. Queued callables retain this owner even after its scene is freed.
signal prepared(ok: bool)

const FRAME_BYTES := 352
const COMMON := """#version 460
#extension GL_EXT_ray_tracing : require
layout(set=0,binding=0) uniform accelerationStructureEXT scene;
layout(set=0,binding=1,rgba16f) uniform image2D output_image;
struct Vertex { vec4 position_u; vec4 normal_v; vec4 diffuse; vec4 emission_layer; };
struct Surface { vec4 colour; vec3 point; vec3 normal; vec3 diffuse; vec3 emission; float visible; float standard; };
layout(set=0,binding=2,std430) readonly buffer Vertices { Vertex vertices[]; };
layout(set=0,binding=3) uniform sampler2DArray colours;
struct Geometry { uint first; uint flags; float cutoff; float pad; };
layout(set=0,binding=5,std430) readonly buffer Materials { Geometry geometry[]; };
layout(set=0,binding=4,std140) uniform Frame {
 mat4 inv_projection;
 mat4 camera_world;
 vec4 ambient;
 vec4 sun; // rgb, shadow rays enabled
 vec4 sun_plane;
 vec4 fog; // near, far, trace reach, orthographic projection
 vec4 sky; // rgb, ray cone width per pixel
 vec4 center_radius;
 vec4 point_position[4];
 vec4 point_colour[4]; // rgb, original additive / enhanced local marker
} frame;
vec3 linear_colour(vec3 c) {
 c=max(c,vec3(0.0));
 return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
"""
const RAYGEN := COMMON + """
layout(location=0) rayPayloadEXT Surface result;
float visibility(vec3 point, vec3 normal, vec3 direction, float reach) {
 if(frame.sun.w<0.5) { return 1.0; }
 // Trace from the raygen stage so shadow rays need no recursive hit stack.
 // Any-hit remains enabled: leaves and fences cast their cutout silhouettes.
 result.visible=0.0;
 vec3 offset=normal*(dot(normal,direction)>=0.0 ? 0.015 : -0.015);
 traceRayEXT(scene,gl_RayFlagsTerminateOnFirstHitEXT|gl_RayFlagsSkipClosestHitShaderEXT,
     2,0,0,0,point+offset,0.002,direction,max(reach-0.02,0.003),0);
 return result.visible;
}
void main() {
 ivec2 pixel=ivec2(gl_LaunchIDEXT.xy);
 vec2 uv=(vec2(pixel)+0.5)/vec2(gl_LaunchSizeEXT.xy);
 vec4 p=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);
 p/=p.w;
 vec3 origin=frame.camera_world[3].xyz;
 vec3 direction=normalize((frame.camera_world*vec4(p.xyz,0.0)).xyz);
 if(frame.fog.w>0.5) {
  origin=(frame.camera_world*vec4(p.xyz,1.0)).xyz;
  direction=-frame.camera_world[2].xyz;
 }
 result.colour=vec4(0.0);
 if(direction.y>0.00001) {
  float entry=(frame.sun_plane.w-origin.y)/direction.y;
  if(entry>0.0 && entry<frame.fog.z) {
   traceRayEXT(scene,gl_RayFlagsNoneEXT,1,0,0,0,
       origin+direction*(entry+0.025),0.001,direction,frame.fog.z-entry,0);
  }
 }
 vec4 colour=result.colour;
 if(colour.a>0.0) {
  vec3 point=result.point, n=result.normal, diffuse=result.diffuse, emission=result.emission;
  float standard=result.standard;
  vec3 light=frame.ambient.rgb;
  vec3 spec=vec3(0.0), extra=vec3(0.0);
  float facing=max(dot(n,frame.sun_plane.xyz),0.0);
  if(facing>0.0) {
   float lit=visibility(point,n,frame.sun_plane.xyz,frame.fog.z);
   light=max(light,frame.sun.rgb*diffuse*facing*lit);
  }
  for(int i=0;i<4;i++) {
   vec4 lamp=frame.point_position[i];
   vec3 delta=lamp.xyz-point;
   float distance=length(delta);
   if(lamp.w<=0.0 || distance>=lamp.w || distance<0.001) { continue; }
   vec3 l=delta/distance;
   float facing=max(dot(n,l),0.0);
   if(facing<=0.0) { continue; }
   float attenuation=max(1.0-distance*distance/(lamp.w*lamp.w),0.0);
   vec3 contribution=frame.point_colour[i].rgb*attenuation*facing*visibility(point,n,l,distance);
   if(frame.point_colour[i].a>1.5) { extra+=linear_colour(contribution)*0.75; }
   else {
    light=max(light,contribution*diffuse);
    if(frame.point_colour[i].a>0.5) { spec=max(spec,contribution); }
   }
  }
  // Authored EI emissive terms multiply the texture; standard material
  // emission is independent, linear radiance and may exceed one.
  vec3 shaded=linear_colour(clamp(colour.rgb*min(light+(standard<0.5 ? emission : vec3(0.0)),vec3(1.0))+spec,0.0,1.0));
  if(standard>0.5) { shaded+=emission; }
  shaded+=linear_colour(colour.rgb)*extra;
  float depth=dot(point-frame.camera_world[3].xyz,-frame.camera_world[2].xyz);
  float fog=clamp((depth-frame.fog.x)/max(frame.fog.y-frame.fog.x,0.001),0.0,1.0);
  colour.rgb=mix(shaded,linear_colour(frame.sky.rgb),fog);
  if(frame.center_radius.w>0.0) {
   colour.a*=1.0-smoothstep(frame.center_radius.w-12.0,frame.center_radius.w,length(point-frame.center_radius.xyz));
  }
 }
 imageStore(output_image,pixel,colour);
}
"""
const MISS := COMMON + """
layout(location=0) rayPayloadInEXT Surface result;
void main() { result.visible=1.0; }
"""
const HIT_COMMON := COMMON + """
hitAttributeEXT vec2 bary;
uint first_vertex() { return geometry[gl_InstanceCustomIndexEXT].first+3u*uint(gl_PrimitiveID); }
vec2 hit_uv(uint i) {
 vec3 b=vec3(1.0-bary.x-bary.y,bary);
 return vec2(dot(b,vec3(vertices[i].position_u.w,vertices[i+1].position_u.w,vertices[i+2].position_u.w)),
              dot(b,vec3(vertices[i].normal_v.w,vertices[i+1].normal_v.w,vertices[i+2].normal_v.w)));
}
"""
const ANY_HIT := HIT_COMMON + """
void main() {
 uint i=first_vertex();
 if(textureLod(colours,vec3(hit_uv(i),vertices[i].emission_layer.w),0.0).a*vertices[i].diffuse.a<geometry[gl_InstanceCustomIndexEXT].cutoff) { ignoreIntersectionEXT; }
}
"""
const CLOSEST_HIT := HIT_COMMON + """
layout(location=0) rayPayloadInEXT Surface result;
void main() {
 uint i=first_vertex();
 vec3 b=vec3(1.0-bary.x-bary.y,bary);
 vec3 n=vertices[i].normal_v.xyz*b.x+vertices[i+1].normal_v.xyz*b.y+vertices[i+2].normal_v.xyz*b.z;
 result.normal=normalize(transpose(mat3(gl_WorldToObjectEXT))*n);
 result.point=gl_WorldRayOriginEXT+gl_WorldRayDirectionEXT*gl_HitTEXT;
 result.diffuse=vertices[i].diffuse.rgb;
 result.emission=vertices[i].emission_layer.rgb;
 result.standard=float(geometry[gl_InstanceCustomIndexEXT].flags & 1u);
 vec3 a=gl_ObjectToWorldEXT*vec4(vertices[i].position_u.xyz,1.0);
 vec3 c=gl_ObjectToWorldEXT*vec4(vertices[i+1].position_u.xyz,1.0);
 vec3 d=gl_ObjectToWorldEXT*vec4(vertices[i+2].position_u.xyz,1.0);
 vec2 ua=vec2(vertices[i].position_u.w,vertices[i].normal_v.w);
 vec2 uc=vec2(vertices[i+1].position_u.w,vertices[i+1].normal_v.w);
 vec2 ud=vec2(vertices[i+2].position_u.w,vertices[i+2].normal_v.w);
 float density=max(length(uc-ua)/max(length(c-a),0.001),length(ud-ua)/max(length(d-a),0.001));
 float distance=frame.fog.w>0.5 ? 1.0 : length(result.point-frame.camera_world[3].xyz);
 float footprint=distance*frame.sky.w*density*float(textureSize(colours,0).x);
 float lod=max(log2(max(footprint,1.0)),0.0);
 result.colour=vec4(textureLod(colours,vec3(hit_uv(i),vertices[i].emission_layer.w),lod).rgb,1.0);
 if(result.standard>0.5) {
  result.colour.rgb*=result.diffuse;
  result.diffuse=vec3(1.0);
 }
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
var _materials := RID()
var _blases: Array[RID] = []
var _geometry: Array = []
var _instances: Array[RDAccelerationStructureInstance] = []
# Keep stable scene indices while omitting masked instances from GPU builds.
var _active_instances := {}
var _placement_geometry := PackedInt32Array()
var _colours := RID()
var _sampler := RID()
var _frame := RID()
var _target := RID()
var _set := RID()
var _size := Vector2i.ZERO
var _ready := false
var _closed := false
var _opaque_fast_path := not OS.get_cmdline_user_args().has("--ei-water-rt-force-anyhit")

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
func build(data: PackedByteArray, images: Array[Image], geometry_data: Array = [], placements: Array = []) -> void:
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
	# Own the descriptors: teardown must not clear the caller's scene array.
	_geometry = geometry_data.duplicate(true) if not geometry_data.is_empty() else [{"offset":0,"count":data.size()/64}]
	var material_data := PackedByteArray(); material_data.resize(_geometry.size()*16)
	for i in _geometry.size():
		var description: Dictionary = _geometry[i]
		material_data.encode_u32(i*16,description.offset)
		material_data.encode_u32(i*16+4,1 if description.get("standard",false) else 0)
		material_data.encode_float(i*16+8,description.get("cutoff",0.5))
	_materials = _own(_rd.storage_buffer_create(material_data.size(),material_data))
	if not _materials.is_valid(): prepared.emit.call_deferred(false); return
	_blases.resize(_geometry.size())
	if placements.is_empty(): placements = [{"geometry":0,"transform":Transform3D.IDENTITY,"mask":255}]
	_tlas = _own(_rd.tlas_create(placements.size(),RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT))
	_sbt = _own(_rd.hit_sbt_create(_pipeline,1))
	if not _tlas.is_valid() or not _sbt.is_valid():
		prepared.emit.call_deferred(false); return
	var hit_range := _rd.hit_sbt_range_alloc(_sbt,1)
	_rd.hit_sbt_range_update(_sbt,hit_range,0,[0])
	for placement: Dictionary in placements:
		var instance := RDAccelerationStructureInstance.new()
		_placement_geometry.append(placement.geometry)
		if placement.get("mask",255) != 0:
			instance.blas = _geometry_blas(placement.geometry)
			if not instance.blas.is_valid(): prepared.emit.call_deferred(false); return
		instance.id = placement.geometry
		instance.transform = placement.transform
		instance.mask = placement.get("mask",255)
		instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
		instance.hit_sbt_range = hit_range
		if instance.mask != 0: _active_instances[_instances.size()] = instance
		_instances.append(instance)
	if _rd.tlas_build(_tlas,_active_instances.values()) != OK:
		prepared.emit.call_deferred(false); return
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = images[0].get_width()
	format.height = images[0].get_height()
	format.array_layers = images.size()
	format.mipmaps = images[0].get_mipmap_count()+1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var layers: Array[PackedByteArray] = []
	for im in images: layers.append(im.get_data())
	_colours = _own(_rd.texture_create(format,RDTextureView.new(),layers))
	var sampler := RDSamplerState.new()
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.max_lod = 20.0
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = _own(_rd.sampler_create(sampler))
	_frame = _own(_rd.uniform_buffer_create(FRAME_BYTES))
	_ready = _colours.is_valid() and _sampler.is_valid() and _frame.is_valid()
	prepared.emit.call_deferred(_ready)

## Hidden meshes keep CPU/vertex data, but acquire a BLAS only when first
## revealed. Reuse it afterward; movement needs only a compact TLAS rebuild.
func _geometry_blas(index: int) -> RID:
	if _blases[index].is_valid(): return _blases[index]
	var description: Dictionary = _geometry[index]
	var geometry := RDAccelerationStructureGeometry.new()
	if _opaque_fast_path and description.get("opaque",false):
		geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	geometry.vertex_buffer = _vertices
	geometry.vertex_offset = description.offset*64
	geometry.vertex_count = description.count
	geometry.vertex_stride = 64
	geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	var blas := _own(_rd.blas_create([geometry],RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT))
	if not blas.is_valid() or _rd.blas_build(blas) != OK: return RID()
	_blases[index] = blas
	return blas

func _uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = kind
	uniform.binding = binding
	for rid in ids: uniform.add_id(rid)
	return uniform

func render(size: Vector2i, frame: PackedByteArray, changes: Dictionary = {}) -> void:
	if _closed or not _ready: return
	var changed := false
	for pose: Dictionary in changes.get("poses",[]):
		_rd.buffer_update(_vertices,_geometry[pose.geometry].offset*64,pose.data.size(),pose.data)
		if _blases[pose.geometry].is_valid() and _rd.blas_build(_blases[pose.geometry]) != OK:
			_ready = false; prepared.emit.call_deferred(false); return
		changed = true
	for placement: Dictionary in changes.get("instances",[]):
		_instances[placement.index].transform = placement.transform
		_instances[placement.index].mask = placement.mask
		if placement.mask != 0:
			var instance := _instances[placement.index]
			instance.blas = _geometry_blas(_placement_geometry[placement.index])
			if not instance.blas.is_valid(): _ready = false; prepared.emit.call_deferred(false); return
			_active_instances[placement.index] = instance
		else: _active_instances.erase(placement.index)
		changed = true
	if changed and _rd.tlas_build(_tlas,_active_instances.values()) != OK:
		_ready = false; prepared.emit.call_deferred(false); return
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
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,4,[_frame]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,[_materials])],_shader,0)
		if not _set.is_valid():
			_ready = false
			prepared.emit.call_deferred(false)
			return
		_size = size
		output.texture_rd_rid = _target
	if frame.size() < FRAME_BYTES: frame.resize(FRAME_BYTES)
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
	# Lazily created BLAS objects can be newer than their TLAS. Release the
	# TLAS explicitly before reversing the remaining dependency order.
	if _tlas.is_valid():
		_rd.free_rid(_tlas); _owned.erase(_tlas); _tlas = RID()
	_owned.reverse()
	for rid in _owned: _rd.free_rid(rid)
	_owned.clear()
	_blases.clear(); _instances.clear(); _active_instances.clear(); _geometry.clear(); _placement_geometry.clear()
	_set = RID()
	_target = RID()
