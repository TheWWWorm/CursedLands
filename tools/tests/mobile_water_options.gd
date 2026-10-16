extends Node
## Exercise retained water materials while scene reflections are disabled,
## restored and switched between Natural/Mirror. Requires real Mobile draws.
var checks := 0
var failures := 0
var rendered := 0
var uniform_cache := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 6) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func sampler_names(shader: Shader) -> Array:
	# Renderer-owned screen/depth samplers are deliberately excluded from
	# Godot's editable uniform metadata. Parse an inspection-only copy with
	# ordinary samplers to verify which declarations survive preprocessing.
	# The GPU draws below always use the untouched production shader.
	var key := shader.code.sha256_text()
	if not uniform_cache.has(key):
		var probe := Shader.new()
		probe.code = shader.code.replace("hint_screen_texture, ","").replace("hint_depth_texture, ","")
		uniform_cache[key] = probe.get_shader_uniform_list().map(func(u): return String(u.name))
	return uniform_cache[key]

func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		printerr("MOBILE_WATER_OPTIONS requires the Mobile renderer"); get_tree().quit(2); return
	GameData.options.merge(GfxPresets.values(GfxPresets.MEDIUM),true)
	GameData.options.gfx_water_reflections = 0
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	var view := SubViewport.new(); view.size = Vector2i(320,240); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position.z = 4; camera.current = true
	var sun := DirectionalLight3D.new(); view.add_child(sun)
	var draw := MeshInstance3D.new(); draw.mesh = QuadMesh.new(); view.add_child(draw)
	var base := EITerrain.WATER_FX_SHADER
	var current: String = EITerrain.WaterCurrentShader.source(base)
	var contact: String = EITerrain.WaterInteractionShader.source(base)
	var running: String = EITerrain.WaterInteractionShader.source(current,true)
	var sources := [base,contact,current,running,EITerrain.WaterWaveShader.source(contact),EITerrain.WaterWaveShader.source(running)]
	var materials: Array[ShaderMaterial] = []
	var shaders: Array[Shader] = []
	for source: String in sources:
		var shader := Gfx.make_shader(source,true,true); shaders.append(shader)
		var material := ShaderMaterial.new(); material.shader = shader; materials.append(material)
		material.set_shader_parameter("wave_ticks",17.25)
		var opacity := PackedFloat32Array(); opacity.resize(64); opacity.fill(.7)
		material.set_shader_parameter("mat_a",opacity)
	# Sheet and volume cloud consumers must retain their sky reflection when
	# the separate scene-reflection option is off.
	for cloud in [0,1,2]:
		GameData.options.gfx_clouds = cloud
		GameData.options.gfx_cloud_reflections = int(cloud > 0)
		for reflection in [0,1,2,0,2,1,0]:
			GameData.options.gfx_water_reflections = reflection
			Gfx.apply_surface_options()
			for i in materials.size():
				var material := materials[i]; var shader := shaders[i]
				material.set_shader_parameter("reflections",reflection > 0)
				material.set_shader_parameter("mirror",float(reflection == 2))
				var names := sampler_names(shader)
				check(names.has("screen_tex") == (reflection > 0),"scene colour dependency follows option")
				check(names.has("depth_tex"),"shore depth retained")
				check(shader.code.contains("hint_screen_texture, filter_linear;"),"level-zero reflection avoids unused screen mips")
				check(shader.code.contains("#define EI_NO_WATER_REFLECTIONS") == (reflection == 0),"intended reflection program")
				check(material.shader == shader and material.get_shader_parameter("wave_ticks") == 17.25,"shader identity and live water clock retained")
				draw.material_override = material; await frames(); rendered += 1
			var before := shaders.map(func(s): return s.code)
			Gfx.apply_surface_options()
			check(before == shaders.map(func(s): return s.code),"unchanged options retain programs")
		print("WATER_OPTIONS_PROGRESS clouds=",cloud," rendered=",rendered)
	Gfx._specialize_materials = false; Gfx.apply_surface_options()
	for i in shaders.size():
		check(not shaders[i].code.contains("#define EI_NO_WATER_REFLECTIONS"),"dynamic fallback restores original program")
		check(sampler_names(shaders[i]).has("screen_tex"),"dynamic fallback restores screen sampler")
		draw.material_override = materials[i]; await frames(); rendered += 1
	view.free(); TexUpscale.shutdown()
	FileAccess.open("user://mobile-water-options.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"draw_variants":rendered},"\t"))
	print("MOBILE_WATER_OPTIONS checks=",checks," failures=",failures," draw_variants=",rendered)
	get_tree().quit(int(failures > 0))
