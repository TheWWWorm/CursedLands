extends Node
## Parse AND draw the real composed shaders. Uniform reflection alone does
## not compile a GLES driver program. Run on physical Android with both
## Compatibility and Mobile; a headless run cannot qualify these shaders.
var rows: Array[Dictionary] = []

class Errors extends Logger:
	var messages: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
		mutex.unlock()
	func snapshot() -> Array[String]:
		mutex.lock()
		var copy := messages.duplicate()
		mutex.unlock()
		return copy

var errors := Errors.new()
var logging := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MOBILE_SHADER_SLOTS requires a rendering device")
		get_tree().quit(2)
		return
	OS.add_logger(errors)
	logging = true
	GameData.options.auto_graphics = 0
	GameData.options.merge(GfxDetect.base_values(), true)
	var view := SubViewport.new()
	view.size = Vector2i(320, 240)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	view.add_child(camera)
	camera.make_current()
	var sun := DirectionalLight3D.new()
	view.add_child(sun)
	var draw := MeshInstance3D.new()
	draw.mesh = QuadMesh.new()
	view.add_child(draw)
	var count := 0
	var sources := [
		[EITerrain.TERRAIN_SHADER,true],[EITerrain.WATER_SHADER,true],
		[EITerrain.WATER_FX_SHADER,true],[EIFigure.FOLIAGE_SHADER,false],
		[EIFigure.OBJECT_SHADER,false],[EIUnitModel.UNIT_SHADER,false],
		[TerrainDetails.GRASS_SHADER,true]]
	for fog in [false, true]:
		Gfx._vol_fog = fog
		for row: Array in sources:
			# make_shader() resets _vol_fog from the live option, silently
			# turning the intended fog cases into another no-fog pass.
			var source := String(row[0])
			if Portability.compatibility():
				source = source.replace("instance uniform", "uniform")
			var s := Shader.new()
			s.code = Gfx.compose(source, true, bool(row[1]))
			var uniforms := s.get_shader_uniform_list()
			if uniforms.is_empty():
				push_error("Composed shader failed, case " + str(count))
				get_tree().quit(1)
				return
			if s.code.contains("vec4 ei_fogv") != fog:
				push_error("Requested fog variant missing, case " + str(count))
				get_tree().quit(1)
				return
			var material := ShaderMaterial.new()
			material.shader = s
			var started := Time.get_ticks_msec()
			print("MOBILE_SHADER_DRAW begin=", count, " fog=", fog)
			draw.material_override = material
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			# Readback waits for GPU execution, not just render submission.
			var pixels := view.get_texture().get_image()
			# A failed driver program can still produce a viewport image.
			# Capture rendering-thread errors as well as GDScript failures.
			if not errors.snapshot().is_empty():
				printerr("MOBILE_SHADER_SLOTS render errors, case ", count, ": ", errors.snapshot())
				get_tree().quit(1)
				return
			if pixels == null or pixels.is_empty():
				push_error("Shader draw produced no image, case " + str(count))
				get_tree().quit(1)
				return
			rows.append({"case":count, "fog":fog, "ms":Time.get_ticks_msec()-started})
			print("MOBILE_SHADER_DRAW end=", count)
			count += 1
	Gfx._vol_fog = false
	view.free()
	var result := {"drawn_variants":count, "rows":rows,
		"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open("user://mobile-shader-slots.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("MOBILE_SHADER_SLOTS ", count, " shader variants drawn and read back")
	get_tree().quit()

func _exit_tree() -> void:
	if logging:
		OS.remove_logger(errors)
