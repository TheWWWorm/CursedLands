extends "res://tools/tests/shader_line_endings.gd"
const SceneRaytraceShader = preload("res://src/game/fx/scene_raytrace_shader.gd")
## Cold compilation of the reported all-effects foliage, including the ground
## contact variants used by both the menu and campaign trees.
func _run() -> void:
	OS.add_logger(errors)
	GameData.options.merge(GfxDetect.base_values(), true)
	GameData.options.merge({"gfx_materials":1, "gfx_wind":1, "gfx_terrain":2,
		"gfx_foliage_light":1, "gfx_ground_contact":1, "gfx_terrain_cliffs":1,
		"gfx_clouds":3, "gfx_cloud_shadows":1, "gfx_volumetric":1,
		"gfx_soft_ground":1, "gfx_weather_surfaces":1, "pt_mode":2}, true)
	check(RenderingServer.get_current_rendering_method() == "forward_plus", "real Forward+ compiler")
	check(SceneRaytraceShader.applicable(EIFigure.FOLIAGE_SHADER, true), "RT/PT shader injection is active")
	view = SubViewport.new()
	view.size = Vector2i(256, 256)
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
	for fog: bool in [false, true]:
		Gfx._vol_fog = fog
		for still: bool in [false, true]:
			for contact: bool in [false, true]:
				for cliffs: bool in [false, true]:
					var source := EIFigure.FOLIAGE_STILL_SHADER if still else EIFigure.FOLIAGE_SHADER
					if contact: source = GroundContactShader.source(source, cliffs)
					if contact and cliffs:
						# Authored terrain transitions insert helper functions before
						# the contact declarations, as on the reported menu island.
						source = preload("res://src/game/fx/terrain_transition_shader.gd").source(source, true)
					for windows: bool in [false, true]:
						var label := "fog=%s still=%s contact=%s cliffs=%s crlf=%s" % [fog, still, contact, cliffs, windows]
						var shader := Shader.new()
						shader.code = Gfx.compose(source.replace("\n", "\r\n") if windows else source)
						var uniforms := shader.get_shader_uniform_list()
						check(not uniforms.is_empty(), "compiles " + label)
						if uniforms.is_empty(): continue
						var material := ShaderMaterial.new()
						material.shader = shader
						draw.material_override = material
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						check(not view.get_texture().get_image().is_empty(), "draw completes " + label)
	Gfx._vol_fog = false
	view.free()
	check(errors.count() == 0, "no shader errors with all effects enabled")
	OS.remove_logger(errors)
	print("FOLIAGE_FEATURE_COMBINATIONS checks=", checks, " failures=", failures, " errors=", errors.count())
	get_tree().quit(1 if failures else 0)
