class_name MoviePlayer
extends ColorRect
## Cutscenes. The original Bink movies (movies/*.bik) are decoded by the
## remake's own decoder (EIBink / EIBinkAudio). GDScript cannot decode the
## longest ones in real time, so a movie is converted once on a background
## thread into user://movies/<name>.eiv (EIBinkCache: JPEG YUV frames + PCM);
## the first showing streams the frames already converted and starts as soon as
## the rest will be ready in time (with a progress note until then). Frames are
## turned into RGB by a shader and letterboxed (aspect kept) on black. Esc or
## Space skips (the original). Each co-op peer plays its own copy (
## `pause_game`).

const SHADER := """
shader_type canvas_item;
uniform sampler2D u_tex : filter_linear;
uniform sampler2D v_tex : filter_linear;
void fragment() {
	float y = (texture(TEXTURE, UV).r - 16.0 / 255.0) * 1.164383;
	float u = texture(u_tex, UV).r - 128.0 / 255.0;
	float v = texture(v_tex, UV).r - 128.0 / 255.0;
	COLOR = vec4(y + 1.596027 * v, y - 0.391762 * u - 0.812968 * v, y + 2.017232 * u, 1.0);
}
"""
const SAFETY := 0.85  # stream when the conversion needs < 85 % of the playing time

enum { IDLE, PREPARING, PLAYING }

## Emitted when a movie ends, is skipped or cannot be played.
signal finished

var hud: GameHUD
## Loading-screen use (LoadingScreen): start over at the end instead of
## stopping, no sound, no skipping.
var loop := false
var silent := false
## the original plays a movie in a modal loop, so the game stands
## still underneath; the HUD's player pauses the tree in single player (a co-op
## peer cannot stop the others' game, so there it keeps running).
var pause_game := false
var _paused_tree := false
var _view: TextureRect
var _label: Label
var _audio: AudioStreamPlayer
var _skip: Button
var _mat: ShaderMaterial
var _tex: Array[ImageTexture] = [null, null, null]
var _state := IDLE
var _name := ""
var _conv: EIBinkCache  # conversion being streamed (null when playing a finished cache)
var _file: FileAccess
var _offsets := PackedInt64Array()
var _frames := 0
var _fps := 25.0
var _width := 0
var _height := 0
var _clock := 0.0
var _shown := -1
var _stalled := false
var _hist: Array[Vector2] = []  # (seconds, frames converted) of the last few seconds
## Off for the test tools (main.gd --tool): movies end at once, so a tool's
## campaign is not held by the intro (tools/ux_test.gd turns them back on).
static var enabled := true
static var _converters := {}  # movie name -> EIBinkCache (running or finished)


func _ready() -> void:
	visible = false
	color = Color.BLACK
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SHADER
	_view.material = _mat
	add_child(_view)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_audio = AudioStreamPlayer.new()
	if AudioServer.get_bus_index("Music") >= 0:
		_audio.bus = "Music"
	add_child(_audio)
	var skip := Button.new()
	_skip = skip
	skip.text = RemakeText.t("Skip")
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -100
	skip.offset_right = -16
	skip.offset_top = -64
	skip.offset_bottom = -16
	skip.pressed.connect(stop)
	skip.visible = not loop
	add_child(skip)
	resized.connect(_layout_skip)
	_layout_skip()

func _layout_skip() -> void:
	var safe := Portability.safe_rect(size)
	var target := TouchInput.target_pixels() if TouchInput.enabled else 48.0
	_skip.offset_left = -(size.x - safe.end.x) - target * 2 - 16
	_skip.offset_right = -(size.x - safe.end.x) - 16
	_skip.offset_top = -(size.y - safe.end.y) - target - 16
	_skip.offset_bottom = -(size.y - safe.end.y) - 16


## Called once when the game quits (main.gd): stops the background
## conversions, which are shared by every player (HUD, loading screens) and
## outlive them.
static func shutdown() -> void:
	# unfinished conversions stop (their cache file stays incomplete and is
	# redone next time); threads must be joined before the game quits
	for c: EIBinkCache in _converters.values():
		c.cancel = true
		c.finish()
	_converters.clear()


