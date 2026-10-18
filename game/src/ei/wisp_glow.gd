class_name EIWispGlow
extends RefCounted
## Light the authored crystal surfaces. No billboard or enlarged shell can
## round their silhouette. Native morphs own motion; their death clip dims
## the added shine while leaving the original fallen crystals intact.

const UNIFORMS := """
uniform float wisp_phase = 0.0;
uniform float wisp_rate = 2.0;
uniform float wisp_strength = 1.0;
uniform float wisp_presence = 1.0;
// Deterministic inspection/previews can hold a phase without freezing motion.
uniform float wisp_time = -1.0;
"""

const FRAGMENT := """
	float clock = wisp_time < 0.0 ? TIME : wisp_time;
	float pulse = 0.5 + 0.5 * sin(clock * wisp_rate + wisp_phase);
	// A face normal keeps the facets distinct even on smooth-shaded source
	// meshes. Light stays inside the original geometry and texture alpha.
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facet = 0.55 + 0.45 * abs(dot(face, normalize(vec3(-0.5, 0.6, 1.0))));
	float brightest = max(t.r, max(t.g, t.b));
	vec3 crystal = mix(t.rgb, vec3(brightest), 0.12);
	float shine = wisp_strength * wisp_presence;
	ALBEDO *= mix(1.0, 0.25, shine);
	EMISSION += crystal * facet * (1.0 + 1.1 * pulse) * shine;
	ALPHA = mix(ALPHA, min(ALPHA * 2.1, 0.88), shine);
"""


static func shader_source(code: String) -> String:
	return Gfx._function_tail(code.replace("void fragment()", UNIFORMS + "\nvoid fragment()"), "fragment", FRAGMENT)


static func material_for(base: Material, index: int, unit_id: int) -> ShaderMaterial:
	# Own each phase on GLES too, while sharing the shader and original atlas.
	# The unit seed avoids whole groups breathing in lockstep; no gameplay RNG.
	var material := base.duplicate() as ShaderMaterial
	material.set_shader_parameter("wisp_phase", TAU * (fposmod(float(unit_id) * 0.61803398875, 1.0) + float(index) / 5.0))
	material.set_shader_parameter("wisp_rate", TAU / (2.8 + float(index) * 0.17))
	return material


static func set_presence(mesh: MeshInstance3D, presence: float) -> void:
	(mesh.material_override as ShaderMaterial).set_shader_parameter("wisp_presence", presence)
	# Selection owns a brightened copy. Keep the original ready for deselection
	# on both Compatibility and RenderingDevice renderers.
	if mesh.has_meta("unlit"):
		(mesh.get_meta("unlit") as ShaderMaterial).set_shader_parameter("wisp_presence", presence)
