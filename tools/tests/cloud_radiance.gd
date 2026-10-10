extends "water_interaction.gd"
## Rendered consumer checks for the optional volume radiance optimization.
const Clouds = preload("res://src/game/fx/clouds.gd")

func capture(view: SubViewport, label: String) -> Image:
	await frames(48)
	var image := view.get_texture().get_image()
	check(image.save_png("user://cloud-radiance-" + label + ".png") == OK, "capture " + label)
	return image

func compare(view: SubViewport, sky: ShaderMaterial, env: Environment, label: String, needed: bool) -> void:
	EISky.update(sky, null, 12, false, true, env)
	check(sky.get_shader_parameter("cloud_radiance") == needed, "live environment policy " + label)
	var automatic := await capture(view, label + "-auto")
	sky.set_shader_parameter("cloud_radiance", true)
	var complete := await capture(view, label + "-complete")
	var delta := difference(automatic, complete)
	rows.append({"case":label, "difference":delta})
	check(delta.changed_pixels == 0, "full radiance preserves presented pixels " + label)
	if needed:
		# Demonstrate that removing this consumer's radiance really is visible.
		sky.set_shader_parameter("cloud_radiance", false)
		var unsafe := await capture(view, label + "-unsafe-control")
		var control := difference(complete, unsafe)
		rows.append({"case":label + "-unsafe-control", "difference":control})
		check(control.pixels_over_2 > 20, "consumer detects missing cloud radiance " + label)
	EISky.update(sky, null, 12, false, true, env)
	var restored := await capture(view, label + "-restored")
	var restoration := difference(automatic, restored)
	rows.append({"case":label + "-restored", "difference":restoration})
	check(restoration.changed_pixels == 0, "live policy restores presented pixels " + label)

func policy() -> void:
	var env := Environment.new()
	Gfx.setup_original_env(env)
	check(not EISky.radiance_needed(env), "original colour ambient consumes no radiance")
	check(EISky.radiance_needed(null), "unknown environments retain full radiance")
	for source in [Environment.AMBIENT_SOURCE_BG, Environment.AMBIENT_SOURCE_SKY]:
		env.ambient_light_source = source
		check(EISky.radiance_needed(env), "sky-capable ambient retains radiance")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	check(not EISky.radiance_needed(env), "disabled ambient consumes no radiance")
	env.sdfgi_enabled = true
	check(EISky.radiance_needed(env), "GI retains radiance")

func scene() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.current = true
	camera.position = Vector3(100, 10, -100); camera.rotation_degrees.x = 4
	var env := Environment.new(); Gfx.setup_original_env(env); Gfx.setup_volumetric(env)
	# Original scenes set this from the regional light table. The engine's
	# specular occlusion suppresses reflections with the default black ambient.
	env.ambient_light_color = Color(.3,.3,.3)
	env.background_mode = Environment.BG_SKY; env.fog_enabled = false
	env.sky = Sky.new(); env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var sky := EISky.material(false); env.sky.sky_material = sky
	var world_env := WorldEnvironment.new(); world_env.environment = env; view.add_child(world_env)
	var sphere := MeshInstance3D.new(); sphere.mesh = SphereMesh.new()
	sphere.position = camera.position + Vector3(0, -0.3, -4); sphere.scale = Vector3.ONE * 2
	var material := StandardMaterial3D.new(); material.metallic = 1; material.roughness = 0.2
	sphere.material_override = material; view.add_child(sphere)
	var wall := MeshInstance3D.new(); wall.mesh = BoxMesh.new()
	wall.position = camera.position + Vector3(0, 0, -40); wall.scale = Vector3(100, 100, 1)
	wall.material_override = StandardMaterial3D.new(); wall.visible = false; view.add_child(wall)
	var field := Clouds.new()
	field.sample(0, "bz2g", "Ingos", Vector4(.7,-.7,.8,.3), 0, 1, 12, false)
	Gfx.set_cloud_frame(view.get_instance_id(), field.sample(120, "bz2g", "Ingos", Vector4(.7,-.7,.8,.3), 0, 1, 12, false))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", Vector3(.3,.9,.2).normalized())
	for quality in [2,3]:
		GameData.options.gfx_clouds = quality; Gfx.apply_surface_options()
		await compare(view, sky, env, "background-" + str(quality), false)
	# Exercise actual sky reflection and ambient consumers, then both fog paths.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	await compare(view, sky, env, "reflection", true)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	material.metallic = 0; material.roughness = 1
	await compare(view, sky, env, "ambient", true)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	wall.visible = true; sphere.visible = false
	env.fog_enabled = true; env.fog_depth_begin = 0; env.fog_depth_end = 40; env.fog_aerial_perspective = 1
	await compare(view, sky, env, "aerial", true)
	env.fog_enabled = false; env.fog_aerial_perspective = 0
	env.volumetric_fog_enabled = true; env.volumetric_fog_density = .025
	env.volumetric_fog_temporal_reprojection_enabled = false
	env.volumetric_fog_ambient_inject = 1
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		await compare(view, sky, env, "volumetric", true)
	else:
		check(EISky.radiance_needed(env), "unsupported fog remains conservatively guarded")
	env.volumetric_fog_enabled = false; wall.visible = false; sphere.visible = true
	await compare(view, sky, env, "background-return", false)
	EISky.update(sky, null, 12, false, true)
	check(sky.get_shader_parameter("cloud_radiance") == true, "caller without environment restores complete radiance")
	view.free(); Gfx.clear_clouds(); await frames(8)

func menu_scene() -> void:
	var view := SubViewport.new(); view.size = Vector2i(1280,720)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var menu := MenuScene.create()
	check(menu != null, "actual menu created")
	if menu == null: view.free(); return
	view.add_child(menu); menu.set_process(false); menu.set_hour(12)
	menu._player.pause(); menu.camera.current = true; menu.rain_bit = false
	check(menu._sky.get_shader_parameter("cloud_radiance") == false, "menu passes its own environment")
	var automatic := await capture(view, "menu-auto")
	menu._sky.set_shader_parameter("cloud_radiance", true)
	var complete := await capture(view, "menu-complete")
	var delta := difference(automatic, complete)
	rows.append({"case":"menu", "difference":delta})
	check(delta.changed_pixels == 0, "actual menu retains all presented pixels")
	menu.set_hour(12)
	check(menu._sky.get_shader_parameter("cloud_radiance") == false, "menu daylight update restores its environment policy")
	view.free(); Gfx.clear_clouds(); await frames(8)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_clouds":3, "q_aa":0, "auto_graphics":0, "confine_mouse":0, "vsync":0, "fps_limit":0}, true)
	Gfx.ensure_globals(); Gfx.apply_surface_options(); Engine.time_scale = 0
	Engine.max_fps = 0; process_mode = Node.PROCESS_MODE_ALWAYS
	policy()
	if DisplayServer.get_name() != "headless" and Clouds.mode() >= 2:
		await scene()
		await menu_scene()
	Gfx.clear_clouds(); TexUpscale.shutdown(); UnitWounds.shutdown()
	FileAccess.open("user://cloud-radiance.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("CLOUD_RADIANCE checks=",checks," failures=",failures)
	get_tree().quit(int(failures > 0))
