shader_type canvas_item;
// A soft outline on the original animated model, not on its entire tile.
uniform vec4 glow_color : source_color = vec4(0.84,0.71,0.43,1.0);
uniform float glow_strength = 0.45;
uniform bool upgrade_pulse = false;
varying vec4 modulation;
void vertex() { modulation = COLOR; }
void fragment() {
	vec4 figure = texture(TEXTURE, UV);
	float pulse = upgrade_pulse ? 0.65 + 0.35 * sin(TIME * 4.0) : 1.0;
	vec2 step_uv = TEXTURE_PIXEL_SIZE * (upgrade_pulse ? 3.5 : 1.5);
	float halo = 0.0;
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.2831853 / 16.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * step_uv;
		halo += texture(TEXTURE, UV + offset).a / 16.0;
		halo += texture(TEXTURE, UV + offset * 0.5).a / 16.0;
	}
	vec3 gold = glow_color.rgb;
	float edge = min(1.0, halo) * (1.0 - figure.a) * glow_strength * pulse;
	float alpha = figure.a + edge;
	vec3 tint = mix(figure.rgb, gold, upgrade_pulse ? 0.04 * pulse : 0.0);
	COLOR = vec4((tint * figure.a + gold * edge) / max(alpha, 0.001), alpha) * modulation;
}