func play(name: String) -> void:
	name = name.to_lower().get_file().get_basename()
	if name.is_empty():
		return
	if not enabled:
		finished.emit.call_deferred()
		return
	if _state != IDLE and name == _name:
		return
	stop()
	_hist.clear()
	_name = name
	var cached := ProjectSettings.globalize_path("user://movies/%s.eiv" % name)
	for n in _converters.keys():  # drop finished conversions
		var old: EIBinkCache = _converters[n]
		if not old.is_running():
			old.finish()
			_converters.erase(n)
	var conv: EIBinkCache = _converters.get(name)
	if conv == null:
		var c := EIBinkCache.open_cache(cached)
		if not c.is_empty():
			_start_cache(c)
			return
		var src := GameData.root.path_join("movies/%s.bik" % name)
		if GameData.root.is_empty() or not GameFiles.exists(src):
			return
		conv = EIBinkCache.new()
		conv.start(src, cached)
		_converters[name] = conv
	_conv = conv
	_pause()
	_state = PREPARING
	_label.text = RemakeText.t("Preparing cutscene...")
	visible = true


## The movie list of a config/movie.ini section ("Start", "Crdtfin", ...):
## the original reads its "movies" key (comma separated) and plays
## each from Movies\.
static func ini_movies(section: String) -> PackedStringArray:
	var out := PackedStringArray()
	var data := GameData.read_file("config/movie.ini")
	if data.is_empty():
		return out
	var cur := ""
	for line in data.get_string_from_utf8().split("\n"):
		line = line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			cur = line.substr(1, line.length() - 2)
		elif cur.to_lower() == section.to_lower() and line.to_lower().begins_with("movies="):
			for m in line.substr(7).split(",", false):
				out.append(m.strip_edges().get_basename().to_lower())
	return out


## Plays `name` only if its conversion is already cached (the loading screen
## cannot wait for one). True when it started.
func play_cached(name: String) -> bool:
	stop()
	if not enabled:
		return false
	var c := EIBinkCache.open_cache(ProjectSettings.globalize_path("user://movies/%s.eiv" % name.to_lower()))
	if c.is_empty():
		return false
	_name = name.to_lower()
	_start_cache(c)
	return true


## Advances playback by `delta` seconds outside _process (the loading screen
## steps it while the main thread is busy building a zone).
func step(delta: float) -> void:
	if _state == PLAYING:
		_advance(delta)


## Converts movies in the background ahead of use (loading screens, intro) if
## they are not cached yet.
static func preconvert(names: Array) -> void:
	if not Portability.threads():
		return
	for n: String in names:
		n = n.to_lower()
		var cached := ProjectSettings.globalize_path("user://movies/%s.eiv" % n)
		if _converters.has(n) or not EIBinkCache.open_cache(cached).is_empty():
			continue
		var src := GameData.root.path_join("movies/%s.bik" % n)
		if GameData.root.is_empty() or not GameFiles.exists(src):
			continue
		var conv := EIBinkCache.new()
		conv.start(src, cached)
		_converters[n] = conv


func stop() -> void:
	if not Portability.threads() and _conv and _conv.is_running():
		_conv.cancel = true
		_converters.erase(_name)
	var was := _state != IDLE
	if _paused_tree and is_inside_tree():
		get_tree().paused = false
	_paused_tree = false
	_audio.stop()
	_audio.stream = null
	_state = IDLE
	_conv = null
	_file = null
	_view.texture = null
	_tex = [null, null, null]
	_label.text = ""
	visible = false
	if was:
		finished.emit()


func _process(delta: float) -> void:
	if hud and TouchInput.enabled:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		global_position = Vector2.ZERO
		size = get_viewport_rect().size
	if _state == PREPARING:
		_prepare()
	elif _state == PLAYING:
		_advance(delta)


func _prepare() -> void:
	var c := _conv
	if c.failed:
		stop()
		return
	if c.ok:  # finished while we waited
		c.finish()
		_converters.erase(_name)
		var cache := EIBinkCache.open_cache(c.path)
		if cache.is_empty():
			stop()
		else:
			_start_cache(cache)
		return
	var total := c.frame_count
	if total <= 0:
		return
	var fps := float(c.fps_num) / maxf(c.fps_den, 1)
	_fps = fps
	_frames = total
	var done := _sample()
	if _can_play_from(0) and c.audio_ready():
		var f := FileAccess.open(c.path, FileAccess.READ)
		if f == null:
			return
		_file = f
		_offsets = PackedInt64Array()
		_begin(total, fps, c.width, c.height, c.audio_pcm(), c.audio_rate, c.audio_channels)
		return
	_label.text = RemakeText.t("Preparing cutscene... %d%%") % clampi(done * 100 / total, 0, 99)


