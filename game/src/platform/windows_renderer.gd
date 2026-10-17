class_name WindowsRenderer
extends RefCounted
## Windows API detection has two stages: Godot's native capability fallback,
## then a journal around the game's first 3D presentation. Arm the next API
## before drawing so a failed menu does not repeat on the following launch.
## Nothing here can recover an OS-wide GPU hang in the current process.

const AUTO := 3
const DRIVERS := ["opengl3", "d3d12", "vulkan"]
const ORDER := ["d3d12", "vulkan", "opengl3"]
const STATE := "user://renderer_auto.cfg"
static var data := {}
static var mode := AUTO
static var desired := ""
static var active := false
static var forced := false
static var initialized := false
static var driver_changed := false


static func chosen() -> int:
	if active: return mode
	var saved := RendererChoice._load(RendererChoice.OVERRIDE, "selection")
	if saved.has("mode"):
		return clampi(int(saved.mode), 0, AUTO)
	# Preserve explicit choices made by an older build. A profile with no
	# renderer override is Automatic, including all pre-picker Windows saves.
	var old := RendererChoice._load(RendererChoice.OVERRIDE, "rendering")
	if old.is_empty(): return AUTO
	if old.get("renderer/rendering_method", "") == "gl_compatibility": return 0
	return 2 if old.get("rendering_device/driver.windows", "") == "vulkan" else 1


static func fingerprint() -> String:
	var driver := OS.get_video_adapter_driver_info() if OS.has_feature("windows") else PackedStringArray()
	return JSON.stringify([OS.get_name(), OS.get_version(), OS.get_model_name(), OS.get_processor_name(), driver, Engine.get_version_info().get("hash", "")])


static func current_driver() -> String:
	return "opengl3" if Portability.compatibility() else RenderingServer.get_current_rendering_driver_name()


static func pick(state: Dictionary) -> String:
	var failed: Array = state.get("failed", [])
	var good := String(state.get("good", ""))
	if good in ORDER and good not in failed: return good
	for driver: String in ORDER:
		if driver not in failed: return driver
	return "opengl3"


static func next_driver(driver: String, state: Dictionary) -> String:
	var copy := state.duplicate(true)
	copy.failed = Array(copy.get("failed", []))
	if driver not in copy.failed: copy.failed.append(driver)
	copy.erase("good")
	return pick(copy)


static func _save() -> void:
	var cfg := ConfigFile.new()
	for key: String in data: cfg.set_value("detection", key, data[key])
	var error := cfg.save(STATE)
	if error != OK: push_warning("Could not save renderer detection: %s" % error_string(error))


static func _failed(driver: String) -> void:
	if driver not in DRIVERS: return
	var failed: Array = data.get("failed", [])
	if driver not in failed: failed.append(driver)
	data.failed = failed
	if data.get("good", "") == driver: data.erase("good")
	if data.get("probed", "") == driver: data.erase("probed")
	_save()


static func write_override(driver: String, selection: int) -> Error:
	var cfg := ConfigFile.new()
	var method := "gl_compatibility" if driver == "opengl3" else "forward_plus"
	cfg.set_value("selection", "mode", selection)
	for key: String in ["renderer/rendering_method", "renderer/rendering_method.windows"]:
		cfg.set_value("rendering", key, method)
	cfg.set_value("rendering", "rendering_device/driver.windows", driver if driver != "opengl3" else "d3d12")
	cfg.set_value("rendering", "driver/threads/thread_model.windows", 1)
	# Do not let native capability fallback return to an API already rejected
	# by a rendered startup. Explicit selections can retry that API.
	for api: String in ["d3d12", "vulkan"]:
		cfg.set_value("rendering", "rendering_device/fallback_to_" + api, api not in data.get("failed", []) or api == driver)
	cfg.set_value("rendering", "rendering_device/fallback_to_opengl3", true)
	return cfg.save(RendererChoice.OVERRIDE)


static func choose(value: int) -> void:
	value = clampi(value, 0, AUTO)
	if value == chosen(): return
	mode = value
	if mode == AUTO:
		# Selecting Automatic explicitly retries modern APIs after, for example,
		# a driver update. Normal launches retain prior detection results.
		data = {"fingerprint": fingerprint(), "failed": []}
		_save()
	desired = pick(data) if mode == AUTO else String(DRIVERS[mode])
	write_override(desired, mode)
	DirAccess.remove_absolute(RendererChoice.TRIAL)
	active = false
	GameData.trace("renderer for the next start: %s (%s)" % [desired, "automatic" if mode == AUTO else "manual"])


