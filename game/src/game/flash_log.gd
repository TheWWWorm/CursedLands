class_name FlashLog
extends Node
## Diagnostic for whole-screen flashes (remake only, off by default). Each
## frame a 32 × 18 copy of the finished window (UI included) is averaged on
## the GPU and read back asynchronously (no stall); when the mean brightness
## jumps away from the last frames by more than the threshold, a timestamped
## line with the frame's colour and the active renderer / effect settings
## goes to the log (godot.log), and another when it comes back (a flash) or
## stays (a scene change). A camera with a non-finite transform is logged too.
## Turn on with either:
##   the command line: "Evil Islands.original" --flash-log (or --flash-log=0.15)
##   settings.cfg:      [debug] flash_log=true   (or a threshold, e.g. 0.15)
## Threshold: mean sRGB luma change, 0..1 (default 0.2).

const W := 32
const H := 18
const DEFAULT_THRESHOLD := 0.2
## Frames compared against; frames a jump may last and still count as a flash.
const BASE_FRAMES := 8
const FLASH_FRAMES := 30
const MAX_IN_FLIGHT := 4
const HEARTBEAT_MS := 60000

const SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D src : filter_nearest;
uniform vec2 cells = vec2(32.0, 18.0);
void fragment() {
	vec2 cell = 1.0 / cells;
	vec2 o = floor(UV * cells) * cell;
	vec3 s = vec3(0.0);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			s += textureLod(src, o + (vec2(float(x), float(y)) + 0.5) * 0.25 * cell, 0.0).rgb;
		}
	}
	COLOR = vec4(s / 16.0, 1.0);
}
"""

var threshold := DEFAULT_THRESHOLD
var _vp: SubViewport
var _rd: RenderingDevice
var _in_flight := 0
var _history: Array[float] = []
var _event := {}            # open jump: {frame, msec, base, peak, rgb}
var _last_heartbeat := 0
var _samples := 0
var _min := 1.0
var _max := 0.0
var _cam_bad := false
var _last_sample_frame := -1


## The threshold asked for by the command line or settings.cfg, or < 0: off.
static func requested() -> float:
	var args := Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	for a: String in args:
		if a == "--flash-log":
			return DEFAULT_THRESHOLD
		if a.begins_with("--flash-log="):
			var v := a.trim_prefix("--flash-log=").to_float()
			return v if v > 0.0 else DEFAULT_THRESHOLD
	var cfg := ConfigFile.new()
	if cfg.load(GameData.CONFIG_PATH) == OK and cfg.has_section_key("debug", "flash_log"):
		var v = cfg.get_value("debug", "flash_log")
		if v is bool:
			return DEFAULT_THRESHOLD if v else -1.0
		if (v is float or v is int) and float(v) > 0.0:
			return float(v) if float(v) < 1.0 else DEFAULT_THRESHOLD
	return -1.0


func _init(thr := DEFAULT_THRESHOLD) -> void:
	threshold = thr
	name = "FlashLog"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		queue_free()
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.size = Vector2(W, H)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SHADER
	m.set_shader_parameter("cells", Vector2(W, H))
	# The window's own picture of the previous frame (sub-viewports draw first).
	m.set_shader_parameter("src", get_tree().root.get_texture())
	r.material = m
	_vp.add_child(r)
	add_child(_vp)
	_rd = RenderingServer.get_rendering_device()
	_last_heartbeat = Time.get_ticks_msec()
	_log("on, threshold %.2f. %s" % [threshold, _system()])


func _process(_dt: float) -> void:
	_check_camera()
	var f := Engine.get_frames_drawn()
	if f == _last_sample_frame:
		return
	_last_sample_frame = f
	if _rd:
		if _in_flight >= MAX_IN_FLIGHT:
			return
		var rid := RenderingServer.texture_get_rd_texture(_vp.get_texture().get_rid())
		if not rid.is_valid():
			return
		_in_flight += 1
		var ms := Time.get_ticks_msec()
		RenderingServer.call_on_render_thread(func() -> void:
			if _rd.texture_get_data_async(rid, 0, _on_data.bind(f, ms)) != OK:
				_in_flight -= 1)
	elif f % 4 == 0:
		# Compatibility renderer: a synchronous read, every 4th frame.
		var img := _vp.get_texture().get_image()
		if img:
			img.convert(Image.FORMAT_RGBA8)
			_measure(img.get_data(), f, Time.get_ticks_msec())
	var now := Time.get_ticks_msec()
	if now - _last_heartbeat >= HEARTBEAT_MS:
		_last_heartbeat = now
		_log("alive: %d samples, luma %.3f..%.3f, %d fps" % [_samples, _min, _max, Engine.get_frames_per_second()])
		_samples = 0
		_min = 1.0
		_max = 0.0


func _on_data(data: PackedByteArray, frame: int, ms: int) -> void:
	_in_flight = maxi(_in_flight - 1, 0)
	_measure.call_deferred(data, frame, ms)


## Mean sRGB colour and Rec. 709 luma of the 32 × 18 cells (RGBA8 or RGBA16F).
func _measure(data: PackedByteArray, frame: int, ms: int) -> void:
	var n := W * H
	var rgb := Vector3.ZERO
	var lo := 1e9
	var hi := -1e9
	var bad := 0
	var half := data.size() >= n * 8
	if data.size() < n * 4:
		return
	for i in n:
		var c: Vector3
		if half:
			c = Vector3(data.decode_half(i * 8), data.decode_half(i * 8 + 2), data.decode_half(i * 8 + 4))
		else:
			c = Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]) / 255.0
		if not c.is_finite():
			bad += 1
			continue
		var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
		lo = minf(lo, l)
		hi = maxf(hi, l)
		rgb += c
	rgb /= float(maxi(n - bad, 1))
	var luma := rgb.dot(Vector3(0.2126, 0.7152, 0.0722))
	_samples += 1
	_min = minf(_min, luma)
	_max = maxf(_max, luma)
	if bad > 0:
		_log("frame %d: %d of %d cells NaN/Inf. %s" % [frame, bad, n, _context()])
	if _history.size() >= BASE_FRAMES:
		var base := 0.0
		for v in _history:
			base += v
		base /= _history.size()
		if _event.is_empty():
			if absf(luma - base) > threshold:
				_event = {"frame": frame, "msec": ms, "base": base, "peak": luma}
				_log("JUMP frame %d: luma %.3f -> %.3f, colour (%.2f, %.2f, %.2f), cells %.2f..%.2f (%s). %s" % [
					frame, base, luma, rgb.x, rgb.y, rgb.z, lo, hi,
					"uniform" if hi - lo < 0.08 else "varied", _context()])
		else:
			var b: float = _event.base
			if absf(luma - b) > absf(float(_event.peak) - b):
				_event.peak = luma
			if absf(luma - b) <= threshold * 0.5:
				_log("FLASH: back to %.3f after %d frames (%d ms), peak %.3f, began frame %d" % [
					luma, frame - int(_event.frame), ms - int(_event.msec), _event.peak, _event.frame])
				_event = {}
			elif frame - int(_event.frame) > FLASH_FRAMES:
				_log("level change (not a flash): %.3f -> %.3f since frame %d" % [b, luma, _event.frame])
				_event = {}
				_history.clear()
	if _event.is_empty():
		_history.append(luma)
		if _history.size() > BASE_FRAMES:
			_history.pop_front()


func _check_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t := cam.global_transform
	var ok := t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite() \
		and is_finite(cam.near) and is_finite(cam.far) and cam.far > cam.near and t.basis.determinant() != 0.0
	if not ok and not _cam_bad:
		_log("camera transform not finite / degenerate: %s near %s far %s" % [t, cam.near, cam.far])
	_cam_bad = not ok


func _log(s: String) -> void:
	print("[flash-log %s +%dms] %s" % [Time.get_time_string_from_system(), Time.get_ticks_msec(), s])


func _system() -> String:
	return "%s / %s, %s (%s), %s, Godot %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(),
		Engine.get_version_info().string]


## What is on and where the view is, for one log line.
func _context() -> String:
	var vp := get_tree().root
	var parts: Array[String] = []
	parts.append("%d fps, frame %.1f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	parts.append("window %s scale %.2f mode %d msaa %d ssaa %d taa %s" % [vp.size, vp.scaling_3d_scale,
		vp.scaling_3d_mode, vp.msaa_3d, vp.screen_space_aa, vp.use_taa])
	var w3 := vp.find_world_3d()
	var env := w3.environment if w3 else null
	if env:
		parts.append("glow %s ssao %s volfog %s (%.4f) fog %s sky %s refl %d" % [env.glow_enabled, env.ssao_enabled,
			env.volumetric_fog_enabled, env.volumetric_fog_density, env.fog_enabled,
			env.background_mode == Environment.BG_SKY, env.reflected_light_source])
	var opts: Array[String] = []
	for k in ["gfx_sky", "gfx_water", "gfx_water_reflections", "gfx_heat_haze", "gfx_torch_glow",
			"gfx_bloom", "gfx_volumetric", "gfx_ssao", "q_aa", "render_scale", "vsync", "fps_limit"]:
		opts.append("%s=%d" % [k.trim_prefix("gfx_"), GameData.option(k)])
	parts.append(" ".join(opts))
	var cam := vp.get_camera_3d()
	if cam:
		parts.append("camera %s near %.2f far %.1f" % [cam.global_position.snapped(Vector3.ONE * 0.01), cam.near, cam.far])
	var scene := get_tree().current_scene
	parts.append("scene %s%s" % [scene.name if scene else "-", " paused" if get_tree().paused else ""])
	var flash_ms: int = ParticleFx.last_flash_light_msec
	if flash_ms >= 0:
		parts.append("last script flash light %d ms ago" % (Time.get_ticks_msec() - flash_ms))
	return "; ".join(parts)
