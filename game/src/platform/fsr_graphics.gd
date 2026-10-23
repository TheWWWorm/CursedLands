class_name FsrGraphics
extends Node
## Explicit SDK versions. Never label the FSR 3.1 provider as FSR 4.

const UPSCALING := "fsr_upscaling"
const QUALITY := "fsr_quality"
const FRAME_GENERATION := "fsr_frame_generation"
const OPTIONS := [UPSCALING, QUALITY, FRAME_GENERATION]
const GROUP := 12 # Screen; there is no separate FSR page.
const SECTION := ["AMD FSR", "FSR 3.1 and FSR 4 for the campaign view on Windows. Select Forward+ (Direct3D 12) in Screen settings and restart if needed. Upscaling and frame generation are off by default."]
const SR_HELP := "Select FSR 3.1 or FSR 4 explicitly. FSR 4 requires a supported Radeon RX 7000 discrete GPU or RX 9000 or newer. FSR 3.1 also supports other compatible GPUs. Unavailable versions are disabled. Overrides Render scale while active."
const QUALITY_HELP := "Native AA renders at full resolution. Quality, Balanced and Performance render fewer pixels and reconstruct the image. Requires FSR upscaling to be selected."
const FG_HELP := "Generate an extra frame during campaign gameplay, with or without FSR upscaling. FSR 3.1 supports compatible AMD and NVIDIA GPUs; FSR 4 requires Windows 11 and Radeon RX 9000 or newer. Pauses in menus, while loading and on focus loss. The FPS counter shows rendered FPS and measured presented FPS, including generated frames."
const VERSIONS := ["Off", "FSR 3.1", "FSR 4"]
const QUALITIES := ["Native AA", "Quality", "Balanced", "Performance"]
const SCALES := [1.0, 2.0 / 3.0, 1.0 / 1.7, 0.5]
const UNAVAILABLE := "This build does not include AMD FSR."
const NEED_API := "Requires Windows and Forward+ (Direct3D 12). Select that renderer in Screen settings and restart."
const NEED_SR := "The selected FSR upscaler is unavailable on this GPU or driver, or its runtime could not be loaded."
const NEED_FG := "The selected FSR frame-generation version is unavailable on this GPU, operating system or driver."
const ENABLE_SR := "Select FSR 3.1 or FSR 4 upscaling first."
const RENDERER_HINT := "FSR: select Forward+ (Direct3D 12), apply and restart."
const PREPARATION_DELAY_MS := 500

static func screen_hint(info: Dictionary) -> String:
	if OS.get_name() == "Windows" and not info.get("api", false): return RENDERER_HINT
	if not info.get("engine", false): return UNAVAILABLE
	if not info.get("sr3", false) and not info.get("sr4", false) and not info.get("fg3", false) and not info.get("fg4", false):
		return "FSR is unavailable on this GPU or driver. See option help."
	return ""

var _previous_fg := 0
var _upscaling_applied := false
var _telemetry_time := 0.0
var _preparation_key := []
var _preparation_pending := false
var _preparation_started_ms := 0
var _preparation_sr_base := 0
var _preparation_fg_base := 0
var _last_allowed_usec := 0
var _ever_active := false

static func bridge() -> Object:
	return Engine.get_singleton("FidelityFX") if Engine.has_singleton("FidelityFX") else null

static func facts() -> Dictionary:
	var native := bridge()
	var result := {
		"engine": native != null and native.has_method("get_status") and ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_FSR_SDK"),
		"api": DisplayServer.get_name() != "headless" and OS.get_name() == "Windows" and RenderingServer.get_current_rendering_method() == "forward_plus" and RenderingServer.get_current_rendering_driver_name() == "d3d12",
		"sr3": false, "sr4": false, "fg3": false, "fg4": false,
	}
	if result.engine:
		var status: Dictionary = native.call("get_status")
		result.engine = status.get("compiled", false)
		for key in ["sr3", "sr4", "fg3", "fg4"]:
			result[key] = status.get(key + "_supported", false)
	return result

