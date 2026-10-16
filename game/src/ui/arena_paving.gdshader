shader_type spatial;
#ifdef ARENA_PAVING_EDGE
render_mode depth_prepass_alpha;
#endif
uniform sampler2D paving : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 atlas_rect = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	vec2 uv = atlas_rect.xy + UV * atlas_rect.zw;
	ALBEDO = texture(paving, uv).rgb * 0.42;
	// Shallow relief follows the actual stone seams; it does not displace the
	// walkable surface or introduce a second, unrelated noise pattern.
	vec2 texel = 1.0 / vec2(textureSize(paving, 0));
	vec3 weights = vec3(0.3, 0.59, 0.11);
	float dx = dot(texture(paving, uv + vec2(texel.x, 0.0)).rgb
		- texture(paving, uv - vec2(texel.x, 0.0)).rgb, weights);
	float dy = dot(texture(paving, uv + vec2(0.0, texel.y)).rgb
		- texture(paving, uv - vec2(0.0, texel.y)).rgb, weights);
	NORMAL_MAP = normalize(vec3(-dx * 1.2, -dy * 1.2, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
#ifdef ARENA_PAVING_EDGE
	vec2 edge = min(uv, vec2(1.0) - uv);
	ALPHA = smoothstep(0.0, 0.045, min(edge.x, edge.y));
#endif
}
