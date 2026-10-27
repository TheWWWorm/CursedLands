extends "res://tools/tests/shader_line_endings.gd"
func _run() -> void:
	OS.add_logger(errors)
	for key in ["hd_textures","materials","sharp_units","detailed_heads","sky","far_view","wind","grass","biome_cover","vegetation_interaction","soft_ground","ground_contact","terrain_cliffs","firelight","torch_glow","lava_light","foliage_light","volumetric","ssao","contact_shadows","bloom","depth_of_field","water","water_reflections","water_interaction","water_caustics","water_current","water_waves","waterfalls","ambient_wildlife","ambient_particles","cloud_shadows","cloud_reflections","weather_mist","weather_surfaces","heat_haze","soft_particles","lit_particles","severed_limbs","rain_puddles"]:
		GameData.options["gfx_"+key] = 1
	GameData.options.merge({"gfx_terrain":2,"gfx_clouds":3,"pt_mode":2,"pt_accumulation":0,"pt_sharc":0,"pt_target_fps":0,"q_aa":3,"q_shadows":3,"q_aniso":4},true)
	var menu := MenuScene.create()
	check(menu != null, "actual all-effects menu loads")
	if menu:
		add_child(menu); menu.set_hour(12.0)
		for i in 30: await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		check(image.save_png("user://all-effects-menu.png") == OK, "menu pixels retained")
		var shaders := {}
		for child in menu.find_children("*", "MeshInstance3D",true,false):
			var mat: Material = child.material_override
			if mat is ShaderMaterial and not shaders.has(mat.shader.get_instance_id()):
				shaders[mat.shader.get_instance_id()]=true
				check(not mat.shader.get_shader_uniform_list().is_empty(), "menu material compiles")
				if mat.shader.code.contains("#define EI_FOLIAGE_WIND"):
					FileAccess.open("user://foliage-%d.gdshader" % shaders.size(),FileAccess.WRITE).store_string(mat.shader.code)
		menu.free()
	check(errors.count()==0,"no shader errors in actual menu")
	OS.remove_logger(errors)
	print("FOLIAGE_ALL_EFFECTS_SCENE checks=",checks," failures=",failures," errors=",errors.count())
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
