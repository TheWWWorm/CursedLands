shader_type canvas_item;
// A soft outline on the original animated model, not on its entire tile.
varying vec4 modulation;
void vertex() { modulation = COLOR; }
void fragment() {
	vec4 figure = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 3.0;
	float halo = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			halo = max(halo, texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).a);
		}
	}
	vec3 gold = vec3(0.84, 0.71, 0.43);
	float edge = halo * (1.0 - figure.a) * 0.45;
	float alpha = figure.a + edge;
	vec3 tint = mix(figure.rgb, gold, 0.10);
	COLOR = vec4((tint * figure.a + gold * edge) / max(alpha, 0.001), alpha) * modulation;
}
