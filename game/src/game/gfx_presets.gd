class_name GfxPresets
extends RefCounted
## Explicit player choices use the established detection ladder, while
## preserving a separate source marker for automatically measured settings.
const CUSTOM := 0
const ORIGINAL := 1
const LOW := 2
const MEDIUM := 3
const HIGH := 4
const DETECTED := 5
const NAMES := ["Custom", "Original", "Low", "Medium", "High"]
const TIERS := {ORIGINAL:GfxDetect.ORIGINAL, LOW:3, MEDIUM:2, HIGH:0}

static func values(preset: int, method: String = RenderingServer.get_current_rendering_method(),
		base: Dictionary = GfxDetect.base_values()) -> Dictionary:
	if not TIERS.has(preset): return {}
	var result := GfxDetect.tier_values(TIERS[preset],base)
	# Unsupported effects should not appear enabled merely because the
	# renderer ignores them. Presets never change the renderer itself.
	if method != "forward_plus":
		for key in ["gfx_volumetric","gfx_ssao","gfx_water_reflections","gfx_depth_of_field"]:
			result[key]=0
	if method == "gl_compatibility":
		result.q_aa=0
	return result

static func controls(key: String) -> bool:
	return key.begins_with("gfx_") or key in ["q_aa","q_shadows","q_aniso","render_scale"]
