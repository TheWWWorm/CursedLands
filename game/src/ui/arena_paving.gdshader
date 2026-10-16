shader_type spatial;
render_mode depth_prepass_alpha;
uniform sampler2D paving : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void fragment() {
	ALBEDO = texture(paving, UV).rgb * 0.42;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	vec2 edge = min(UV, vec2(1.0) - UV);
	ALPHA = smoothstep(0.0, 0.045, min(edge.x, edge.y));
}
