extends RefCounted
## Stable player presets over the existing saved bounce IDs. Keep raw tuning
## preferences intact for diagnostics and for standalone RT when PT is off.
## This is called from GameData.option's hot path: no capability queries,
## dictionary copies, option recursion or per-call command-line parsing.
const LABEL := "Path tracing"
const HELP := "Performance uses one light bounce for the fastest play; indirect light is slightly darker. Balanced uses two bounces. Quality uses four bounces and traces refraction through water and glass. All modes manage reconstruction and lighting settings automatically. Use Screen settings to adjust upscaling and frame generation. Requires a ray-tracing GPU and Forward+."
## Saved pt_mode IDs: 0 Off, 1 Balanced, 2 Quality, 3 Performance. The
## later Performance ID keeps older saves unchanged. CHOICES and BOUNCES are
## indexed by the saved ID; ORDER is the menu's stepping order.
const OFF := 0
const BALANCED := 1
const QUALITY := 2
const PERFORMANCE := 3
const CHOICES := ["Off", "Balanced", "Quality", "Performance"]
const ORDER := [OFF, PERFORMANCE, BALANCED, QUALITY]
## Continuation bounces after the visible surface's direct light.
const BOUNCES := [0, 2, 4, 1]
const SCREEN_LABEL := "Upscaling and frame generation…"
const SCREEN_HELP := "Open Screen settings to choose upscaling quality and frame generation. These settings also control path-tracing performance."
const HIDDEN := ["pt_accumulation", "pt_target_fps", "pt_sharc", "pt_denoiser",
	"pt_ray_reconstruction", "pt_restir", "pt_refraction"]
const MANAGED := {"pt_accumulation":0, "pt_target_fps":0, "pt_sharc":0,
	"pt_denoiser":0, "pt_ray_reconstruction":1, "q_rt_lighting":0}
static var _tuning := OS.get_cmdline_user_args().has("--ei-pt-tuning")


static func tuning_enabled() -> bool:
	return _tuning


## A saved ID from a newer or edited profile stays bounded: values above the
## known IDs keep the old four-bounce behaviour, negatives are Off.
static func mode(saved: int) -> int:
	return saved if saved >= OFF and saved <= PERFORMANCE else (QUALITY if saved > PERFORMANCE else OFF)


static func bounces(saved: int) -> int:
	return BOUNCES[mode(saved)]


static func value(name: String, preferences: Dictionary, tuning: bool) -> int:
	var saved := int(preferences.get(name, 0))
	if name == "pt_mode": return mode(saved)
	if not MANAGED.has(name) and name != "pt_refraction" and name != "pt_restir": return saved
	var path := mode(int(preferences.get("pt_mode", 0)))
	if tuning or path == OFF: return saved
	if name == "pt_refraction" or name == "pt_restir": return int(path == QUALITY)
	return int(MANAGED.get(name, saved))


static func retained(name: String) -> bool:
	return name == "q_rt_lighting" or name in HIDDEN
