extends RefCounted
## Stable player presets over the existing saved bounce IDs. Keep raw tuning
## preferences intact for diagnostics and for standalone RT when PT is off.
## This is called from GameData.option's hot path: no capability queries,
## dictionary copies, option recursion or per-call command-line parsing.
const LABEL := "Path tracing"
const HELP := "Balanced uses two light bounces for faster play. Quality uses four bounces and traces refraction through water and glass. Both manage reconstruction and lighting settings automatically. Use Screen settings to adjust upscaling and frame generation. Requires a ray-tracing GPU and Forward+."
const CHOICES := ["Off", "Balanced", "Quality"]
const SCREEN_LABEL := "Upscaling and frame generation…"
const SCREEN_HELP := "Open Screen settings to choose upscaling quality and frame generation. These settings also control path-tracing performance."
const HIDDEN := ["pt_accumulation", "pt_target_fps", "pt_sharc", "pt_denoiser",
	"pt_ray_reconstruction", "pt_restir", "pt_refraction"]
const MANAGED := {"pt_accumulation":0, "pt_target_fps":0, "pt_sharc":0,
	"pt_denoiser":0, "pt_ray_reconstruction":1, "q_rt_lighting":0}
static var _tuning := OS.get_cmdline_user_args().has("--ei-pt-tuning")


static func tuning_enabled() -> bool:
	return _tuning


static func value(name: String, preferences: Dictionary, tuning: bool) -> int:
	var saved := int(preferences.get(name, 0))
	if not MANAGED.has(name) and name != "pt_refraction" and name != "pt_restir": return saved
	var mode := int(preferences.get("pt_mode", 0))
	if tuning or mode <= 0: return saved
	if name == "pt_refraction" or name == "pt_restir": return int(mode >= 2)
	return int(MANAGED.get(name, saved))


static func retained(name: String) -> bool:
	return name == "q_rt_lighting" or name in HIDDEN
