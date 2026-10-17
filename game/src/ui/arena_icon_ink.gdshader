shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink : source_color = vec4(1.0);
uniform vec4 edge_ink : source_color = vec4(0.045, 0.075, 0.09, 1.0);
void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	vec2 step = fwidth(UV) * 1.25;
	float edge = alpha;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			edge = max(edge, texture(TEXTURE, UV + vec2(float(x), float(y)) * step).a);
		}
	}
	COLOR = vec4(mix(edge_ink.rgb, ink.rgb, alpha), edge * ink.a * COLOR.a);
}
