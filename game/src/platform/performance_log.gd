class_name PerformanceLog
extends Node
## Low-frequency local breadcrumbs for session-dependent slowdowns. No frame
## readbacks, renderer timing queries, scene traversal or retained world refs.
## CrashReport's existing export includes these lines from the ordinary log.

const INTERVAL := 30.0
const MAX_WORLDS := 64
var _timer: Timer
var _last_usec := 0
var _last_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	_last_frames = Engine.get_frames_drawn()
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.ignore_time_scale = true
	_timer.timeout.connect(sample.bind("interval"))
	add_child(_timer)
	_timer.start()


func stop() -> void:
	if is_instance_valid(_timer): _timer.stop()


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
		"msaa_3d": root.msaa_3d, "screen_space_aa": root.screen_space_aa, "taa": root.use_taa,
		"vsync": DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else null,
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
	# Print directly: GameData.trace calls CrashReport.note and would recurse
	# on scene-transition samples. Existing file logging owns rotation/export.
	print("PERFORMANCE ", JSON.stringify(row))
