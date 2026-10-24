class_name RtxGraphics
extends Node
## Optional Windows DLSS. Native capability queries decide availability.
## Settings are requests; a selected value never proves the SDK is rendering.

const UPSCALING := "rtx_upscaling"
const FRAME_GENERATION := "rtx_frame_generation"
const GROUP := -1
const SECTION := ["NVIDIA DLSS", "DLSS and DLAA for Windows with Direct3D 12. Switching between AMD and NVIDIA requires a restart. Both features start off."]
const SR_HELP := "Reconstruct the campaign view with NVIDIA DLSS. Native AA uses DLAA; Quality, Balanced and Performance render fewer pixels. Overrides anti-aliasing and Render scale. Requires an RTX GPU and Forward+ (Direct3D 12). Switching between AMD and NVIDIA requires a restart."
const FG_HELP := "Generate one extra display frame per rendered frame in campaign gameplay. Requires DLSS or DLAA, RTX 40 or 50 hardware, a compatible driver and Windows hardware-accelerated GPU scheduling. NVIDIA Reflex is enabled automatically. Pauses during menus, loading and loss of focus. The FPS counter shows rendered frames."
const CHOICES := ["Off", "DLAA", "Quality", "Balanced", "Performance"]
const SCALES := [1.0, 1.0, 2.0 / 3.0, 0.58, 0.5]
const UNAVAILABLE := "This build does not include NVIDIA DLSS."
const NEED_RESTART := "Apply and restart to switch graphics technologies."
const NEED_API := "Requires Windows and the Direct3D 12 Forward+ renderer."
const NEED_SR := "DLSS is unavailable on this GPU or driver, or its runtime could not be loaded."
const NEED_FG := "Frame generation is unavailable. Check RTX 40/50 support, the driver and Windows GPU scheduling."
const ENABLE_SR := "Select DLSS or DLAA first."

var _previous_fg := false
var _telemetry_time := 0.0
var _upscaling_applied := false

static func bridge() -> Object:
	return Engine.get_singleton("Streamline") if Engine.has_singleton("Streamline") else null

static func facts() -> Dictionary:
	var native := bridge()
	var result := {
		"engine": native != null and native.has_method("get_status") and ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"),
		"launch": false,
		"api": DisplayServer.get_name() != "headless" and OS.get_name() == "Windows" and RenderingServer.get_current_rendering_method() == "forward_plus" and RenderingServer.get_current_rendering_driver_name() == "d3d12",
		"sr": false, "fg": false, "reflex": false,
	}
	if result.engine:
		var status: Dictionary = native.call("get_status")
		result.engine = status.get("compiled", false)
		result.launch = status.get("requested", false)
		result.sr = status.get("sr_supported", false)
		result.fg = status.get("fg_supported", false)
		result.reflex = status.get("reflex_supported", false)
	return result

static func reason_for(name: String, info: Dictionary, sr: int) -> String:
	if not info.get("engine", false): return UNAVAILABLE
	if not info.get("api", false): return NEED_API
	if not info.get("launch", false): return NEED_RESTART
	if not info.get("sr", false): return NEED_SR
	if name == FRAME_GENERATION:
		if not info.get("fg", false) or not info.get("reflex", false): return NEED_FG
		if sr <= 0: return ENABLE_SR
	return ""

static func reason(name: String, values: Dictionary = {}) -> String:
	return reason_for(name, facts(), int((GameData.options if values.is_empty() else values).get(UPSCALING, 0)))

static func selected(values: Dictionary) -> bool:
	return int(values.get(UPSCALING, 0)) > 0

static func selection_reason(values: Dictionary) -> String:
	var info := facts()
	if not info.engine: return UNAVAILABLE
	if not info.api: return NEED_API
	# Capabilities become available only after selecting the presentation owner
	# at startup. Permit a request, then show the actual SDK result next start.
	return NEED_SR if info.launch and not info.sr else ""

static func needs_restart(values: Dictionary) -> bool:
	var info := facts()
	return info.engine and info.api and selected(values) != bool(info.launch)

static func sr_active() -> bool:
	return GameData.option(UPSCALING) > 0 and reason(UPSCALING).is_empty()

static func apply_upscaling(vp: Viewport) -> void:
	# Campaign cameras render to the root. Portraits, reflections and Trials
	# use subviewports and do not share the presentation/depth contract.
	if vp != GameData.get_tree().root or not sr_active(): return
	var mode := ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS")
	var scale: float = SCALES[clampi(GameData.option(UPSCALING), 1, SCALES.size() - 1)]
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	if vp.scaling_3d_scale > 1.0 and int(vp.scaling_3d_mode) != Viewport.SCALING_3D_MODE_BILINEAR:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.set("scaling_3d_mode", mode)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No per-frame work in ordinary builds, workers or non-Windows runs.
	set_process(facts().engine and facts().api and facts().launch)

func _process(dt: float) -> void:
	var root := get_tree().root
	var applied := sr_active()
	if _upscaling_applied and not applied:
		# Restore ordinary scale/AA after an SDK failure without changing the
		# player's saved request or leaving a permanently jittered fallback.
		GameData._apply_window()
	_upscaling_applied = applied
	var enable := GameData.option(FRAME_GENERATION) != 0 and reason(FRAME_GENERATION).is_empty()
	enable = enable and (not get_tree().paused or ShaderCompilationScreen.owns_pause(get_tree())) and root.has_focus() and root.get_camera_3d() != null
	enable = enable and FsrGraphics.campaign_gate(get_tree(), root.get_camera_3d()).allowed
	if enable != _previous_fg:
		root.set("frame_generation", enable)
		# The native bridge applies this at a frame boundary.
		bridge().call("set_parameter", 0, 1.0 if enable else 0.0)
		_previous_fg = enable
	_telemetry_time += dt
	if _telemetry_time >= 1.0:
		_telemetry_time = 0.0
		var status: Dictionary = bridge().call("get_status")
		status["requested_upscaling"] = GameData.option(UPSCALING)
		status["requested_frame_generation"] = GameData.option(FRAME_GENERATION)
		status["gameplay_allows_frame_generation"] = enable
		status["rendered_fps"] = Engine.get_frames_per_second()
		var out := FileAccess.open("user://rtx-status.json", FileAccess.WRITE)
		if out: out.store_string(JSON.stringify(status, "\t") + "\n")

func _exit_tree() -> void:
	if _previous_fg and is_inside_tree():
		get_tree().root.set("frame_generation", false)
