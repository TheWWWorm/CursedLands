class_name ShaderCompilationScreen
extends CanvasLayer
## A canvas-only cover that can be presented BEFORE a blocking first 3D draw.
## Raw canvas commands are deliberate: Control redraws are deferred and do not
## update inside ShaderWarmup's synchronous material loop. No new UI shader.

const TITLE := "Compiling shaders"
const SETTINGS_TITLE := "Applying settings"
const SCENE_TITLE := "Preparing scene"
const SCENE := "Preparing scene shaders…"
const MATERIALS := "Preparing materials…"
const GRAPHICS := "Applying graphics settings…"
const GEOMETRY := "Preparing scene geometry…"
const RAYTRACE := "Preparing ray-tracing shaders…"
const PATH_TRACE := "Preparing path-tracing shaders…"
const WATER := "Preparing water reflections…"
const TERRAIN := "Preparing terrain and vegetation…"
const FIRST_FRAME := "Preparing the first frame…"
const TEMPORAL := "Preparing temporal shaders…"
const UPSCALER := "Preparing FSR upscaling…"
const FRAMES := "Preparing frame generation…"
const FINISHING := "Finishing preparation…"
const FIRST_USE := "The first preparation can take longer."
const COUNT := "%d of %d materials ready"
const ELAPSED := "Elapsed: %s"
const HEADING = preload("res://fonts/LiberationSerif-Regular.ttf")
const BODY = preload("res://fonts/LiberationSans-Regular.ttf")
const BACKGROUND := Color("12110f")
const FOREGROUND := Color("ede4d3")
const MUTED := Color("b7ab96")
const ACCENT := Color("bc9760")

static var _current: ShaderCompilationScreen
## Validation observes the actual raw-canvas updates, including forced draws.
static var on_progress := Callable()
var hint := FIRST_USE:
	set(value):
		hint = value
		_draw()
var _owners := {}
var _canvas: RID
var _item: RID
var _phase := SCENE
var _title := TITLE
var _completed := 0
var _total := 0
var _started_ms := 0
var _last_redraw_ms := 0
var _presentations := 0
var _finish_presentations := 0
var _observed_presentations := 0
var _last_pipeline_count := -1
var _stable_frames := 0
var _owns_pause := false
var _removing := false
var _text_rects: Array[Rect2] = []
var _terrain_work: Array[Dictionary] = []


static func active() -> bool:
	return is_instance_valid(_current) and not _current._removing


static func owns_pause(tree: SceneTree) -> bool:
	return active() and _current.get_tree() == tree and _current._owns_pause


static func terrain_pending(terrain: EITerrain) -> bool:
	if not active(): return false
	for row: Dictionary in _current._terrain_work:
		if is_instance_valid(row.worker) and row.worker.terrain == terrain: return true
	return false


static func graphics_change(values: Dictionary) -> bool:
	for key: String in values:
		if int(values[key]) == GameData.option(key): continue
		if key.begins_with("q_") or key.begins_with("gfx_") or key.begins_with("rt_") \
				or key.begins_with("fsr_") or key.begins_with("pt_") or key in ["render_scale", "resolution", "display_mode"]:
			return true
	return false


static func begin(tree: SceneTree, owner: StringName, phase := SCENE, completed := 0, total := 0, title := TITLE) -> ShaderCompilationScreen:
	if DisplayServer.get_name() == "headless" or Engine.get_process_frames() == 0:
		return null
	if not active():
		var screen := ShaderCompilationScreen.new()
		screen.layer = 1100
		screen.process_mode = Node.PROCESS_MODE_ALWAYS
		screen._started_ms = Time.get_ticks_msec()
		tree.root.add_child(screen)
		screen._canvas = RenderingServer.canvas_create()
		RenderingServer.viewport_attach_canvas(tree.root.get_viewport_rid(), screen._canvas)
		RenderingServer.viewport_set_canvas_stacking(tree.root.get_viewport_rid(), screen._canvas, 1100, 0)
		screen._item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(screen._item, screen._canvas)
		tree.root.size_changed.connect(screen._draw)
		RenderingServer.frame_post_draw.connect(screen._posted)
		_current = screen
		screen._cancel_input()
	_current._owners[owner] = {"phase":phase, "completed":completed, "total":total, "title":title}
	_current._stable_frames = 0
	_current._select_progress()
	return _current


static func update(owner: StringName, phase: String, completed := 0, total := 0) -> void:
	if not active() or not _current._owners.has(owner): return
	_current._owners[owner].merge({"phase":phase, "completed":completed, "total":total}, true)
	_current._select_progress()


