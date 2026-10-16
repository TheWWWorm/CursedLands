shader_type spatial;
render_mode cull_disabled;
uniform bool deploying = true;
varying vec3 point;
void vertex() { point = VERTEX; }
void fragment() {
	vec2 p = point.xz;
	vec2 tile = floor(p * 0.5);
	float noise = fract(sin(dot(tile, vec2(127.1, 311.7))) * 43758.5453);
	vec2 edge = abs(fract(p * 0.5) - 0.5);
	float seam = smoothstep(0.475, 0.493, max(edge.x, edge.y));
	vec3 stone = mix(vec3(0.105, 0.126, 0.137), vec3(0.145, 0.159, 0.158), noise);
	float grain = fract(sin(dot(floor(p * 90.0), vec2(78.233, 13.71))) * 15731.23);
	stone *= 0.94 + grain * 0.12;
	stone *= 1.0 - seam * 0.3;
	float ring = 1.0 - smoothstep(0.035, 0.11, abs(length(p) - 4.8));
	float center = 1.0 - smoothstep(0.025, 0.08, abs(p.x));
	float border = 1.0 - smoothstep(0.04, 0.13, abs(max(abs(p.x), abs(p.y)) - 13.5));
	vec3 team = p.x < 0.0 ? vec3(0.22, 0.65, 0.83) : vec3(0.85, 0.32, 0.24);
	stone = mix(stone, vec3(0.30, 0.235, 0.13), ring * 0.65);
	stone = mix(stone, team * 0.55, border * 0.8);
	if (deploying) stone = mix(stone, team * 0.45, center * 0.55 + 0.035);
	ALBEDO = stone;
	ROUGHNESS = 0.92;
}
