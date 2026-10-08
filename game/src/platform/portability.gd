class_name Portability
extends RefCounted

static func handheld() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android")

static func constrained() -> bool:
	return handheld() or OS.has_feature("web")

static func compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

## The sun's shadow is held and re-aimed (Game._aim_sun) instead of turned
## every frame: a shimmer/cost fallback for phones and the web, on any
## renderer. Desktop keeps continuous sunlight, including Compatibility.
## Tests: --held-sun on a PC; --shadow-diag=continuous bypasses the fallback
## for device comparisons before choosing a better constrained-device policy.
static func held_sun() -> bool:
	return constrained() or OS.get_cmdline_user_args().has("--held-sun")

static func threads() -> bool:
	return not OS.has_feature("web") or OS.has_feature("threads")

static func group(job: Callable, count: int) -> void:
	if count <= 0:
		return
	if threads():
		var task := WorkerThreadPool.add_group_task(job, count)
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for i in count:
			job.call(i)

static func defaults() -> Dictionary:
	if not constrained():
		return {}
	var d := {"gfx_hd_textures": 0, "gfx_volumetric": 0, "gfx_ssao": 0,
		"gfx_water_reflections": 0, "gfx_heat_haze": 0, "gfx_soft_particles": 0,
		"gfx_torch_glow": 0, "gfx_far_view": 0, "gfx_materials": 0,
		"gfx_grass": 0, "gfx_soft_ground": 0, "gfx_ground_contact": 0,
		"q_aa": 0, "q_shadows": 0, "q_aniso": 1, "fps_limit": 2,
		"render_scale": 2, "confine_mouse": 0}
	# A phone has no pointer at the screen edges. A browser keeps the desktop
	# edge scrolling for its mouse (touch mode turns it off, CameraRig).
	if handheld():
		d.scroll_border = 0
	return d

static var _safe_frame := -1
static var _safe_insets := Vector4.ZERO
static var _phone := false

static func safe_rect(viewport_size: Vector2) -> Rect2:
	# Drawing helpers call this many times per frame. Read the OS / browser
	# once, while still reacting immediately to rotation and window resizing.
	if _safe_frame != Engine.get_process_frames():
		_safe_frame = Engine.get_process_frames()
		_read_safe_insets()
	return inset_rect(viewport_size, _safe_insets, _phone or TouchInput.enabled)

static func _read_safe_insets() -> void:
	_safe_insets = Vector4.ZERO
	_phone = handheld()
	if OS.has_feature("web"):
		var b := JavaScriptBridge.get_interface("CursedFiles")
		if b:
			var a: Variant = JSON.parse_string(str(b.insets()))
			if a is Array and a.size() == 4:
				_safe_insets = Vector4(a[0], a[1], a[2], a[3])
		_phone = false   # a browser's touch layout follows TouchInput.enabled (the input in use)
	elif handheld():
		var area := DisplayServer.get_display_safe_area()
		var screen := Vector2(DisplayServer.screen_get_size())
		if screen.x > 0 and screen.y > 0 and area.has_area():
			_safe_insets = Vector4(area.position.x / screen.x, area.position.y / screen.y,
				(screen.x - area.end.x) / screen.x, (screen.y - area.end.y) / screen.y)

static func inset_rect(viewport_size: Vector2, inset: Vector4, phone: bool) -> Rect2:
	# Reserve the larger cutout on BOTH sides, including after rotating the
	# phone. Some Android/browser combinations report zero for camera cutouts.
	var side := maxf(inset.x, inset.z)
	if phone and viewport_size.x / maxf(viewport_size.y, 1.0) > 1.85:
		side = maxf(side, 0.055)
	if phone:
		inset.y = maxf(inset.y, 0.01)
		inset.w = maxf(inset.w, 0.015)
	inset.x = clampf(side, 0.0, 0.25)
	inset.z = inset.x
	inset.y = clampf(inset.y, 0.0, 0.25)
	inset.w = clampf(inset.w, 0.0, 0.25)
	var pos := Vector2(inset.x, inset.y) * viewport_size
	return Rect2(pos, viewport_size - pos - Vector2(inset.z, inset.w) * viewport_size)
