shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float side = smoothstep(0.30, 0.53, abs(UV.x - 0.5));
	float top = 1.0 - smoothstep(0.0, 0.25, UV.y);
	float bottom = smoothstep(0.78, 1.0, UV.y);
	COLOR = vec4(0.015, 0.025, 0.029, max(side * 0.25, max(top * 0.92, bottom * 0.92)));
}
