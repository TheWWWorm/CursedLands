class_name RendererDetector
extends Control
## Keep the parent on a 2D status screen while independent GPU tests run.
## A probe cannot load original game data, change settings or rotate its log.
const TIMEOUT_S := 45.0
const REVISION := 1
const STATUS := "Checking graphics API: %s"
const DETAIL := "This first-start check tries modern graphics APIs before OpenGL. The result is saved."
var child_pid := -1
var cancelled := false
var _status: Label

static func probe_args(driver: String, output: String, token: String) -> PackedStringArray:
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--rendering-method", "gl_compatibility" if driver == "opengl3" else "forward_plus", "--rendering-driver", driver, "--render-thread", "safe", "--audio-driver", "Dummy", "--windowed", "--resolution", "320x200", "--max-fps", "30", "--log-file", output + ".log", "--", "--renderer-probe", "--probe-output=" + output, "--probe-token=" + token, "--probe-driver=" + driver])
	return args

static func valid_result(result: Variant, driver: String, token: String) -> bool:
	return result is Dictionary and result.get("token", "") == token and result.get("driver", "") == driver and result.get("rendered", false) == true and int(result.get("frames", 0)) >= 48

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.05, 0.06)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = minf(560, get_viewport_rect().size.x - 48)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 24)
	column.add_child(_status)
	var help := Label.new()
	help.text = RemakeText.t(DETAIL)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)
	var cancel := Button.new()
	cancel.text = RemakeText.t("Cancel")
	cancel.pressed.connect(func(): cancelled = true; _stop(); get_tree().quit())
	column.add_child(cancel)
	cancel.grab_focus()

func run() -> bool:
	for driver: String in WindowsRenderer.ORDER:
		if cancelled: return false
		if driver in WindowsRenderer.data.get("failed", []): continue
		_status.text = RemakeText.t(STATUS) % {"d3d12":"Direct3D 12", "vulkan":"Vulkan", "opengl3":"OpenGL"}[driver]
		await get_tree().process_frame
		var token := "%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
		var folder := "user://renderer-tests"
		DirAccess.make_dir_recursive_absolute(folder)
		var output := ProjectSettings.globalize_path(folder.path_join(token + ".json"))
		# The next executable start already knows to skip an interrupted probe.
		WindowsRenderer.data.probe_running = driver
		WindowsRenderer._save()
		WindowsRenderer.write_override(WindowsRenderer.next_driver(driver, WindowsRenderer.data), WindowsRenderer.AUTO)
		child_pid = _launch(driver, output, token)
		var start := Time.get_ticks_msec()
		while child_pid > 0 and OS.is_process_running(child_pid) and Time.get_ticks_msec() - start < _timeout() * 1000:
			await get_tree().process_frame
			if cancelled: return false
		var timeout := child_pid > 0 and OS.is_process_running(child_pid)
		var exit_code := -1 if child_pid <= 0 or timeout else OS.get_process_exit_code(child_pid)
		_stop()
		var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(output)) if FileAccess.file_exists(output) else null
		WindowsRenderer.data.erase("probe_running")
		var passed := not timeout and exit_code == 0 and valid_result(result, driver, token)
		GameData.trace("renderer probe: %s %s (exit %s, timeout %s)" % [driver, "passed" if passed else "failed", exit_code, timeout])
		if passed:
			WindowsRenderer.desired = driver
			WindowsRenderer.data.probed = driver
			WindowsRenderer.data.probe_revision = REVISION
			WindowsRenderer.write_override(driver, WindowsRenderer.AUTO)
			WindowsRenderer._save()
			return true
		WindowsRenderer._failed(driver)
	# OpenGL remains the final attempt. Its failure is reported by the engine
	# on the next normal launch; do not loop probes forever.
	WindowsRenderer.desired = "opengl3"
	WindowsRenderer.write_override("opengl3", WindowsRenderer.AUTO)
	WindowsRenderer._save()
	return true

func _launch(driver: String, output: String, token: String) -> int:
	return OS.create_process(OS.get_executable_path(), probe_args(driver, output, token))

func _timeout() -> float:
	return TIMEOUT_S

func _stop() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	child_pid = -1

func _exit_tree() -> void:
	cancelled = true
	_stop()
	if WindowsRenderer.data.has("probe_running"):
		WindowsRenderer.data.erase("probe_running")
		WindowsRenderer._save()
