extends RefCounted
## A separate program leaves both prior water variants unchanged when off.
const DECLARATIONS := """
uniform sampler2D water_current : filter_nearest, repeat_disable;
uniform float river_phase = 0.0; // bounded on the owning terrain's double clock
varying vec3 river_flow;
vec3 river_at(vec2 grid) {
	// Four vertex fetches avoid depending on float-linear filtering support.
	ivec2 extent = textureSize(water_current, 0);
	vec2 p = clamp(grid, vec2(0.0), vec2(extent - ivec2(1)));
	ivec2 a = ivec2(floor(p));
	ivec2 b = min(a + ivec2(1), extent - ivec2(1));
	vec2 f = fract(p);
	return mix(mix(texelFetch(water_current, a, 0).xyz, texelFetch(water_current, ivec2(b.x,a.y), 0).xyz, f.x),
		mix(texelFetch(water_current, ivec2(a.x,b.y), 0).xyz, texelFetch(water_current, b, 0).xyz, f.x), f.y);
}
"""
const CODE := """
vec2 river_velocity(vec2 current) {
	float slope = length(current);
	return current * (min(0.5 + 2.5 * slope, 4.0) * smoothstep(0.015, 0.08, slope) / max(slope, 0.00001));
}
vec2 river_normals(vec2 q, vec2 dx, vec2 dy, vec2 shift, float phase, float widening, vec2 offset) {
	vec2 p = q - shift * (phase - 0.5) + offset;
	float footprint = 1.0 + widening * abs(phase - 0.5);
	vec2 a = textureGrad(wave_a, p * 0.055, dx * (0.055 * footprint), dy * (0.055 * footprint)).xy * 2.0 - 1.0;
	vec2 b = textureGrad(wave_b, p * 0.13, dx * (0.13 * footprint), dy * (0.13 * footprint)).xy * 2.0 - 1.0;
	return a * 0.6 + b * 0.4;
}
vec2 river_surface(vec2 q, float seconds, bool swamp, vec2 dx, vec2 dy) {
	float slope = length(river_flow.xy);
	float running = swamp ? 0.0 : smoothstep(0.015, 0.08, slope);
	// Keep the original sampling and derivatives for still water and bogs.
	vec3 old_a = texture(wave_a, q * 0.055 + seconds * vec2(0.010, 0.006)).rgb * 2.0 - 1.0;
	vec3 old_b = texture(wave_b, q * 0.13 + seconds * vec2(-0.008, 0.012)).rgb * 2.0 - 1.0;
	vec2 normal = (old_a.xy * 0.6 + old_b.xy * 0.4) * (1.0 - running);
	if (running > 0.0) {
		// Two short, cross-faded phases avoid cumulative flow*time shear.
		// Precomputed bend also keeps mip widening continuous across triangles.
		float gain = min(0.5 + 2.5 * slope, 4.0) / max(slope, 0.00001);
		float widening = river_flow.z * gain * 0.9;
		float fold = min(1.0, 1.0 / max(widening, 0.0001));
		vec2 shift = river_flow.xy * (gain * 0.9 * fold);
		float a = fract(river_phase);
		float b = fract(river_phase + 0.5);
		vec2 advected = mix(river_normals(q, dx, dy, shift, a, widening * fold, vec2(0.0)),
			river_normals(q, dx, dy, shift, b, widening * fold, vec2(3.7, 1.9)), abs(1.0 - 2.0 * a));
		normal += advected * running;
	}
	return normal * (swamp ? 0.18 : ripple_amount) * 0.35;
}
"""

static func source(original: String) -> String:
	var marker := "void vertex() {"
	assert(original.contains(marker),"water vertex insertion point changed")
	var result := original.replace(marker,DECLARATIONS+marker)
	marker = "\tvec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;"
	assert(result.contains(marker),"water rest-position insertion point changed")
	result = result.replace(marker,marker+"\n\triver_flow = river_at(vec2(w0.x, -w0.z));")
	result = result.replace("void fragment() {",CODE+"\nvoid fragment() {")
	marker = """
		vec3 na = texture(wave_a, q * 0.055 + water_time * vec2(0.010, 0.006)).rgb * 2.0 - 1.0;
		vec3 nb = texture(wave_b, q * 0.13 + water_time * vec2(-0.008, 0.012)).rgb * 2.0 - 1.0;
		vec2 slope = (na.xy * 0.6 + nb.xy * 0.4) * (swamp ? 0.18 : ripple_amount) * 0.35;"""
	assert(result.contains(marker),"water detail insertion point changed")
	return result.replace(marker,"\n\t\tvec2 slope = river_surface(q,water_time,swamp,dFdx(q),dFdy(q));")
