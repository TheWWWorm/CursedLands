extends Node
## Exercise the actual shader compiler with Unix and Windows source strings.
## Run through --tool with a real renderer to cover driver compilation too.
var checks := 0
var failures := 0

class Errors extends Logger:
	var messages: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING: return
		mutex.lock()
		messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
		mutex.unlock()
	func count() -> int:
		mutex.lock()
		var result := messages.size()
		mutex.unlock()
		return result

var errors := Errors.new()
var view: SubViewport
var draw: MeshInstance3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "display_mode":0}, true)
	_run.call_deferred()

func _run() -> void:
	OS.add_logger(errors)
	GameData.options.auto_graphics = 0
	GameData.options.merge(GfxDetect.base_values(), true)
	if DisplayServer.get_name() != "headless":
		view = SubViewport.new()
		view.size = Vector2i(128, 128)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 0, 4)
		view.add_child(camera)
		camera.make_current()
		view.add_child(DirectionalLight3D.new())
		draw = MeshInstance3D.new()
		draw.mesh = QuadMesh.new()
		view.add_child(draw)
	var sources := [
		["terrain", EITerrain.TERRAIN_SHADER, true],
		["water", EITerrain.WATER_SHADER, true],
		["enhanced water", EITerrain.WATER_FX_SHADER, true],
		["foliage", EIFigure.FOLIAGE_SHADER, false],
		["still foliage", EIFigure.FOLIAGE_STILL_SHADER, false],
		["object", EIFigure.OBJECT_SHADER, false],
		["unit", EIUnitModel.UNIT_SHADER, false],
		["grass", TerrainDetails.GRASS_SHADER, true],
		["ground contact", GroundContactShader.source(EIFigure.OBJECT_SHADER), false]]
	var fog_modes := [false, true] if RenderingServer.get_current_rendering_method() == "forward_plus" else [false]
	for fog: bool in fog_modes:
		Gfx._vol_fog = fog
		for row: Array in sources:
			var unix := String(row[1]).replace("\r\n", "\n")
			if Portability.compatibility(): unix = unix.replace("instance uniform", "uniform")
			var reference_uniforms: Array = []
			for windows: bool in [false, true]:
				var label := "%s fog=%s crlf=%s" % [row[0], fog, windows]
				var source := unix.replace("\n", "\r\n") if windows else unix
				var shader := Shader.new()
				shader.code = Gfx.compose(source, true, row[2])
				var uniforms := shader.get_shader_uniform_list().map(func(u): return String(u.name))
				check(not uniforms.is_empty(), "compiles " + label)
				if not windows: reference_uniforms = uniforms
				else: check(uniforms == reference_uniforms, "same uniform interface " + label)
				if draw and not uniforms.is_empty():
					var material := ShaderMaterial.new()
					material.shader = shader
					draw.material_override = material
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var pixels := view.get_texture().get_image()
					check(pixels != null and not pixels.is_empty(), "draw completes " + label)
	Gfx._vol_fog = false
	if view: view.free()
	check(errors.count() == 0, "no shader or script errors")
	OS.remove_logger(errors)
	print("SHADER_LINE_ENDINGS checks=", checks, " failures=", failures, " errors=", errors.count())
	get_tree().quit(1 if failures else 0)
