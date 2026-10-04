class_name RendererChoice
extends Node
## Remake: the renderer on Android (option "renderer", Options › Screen
## row 12; no counterpart in the 2000 game). 0 Compatibility (OpenGL ES 3,
## the default), 1 Forward+ (Vulkan), 2 Mobile (Vulkan). Desktop always runs
## Forward+ and the web Compatibility: the row is hidden there (`available`).
## Godot picks the rendering method at startup, before any script runs:
## project.godot's application/config/project_settings_override.android names
## OVERRIDE, which `choose` writes ([rendering] renderer/rendering_method and
## its .mobile override; the driver follows the method: vulkan / opengl3).
## Without the file the project's own Compatibility setting stays. A device
## without Vulkan 1.1 gets OpenGL anyway: Godot's Android layer checks the
## Vulkan feature level and falls back (rendering_device/fallback_to_opengl3,
## Godot's default, on). Whatever branches on the renderer reads the running
## one (Portability.compatibility()), never this option.
## Crash safety: the first start on a newly chosen Vulkan renderer is a trial
## (TRIAL, state "pending"). Once it runs (`startup`, state "running"),
## OVERRIDE goes back to Compatibility, so if this run crashes the next start
## is on OpenGL again; after TRIAL_S seconds in the foreground, the app going
## to the background or a clean quit, the choice is confirmed and OVERRIDE
## written again. A start that finds a trial still "running" (that run ended
## unexpectedly) or Godot on another renderer than the pending one (Vulkan
## could not start) puts the option back on Compatibility; the main menu
## tells the player (`offer`). A crash inside the Vulkan driver's own start
## (before any script) cannot be caught here: clearing the app's data
## resets the choice.

const OVERRIDE := "user://renderer.cfg"
const TRIAL := "user://renderer_trial.cfg"
const METHODS := ["gl_compatibility", "forward_plus", "mobile"]
const TRIAL_S := 60.0
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

var _start_ms := Time.get_ticks_msec()


## The row is offered: Android (and tests on a PC: --renderer-option).
static func available() -> bool:
	return OS.has_feature("android") or OS.get_cmdline_user_args().has("--renderer-option")


## The option value the player chose (a trial counts as chosen).
static func chosen() -> int:
	var t := _load(TRIAL, "trial")
	if not t.is_empty():
		return maxi(0, METHODS.find(String(t.get("method", ""))))
	var o := _load(OVERRIDE, "rendering")
	return maxi(0, METHODS.find(String(o.get("renderer/rendering_method", ""))))


## Option set (GameData.set_option): the method for the next start.
static func choose(v: int) -> void:
	v = clampi(v, 0, METHODS.size() - 1)
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
	var node: RendererChoice = null
	var t := _load(TRIAL, "trial")
	var running := RenderingServer.get_current_rendering_method()
	if available() and not t.is_empty():
		var method := String(t.get("method", ""))
		var i := maxi(0, METHODS.find(method))
		if String(t.get("state", "")) == "running":
			GameData.trace("renderer trial on %s ended unexpectedly: back to %s" % [method, METHODS[0]])
			_reset()
			notice = CRASHED
			notice_method = i
		elif running != method:
			GameData.trace("renderer %s did not start (running %s): back to %s" % [method, running, METHODS[0]])
			_reset()
			notice = FAILED
		else:
			t.state = "running"
			_save_trial(t)
			DirAccess.remove_absolute(OVERRIDE)   # a crash in this run: the next start is on OpenGL
			GameData.trace("renderer trial: %s" % method)
			node = RendererChoice.new()
	GameData.options.renderer = chosen()
	return node


## The trial run works: its renderer stays for the next starts.
static func confirm() -> void:
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
		else RemakeText.t(FAILED)
	b.ok_only = true
	b.esc_closes = true
	notice = ""
	parent.add_child(b)
	return b


## Options ✓ with the renderer row changed: the game offers to restart, in a
## game (`from_menu` false) saying that unsaved progress goes; ✗ or Esc:
## the new renderer comes with the next start.
static func ask_restart(parent: Node, from_menu: bool) -> MessageBox:
	var b := MessageBox.new()
	b.title = RemakeText.t(RESTART[0])
	b.message = RemakeText.t(RESTART[1] if from_menu else RESTART_GAME)
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


## Quits; Android starts the app again where Godot supports it
## (OS.set_restart_on_exit), else the player opens it again.
static func restart(tree: SceneTree) -> void:
	if on_restart.is_valid():
		on_restart.call()
		return
	GameData.trace("restart for the renderer")
	if OS.has_feature("android"):
		OS.set_restart_on_exit(true)
	tree.quit()


static func _reset() -> void:
	DirAccess.remove_absolute(OVERRIDE)
	DirAccess.remove_absolute(TRIAL)
	GameData.options.renderer = 0


static func _write_override(method: String) -> void:
	var cfg := ConfigFile.new()
	# Both keys: the exported project.binary may keep project.godot's
	# .mobile override, which wins over the plain key on Android.
	cfg.set_value("rendering", "renderer/rendering_method", method)
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
	if Time.get_ticks_msec() - _start_ms >= TRIAL_S * 1000.0:
		confirm()
		queue_free()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		confirm()


func _exit_tree() -> void:
	confirm()
