extends "ground_contact.gd"
## Cold view initialization must match the renderer settings established by
## opening a campaign. Use pixels so a missing quality application is observable.
func _ready() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA), true)
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0}, true)
	for i in 24: await get_tree().process_frame
	var view := SubViewport.new(); view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	var camera := Camera3D.new(); view.add_child(camera)
	camera.position = Vector3(3, 3, 4); camera.look_at(Vector3.ZERO); camera.current = true
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	var env := environment.environment
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.7
	env.ssao_enabled = true; env.ssao_radius = 1.1; env.ssao_intensity = 0.8
	view.add_child(environment)
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.65, 0.7, 0.8)
	for bounds: AABB in [AABB(Vector3(-4,-0.2,-4),Vector3(8,0.2,8)),
			AABB(Vector3(-1,0,-0.7),Vector3(1,1.6,1)), AABB(Vector3(0.4,0,-0.2),Vector3(0.4,0.7,1.8))]:
		var node := MeshInstance3D.new(); var mesh := BoxMesh.new()
		mesh.size = bounds.size; node.mesh = mesh; node.position = bounds.get_center()
		node.material_override = material; view.add_child(node)
	# Deliberately start from engine defaults, as a direct arena launch did.
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, false, 0.5, 2, 50.0, 300.0)
	var engine_default := await capture(view)
	Gfx.apply_quality(view)
	var cold := await capture(view)
	# A detached environment exercises the campaign's global initialization
	# without changing this fixture's lights, enabled effects or materials.
	Gfx.apply_env(Environment.new())
	var after_campaign := await capture(view)
	var area := Rect2i(0, 0, SIZE, SIZE)
	var history_difference := compare(cold, after_campaign, area)
	check(history_difference.peak <= 1.0/255.0, "cold view matches the campaign-initialized renderer: " + str(history_difference))
	var default_difference := compare(cold, engine_default, area)
	check(default_difference.peak > 1.0/255.0, "fixture detects the old engine-default SSAO path")
	check(view.msaa_3d == Viewport.MSAA_4X and is_equal_approx(view.scaling_3d_scale, 1.0), "native resolution and Ultra antialiasing stay enabled")
	check(env.ssao_enabled and is_equal_approx(env.ssao_intensity, 0.8), "view effect enablement and strength stay owned by the view")
	Gfx.apply_quality(view)
	var repeated := await capture(view)
	check(compare(cold, repeated, area).peak <= 1.0/255.0, "reapplying quality does not change the image")
	cold.save_png("user://arena-effect-quality-cold.png")
	after_campaign.save_png("user://arena-effect-quality-after-campaign.png")
	FileAccess.open("user://arena-effect-quality.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"history_difference":history_difference,"engine_default_difference":default_difference,"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	view.free()
	print("ARENA_EFFECT_QUALITY ", checks, " checks; failures=", failures)
	TexUpscale.shutdown(); get_tree().quit(int(failures > 0))
