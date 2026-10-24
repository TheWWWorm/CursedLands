class_name RendererChoice
extends Node
## Persistent renderer choice for Android and Windows, applied before scripts
## by project.godot's platform-specific project_settings_override. Android
## defaults to Compatibility; Windows automatically tests modern APIs with
## the Safe render thread (WindowsRenderer). Android enhanced modes are trials.
## Before drawing 3D the next fallback is saved for restart; only a menu that
## has actually been presented may confirm the trial. Waiting on startup
## notices, an early clean quit or backgrounding cannot accept an untested GPU.

const OVERRIDE := "user://renderer.cfg"
const TRIAL := "user://renderer_trial.cfg"
const METHODS := ["gl_compatibility", "forward_plus", "mobile"]
const TRIAL_S := 60.0
const WINDOWS_CHOICES := ["Compatibility", "Forward+ (Direct3D 12)", "Forward+ (Vulkan)", "Automatic"]
const WINDOWS_HELP := "Automatic prefers Direct3D 12, then Vulkan, with OpenGL as the last fallback. A failed menu startup tries the next API on the following launch. Successful detection is remembered until the graphics driver changes. You can also choose an API yourself. Changes require a restart."
const WINDOWS_FAILED := "The selected renderer could not start. The next launch uses Compatibility (OpenGL 3)."
const WINDOWS_CRASHED := "The previous renderer test did not finish. Automatic will try another graphics API. Direct3D 12 and Vulkan are preferred; OpenGL is the last fallback."
static var _menu_ready_ms := -1
const RESTART := ["Renderer", "The renderer changes when the game starts again. Restart the game now? If it does not start again by itself, open it again."]
## In a game: the same box, which says what a restart costs.
const RESTART_GAME := "The renderer changes when the game starts again. Restart now? Progress since the last save will be lost."
## Forward+ on a phone: slower than the other two, and some drivers cannot
## build all of its compute shaders (an Adreno 650's 2023 driver: "Couldn't
## create Vulkan compute pipelines" at every start).
const FORWARD_PLUS := 1
const EXPERIMENTAL := "Forward+ is experimental on phones and handhelds: it is slower than Compatibility and Mobile, and on some devices it shows graphics problems or parts of it do not work. Use it anyway?"
const FAILED := "Vulkan could not be started on this device. The game uses Compatibility (OpenGL ES 3) again."
const CRASHED := "The game closed unexpectedly right after switching to %s. It uses Compatibility (OpenGL ES 3) again; you can choose another renderer in Options."

## The notice for the main menu (FAILED / CRASHED, "" none) and the
## renderer it names, set by `startup`; translated when shown (the
## edition's language is known only once the game files are open).
static var notice := ""
static var notice_method := 0
## Tests: called instead of quitting the game (`restart`).
static var on_restart := Callable()



## The test flags exercise each platform's policy on an isolated PC profile.
static func windows() -> bool:
	return OS.has_feature("windows") or OS.get_cmdline_user_args().has("--windows-renderer-option")


static func labels() -> Array:
	return WINDOWS_CHOICES if windows() else GameData.DISPLAY_CHOICES.renderer


## The row is offered on Android and Windows.
static func available() -> bool:
	return windows() or OS.has_feature("android") or OS.get_cmdline_user_args().has("--renderer-option")


## The option value the player chose (a trial counts as chosen).
static func chosen() -> int:
	if windows(): return WindowsRenderer.chosen()
	var t := _load(TRIAL, "trial")
	if not t.is_empty():
		return maxi(0, METHODS.find(String(t.get("method", ""))))
	var o := _load(OVERRIDE, "rendering")
	return maxi(0, METHODS.find(String(o.get("renderer/rendering_method", "forward_plus" if windows() else "gl_compatibility"))))


## Option set (GameData.set_option): the method for the next start.
static func choose(v: int) -> void:
	if windows():
		WindowsRenderer.choose(v)
		return
	v = clampi(v, 0, labels().size() - 1)
	if v == chosen():
		return
	if v == 0:
		_reset()
	else:
		_write_override(METHODS[v])
		_save_trial({"method": METHODS[v], "state": "pending"})
	GameData.trace("renderer for the next start: %s" % METHODS[v])


## GameData._ready: the trial's step for this start; returns a node to add
## (the confirmation timer) or null. Sets GameData.options.renderer.
static func startup() -> RendererChoice:
	if windows():
		_menu_ready_ms = -1
		WindowsRenderer.startup()
		return RendererChoice.new()
	var node: RendererChoice = null
	_menu_ready_ms = -1
	if windows() and OS.get_cmdline_user_args().has("--compatibility-recovery") and Portability.compatibility():
		_reset()
		GameData.set_options(GfxDetect.original_recovery_values(GameData.options))
		GameData.trace("startup recovery: Compatibility launcher; basic graphics selected")
	var t := _load(TRIAL, "trial")
	var running := RenderingServer.get_current_rendering_method()
	var boot := CrashReport.android_startup()
	var early: Dictionary = boot.current if boot.get("current") is Dictionary else {}
	if available() and not String(early.get("recovered_renderer", "")).is_empty():
		_reset()
		notice = WINDOWS_FAILED if windows() else FAILED
		GameData.trace("renderer recovered before engine startup: %s" % early.recovered_renderer)
	elif available() and not t.is_empty():
		var method := String(t.get("method", ""))
		var i := maxi(0, METHODS.find(method))
		if String(t.get("state", "")) == "running":
			GameData.trace("renderer trial on %s ended unexpectedly: back to %s" % [method, METHODS[0]])
			_reset()
			notice = WINDOWS_CRASHED if windows() else CRASHED
			notice_method = i
		elif running != method:
			GameData.trace("renderer %s did not start (running %s): back to %s" % [method, running, METHODS[0]])
			_reset()
			notice = WINDOWS_FAILED if windows() else FAILED
		else:
			t.state = "running"
			_save_trial(t)
			_fallback_override()   # written before the first 3D draw
			GameData.trace("renderer trial: %s" % method)
			node = RendererChoice.new()
	GameData.options.renderer = chosen()
	return node