static func reason_for(name: String, info: Dictionary, sr: int, fg: int = 0) -> String:
	if not info.get("engine", false): return UNAVAILABLE
	if not info.get("api", false): return NEED_API
	if name == FRAME_GENERATION:
		if fg > 0 and not info.get("fg" + str(fg + 2), false): return NEED_FG
		if fg == 0 and not info.get("fg3", false) and not info.get("fg4", false): return NEED_FG
		return ""
	if name == QUALITY and sr <= 0: return ENABLE_SR
	if sr > 0 and not info.get("sr" + str(sr + 2), false): return NEED_SR
	if sr == 0 and not info.get("sr3", false) and not info.get("sr4", false): return NEED_SR
	return ""

static func reason(name: String, values: Dictionary = {}) -> String:
	var options := GameData.options if values.is_empty() else values
	return reason_for(name, facts(), int(options.get(UPSCALING, 0)), int(options.get(FRAME_GENERATION, 0)))

static func next_value(name: String, current: int, values: Dictionary) -> int:
	var choices: Array = QUALITIES if name == QUALITY else VERSIONS
	for offset in range(1, choices.size() + 1):
		var value := (current + offset) % choices.size()
		if name != QUALITY and value == 0: return 0
		var proposed := values.duplicate()
		proposed[name] = value
		if reason(name, proposed).is_empty(): return value
	return current

static func sr_active() -> bool:
	return GameData.option(UPSCALING) > 0 and reason(UPSCALING).is_empty()

static func aa_selection(values: Dictionary) -> int:
	# Retain the old saved keys and the non-FSR fallback on unsupported builds.
	var sr := int(values.get(UPSCALING, 0))
	return sr + 5 if sr > 0 else int(values.get("q_aa", 1))

static func aa_reason(selection: int, values: Dictionary) -> String:
	if selection < 6: return ""
	var proposed := values.duplicate()
	proposed[UPSCALING] = selection - 5
	return reason(UPSCALING, proposed)