static func end(owner: StringName) -> void:
	if not active() or not _current._owners.erase(owner): return
	_current._finish_presentations = _current._presentations
	_current._observed_presentations = _current._presentations
	_current._last_pipeline_count = -1
	_current._stable_frames = 0
	_current._select_progress()


func _select_progress() -> void:
	# Material batches have a real denominator. SDK readiness has no total;
	# use a moving marker and elapsed time instead of inventing a percentage.
	for group in ["materials", "terrain", "pipeline", "fsr", "settings", ""]:
		var owners := _owners.keys()
		owners.reverse()
		for owner in owners:
			if group != "" and String(owner).get_slice(":", 0) != group: continue
			var row: Dictionary = _owners[owner]
			_phase = row.phase
			_title = row.title
			_total = maxi(0, int(row.total))
			_completed = clampi(int(row.completed), 0, _total) if _total > 0 else 0
			_draw()
			return
	_phase = FINISHING
	_draw()


## Updating a Label then force_draw would still show its previous text.
## Exclude the first 3D draw here so the cover reaches the screen first.
func present() -> void:
	if LoadingScreen.deferred() or _removing: return
	var root := get_tree().root
	var views: Array = [root]
	views.append_array(root.find_children("*", "SubViewport", true, false))
	var previous: Array[bool] = []
	for view: Viewport in views:
		previous.append(view.disable_3d)
		view.disable_3d = true
	RenderingServer.force_draw(true, 0.0)
	RenderingServer.force_sync()
	for i in views.size():
		if is_instance_valid(views[i]): views[i].disable_3d = previous[i]


func _posted() -> void:
	_presentations += 1


func _process(_dt: float) -> void:
	if _removing: return
	_acquire_pause()
	_step_terrain()
	if _owners.is_empty() and _presentations != _observed_presentations:
		_observed_presentations = _presentations
		var count := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
		_stable_frames = _stable_frames + 1 if count == _last_pipeline_count else 0
		_last_pipeline_count = count
		# Cover the actual post-change draws and asynchronous SDK handoffs.
		# Ordinary animated scenes can keep creating incidental pipelines.
		if _stable_frames >= 3 or _presentations - _finish_presentations >= 8:
			_remove()
			return
	if Time.get_ticks_msec() - _last_redraw_ms >= 100:
		_draw()


## Settings can queue visible ground/cover work on PAUSABLE nodes. Snapshot
## this request only; normal camera streaming never acquires a modal owner.
func prepare_terrain() -> void:
	_terrain_work.clear()
	for candidate: Node in get_tree().get_nodes_in_group("fsr_campaign_view"):
		if not candidate is Game or not candidate.is_visible_in_tree() or candidate.world == null \
				or candidate.rig == null or candidate.rig.camera != get_tree().root.get_camera_3d(): continue
		var terrain: EITerrain = candidate.world.terrain
		if not is_instance_valid(terrain): continue
		for worker: Node in [terrain.details, terrain.color_cache]:
			if is_instance_valid(worker): _terrain_work.append({"worker":worker,"started":false,"keys":[]})
	if _terrain_work.is_empty(): end(&"terrain:settings")
	else: begin(get_tree(), &"terrain:settings", TERRAIN, 0, 0, SETTINGS_TITLE)


func _step_terrain() -> void:
	for i in range(_terrain_work.size()-1, -1, -1):
		var row: Dictionary = _terrain_work[i]
		if not is_instance_valid(row.worker):
			_terrain_work.remove_at(i); continue
		var worker: Node = row.worker
		if not worker.is_inside_tree() or not is_instance_valid(worker.terrain) \
				or not worker.terrain.is_visible_in_tree() or worker.get_viewport().get_camera_3d() == null:
			_terrain_work.remove_at(i); continue
		# The first step admits the current view. Subsequent steps only pump
		# workers whose normal callback is paused; game simulation stays frozen.
		if not row.started or not worker.can_process(): worker._process(0.0)
		if not row.started:
			row.started = true
			if worker is TerrainDetails:
				row.keys = worker._wanted_chunks.keys()
				row.generation = worker._grass_generation
			else: row.keys = worker._wanted_keys.keys()
		var pending := false
		for key in row.keys:
			if worker is TerrainDetails:
				if row.generation == worker._grass_generation and worker._wanted_chunks.has(key) \
						and (worker._queue.has(key) or worker._building_chunks.has(key)): pending = true
			elif worker._enabled and worker._wanted_keys.has(key) and not worker._resident.has(key) and not worker._failed.has(key):
				pending = true
		if not pending: _terrain_work.remove_at(i)
	if _terrain_work.is_empty(): end(&"terrain:settings")


