extends RefCounted
## Shading-only disturbance in the existing transparent water pass. The
## rendered/navigation geometry and authored geometric wave state are intact.
const CODE := """
uniform sampler2D water_wave_field : filter_linear, repeat_disable;
uniform vec4 water_wave_window = vec4(0.0);
vec3 water_propagating_wave(vec3 position, float footprint) {
	if (water_wave_window.w < 0.5) { return vec3(0.0); }
	vec2 uv = (position.xz-water_wave_window.xy)*water_wave_window.z;
	if (any(lessThan(uv,vec2(0.01))) || any(greaterThan(uv,vec2(0.99)))) { return vec3(0.0); }
	vec4 field = texture(water_wave_field,uv);
	// Conservative mean-height rejection prevents a second overlapping layer
	// inheriting a trail. Fine shoreline shape still uses the existing depth.
	float wave_level = 1.0-smoothstep(0.35,0.7,abs(position.y-field.w));
	vec2 texel = vec2(1.0/128.0);
	vec2 gradient = vec2(texture(water_wave_field,uv+vec2(texel.x,0.0)).r-texture(water_wave_field,uv-vec2(texel.x,0.0)).r,
		texture(water_wave_field,uv+vec2(0.0,texel.y)).r-texture(water_wave_field,uv-vec2(0.0,texel.y)).r)/0.5;
	float fine = 1.0-smoothstep(0.25,0.8,footprint);
	return vec3(clamp(-gradient,vec2(-0.3),vec2(0.3)),field.z*0.22)*wave_level*fine;
}
"""

static func source(original: String) -> String:
	var source := original.replace("void fragment() {",CODE+"\nvoid fragment() {")
	var marker := "\t\t// Raindrops on open water; subpixel rings fade out with distance."
	assert(source.contains(marker),"water wave normal insertion point changed")
	source=source.replace(marker,"""
		vec3 propagated = vec3(0.0);
		if (!swamp) {
			propagated = water_propagating_wave(wpos,max(length(dFdx(wpos.xz)),length(dFdy(wpos.xz))));
			propagated *= 1.0-smoothstep(30.0,55.0,length(VERTEX));
			slope += propagated.xy;
		}
"""+marker)
	marker="\t\t// Reflection weight: Schlick's Fresnel term without its 2 % floor,"
	assert(source.contains(marker),"water wave colour insertion point changed")
	return source.replace(marker,"""
		float stirred = propagated.z*shore;
		t=mix(t,vec3(0.72,0.79,0.8),stirred*0.45);
		a=mix(a,0.82,stirred*0.45);
		foam=max(foam,stirred);
"""+marker)
