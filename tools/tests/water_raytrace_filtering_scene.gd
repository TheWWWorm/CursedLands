extends "res://tools/tests/water_raytrace_live.gd"
## Exercise the real river controller and existing Texture filtering setting.
## The baseline flag captures the same view with the previous shader package.
func settle_window() -> void:
	# X11 may finish reframing the native window after the first ready frames.
	# Compare filtering at one size, rather than accidentally comparing FOVs.
	Engine.max_fps = 60
	await get_tree().create_timer(0.2,true,false,true).timeout
	get_window().borderless = true
	get_window().size = Vector2i(1280,720)
	await get_tree().create_timer(0.2,true,false,true).timeout
	check(Vector2i(get_viewport().get_visible_rect().size) == Vector2i(1280,720),"river viewport settles to 1280x720")

func run() -> void:
	var context := await setup()
	await settle_window()
	var baseline := OS.get_cmdline_user_args().has("--baseline-filtering")
	GameData.options.gfx_water_reflections = 3
	GameData.options.q_water_rt_quality = 2
	GameData.options.q_aniso = 4
	t.apply_gfx()
	check(await ready_rt(),"real river prepares hardware RT")
	if not t._reflection._rt_ready: get_tree().quit(1); return
	var owner: Object = t._reflection._rt_live
	var target: RID = t._reflection._rt.output.texture_rd_rid
	var material_texture: Texture2D = t._water_mat.get_shader_parameter("planar_texture")
	var sharp := await reflected("river-reflection-16x")
	await shot("river-water-16x")
	check(sharp.get_size() == Vector2i(1280,720),"High uses the full river viewport")
	var changed := 0
	if not baseline:
		check(t._reflection.rt_stats.texture_anisotropy == 16,"real controller selects 16x texture filtering")
		# Apply through the public settings path, then let its window/layout
		# notifications settle before comparing the same-sized reflection.
		GameData.set_option("q_aniso",0)
		await settle_window()
		var off := await reflected("river-reflection-off")
		await shot("river-water-off")
		check(off.get_size() == sharp.get_size(),"filtering retains the reflection resolution")
		if off.get_size() == sharp.get_size(): changed = difference(sharp,off)
		check(changed > 100,"Texture filtering changes visible river reflection detail")
		check(t._reflection.rt_stats.texture_anisotropy == 1,"real controller applies Texture filtering Off")
		GameData.set_option("q_aniso",4)
		await settle_window()
		var restored := await reflected("river-reflection-restored")
		check(restored.get_data() == sharp.get_data(),"restoring 16x reproduces the frozen river reflection")
		check(t._reflection._rt_live == owner,"filtering changes retain the river geometry snapshot")
		check(t._reflection._rt.output.texture_rd_rid == target,"filtering changes retain the GPU image")
		check(t._water_mat.get_shader_parameter("planar_texture") == material_texture,"water keeps its bound reflection texture")
	FileAccess.open(out.path_join("filtering-scene.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"baseline":baseline,"changed_pixels":changed,"stats":t._reflection.rt_stats},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
