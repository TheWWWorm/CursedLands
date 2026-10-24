class_name PerformanceLog
extends Node
## Low-frequency local breadcrumbs for session-dependent slowdowns. A bounded
## wall-clock histogram observes process callbacks, without frame readbacks,
## renderer timing queries, scene traversal or retained world refs.
## CrashReport's existing export includes these lines from the ordinary log.

const INTERVAL := 30.0
const MAX_WORLDS := 64
const FRAME_BUCKET_US := [8334,11112,16667,20000,25000,33334,50000,66667,100000,200000,500000,1000000]

class FrameWindow:
	var count := 0
	var total_us := 0
	var maximum_us := 0
	var maximum_at_us := 0
	var over_25ms := 0
	var over_50ms := 0
	var over_100ms := 0
	var buckets := PackedInt64Array()
	func _init() -> void:
		buckets.resize(FRAME_BUCKET_US.size()+1)
	func record(elapsed_us: int, now_us: int) -> void:
		if elapsed_us <= 0: return
		count += 1
		total_us += elapsed_us
		if elapsed_us > maximum_us:
			maximum_us = elapsed_us
			maximum_at_us = now_us
		if elapsed_us > 25000: over_25ms += 1
		if elapsed_us > 50000: over_50ms += 1
		if elapsed_us > 100000: over_100ms += 1
		var bin := 0
		while bin < FRAME_BUCKET_US.size() and elapsed_us > FRAME_BUCKET_US[bin]: bin += 1
		buckets[bin] += 1
	func summary() -> Dictionary:
		if count == 0: return {"frames":0}
		var seen := 0
		var p95_us := maximum_us
		for bin in buckets.size():
			seen += buckets[bin]
			if seen >= ceili(count*0.95):
				p95_us = FRAME_BUCKET_US[bin] if bin < FRAME_BUCKET_US.size() else maximum_us
				break
		return {"frames":count,"mean_ms":total_us/1000.0/count,"max_ms":maximum_us/1000.0,
			"max_at_uptime_s":maximum_at_us/1000000.0,"p95_upper_ms":p95_us/1000.0,
			"over_25ms":over_25ms,"over_50ms":over_50ms,"over_100ms":over_100ms}

var _timer: Timer
var _last_usec := 0
var _last_frames := 0
var _last_frame_usec := 0
var _last_frame_phase := ""
var _frame_windows := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	_last_frames = Engine.get_frames_drawn()
	_reset_pacing()
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.ignore_time_scale = true
	_timer.timeout.connect(sample.bind("interval"))
	add_child(_timer)
	_timer.start()


func stop() -> void:
	if is_instance_valid(_timer): _timer.stop()
	set_process(false)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_RESUMED]:
		_last_frame_usec = 0


func _reset_pacing() -> void:
	_frame_windows = {"foreground":FrameWindow.new(),"background":FrameWindow.new(),"loading":FrameWindow.new()}


func _process(_delta: float) -> void:
	var cr := CrashReport.instance
	var phase := "foreground"
	if is_instance_valid(cr):
		if String(cr.info.get("zone", "")).ends_with(" (loading)"): phase = "loading"
		elif cr.info.get("focus", "in") != "in" or cr.info.get("state", "foreground") != "foreground": phase = "background"
	_observe_frame(Time.get_ticks_usec(),phase)


func _observe_frame(now_us: int, phase: String) -> void:
	# Discard the gap spanning a focus/scene transition: a synchronous load or
	# a background-throttled frame must not masquerade as a gameplay hitch.
	if _last_frame_usec > 0 and phase == _last_frame_phase:
		(_frame_windows[phase] as FrameWindow).record(now_us-_last_frame_usec,now_us)
	_last_frame_usec = now_us
	_last_frame_phase = phase


func _pacing_snapshot() -> Dictionary:
	var result := {}
	for phase: String in _frame_windows:
		result[phase] = (_frame_windows[phase] as FrameWindow).summary()
	return result


static func _available(value: float) -> Variant:
	# Release templates omit several Performance counters. Zero is not proof
	# of zero heap/graphics allocation or zero processing cost.
	return value if value > 0.0 else null


