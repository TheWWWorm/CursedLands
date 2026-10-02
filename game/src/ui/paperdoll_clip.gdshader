shader_type canvas_item;
render_mode unshaded;

//  permits the figure only in these six depth-clear rectangles.
uniform vec4 view_rect;
uniform vec4 clip_rects[6];

void fragment() {
	vec2 p = view_rect.xy + UV * view_rect.zw;
	float visible = 0.0;
	for (int i = 0; i < 6; i++) {
		vec4 r = clip_rects[i];
		vec2 inside = step(r.xy, p) * (vec2(1.0) - step(r.zw, p));
		visible = max(visible, inside.x * inside.y);
	}
	COLOR.a *= visible;
}