static func startup() -> void:
	initialized = true
	active = false
	mode = chosen()
	data = RendererChoice._load(STATE, "detection")
	var changed: bool = data.get("fingerprint", "") != fingerprint()
	driver_changed = changed and not data.is_empty()
	if changed: data = {"fingerprint": fingerprint(), "failed": []}
	if not changed and data.has("probe_running"):
		_failed(String(data.probe_running))
		data.erase("probe_running")
		mode = AUTO
	var trial := RendererChoice._load(RendererChoice.TRIAL, "trial")
	if not changed and trial.get("state", "") == "running":
		_failed(String(trial.get("driver", "d3d12")))
		mode = AUTO
		RendererChoice.notice = RendererChoice.WINDOWS_CRASHED
	DirAccess.remove_absolute(RendererChoice.TRIAL)
	var args := OS.get_cmdline_user_args()
	forced = OS.get_cmdline_args().has("--rendering-driver") or OS.get_cmdline_args().has("--rendering-method")
	# Test-only platform simulation must exercise policy despite Linux's CLI.
	if args.has("--windows-renderer-option"): forced = false
	if args.has("--compatibility-recovery") and Portability.compatibility():
		mode = 0
		GameData.set_options(GfxDetect.original_recovery_values(GameData.options))
	elif args.has("--vulkan-recovery") and current_driver() == "vulkan":
		mode = 2
	elif forced:
		mode = maxi(0, DRIVERS.find(current_driver()))
	desired = pick(data) if mode == AUTO else String(DRIVERS[mode])
	var saved := RendererChoice._load(RendererChoice.OVERRIDE, "rendering")
	var requested := "opengl3" if saved.get("renderer/rendering_method", "") == "gl_compatibility" else String(saved.get("rendering_device/driver.windows", "d3d12"))
	# Native fallback already found a supported API. Keep it instead of
	# restarting forever into the unavailable one; still test its 3D menu.
	if current_driver() != requested and desired == requested and not forced:
		_failed(requested)
		desired = current_driver()
		mode = AUTO
	write_override(desired, mode)
	_save()
	GameData.options.renderer = mode


## Only the narrow, known startup stage is evidence for API recovery. A
## gameplay crash, cancelled report, or ordinary shutdown is not a GPU test.
static func observe_previous(previous: Dictionary) -> void:
	if driver_changed or mode != AUTO or previous.is_empty() or previous.get("session", "") == data.get("seen_session", ""): return
	data.seen_session = previous.get("session", "")
	if previous.get("zone", "") == "(menu)" and previous.get("last", "") == "startup: main menu built; presenting loading animation":
		var driver := String(previous.get("renderer", "")).get_slice(" / ", 1)
		_failed(driver)
		desired = pick(data)
		write_override(desired, mode)
		GameData.trace("renderer detection: previous menu presentation failed on %s; next API %s" % [driver, desired])
	_save()


## Called immediately before any first 3D scene, after the 2D crash report.
## Returns false if a restart is needed; no 3D scene should then be built.
static func prepare(parent: Node) -> bool:
	if not RendererChoice.windows() or DisplayServer.get_name() == "headless": return true
	if mode == AUTO and not forced and (data.get("probed", "") != desired or int(data.get("probe_revision", 0)) != RendererDetector.REVISION):
		var detector := RendererDetector.new()
		parent.add_child(detector)
		var completed := await detector.run()
		detector.queue_free()
		if not completed: return false
	return before_scene(parent.get_tree())


static func before_scene(tree: SceneTree) -> bool:
	if not RendererChoice.windows() or DisplayServer.get_name() == "headless": return true
	if not initialized: startup()
	if desired != current_driver():
		write_override(desired, mode)
		RendererChoice.restart(tree)
		return false
	if not active:
		var driver := current_driver()
		var fallback := next_driver(driver, data) if driver != "opengl3" else driver
		# A successful disk write is required before starting a risky trial.
		var error := write_override(fallback, AUTO if mode != 0 else 0)
		if error != OK:
			push_warning("Could not arm renderer fallback: %s" % error_string(error))
			return true
		RendererChoice._save_trial({"state": "running", "driver": driver, "mode": mode, "fingerprint": fingerprint()})
		active = true
		GameData.trace("renderer detection: testing %s; next launch fallback %s" % [driver, fallback])
	return true


static func confirm() -> void:
	if not active or RendererChoice._menu_ready_ms < 0: return
	var trial := RendererChoice._load(RendererChoice.TRIAL, "trial")
	if trial.get("driver", "") != current_driver(): return
	# A new choice made in Options must not be overwritten by the old timer.
	if write_override(current_driver(), mode) != OK: return
	data.good = current_driver()
	_save()
	DirAccess.remove_absolute(RendererChoice.TRIAL)
	active = false
	GameData.options.renderer = mode
	GameData.trace("renderer detection: menu presented; keeping %s" % current_driver())