func snapshot(reason: String) -> Dictionary:
	var now := Time.get_ticks_usec()
	var frames := Engine.get_frames_drawn()
	var elapsed := (now - _last_usec) / 1000000.0
	var root := get_tree().root
	var cr := CrashReport.instance
	var worlds := get_tree().get_nodes_in_group(GameWorld.DIAGNOSTIC_GROUP)
	var render_options := {}
	for key in ["pt_mode","pt_accumulation","pt_target_fps","rtx_upscaling","rtx_frame_generation",
			"fsr_upscaling","fsr_quality","fsr_frame_generation"]:
		render_options[key] = GameData.option(key)
	var result := {
		"reason": reason, "pid": OS.get_process_id(), "uptime_s": now / 1000000.0,
		"interval_s": elapsed, "drawn_frames": frames - _last_frames,
		"interval_fps": (frames - _last_frames) / elapsed if elapsed >= 0.1 and frames > _last_frames else null,
		"recent_fps": _available(Engine.get_frames_per_second()), "frame_limit": Engine.max_fps,
		"time_scale": Engine.time_scale, "paused": get_tree().paused,
		"focus": cr.info.get("focus", "unknown") if is_instance_valid(cr) else "unknown",
		"zone": cr.info.get("zone", "") if is_instance_valid(cr) else "",
		"window": [root.size.x, root.size.y], "render_scale": root.scaling_3d_scale,
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(), "render_options": render_options,
		"frame_pacing": _pacing_snapshot(),
		"msaa_3d": root.msaa_3d, "screen_space_aa": root.screen_space_aa, "taa": root.use_taa,
		"vsync": DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else null,
		# Engine counters are the preceding second's maxima, not thirty-second
		# means. TIME_PROCESS includes renderer sync/draw, not just script CPU.
		"process_ms": _available(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"physics_ms": _available(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) if OS.is_debug_build() else null,
		"static_bytes": _available(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"video_allocated_bytes": _available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_bytes": _available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_bytes": _available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"world_count": worlds.size(), "worlds": [],
		"cache_entries": {"figure_meshes": EIFigure._meshes.size(), "figure_models": EIFigure._models.size(),
			"figure_materials": EIFigure._materials.size(), "object_textures": GameData._texture_cache.size(),
			"unit_textures": EIUnitModel._textures.size(), "camera_materials": CameraFade._derived.size(),
			"wound_layers": UnitWounds._layer_textures.size(), "wound_jobs": UnitWounds._jobs.size()},
		"options": CrashReport.options_summary(),
	}
	var camera := root.get_camera_3d()
	if camera:
		result.camera = {"position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],
			"rotation":[camera.global_rotation.x,camera.global_rotation.y,camera.global_rotation.z],"fov":camera.fov}
	for i in mini(worlds.size(), MAX_WORLDS):
		var world: GameWorld = worlds[i]
		var row := {"instance": world.get_instance_id(), "authority": world.authority,
			"presentation": world.presentation, "visible": world.is_visible_in_tree(),
			"process_mode": world.process_mode, "time": world.time,
			"units": world.units.size(), "looted": world.looted.size(),
			"logic_debt_s": world._logic_debt}
		if is_instance_valid(world.session):
			row.zone = world.session.zone_id
			row.pending_inputs = world.session._input_out.pending.size()
		# Never use ParticleFx.of(): diagnostics must not create presentation
		# effects in an authority worker or an otherwise empty world.
		var fx := world.get_node_or_null("ParticleFx") as ParticleFx
		if fx:
			row.effects = {"emitters": fx.effects.size(), "bolts": fx.bolts.size(),
				"lights": fx.lights.size(), "missiles": fx.missiles.size(),
				"delayed": fx._delayed.size(), "magic_endings": fx._magic_ends.size()}
		var casts := world.get_node_or_null("SpellTimers") as Spells.WorldTimers
		if casts: row.pending_casts = casts.pending.size()
		result.worlds.append(row)
	return result


func sample(reason: String) -> void:
	var row := snapshot(reason)
	_last_usec = Time.get_ticks_usec()
	_last_frames = Engine.get_frames_drawn()
	_reset_pacing()
	if reason == "scene": _last_frame_usec = 0
	# Print directly: GameData.trace calls CrashReport.note and would recurse
	# on scene-transition samples. Existing file logging owns rotation/export.
	print("PERFORMANCE ", JSON.stringify(row))
