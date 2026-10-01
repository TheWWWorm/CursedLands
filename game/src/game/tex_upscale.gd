class_name TexUpscale
extends RefCounted
## Remake option gfx_hd_textures: the original textures upscaled 2x once at
## load, on the GPU (a compute shader on a local RenderingDevice): Lanczos-2
## on premultiplied colour with a de-ringing clamp to the 2x2 source texels
## round each output pixel (edges stay crisp without halos), half of the
## Lanczos overshoot kept as light sharpening. Transparent texels keep the
## nearest source colour so alpha-tested edges and mipmaps do not darken.
## No GPU (headless, Compatibility renderer): Image.resize Lanczos instead.
## A 256² texture takes well under a millisecond, so nothing is cached on
## disk: decoding a cached 512² PNG would take longer than the upscale.

const SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba8) uniform readonly image2D src;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D dst;
layout(push_constant, std430) uniform Params {
	int sw;
	int sh;
	int wrap;
	float keep_ring;
} pc;

float lanczos2(float x) {
	x = abs(x);
	if (x < 1e-5) return 1.0;
	if (x >= 2.0) return 0.0;
	float px = 3.14159265 * x;
	return 2.0 * sin(px) * sin(px * 0.5) / (px * px);
}

ivec2 at(ivec2 p) {
	if (pc.wrap == 1)
		return ivec2((p.x % pc.sw + pc.sw) % pc.sw, (p.y % pc.sh + pc.sh) % pc.sh);
	return clamp(p, ivec2(0), ivec2(pc.sw - 1, pc.sh - 1));
}

void main() {
	ivec2 o = ivec2(gl_GlobalInvocationID.xy);
	if (o.x >= pc.sw * 2 || o.y >= pc.sh * 2)
		return;
	vec2 s = (vec2(o) + 0.5) * 0.5 - 0.5;
	ivec2 b = ivec2(floor(s));
	vec2 f = s - vec2(b);
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	vec4 mn = vec4(1e9);
	vec4 mx = vec4(-1e9);
	for (int j = -1; j <= 2; j++) {
		float wy = lanczos2(float(j) - f.y);
		for (int i = -1; i <= 2; i++) {
			float w = lanczos2(float(i) - f.x) * wy;
			vec4 c = imageLoad(src, at(b + ivec2(i, j)));
			c.rgb *= c.a;
			acc += c * w;
			wsum += w;
			if (i >= 0 && i <= 1 && j >= 0 && j <= 1) {
				mn = min(mn, c);
				mx = max(mx, c);
			}
		}
	}
	vec4 r = acc / wsum;
	r = mix(clamp(r, mn, mx), r, pc.keep_ring);
	r = clamp(r, 0.0, 1.0);
	if (r.a > 0.004)
		r.rgb = clamp(r.rgb / r.a, 0.0, 1.0);
	else
		r.rgb = imageLoad(src, at(b + ivec2(round(f)))).rgb;
	imageStore(dst, o, r);
}
"""

static var _rd: RenderingDevice
static var _shader: RID
static var _pipeline: RID
static var _tried := false
## Total time spent upscaling (ms) and textures done, for the load report.
static var ms := 0.0
static var count := 0


static func _init_gpu() -> bool:
	if _tried:
		return _rd != null
	_tried = true
	if DisplayServer.get_name() == "headless":
		return false
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		return false
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = SHADER
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_warning("TexUpscale: " + spirv.compile_error_compute)
		_rd.free()
		_rd = null
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	return true


## Frees the local RenderingDevice. Called when Main leaves the tree: left to
## the static teardown it would be freed after the RenderingServer, and the
## process aborts on exit (rc 134).
static func shutdown() -> void:
	if _rd:
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
		_rd.free()
	_rd = null
	_pipeline = RID()
	_shader = RID()
	_tried = false


## `img` 2x larger (RGBA8, no mipmaps); `wrap`: the texture repeats (else
## its edges clamp, e.g. the terrain atlases).
static func up2(img: Image, wrap := true) -> Image:
	if img == null:
		return null
	var t0 := Time.get_ticks_usec()
	var src := img.duplicate() as Image
	if src.has_mipmaps():
		src.clear_mipmaps()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var out: Image = null
	if _init_gpu():
		out = _gpu(src, w, h, wrap)
	if out == null:
		src.fix_alpha_edges()
		src.resize(w * 2, h * 2, Image.INTERPOLATE_LANCZOS)
		out = src
	ms += (Time.get_ticks_usec() - t0) / 1000.0
	count += 1
	return out


static func _gpu(src: Image, w: int, h: int, wrap: bool) -> Image:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = w
	fmt.height = h
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var tin := _rd.texture_create(fmt, RDTextureView.new(), [src.get_data()])
	fmt.width = w * 2
	fmt.height = h * 2
	var tout := _rd.texture_create(fmt, RDTextureView.new())
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(tin)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(tout)
	var uset := _rd.uniform_set_create([u0, u1], _shader, 0)
	var pc := PackedByteArray()
	pc.resize(16)
	pc.encode_s32(0, w)
	pc.encode_s32(4, h)
	pc.encode_s32(8, 1 if wrap else 0)
	pc.encode_float(12, 0.5)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, uset, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, ceili(w * 2 / 8.0), ceili(h * 2 / 8.0), 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var data := _rd.texture_get_data(tout, 0)
	_rd.free_rid(uset)
	_rd.free_rid(tin)
	_rd.free_rid(tout)
	if data.size() != w * h * 16:
		return null
	return Image.create_from_data(w * 2, h * 2, false, Image.FORMAT_RGBA8, data)
