shader_type spatial;
// Particle quads (ParticleFx). One MultiMesh instance per particle, filled
// once per 55 ms tick with the previous and the current state, lerped here
// by lerp_t. The instance "transform" rows hold
// (prev x, prev y, prev z, cur x), (cur y, cur z, prev size, cur size) and
// the previous colour; COLOR is the current colour, INSTANCE_CUSTOM the atlas
// rect (u0, v_top, u1, v_bottom).
// The 2000 renderer (display =
// 3dfpfpu.dll TLP =) projects each centre and expands a
// screen-aligned square of half-size size / w pixels-per-unit (x scale for
// both axes), w = sin(fov / 2) * depth, whose x scale is
// cos(fov / 2): in view space a camera-facing square of half-extent
// size / cos(pi / 7) (SIZE_K). Z write off (state 0xe = 0 before
// the particles). ParticleFx swaps blend_mix for blend_add (D3D SRCALPHA /
// ONE) per emitter. Remake addition: soft particles near opaque geometry.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_distance = 0.35;   // 0: off (option gfx_soft_particles)
uniform float lerp_t = 1.0;
// Remake options, set by ParticleFx each frame: light_tint = the scene light
// on smoke / dust (gfx_lit_particles, white in daylight), boost = HDR gain of
// fire / magic / additive effects so only they pass the bloom threshold
// (gfx_bloom).
uniform vec3 light_tint = vec3(1.0);
uniform float boost = 1.0;
// Remake option path_through (ParticleFx.THROUGH_TYPES): the move path dots
// and target marks are drawn with the depth test off (ParticleFx swaps in
// depth_test_disabled); where the scene's depth is nearer than the quad the
// fragment is covered and keeps through_alpha of its alpha. 0: normal.
uniform float through_alpha = 0.0;
varying float psize;
const float SIZE_K = 1.1099162;   // 1 / cos(pi / 7)

void vertex() {
	mat4 m = MODEL_MATRIX;
	vec3 centre = mix(vec3(m[0][0], m[1][0], m[2][0]), vec3(m[3][0], m[0][1], m[1][1]), lerp_t);
	float size = abs(mix(m[2][1], m[3][1], lerp_t)) * SIZE_K;
	COLOR = mix(vec4(m[0][2], m[1][2], m[2][2], m[3][2]), COLOR, lerp_t);
	vec4 vc = VIEW_MATRIX * vec4(centre, 1.0);
	// A non-finite particle collapses behind the eye instead of a huge quad.
	if (any(isnan(vc.xyz)) || any(isinf(vc.xyz)) || isnan(size) || isinf(size)) {
		vc = vec4(0.0, 0.0, 1.0, 1.0);
		size = 0.0;
	}
	VERTEX = vc.xyz + vec3(VERTEX.xy * size, 0.0);
	psize = size;
	NORMAL = vec3(0.0, 0.0, 1.0);
	UV = vec2(mix(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.z, UV.x), mix(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.w, UV.y));
}

void fragment() {
	vec4 t = texture(tex, UV);
	float soft = 1.0;
	if (through_alpha > 0.0) {
		float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		depth = depth * 2.0 - 1.0;
#endif
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene = -v.z / v.w;
		// Covered: the opaque scene lies nearer than the quad by more than its
		// size (a dot on the ground pokes into it a little).
		soft = scene < -VERTEX.z - max(psize, 0.05) ? through_alpha : 1.0;
	} else if (soft_distance > 0.0) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene = -v.z / v.w;
		// Fade range at most the particle's own half-size: small sprites
		// sitting on the ground (zone exit stars, path dots) stay visible.
		float range = max(min(soft_distance, psize), 0.02);
		soft = clamp((scene - (-VERTEX.z)) / range, 0.0, 1.0);
		soft = soft * soft * (3.0 - 2.0 * soft);
	}
	ALBEDO = t.rgb * COLOR.rgb * light_tint * boost;
	ALPHA = t.a * COLOR.a * soft;
}
