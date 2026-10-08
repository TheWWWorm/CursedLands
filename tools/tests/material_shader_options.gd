extends Node
## Compile both option values and fog forms, then switch existing materials.
var checks := 0
var failures := 0
var draw: MeshInstance3D
var render_view: SubViewport
var rendered_variants := 0

func render_shader(shader: Shader) -> void:
	if draw == null: return
	var started := Time.get_ticks_msec()
	rendered_variants += 1
	print("MATERIAL_SHADER_DRAW begin=", rendered_variants, " source_chars=", shader.code.length())
	var material := ShaderMaterial.new()
	material.shader = shader
	draw.material_override = material
	# Shader parsing alone does not exercise a GLES driver's generated program.
	await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	print("MATERIAL_SHADER_DRAW end=", rendered_variants, " elapsed_ms=", Time.get_ticks_msec() - started)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func uniform_names(shader: Shader) -> Array:
	if DisplayServer.get_name() == "headless":
		# Godot's dummy backend retains old uniform metadata on recompilation.
		# Parse a fresh copy here; rendered runs inspect the actual live shader.
		var current := Shader.new()
		current.code = shader.code
		shader = current
	return shader.get_shader_uniform_list().map(func(u): return String(u.name))

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		render_view = SubViewport.new()
		render_view.size = Vector2i(320, 240)
		render_view.own_world_3d = true
		render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(render_view)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 0, 4)
		render_view.add_child(camera); camera.make_current()
		var light := DirectionalLight3D.new()
		render_view.add_child(light)
		draw = MeshInstance3D.new()
		draw.mesh = QuadMesh.new()
		render_view.add_child(draw)
	var sources := [
		[EITerrain.TERRAIN_SHADER, true], [EITerrain.WATER_SHADER, true],
		[EITerrain.WATER_FX_SHADER, true], [EIFigure.FOLIAGE_SHADER, false],
		[EIFigure.OBJECT_SHADER, false], [EIUnitModel.UNIT_SHADER, false],
		[TerrainDetails.GRASS_SHADER, true],
		[EITerrain.TERRAIN_SHADER.replace("shader_type spatial;", "shader_type spatial;\n#define EI_BAKED_TERRAIN"), true],
		[GroundContactShader.source(EIFigure.OBJECT_SHADER), false],
		[GroundContactShader.source(EIFigure.FOLIAGE_SHADER), false],
		[EIFigure.FOLIAGE_STILL_SHADER, false],
		[GroundContactShader.source(EIFigure.FOLIAGE_STILL_SHADER), false]]
	var shaders: Array[Shader] = []
	var materials: Array[ShaderMaterial] = []
	GameData.options["gfx_materials"] = 0
	Gfx.apply_surface_options()
	for row: Array in sources:
		var shader := Gfx.make_shader(row[0], true, row[1])
		shaders.append(shader)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("ei_material_diffuse", Color(.25, .5, .75, 1))
		materials.append(material)
		check(not shader.code.contains("ei_surface_fx.x"), "initial specialization")
	for detail in [1, 0, 1, 0]:
		var before := shaders.map(func(s): return s.code)
		GameData.options["gfx_materials"] = detail
		Gfx.apply_surface_options()
		for i in shaders.size():
			check(shaders[i].code != before[i] and not shaders[i].code.contains("ei_surface_fx.x"), "existing shader recompiles")
			check(materials[i].shader == shaders[i], "material keeps shader identity")
			check(materials[i].get_shader_parameter("ei_material_diffuse") == Color(.25, .5, .75, 1), "material keeps parameters")
			check(not shaders[i].get_shader_uniform_list().is_empty(), "switched real shader compiles")
			await render_shader(shaders[i])
	# Compose directly so both fog forms compile even on renderers where the
	# options UI intentionally disallows volumetric fog.
	for detail in [0, 1]:
		GameData.options["gfx_materials"] = detail
		for fog in [false, true]:
			Gfx._vol_fog = fog
			for row: Array in sources:
				var code: String = row[0]
				if Portability.compatibility(): code = code.replace("instance uniform", "uniform")
				var shader := Shader.new()
				shader.code = Gfx.compose(code, true, row[1])
				check(not shader.get_shader_uniform_list().is_empty(), "detail/fog variant compiles")
				check(shader.code.contains("vec4 ei_fogv") == fog, "requested fog path present")
				await render_shader(shader)
	# Toggle each terrain feature independently on existing ordinary/cached
	# materials. Disabled constants must not strand the live uniforms or
	# their per-sector values when the player restores the option.
	for mask in [0, 1, 3, 2, 6, 7, 5, 4, 0]:
		GameData.options.gfx_terrain = mask & 1
		GameData.options.gfx_soft_ground = (mask >> 1) & 1
		GameData.options.gfx_weather_surfaces = (mask >> 2) & 1
		Gfx.apply_surface_options()
		for i in [0, 7]:
			var material := materials[i]
			material.set_shader_parameter("detail", 1.0)
			material.set_shader_parameter("soft_ground", true)
			material.set_shader_parameter("soft_tracks", true)
			var uniforms := uniform_names(shaders[i])
			check(uniforms.has("detail") == bool(mask & 1), "terrain detail restores its live uniform")
			check(uniforms.has("soft_ground") == bool(mask & 2), "deformation restores its live uniform")
			check(uniforms.has("soft_tracks") == bool(mask & 2), "tracks restore their per-sector uniform")
			check(material.shader == shaders[i] and material.get_shader_parameter("detail") == 1.0 \
				and material.get_shader_parameter("soft_tracks") == true, "terrain switch retains material and values")
			check(shaders[i].code.contains("ei_surface_fx.z") == bool(mask & 4), "weather can be toggled independently")
			await render_shader(shaders[i])
	Gfx._specialize_materials = false
	Gfx.apply_surface_options()
	for shader in shaders:
		check(shader.code.contains("ei_surface_fx.x"), "dynamic diagnostic fallback restored")
		check(not shader.get_shader_uniform_list().is_empty(), "dynamic fallback compiles")
		await render_shader(shader)
	for i in [0, 7]:
		var uniforms := uniform_names(shaders[i])
		check(uniforms.has("detail") and uniforms.has("soft_ground") and uniforms.has("soft_tracks"), "dynamic terrain fallback restores every option")
	print("MATERIAL_SHADER_OPTIONS checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
