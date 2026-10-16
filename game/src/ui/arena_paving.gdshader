shader_type spatial;
render_mode depth_prepass_alpha;
uniform sampler2D paving : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void fragment() {
	ALBEDO = texture(paving, UV).rgb * 0.42;
	// Shallow relief follows the actual stone seams; it does not displace the
	// walkable surface or introduce a second, unrelated noise pattern.
	vec2 texel = 1.0 / vec2(textureSize(paving, 0));
	vec3 weights = vec3(0.3, 0.59, 0.11);
	float dx = dot(texture(paving, UV + vec2(texel.x, 0.0)).rgb
		- texture(paving, UV - vec2(texel.x, 0.0)).rgb, weights);
	float dy = dot(texture(paving, UV + vec2(0.0, texel.y)).rgb
		- texture(paving, UV - vec2(0.0, texel.y)).rgb, weights);
	NORMAL_MAP = normalize(vec3(-dx * 1.2, -dy * 1.2, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
	vec2 edge = min(UV, vec2(1.0) - UV);
	ALPHA = smoothstep(0.0, 0.045, min(edge.x, edge.y));
}
