class_name LocalLightShader
extends RefCounted
## GLES adds its shadow passes after encoding to sRGB. Accumulate each enhanced
## local light's encoded contribution the same way in the base pass, including
## the actual fragment emission/fog. Original lighting keeps its existing math.
## The encode/inverse pair matches Godot's GLES tonemap_inc.glsl, including its
## omitted linear segment near black; ei_lin/ei_srgb are not exact inverses of it.

static func enabled() -> bool:
	if not Portability.compatibility():
		return false
	var args := OS.get_cmdline_user_args()
	if args.has("--no-local-shadow-fades"):
		return false
	# The extra colour conversions buy continuity, not cheaper shadows. Keep
	# constrained devices on their existing shader until measured on-device.
	return not Portability.constrained() or args.has("--local-shadow-fades")

const COMMON := """
varying vec3 ei_pass_emission;
varying vec4 ei_pass_fog;
vec3 ei_pass_encode(vec3 c) {
	return max(1.055 * pow(max(c, vec3(0.0)), vec3(0.416666667)) - 0.055, vec3(0.0));
}
vec3 ei_pass_decode(vec3 c) {
	return pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)) * step(vec3(1e-7), c);
}
"""

const CAPTURE := """
	// GLES converts EMISSION with this polynomial after fragment(). FOG is
	// already linear. Capture after all fragment options have written them.
	ei_pass_emission = EMISSION * (EMISSION * (EMISSION * 0.305306011 + 0.682171111) + 0.012522878);
	// Match the renderer's packed half-precision fog, especially near fully
	// opaque fog where a small alpha difference would amplify the inverse.
	ei_pass_fog = vec4(unpackHalf2x16(packHalf2x16(FOG.rg)), unpackHalf2x16(packHalf2x16(FOG.ba)));
"""

const BEGIN := "\tvec3 ei_previous_specular = SPECULAR_LIGHT;"

const END := """
	if (local_light && ei_pass_fog.a < 1.0) {
		// Include this light's optional highlight/transmission in the same
		// addition. The reference is independent of which pass owns the light.
		vec3 addition = SPECULAR_LIGHT - ei_previous_specular;
		vec3 reference = ei_draw_colour(ei_alb, d, s);
		addition = max(ei_pass_encode(ei_pass_decode(reference) + addition) - reference, vec3(0.0));
		if (SPECULAR_AMOUNT > 0.0245) {
			SPECULAR_LIGHT = ei_previous_specular + ei_pass_decode(addition);
		} else {
			// Predict the base pass's encoded/fogged colour, add the same
			// fogged contribution as a separate pass, then undo the final
			// base operations. The game's environment uses exposure 1/linear
			// tone mapping. Do not clamp intermediate values to LDR here.
			vec3 base = DIFFUSE_LIGHT * ALBEDO + ei_pass_emission;
			float clear = 1.0 - ei_pass_fog.a;
			vec3 current = (base + ei_previous_specular) * clear + ei_pass_fog.rgb * ei_pass_fog.a;
			vec3 fogged_addition = addition;
			if (ei_pass_fog.a > 0.0) {
				fogged_addition = ei_pass_encode(ei_pass_decode(addition) * clear);
			}
			vec3 total = ei_pass_decode(ei_pass_encode(current) + fogged_addition);
			SPECULAR_LIGHT = (total - ei_pass_fog.rgb * ei_pass_fog.a) / clear - base;
		}
	}
"""