func _acquire_pause() -> void:
	var tree := get_tree()
	# Acquire on an ordinary frame, after the options menu restores its own
	# pause. Never steal an existing player/menu pause or pause multiplayer.
	if _owns_pause or tree.paused: return
	for candidate: Node in tree.get_nodes_in_group("fsr_campaign_view"):
		if candidate is Game and candidate.is_visible_in_tree() and candidate.session \
				and candidate.rig and candidate.rig.camera == tree.root.get_camera_3d() \
				and not candidate.session.multiplayer_game and not candidate.session.loading_game:
			_owns_pause = true # LocalHost's pause notification reads saved_play_clock synchronously.
			tree.paused = true
			return


func _input(_event: InputEvent) -> void:
	if not _removing: get_viewport().set_input_as_handled()


func _cancel_input() -> void:
	# Releases consumed by a modal cover must not leave cached pad/touch
	# gestures down. Suppress synthetic taps when cancelling held buttons.
	PadInput.release_all(true)
	TouchInput.cancel_gesture()
	for candidate: Node in get_tree().get_nodes_in_group("fsr_campaign_view"):
		if not candidate is Game: continue
		if candidate.direct: candidate.direct.suspend_for_shader_preparation()
		var field := candidate.get_node_or_null("PadField") as PadField
		if field:
			field._stop_moving()
			field.close_wheel()


func _draw() -> void:
	if not _item.is_valid() or _removing: return
	_last_redraw_ms = Time.get_ticks_msec()
	var screen := get_viewport().get_visible_rect().size
	var width := maxf(1.0, minf(560.0, screen.x - 48.0))
	var x := (screen.x - width) * 0.5
	var title := RemakeText.t(_title)
	var phase := RemakeText.t(_phase)
	var detail := RemakeText.t(COUNT) % [_completed, _total] if _total > 0 else RemakeText.t(hint)
	var seconds := maxi(0, (Time.get_ticks_msec() - _started_ms) / 1000)
	var elapsed := RemakeText.t(ELAPSED) % ("%d:%02d" % [seconds / 60, seconds % 60])
	var title_height := HEADING.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, width, 32).y
	var phase_height := BODY.get_multiline_string_size(phase, HORIZONTAL_ALIGNMENT_CENTER, width, 20).y
	var detail_height := BODY.get_multiline_string_size(detail, HORIZONTAL_ALIGNMENT_CENTER, width, 18).y
	var height := title_height + phase_height + detail_height + 112.0
	var y := maxf(16.0, (screen.y - height) * 0.5)
	_text_rects.clear()
	RenderingServer.canvas_item_clear(_item)
	RenderingServer.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, screen), BACKGROUND)
	_text(HEADING, title, Rect2(x, y, width, title_height), 32, FOREGROUND)
	y += title_height + 20
	_text(BODY, phase, Rect2(x, y, width, phase_height), 20, FOREGROUND)
	y += phase_height + 24
	var bar := Rect2(x, y, width, 5)
	RenderingServer.canvas_item_add_rect(_item, bar, Color("3b342a"))
	var fill := bar
	if _total > 0:
		fill.size.x *= float(_completed) / _total
	else:
		fill.size.x = width * 0.18
		var t := float(Time.get_ticks_msec() - _started_ms) / 1000.0
		fill.position.x += (width - fill.size.x) * (0.5 - 0.5 * cos(t * 2.0))
	RenderingServer.canvas_item_add_rect(_item, fill, ACCENT)
	y += 25
	_text(BODY, detail, Rect2(x, y, width, detail_height), 18, MUTED)
	y += detail_height + 18
	_text(BODY, elapsed, Rect2(x, y, width, 24), 16, MUTED)
	if on_progress.is_valid():
		on_progress.call({"title":_title, "phase":_phase, "completed":_completed, "total":_total,
			"elapsed_ms":Time.get_ticks_msec()-_started_ms, "presentations":_presentations})


func _text(font: Font, value: String, rect: Rect2, font_size: int, color: Color) -> void:
	_text_rects.append(rect)
	font.draw_multiline_string(_item, rect.position + Vector2(0, font.get_ascent(font_size)), value,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, -1, color)


func _remove() -> void:
	if _removing: return
	_removing = true
	if _current == self: _current = null
	_release()
	queue_free()


func _release() -> void:
	if get_viewport().size_changed.is_connected(_draw): get_viewport().size_changed.disconnect(_draw)
	if RenderingServer.frame_post_draw.is_connected(_posted): RenderingServer.frame_post_draw.disconnect(_posted)
	if _item.is_valid(): RenderingServer.free_rid(_item); _item = RID()
	if _canvas.is_valid(): RenderingServer.free_rid(_canvas); _canvas = RID()
	if _owns_pause:
		_owns_pause = false
		get_tree().paused = false


func _exit_tree() -> void:
	if _current == self: _current = null
	_release()
