class_name StartupGraphicsProbe
extends Node
## Explicit recovery action. Each boundary is flushed into the existing crash
## report before constructing/submitting work. Never change saved settings or
## run calibration; a native failure leaves the precise pending stage behind.
signal finished(ok: bool)

const LABELS := ["Loading picture", "Building the menu", "Menu sky", "Menu terrain",
	"Menu water", "Menu objects", "Menu signpost", "Complete menu scene", "Menu screens"]
var rows: Array[Dictionary] = []
var _label: Label
var _scene: MenuScene
var _menu: Control
var _splash: StartupScreen
var _geometry := {}
var _background := Environment.BG_SKY
var _stage := ""
var _started := 0

class Errors extends Logger:
	var messages: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING: return
		mutex.lock()
		messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
		mutex.unlock()
	func snapshot() -> Array[String]:
		mutex.lock()
		var copy := messages.duplicate()
		mutex.unlock()
		return copy

var _errors := Errors.new()
var _logging := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_finish.call_deferred(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(_errors)
	_logging = true
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var cover := Control.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(cover)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = -120
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", SettingsDialog.plate(Color("24241c"), Color("8b7953"), 8))
	cover.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_override("font", Interface800.font())
	_label.add_theme_font_size_override("font_size", 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_label)
	_run.call_deferred()

func _begin(id: String, index: int) -> void:
	_stage = id
	_label.text = RemakeText.t("Startup graphics check") + "\n%d / %d: " % [index + 1, LABELS.size()] + RemakeText.t(LABELS[index])
	GameData.trace("startup graphics probe: preparing " + id)
	await RenderingServer.frame_post_draw
	_started = Time.get_ticks_msec()
	GameData.trace("startup graphics probe: begin " + id)

func _present() -> bool:
	for i in 3:
		await RenderingServer.frame_post_draw
	# Synchronize GPU execution as well as CPU submission. Do not retain images.
	var pixels := get_viewport().get_texture().get_image()
	var errors := _errors.snapshot()
	var ok := pixels != null and not pixels.is_empty() and errors.is_empty()
	rows.append({"stage":_stage, "ok":ok, "ms":Time.get_ticks_msec()-_started})
	GameData.trace("startup graphics probe: %s %s" % ["passed" if ok else "failed", _stage])
	if not errors.is_empty():
		GameData.trace("startup graphics probe: errors " + JSON.stringify(errors))
	return ok

func _run() -> void:
	await _begin("loading_picture", 0)
	_splash = StartupScreen.open(self)
	if _splash:
		await _splash.presented()
		await _splash.finish()
	else:
		GameData.trace("startup graphics probe: loading picture unavailable")
		_finish(false); return
	if not await _present():
		_finish(false); return
	await _begin("menu_build", 1)
	_scene = MenuScene.create()
	if _scene == null:
		GameData.trace("startup graphics probe: menu unavailable")
		_finish(false); return
	_scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_scene)
	_scene.camera.current = true
	_background = _scene._env.background_mode
	var terrain: EITerrain
	for child in _scene.get_children():
		if child is EIMapScene: terrain = child.terrain
	for node: GeometryInstance3D in _scene.find_children("*", "GeometryInstance3D", true, false):
		var group := "objects"
		if node == _scene._column or _scene._column.is_ancestor_of(node):
			group = "signpost"
		elif terrain and terrain.is_ancestor_of(node):
			group = "terrain"
			if node is MeshInstance3D and node.mesh:
				for surface in node.mesh.get_surface_count():
					if node.get_active_material(surface) == terrain._water_mat: group = "water"
		_geometry[node] = {"group":group, "visible":node.is_visible_in_tree()}
		node.visible = false
	_scene._env.background_mode = Environment.BG_COLOR
	var counts := {}
	for data: Dictionary in _geometry.values():
		counts[data.group] = int(counts.get(data.group,0)) + 1
	GameData.trace("startup graphics probe: geometry " + JSON.stringify(counts))
	if not await _present():
		_finish(false); return
	var groups := ["sky", "terrain", "water", "objects", "signpost", "whole_scene"]
	for i in groups.size():
		await _begin(groups[i], i + 2)
		for node: GeometryInstance3D in _geometry:
			var data: Dictionary = _geometry[node]
			node.visible = data.visible and (groups[i] == "whole_scene" or data.group == groups[i])
		_scene._env.background_mode = _background if groups[i] in ["sky", "whole_scene"] else Environment.BG_COLOR
		if not await _present():
			_finish(false); return
	_geometry.clear()
	_scene.free()
	_scene = null
	await _begin("menu_screens", 8)
	_menu = preload("res://src/ui/main_menu.gd").new()
	_menu.detect_graphics = false
	add_child(_menu)
	if not await _present():
		_finish(false); return
	_finish(true)

func _finish(ok: bool) -> void:
	if is_instance_valid(_splash): _splash.free()
	_geometry.clear()
	if is_instance_valid(_scene): _scene.free()
	if is_instance_valid(_menu): _menu.free()
	var result := {"ok":ok, "rows":rows, "errors":_errors.snapshot(),
		"renderer":RenderingServer.get_current_rendering_method(), "gpu":RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open("user://startup-graphics-probe.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t")+"\n")
	GameData.trace("startup graphics probe: result " + JSON.stringify(result))
	finished.emit(ok)
	queue_free()

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _logging: OS.remove_logger(_errors)