## Frames converted so far; also records the recent conversion speed.
func _sample() -> int:
	var done := _conv.frames_done()
	var now := Time.get_ticks_msec() / 1000.0
	_hist.append(Vector2(now, done))
	while _hist.size() > 2 and now - _hist[0].x > 6.0:
		_hist.pop_front()
	return done


## Seconds of conversion per unit of EIBinkCache.cum_cost: the slower of the
## recent and the overall speed (0 until measurable).
func _sec_per_cost() -> float:
	var cum := _conv.cum_cost
	var done := int(_hist[-1].y)
	var r := 0.0
	if done > 0 and _conv.elapsed() > 0.5:
		r = _conv.elapsed() / cum[done]
	if _hist.size() >= 2 and _hist[-1].x - _hist[0].x >= 2.0 and _hist[-1].y > _hist[0].y:
		r = maxf(r, (_hist[-1].x - _hist[0].x) / (cum[int(_hist[-1].y)] - cum[int(_hist[0].y)]))
	return r


## True when playing on from frame `f` will not overtake the conversion: every
## later frame (predicted from its size) is converted before it is due.
func _can_play_from(f: int) -> bool:
	var done := int(_hist[-1].y)
	if done >= _frames:
		return true
	var spc := _sec_per_cost()
	if spc <= 0.0 or done - f < mini(_frames - f, ceili(_fps)):
		return false
	var cum := _conv.cum_cost
	var step := maxi(1, (_frames - done) / 256)
	var k := done
	while true:
		if (cum[k + 1] - cum[done]) * spc > (k - f) / _fps * SAFETY:
			return false
		if k == _frames - 1:
			return true
		k = mini(k + step, _frames - 1)
	return true


func _start_cache(c: Dictionary) -> void:
	_conv = null
	_file = c.file
	_offsets = c.offsets
	_begin(c.frames, float(c.fps_num) / maxf(c.fps_den, 1), c.width, c.height, c.pcm, c.audio_rate, c.audio_channels)


func _begin(frames: int, fps: float, w: int, h: int, pcm: PackedByteArray, rate: int, channels: int) -> void:
	_frames = frames
	_fps = fps
	_width = w
	_height = h
	_clock = 0.0
	_shown = -1
	_stalled = false
	_hist.clear()
	_state = PLAYING
	_label.text = ""
	visible = true
	_pause()
	if pcm.size() > 0 and rate > 0 and not silent:
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.stereo = channels == 2
		s.mix_rate = rate
		s.data = pcm
		_audio.stream = s
		_audio.play()
	_advance(0.0)


func _advance(delta: float) -> void:
	var avail := _sample() if _conv else _frames
	if _stalled:
		# the conversion fell behind: hold picture and sound until enough is
		# buffered to play on without stalling again
		var f0 := int(_clock * _fps)
		if not _can_play_from(f0):
			_label.text = "..."
			return
		_stalled = false
		_label.text = ""
		_audio.stream_paused = false
	_clock += delta
	var f := int(_clock * _fps)
	if f >= _frames and loop and _frames > 0:
		_clock = fmod(_clock, _frames / _fps)
		f = int(_clock * _fps) % _frames
	if f >= _frames:
		stop()
		return
	if f == _shown:
		return
	if f >= avail:
		_stalled = true
		_audio.stream_paused = true
		_clock = float(f) / _fps
		return
	_show(f)


func _show(i: int) -> void:
	var span := _conv.frame_span(i) if _conv else Vector2i(_offsets[i], _offsets[i + 1])
	_file.seek(span.x)
	var img := Image.new()
	if img.load_jpg_from_buffer(_file.get_buffer(span.y - span.x)) != OK:
		return
	_shown = i
	var cw := (_width + 1) >> 1
	var ch := (_height + 1) >> 1
	var parts := [img.get_region(Rect2i(0, 0, _width, _height)), img.get_region(Rect2i(0, _height, cw, ch)),
		img.get_region(Rect2i(cw, _height, cw, ch))]
	for k in 3:
		if _tex[k] == null:
			_tex[k] = ImageTexture.create_from_image(parts[k])
		else:
			_tex[k].update(parts[k])
	_view.texture = _tex[0]
	_mat.set_shader_parameter("u_tex", _tex[1])
	_mat.set_shader_parameter("v_tex", _tex[2])


func _pause() -> void:
	if pause_game and not _paused_tree and is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_tree = true


func _unhandled_input(e: InputEvent) -> void:
	if visible and not loop and e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_SPACE, KEY_ESCAPE]:
		stop()
		get_viewport().set_input_as_handled()
