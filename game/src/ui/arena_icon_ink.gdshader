shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink : source_color = vec4(1.0);
uniform vec4 edge_ink : source_color = vec4(0.133333, 0.133333, 0.133333, 1.0);
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	vec2 step = fwidth(UV);
	float edge = alpha;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			edge = max(edge, texture(TEXTURE, clamp(UV + vec2(float(x), float(y)) * step, vec2(0.0), vec2(1.0))).a);
		}
	}
	float body = alpha * ink.a;
	float rim = max(edge - alpha, 0.0) * edge_ink.a;
	float coverage = body + rim;
	vec3 colour = (ink.rgb * body + edge_ink.rgb * rim) / max(coverage, 0.0001);
	COLOR = vec4(colour, coverage) * vertex_tint;
}
