class_name TexUpscaleTexture
extends RefCounted
## Scenery-only HD output on the renderer's own device. Terrain callers that
## need CPU Images continue to use TexUpscale.up2. All RD ownership stays on
## the rendering thread; there is no local-device submit/sync or readback.

const MIP_SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba8) uniform readonly image2D src;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D dst;
uvec4 pixel(ivec2 p) { return uvec4(round(imageLoad(src, p) * 255.0)); }
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(dst)))) return;
	ivec2 limit = imageSize(src) - ivec2(1);
	ivec2 a = min(p * 2, limit);
	ivec2 b = min(a + ivec2(1), limit);
	// Image::average_4_uint8: encoded RGBA bytes, rounding half upward.
	uvec4 sum = pixel(a) + pixel(ivec2(b.x,a.y)) + pixel(ivec2(a.x,b.y)) + pixel(b);
	imageStore(dst, p, vec4((sum + uvec4(2)) >> 2) / 255.0);
}
"""

class OwnedTexture extends Texture2DRD:
	var backing := RID()
	func release() -> void:
		if not backing.is_valid(): return
		var rid := backing; backing = RID()
		# Detach the RenderingServer's shared views before freeing their owner.
		texture_rd_rid = RID()
		RenderingServer.call_on_render_thread(TexUpscaleTexture._free_texture.bind(rid))
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and backing.is_valid():
			# Clean up inline: last-reference teardown must not call release()
			# through the dying Resource (covered by the ownership regression).
			var rid := backing; backing = RID()
			texture_rd_rid = RID()
			RenderingServer.call_on_render_thread(TexUpscaleTexture._free_texture.bind(rid))

static var _tried := false
static var _up_shader := RID()
static var _up_pipeline := RID()
static var _mip_shader := RID()
static var _mip_pipeline := RID()
static var _live := {} # backing RID -> WeakRef, accessed only on render thread

## Returns null for unsupported devices so the caller can use the established
## Image path. Waiting here finishes CPU resource setup, not GPU execution.
static func create(source: Image, wrap := true) -> Texture2D:
	if source == null or source.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		return null
	var src := source.duplicate() as Image
	if src.is_compressed() and src.decompress() != OK: return null
	src.clear_mipmaps(); src.convert(Image.FORMAT_RGBA8)
	var job := {"source":src,"wrap":wrap,"texture":null,"done":Semaphore.new()}
	RenderingServer.call_on_render_thread(_create_on_render_thread.bind(job))
	job.done.wait()
	return job.texture

static func _program(rd: RenderingDevice, code: String) -> Array[RID]:
	var source := RDShaderSource.new(); source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = code
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_warning("TexUpscaleTexture: " + spirv.compile_error_compute)
		return []
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader) if shader.is_valid() else RID()
	if not pipeline.is_valid():
		if shader.is_valid(): rd.free_rid(shader)
		return []
	return [shader,pipeline]

static func _init_device(rd: RenderingDevice) -> bool:
	if _tried: return _up_pipeline.is_valid() and _mip_pipeline.is_valid()
	_tried = true
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if not rd.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,usage): return false
	var up := _program(rd,TexUpscale.SHADER)
	if up.is_empty(): return false
	_up_shader = up[0]; _up_pipeline = up[1]
	var mip := _program(rd,MIP_SHADER)
	if mip.is_empty():
		rd.free_rid(_up_pipeline); rd.free_rid(_up_shader)
		_up_pipeline = RID(); _up_shader = RID()
		return false
	_mip_shader = mip[0]; _mip_pipeline = mip[1]
	return true

static func _uniforms(rd: RenderingDevice, input: RID, output: RID, shader: RID) -> RID:
	var a := RDUniform.new(); a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; a.binding = 0; a.add_id(input)
	var b := RDUniform.new(); b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; b.binding = 1; b.add_id(output)
	return rd.uniform_set_create([a,b],shader,0)

static func _create_on_render_thread(job: Dictionary) -> void:
	job.texture = _create(job.source,job.wrap)
	job.done.post()

static func _create(src: Image, wrap: bool) -> Texture2D:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not _init_device(rd): return null
	var fmt := RDTextureFormat.new(); fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = src.get_width(); fmt.height = src.get_height()
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var input := rd.texture_create(fmt,RDTextureView.new(),[src.get_data()])
	if not input.is_valid(): return null
	fmt.width *= 2; fmt.height *= 2
	fmt.mipmaps = 1
	var mip_w := fmt.width; var mip_h := fmt.height
	while mip_w > 1 or mip_h > 1:
		mip_w = maxi(1,mip_w>>1); mip_h = maxi(1,mip_h>>1)
		fmt.mipmaps += 1
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	fmt.add_shareable_format(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	fmt.add_shareable_format(RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB)
	var output := rd.texture_create(fmt,RDTextureView.new())
	if not output.is_valid(): rd.free_rid(input); return null
	var slices: Array[RID] = []
	var sets: Array[RID] = []
	for level in fmt.mipmaps:
		var slice := rd.texture_create_shared_from_slice(RDTextureView.new(),output,0,level)
		if not slice.is_valid(): rd.free_rid(input); rd.free_rid(output); return null
		slices.append(slice)
		var uniforms := _uniforms(rd,input if level == 0 else slices[level-1],slice,_up_shader if level == 0 else _mip_shader)
		if not uniforms.is_valid():
			for old: RID in sets: rd.free_rid(old)
			rd.free_rid(input); rd.free_rid(output); return null
		sets.append(uniforms)
	var constants := PackedByteArray(); constants.resize(16)
	constants.encode_s32(0,src.get_width()); constants.encode_s32(4,src.get_height())
	constants.encode_s32(8,int(wrap)); constants.encode_float(12,0.5)
	var commands := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands,_up_pipeline)
	rd.compute_list_bind_uniform_set(commands,sets[0],0)
	rd.compute_list_set_push_constant(commands,constants,constants.size())
	rd.compute_list_dispatch(commands,ceili(fmt.width/8.0),ceili(fmt.height/8.0),1)
	var w := fmt.width; var h := fmt.height
	for level in range(1,fmt.mipmaps):
		rd.compute_list_add_barrier(commands)
		rd.compute_list_bind_compute_pipeline(commands,_mip_pipeline)
		rd.compute_list_bind_uniform_set(commands,sets[level],0)
		w = maxi(1,w>>1); h = maxi(1,h>>1)
		rd.compute_list_dispatch(commands,ceili(w/8.0),ceili(h/8.0),1)
	rd.compute_list_end()
	for uniforms: RID in sets: rd.free_rid(uniforms)
	for slice: RID in slices: rd.free_rid(slice)
	rd.free_rid(input)
	var texture := OwnedTexture.new(); texture.backing = output; texture.texture_rd_rid = output
	_live[output] = weakref(texture)
	return texture

static func _free_texture(rid: RID) -> void:
	_live.erase(rid)
	var rd := RenderingServer.get_rendering_device()
	if rd and rd.texture_is_valid(rid): rd.free_rid(rid)

static func shutdown() -> void:
	var done := Semaphore.new()
	RenderingServer.call_on_render_thread(_shutdown.bind(done))
	done.wait()

static func _shutdown(done: Semaphore) -> void:
	for reference: WeakRef in _live.values():
		var texture := reference.get_ref() as OwnedTexture
		if texture: texture.release()
	_live.clear()
	var rd := RenderingServer.get_rendering_device()
	if rd:
		for rid: RID in [_up_pipeline,_mip_pipeline,_up_shader,_mip_shader]:
			if rid.is_valid(): rd.free_rid(rid)
	_up_pipeline = RID(); _mip_pipeline = RID(); _up_shader = RID(); _mip_shader = RID()
	_tried = false
	done.post()
