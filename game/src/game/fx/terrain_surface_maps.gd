class_name TerrainSurfaceMaps
extends RefCounted
## Terrain surface data derived on the player's GPU from the installed, padded
## terrain atlases. Nothing is stored or shipped: each map is rebuilt from the
## player's own textures when a map loads, in the colour atlas's exact layout.
##
## RG: painted relief slope in atlas pixel axes (x right, y down), as the
##     brightness change across three source texels, the convention of the
##     established painted relief. The broad painted shading is removed first,
##     so baked light and shadow do not become a second, embossed relief.
## B:  perceptual roughness. The terrain type's base value (the same values the
##     path tracer already used per type) varied by cavities and crests.
## A:  loose-sand weight (ground type 3), for sand-only detail.

const SLOPE_RANGE := 0.6
# Broad shading is measured in a coarse atlas mip, eight source texels across:
# painted stones and cracks stay, gradual painted light and shadow go. Padded
# slots are 80 source texels wide, so its boxes stay aligned with each slot.
const BROAD_TEXELS := 8.0

const SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2DArray atlas;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D dst;
layout(set = 0, binding = 2, std430) restrict readonly buffer Types { int types[]; };
layout(push_constant, std430) uniform Params {
	int layer;
	int per_row;
	float stride;
	float texel;
	int type_count;
	float slope_range;
	float broad_texels;
	float pad;
} params;
vec2 size;
vec2 low;
vec2 high;
vec3 decode(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
// The established painted relief works in perceptual brightness.
float brightness(vec4 c) { return sqrt(max(dot(decode(c.rgb), vec3(0.2126, 0.7152, 0.0722)), 0.0)); }
float fine(vec2 q) {
	q = clamp(q, low, high);
	return brightness(textureLod(atlas, vec3(q / size, float(params.layer)), 0.0));
}
float broad(vec2 q) {
	float lod = log2(params.broad_texels * params.texel);
	float margin = exp2(lod);
	q = clamp(q, low + margin, high - margin);
	return brightness(textureLod(atlas, vec3(q / size, float(params.layer)), lod));
}
float height(vec2 q) { return fine(q) - broad(q); }
bool any_of(int t, int a, int b, int c) { return t == a || t == b || t == c; }
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(dst)))) return;
	size = vec2(imageSize(dst));
	vec2 q = vec2(p) + 0.5;
	// Each padded slot is isolated: taps never read a neighbouring slot.
	ivec2 slot = ivec2(floor(q / params.stride));
	low = vec2(slot) * params.stride + 0.5;
	high = vec2(slot + 1) * params.stride - 0.5;
	float step_px = 1.5 * params.texel;
	vec2 slope = vec2(height(q + vec2(step_px, 0.0)) - height(q - vec2(step_px, 0.0)),
		height(q + vec2(0.0, step_px)) - height(q - vec2(0.0, step_px)));
	// Atlas tile rows are counted from the bottom of the stored image.
	int tile = (params.per_row - 1 - slot.y) * params.per_row + slot.x;
	int index = params.layer * params.per_row * params.per_row + tile;
	int t = index >= 0 && index < params.type_count ? types[index] : 0;
	float stone = any_of(t, 2, 4, 15) ? 1.0 : 0.0;
	float soft = any_of(t, 3, 9, 12) ? 1.0 : 0.0;
	float grass = any_of(t, 0, 5, 11) ? 1.0 : 0.0;
	float ice = t == 10 ? 1.0 : 0.0;
	float sand = t == 3 ? 1.0 : 0.0;
	float rough = mix(mix(mix(mix(0.94, 0.84, stone), 0.98, soft), 0.96, grass), 0.25, ice);
	float local_height = height(q);
	float cavity = clamp(-local_height * 6.0, 0.0, 1.0);
	float crest = clamp(local_height * 6.0, 0.0, 1.0);
	rough += 0.05 * cavity * (1.0 - ice);
	rough -= crest * (0.10 * stone + 0.03 * (1.0 - stone - soft - grass - ice));
	// Bright sand grains are slightly smoother than the shaded hollows.
	float grain = fine(q) - 0.25 * (fine(q + vec2(params.texel, 0.0)) + fine(q - vec2(params.texel, 0.0))
		+ fine(q + vec2(0.0, params.texel)) + fine(q - vec2(0.0, params.texel)));
	rough -= 0.06 * sand * clamp(grain * 10.0, 0.0, 1.0);
	vec2 encoded = clamp(0.5 + slope / (2.0 * params.slope_range), 0.0, 1.0);
	imageStore(dst, p, vec4(encoded, clamp(rough, 0.08, 1.0), sand));
}
"""

## Shading strength of the derived maps (shader `surface_tuning`, PT header
## offset 64): relief gain, ripple gain, ripple reach in metres per pixel,
## roughness contrast around each ground type's base.
static var tuning := Vector4(1.6, 2.5, 0.25, 2.0)
static var _tried := false
static var _shader := RID()
static var _pipeline := RID()
static var _mip_shader := RID()
static var _mip_pipeline := RID()
static var _sampler := RID()

## Forward+ only. Compatibility and Mobile keep the established relief: no
## compute device there, or a large extra cost on the qualified Adreno path.
static func supported() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null \
		and RenderingServer.get_current_rendering_method() == "forward_plus"

static func requested() -> bool:
	return Gfx.on("gfx_terrain") and Gfx.on("gfx_materials") and Gfx.on("gfx_terrain_surface") and supported()

## Per atlas slot (layer * slots per atlas + slot) original ground type.
static func slot_types(tile_types: PackedInt32Array, layers: int, per_atlas: int) -> PackedInt32Array:
	var types := PackedInt32Array(); types.resize(maxi(layers * per_atlas, 1))
	for i in mini(tile_types.size(), types.size()): types[i] = tile_types[i]
	return types

## atlas: the padded detail atlas array. per_row: tiles per atlas side.
## stride_texels: original tile plus both gutters, in source texels.
## Returns null when unsupported; callers keep the established relief.
static func create(atlas: TextureLayered, types: PackedInt32Array, per_row: int, stride_texels: int) -> TextureLayered:
	if atlas == null or not supported() or atlas.get_layers() < 2 or per_row <= 0 or stride_texels <= 0:
		return null
	var stride := float(atlas.get_width()) / per_row
	var job := {"atlas":atlas.get_rid(),"layers":atlas.get_layers(),"width":atlas.get_width(),"height":atlas.get_height(),
		"types":slot_types(types,atlas.get_layers(),per_row*per_row),"per_row":per_row,"stride":stride,
		"texel":stride/stride_texels,"texture":null,"done":Semaphore.new()}
	RenderingServer.call_on_render_thread(_create_on_render_thread.bind(job))
	job.done.wait()
	return job.texture

static func _create_on_render_thread(job: Dictionary) -> void:
	job.texture = _create(job)
	job.done.post()

static func _init_device(rd: RenderingDevice) -> bool:
	if _tried: return _pipeline.is_valid() and _mip_pipeline.is_valid() and _sampler.is_valid()
	_tried = true
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	if not rd.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,usage): return false
	var main := TexUpscaleTexture._program(rd,SHADER)
	if main.is_empty(): return false
	var mip := TexUpscaleTexture._program(rd,TexUpscaleTexture.MIP_SHADER)
	if mip.is_empty():
		rd.free_rid(main[1]); rd.free_rid(main[0])
		return false
	_shader = main[0]; _pipeline = main[1]; _mip_shader = mip[0]; _mip_pipeline = mip[1]
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR; state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE; state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(state)
	return _sampler.is_valid()

static func _create(job: Dictionary) -> Texture:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not _init_device(rd): return null
	var source := RenderingServer.texture_get_rd_texture(job.atlas,false)
	if not source.is_valid(): return null
	var fmt := RDTextureFormat.new(); fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = job.width; fmt.height = job.height
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY; fmt.array_layers = job.layers
	fmt.mipmaps = 1
	var mip_w: int = fmt.width; var mip_h: int = fmt.height
	while mip_w > 1 or mip_h > 1:
		mip_w = maxi(1,mip_w>>1); mip_h = maxi(1,mip_h>>1)
		fmt.mipmaps += 1
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var output := rd.texture_create(fmt,RDTextureView.new())
	if not output.is_valid(): return null
	var types: PackedInt32Array = job.types
	var buffer := rd.storage_buffer_create(types.size()*4,types.to_byte_array())
	var slices: Array[RID] = []
	var sets: Array[RID] = []
	var ready := buffer.is_valid()
	for layer in fmt.array_layers:
		if not ready: break
		var previous := RID()
		for level in fmt.mipmaps:
			var slice := rd.texture_create_shared_from_slice(RDTextureView.new(),output,layer,level)
			if not slice.is_valid(): ready = false; break
			slices.append(slice)
			var uniforms := RID()
			if level == 0:
				var a := RDUniform.new(); a.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE; a.binding = 0
				a.add_id(_sampler); a.add_id(source)
				var b := RDUniform.new(); b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; b.binding = 1; b.add_id(slice)
				var c := RDUniform.new(); c.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; c.binding = 2; c.add_id(buffer)
				uniforms = rd.uniform_set_create([a,b,c],_shader,0)
			else:
				uniforms = TexUpscaleTexture._uniforms(rd,previous,slice,_mip_shader)
			if not uniforms.is_valid(): ready = false; break
			sets.append(uniforms); previous = slice
	if not ready:
		_free(rd,buffer,slices,sets)
		rd.free_rid(output)
		return null
	# One compute list per dispatch; the render graph orders the slices between
	# lists. compute_list_add_barrier (an end + begin) replays the last push
	# constant after rebinding, which pushed these 32 bytes to the constant-free
	# mip pipeline once per layer (tex_upscale_texture.gd has the same note).
	for layer in fmt.array_layers:
		var constants := PackedByteArray(); constants.resize(32)
		constants.encode_s32(0,layer); constants.encode_s32(4,job.per_row)
		constants.encode_float(8,job.stride); constants.encode_float(12,job.texel)
		constants.encode_s32(16,types.size()); constants.encode_float(20,SLOPE_RANGE)
		constants.encode_float(24,BROAD_TEXELS)
		var commands := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(commands,_pipeline)
		rd.compute_list_bind_uniform_set(commands,sets[layer*fmt.mipmaps],0)
		rd.compute_list_set_push_constant(commands,constants,constants.size())
		rd.compute_list_dispatch(commands,ceili(fmt.width/8.0),ceili(fmt.height/8.0),1)
		rd.compute_list_end()
		var w: int = fmt.width; var h: int = fmt.height
		for level in range(1,fmt.mipmaps):
			commands = rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(commands,_mip_pipeline)
			rd.compute_list_bind_uniform_set(commands,sets[layer*fmt.mipmaps+level],0)
			w = maxi(1,w>>1); h = maxi(1,h>>1)
			rd.compute_list_dispatch(commands,ceili(w/8.0),ceili(h/8.0),1)
			rd.compute_list_end()
	_free(rd,buffer,slices,sets)
	var layered := TexUpscaleTexture.OwnedArray.new(); layered.backing = output; layered.texture_rd_rid = output
	# Shared ownership registry: TexUpscaleTexture.shutdown releases it too.
	TexUpscaleTexture._live[output] = weakref(layered)
	return layered

static func _free(rd: RenderingDevice, buffer: RID, slices: Array[RID], sets: Array[RID]) -> void:
	for uniforms: RID in sets: rd.free_rid(uniforms)
	for slice: RID in slices: rd.free_rid(slice)
	if buffer.is_valid(): rd.free_rid(buffer)

static func shutdown() -> void:
	var done := Semaphore.new()
	RenderingServer.call_on_render_thread(_shutdown.bind(done))
	done.wait()

static func _shutdown(done: Semaphore) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd:
		for rid: RID in [_pipeline,_mip_pipeline,_shader,_mip_shader,_sampler]:
			if rid.is_valid(): rd.free_rid(rid)
	_pipeline = RID(); _mip_pipeline = RID(); _shader = RID(); _mip_shader = RID(); _sampler = RID()
	_tried = false
	done.post()
