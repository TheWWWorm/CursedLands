extends RefCounted
## A separate opt-in water program keeps the original/off path free of the
## per-unit loop. This uses the existing water pass, depth and lighting.
const CODE := """
uniform int water_contact_count = 0;
uniform vec4 water_contact_position[16]; // world x/z, surface y, body radius
uniform vec4 water_contact_motion[16];   // heading x/z, speed, motion weight
uniform vec2 water_contact_presence[16]; // presence weight, stable phase
uniform float water_contact_phase = 0.0;
vec3 water_unit_contact(vec3 position, float footprint) {
	vec2 slope = vec2(0.0);
	float foam = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= water_contact_count) { break; }
		vec4 body = water_contact_position[i];
		vec4 motion = water_contact_motion[i];
		vec2 presence = water_contact_presence[i];
		vec2 q = position.xz - body.xy;
		float reach = min(5.0, 1.0 + motion.z * 0.9 + body.w * 2.0);
		if (max(abs(q.x), abs(q.y)) > reach || abs(position.y - body.z) > 0.3) { continue; }
		float distance = max(length(q), 0.001);
		vec2 radial = q / distance;
		float width = max(0.045, footprint * 1.3);
		float radius = body.w * (1.0 + 0.015 * sin(water_contact_phase + presence.y));
		float rim = distance - radius;
		float ring = exp(-rim * rim / (width * width));
		float moving = motion.w * clamp(motion.z / 3.0, 0.0, 1.0);
		slope += radial * (-2.0 * rim / (width * width)) * ring * 0.0045 * presence.x;
		float breakup = 0.6 + 0.4 * sin(position.x * 19.0 + presence.y) * sin(position.z * 17.0 + water_contact_phase);
		foam = max(foam, ring * breakup * (0.28 + 0.50 * moving) * presence.x);
		// Diverging crests follow the previous travel heading. The controller
		// eases direction and retains the last speed while a stopped wake fades.
		float behind = -dot(q, motion.xy);
		if (behind > 0.0 && behind < reach && motion.w > 0.001) {
			vec2 across = vec2(-motion.y, motion.x);
			float side = dot(q, across);
			float arm = abs(side) - (body.w + behind * 0.36);
			float band = max(0.10 + behind * 0.04, footprint * 1.5);
			float crest = exp(-arm * arm / (band * band));
			float fade = smoothstep(0.0, max(body.w,0.1), behind) * (1.0 - smoothstep(reach * 0.55, reach, behind));
			float wake_ripple = 0.65 + 0.35 * cos(behind * 10.0 - water_contact_phase * 2.0);
			vec2 gradient = sign(side) * across + 0.36 * motion.xy;
			slope += gradient * (-2.0 * arm / (band * band)) * crest * fade * wake_ripple * 0.012 * moving;
			foam = max(foam, crest * fade * wake_ripple * breakup * 0.14 * moving * presence.x);
		}
	}
	return vec3(clamp(slope, vec2(-0.35), vec2(0.35)), clamp(foam,0.0,0.8));
}
"""

static func source(original: String) -> String:
	var source := original.replace("void fragment() {",CODE+"\nvoid fragment() {")
	var marker := "\t\t// Raindrops on open water; subpixel rings fade out with distance."
	assert(source.contains(marker),"water normal insertion point changed")
	source = source.replace(marker,"""
		vec3 unit_contact = vec3(0.0);
		if (!swamp && water_contact_count > 0) {
			float footprint = max(length(dFdx(wpos.xz)),length(dFdy(wpos.xz)));
			unit_contact = water_unit_contact(wpos,footprint) * (1.0-smoothstep(30.0,55.0,length(VERTEX)));
			slope += unit_contact.xy;
		}
"""+marker)
	marker = "\t\t// Reflection weight: Schlick's Fresnel term without its 2 % floor,"
	assert(source.contains(marker),"water colour insertion point changed")
	return source.replace(marker,"""
		float contact_foam = unit_contact.z * shore;
		t = mix(t,vec3(0.85),contact_foam * 0.55);
		a = mix(a,0.85,contact_foam * 0.55);
		foam = max(foam,contact_foam);
"""+marker)