## The trial run works: its renderer stays for the next starts.
static func confirm() -> void:
	if windows():
		WindowsRenderer.confirm()
		return
	if _menu_ready_ms < 0:
		return
	var t := _load(TRIAL, "trial")
	if t.is_empty() or String(t.get("state", "")) != "running":
		return
	var method := String(t.get("method", ""))
	if RenderingServer.get_current_rendering_method() != method:
		return
	_write_override(method)
	DirAccess.remove_absolute(TRIAL)
	GameData.trace("renderer trial confirmed: %s" % method)


## The main menu: the notice of `startup` once, after `after` (a box already
## up, e.g. CrashReportBox) closes.
static func offer(parent: Node, after: Node = null) -> MessageBox:
	if notice.is_empty():
		return null
	if is_instance_valid(after):
		after.tree_exited.connect(func():
			if is_instance_valid(parent) and parent.is_inside_tree():
				offer(parent), CONNECT_ONE_SHOT)
		return null
	var b := MessageBox.new()
	b.title = RemakeText.t(RESTART[0])
	b.message = RemakeText.t(CRASHED) % RemakeText.t(GameData.DISPLAY_CHOICES.renderer[notice_method]) if notice == CRASHED \
		else RemakeText.t(notice)
	b.ok_only = true
	b.esc_closes = true
	notice = ""
	parent.add_child(b)
	return b


## Options ✓ with the renderer row changed: the game offers to restart, in a
## game (`from_menu` false) saying that unsaved progress goes; ✗ or Esc:
## the new renderer comes with the next start.
static func ask_restart(parent: Node, from_menu: bool, graphics_technology := false) -> MessageBox:
	var b := MessageBox.new()
	b.title = RemakeText.t(RESTART[0])
	b.message = RemakeText.t(("The graphics technology changes after restarting. Restart the game now?" if from_menu else "The graphics technology changes after restarting. Restart now? Progress since the last save will be lost.") if graphics_technology else RESTART[1] if from_menu else RESTART_GAME)
	b.esc_closes = true
	parent.add_child(b)
	var tree := parent.get_tree()
	b.answered.connect(func(yes: bool):
		if yes:
			restart(tree))
	return b


## The Options row stepped to Forward+: ✓ keeps it, ✗ / Esc answers no.
static func ask_experimental(parent: Node) -> MessageBox:
	var b := MessageBox.new()
	b.title = RemakeText.t(RESTART[0])
	b.message = RemakeText.t(EXPERIMENTAL)
	parent.add_child(b)
	return b


## Restart into the selected backend. Drop old engine renderer overrides and
## direct-start/tool arguments so they cannot defeat the saved recovery choice.
static func restart(tree: SceneTree) -> void:
	if on_restart.is_valid():
		on_restart.call()
		return
	GameData.trace("restart for the renderer")
	if windows():
		OS.set_restart_on_exit(true, restart_args())
	elif OS.has_feature("android"):
		OS.set_restart_on_exit(true)
	tree.quit()


static func restart_args() -> PackedStringArray:
	var args := PackedStringArray()
	var skip := false
	for arg in OS.get_cmdline_args():
		if skip:
			skip = false
			continue
		if arg in ["--rendering-method", "--rendering-driver", "--render-thread", "--path"]:
			skip = true
			continue
		args.append(arg)
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--render-thread", "safe"])
	var user := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ei-path="):
			user.append(arg)
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	return args


static func menu_presented() -> void:
	_menu_ready_ms = Time.get_ticks_msec()


static func _fallback_override() -> void:
	if windows():
		_write_override("gl_compatibility")
	else:
		DirAccess.remove_absolute(OVERRIDE)


static func _reset() -> void:
	_fallback_override()
	DirAccess.remove_absolute(TRIAL)
	GameData.options.renderer = 0


static func _write_override(method: String) -> void:
	var cfg := ConfigFile.new()
	# The platform override wins over the plain key in exported projects.
	cfg.set_value("rendering", "renderer/rendering_method", method)
	if windows():
		cfg.set_value("rendering", "renderer/rendering_method.windows", method)
		cfg.set_value("rendering", "rendering_device/driver.windows", "d3d12")
		cfg.set_value("rendering", "driver/threads/thread_model.windows", 1)
	else:
		cfg.set_value("rendering", "renderer/rendering_method.mobile", method)
	cfg.save(OVERRIDE)


static func _save_trial(t: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for k: String in t:
		cfg.set_value("trial", k, t[k])
	cfg.save(TRIAL)


static func _load(path: String, section: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path) or cfg.load(path) != OK or not cfg.has_section(section):
		return {}
	var d := {}
	for k in cfg.get_section_keys(section):
		d[k] = cfg.get_value(section, k)
	return d


# ------------------------------------------------------------------ trial run

func _ready() -> void:
	name = "RendererChoice"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_dt: float) -> void:
	if _menu_ready_ms >= 0 and Time.get_ticks_msec() - _menu_ready_ms >= TRIAL_S * 1000.0:
		confirm()
		queue_free()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		confirm()


func _exit_tree() -> void:
	confirm()
