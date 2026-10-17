shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink : source_color = vec4(1.0);
uniform vec4 edge_ink : source_color = vec4(0.133333, 0.133333, 0.133333, 1.0);
uniform vec4 glow_ink : source_color = vec4(1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
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
	float halo = 0.0;
	if (glow > 0.0) {
		// A small local halo also works in Compatibility without scene bloom.
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				vec2 offset = vec2(float(x), float(y));
				float sample_alpha = texture(TEXTURE, clamp(UV + offset * step, vec2(0.0), vec2(1.0))).a;
				halo = max(halo, sample_alpha * (1.0 - length(offset) / 4.0));
			}
		}
	}
	float light = halo * glow * (1.0 - body - rim);
	float coverage = body + rim + light;
	vec3 colour = (ink.rgb * body + edge_ink.rgb * rim + glow_ink.rgb * light) / max(coverage, 0.0001);
	COLOR = vec4(colour, coverage) * vertex_tint;
}
