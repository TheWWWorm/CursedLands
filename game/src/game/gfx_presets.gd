class_name GfxPresets
extends RefCounted
## Stable saved IDs. Manual presets use explicit quality budgets, independent
## of platform defaults and the automatic detector's conservative ladder.
const CUSTOM := 0
const ORIGINAL := 1
const LOW := 2
const MEDIUM := 3
const HIGH := 4
const DETECTED := 5
const VERY_LOW := 6
const VERY_HIGH := 7
const ULTRA := 8
const NAMES := ["Custom", "Original", "Low", "Medium", "High", "Detected", "Very low", "Very high", "Ultra"]
const ORDER := [ORIGINAL, VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH, ULTRA, CUSTOM, DETECTED]
const TIERS := {ORIGINAL:5, VERY_LOW:4, LOW:3, MEDIUM:2, HIGH:1, VERY_HIGH:0, ULTRA:0}

static func values(preset: int, method: String = RenderingServer.get_current_rendering_method(),
		_base: Dictionary = {}) -> Dictionary:
	if not TIERS.has(preset): return {}
	var maximum := {}
	for o in GameData.OPTIONS:
		if String(o[0]).begins_with("gfx_"): maximum[o[0]] = int(o[2]) - 1
	maximum.merge({"q_aa":3, "q_shadows":3, "q_aniso":4, "q_shadow_fit":1, "render_scale":4})
	var result := GfxDetect.tier_values(TIERS[preset], maximum)
	# Low already draws clouds; High and Very high increase their quality.
	# Ultra reserves the costly cloud shadows/reflections, highest
	# shadow/terrain quality and cinematic effects. Enabled water reflections
	# keep Mirror, the default appearance, across the quality presets.
	if preset != ULTRA:
		result.gfx_depth_of_field = 0
		result.gfx_terrain = mini(result.gfx_terrain, 1)
		result.gfx_clouds = 0 if preset in [ORIGINAL, VERY_LOW] else (3 if preset == VERY_HIGH else (2 if preset == HIGH else 1))
		result.gfx_cloud_shadows = 0
		result.gfx_cloud_reflections = 0
		result.gfx_ground_contact = 0
		result.q_shadows = mini(result.q_shadows, 2)
	# Ultra records every effect as enabled, also when the current renderer
	# uses a fallback. Switching to Forward+ then realizes the full preset.
	if preset != ULTRA and method != "forward_plus":
		for key in ["gfx_volumetric", "gfx_ssao", "gfx_water_reflections", "gfx_depth_of_field"]:
			result[key] = 0
	# AA/upscaling is an independent Screen choice. The detector's ladder
	# still needs its AA seed internally, but a preset must not apply it.
	result.erase("q_aa")
	return result

static func controls(key: String) -> bool:
	return key.begins_with("gfx_") or key in ["q_shadows", "q_aniso", "q_shadow_fit", "render_scale"]