static func apply_upscaling(vp: Viewport) -> void:
	if vp != GameData.get_tree().root or not sr_active(): return
	bridge().call("set_upscaler_version", GameData.option(UPSCALING) + 2)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	if vp.scaling_3d_scale > 1.0 and int(vp.scaling_3d_mode) != Viewport.SCALING_3D_MODE_BILINEAR:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = SCALES[clampi(GameData.option(QUALITY), 0, SCALES.size() - 1)]
	vp.set("scaling_3d_mode", ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_FSR_SDK"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(facts().engine and facts().api)

## Choose the view owning the current camera. A hidden/previous Game in
## the same group must not suspend frame generation for the visible one.
static func campaign_gate(tree: SceneTree, camera: Camera3D) -> Dictionary:
	var game: Game
	for candidate: Node in tree.get_nodes_in_group("fsr_campaign_view"):
		if candidate is Game and candidate.rig != null and candidate.rig.camera == camera \
				and candidate.is_visible_in_tree() and not candidate.is_queued_for_deletion():
			game = candidate
			break
	var blockers: Array[String] = []
	if game == null:
		blockers.append("no_active_campaign_view")
	else:
		if game.simulation_only: blockers.append("simulation_only")
		if game.world == null: blockers.append("no_world")
		if game.session == null:
			blockers.append("no_session")
		else:
			if game.session.loading_game: blockers.append("loading")
			if game.session.movie_active(): blockers.append("movie")
		if game.hud == null or game.hud.blocks_camera(): blockers.append("hud_panel")
	return {"allowed":blockers.is_empty(),"blockers":blockers}

func _process(dt: float) -> void:
	var root := get_tree().root
	var applied := sr_active()
	if _upscaling_applied and not applied: GameData._apply_window()
	_upscaling_applied = applied
	var gate := campaign_gate(get_tree(),root.get_camera_3d())
	if GameData.option(FRAME_GENERATION) <= 0: gate.blockers.append("option_off")
	var unavailable := reason(FRAME_GENERATION)
	if not unavailable.is_empty(): gate.blockers.append("unsupported")
	# The compilation screen pauses single-player simulation while scene
	# rendering continues. Only that owned pause may initialize FG under cover.
	if get_tree().paused and not ShaderCompilationScreen.owns_pause(get_tree()): gate.blockers.append("paused")
	if not root.has_focus(): gate.blockers.append("window_unfocused")
	var enable: bool = gate.blockers.is_empty()
	if enable: _last_allowed_usec = Time.get_ticks_usec()
	var version := GameData.option(FRAME_GENERATION) + 2 if enable else 0
	if version != _previous_fg:
		root.set("frame_generation", enable)
		bridge().call("set_frame_generation_version", version)
		_previous_fg = version
	var status: Dictionary = bridge().call("get_status")
	_ever_active = _ever_active or bool(status.get("frame_generation_active",false))
	_update_preparation(status, applied, enable)
	_telemetry_time += dt
	if _telemetry_time >= 1.0:
		_telemetry_time = 0.0
		status["requested_upscaling"] = GameData.option(UPSCALING)
		status["requested_quality"] = GameData.option(QUALITY)
		status["requested_frame_generation"] = GameData.option(FRAME_GENERATION)
		status["gameplay_allows_frame_generation"] = enable
		status["frame_generation_blockers"] = gate.blockers
		status["frame_generation_unavailable_reason"] = unavailable
		status["frame_generation_ever_active"] = _ever_active
		status["frame_generation_last_allowed_ms_ago"] = (Time.get_ticks_usec()-_last_allowed_usec)/1000 if _last_allowed_usec > 0 else -1
		status["rendered_fps"] = Engine.get_frames_per_second()
		var out := FileAccess.open("user://fsr-status.json", FileAccess.WRITE)
		if out: out.store_string(JSON.stringify(status, "\t") + "\n")


func _update_preparation(status: Dictionary, upscaling: bool, generation: bool) -> void:
	var root := get_tree().root
	var camera := root.get_camera_3d()
	var key := [upscaling, GameData.option(UPSCALING), GameData.option(QUALITY),
		GameData.option(FRAME_GENERATION), root.size]
	var initializing: bool = status.get("temporal_shaders_initializing", false) \
		or (upscaling and status.get("upscaler_initializing", false)) \
		or (generation and status.get("frame_generation_initializing", false))
	# Menus, tutorials, focus and pause temporarily suspend FG. Camera
	# replacement also happens on every load. None invalidates cached shaders;
	# the SDK reports actual preparation if a new view needs more work.
	var changed := key != _preparation_key
	_preparation_key = key
	if camera == null or not (upscaling or generation):
		_preparation_pending = false
		ShaderCompilationScreen.end(&"fsr")
		return
	if changed or (initializing and not _preparation_pending):
		_preparation_sr_base = int(status.get("upscale_evaluations", 0))
		_preparation_fg_base = int(status.get("frame_generation_dispatches", 0))
		_preparation_pending = true
		_preparation_started_ms = Time.get_ticks_msec()
	if not _preparation_pending:
		ShaderCompilationScreen.end(&"fsr")
		return
	# Initially all flags are false; they can also clear briefly between
	# shader and SDK context preparation. Actual evaluations finish the hold.
	var ready := not initializing \
		and (not upscaling or int(status.get("upscale_evaluations", 0)) > _preparation_sr_base) \
		and (not generation or int(status.get("frame_generation_dispatches", 0)) > _preparation_fg_base)
	# last_error is shared and sticky across SR/FG. A historical failure in
	# the other effect must not end a healthy request. Capability changes
	# already cancel the affected request through upscaling/generation above.
	if ready:
		_preparation_pending = false
		ShaderCompilationScreen.end(&"fsr")
		return
	# Cached context restoration commonly completes in one or two frames.
	# Keep that work silent; join an existing loading/settings cover at once,
	# or show progress only if preparation actually takes perceptible time.
	if not ShaderCompilationScreen.active() and Time.get_ticks_msec() - _preparation_started_ms < PREPARATION_DELAY_MS:
		return
	var phase := ShaderCompilationScreen.TEMPORAL if status.get("temporal_shaders_initializing", false) \
		else ShaderCompilationScreen.UPSCALER if upscaling and (status.get("upscaler_initializing", false) \
			or int(status.get("upscale_evaluations", 0)) <= _preparation_sr_base) else ShaderCompilationScreen.FRAMES
	ShaderCompilationScreen.begin(get_tree(), &"fsr", phase)

func _exit_tree() -> void:
	ShaderCompilationScreen.end(&"fsr")
	if _previous_fg > 0 and is_inside_tree():
		get_tree().root.set("frame_generation", false)
		bridge().call("set_frame_generation_version", 0)
