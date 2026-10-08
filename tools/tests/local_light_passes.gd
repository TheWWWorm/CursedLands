extends "local_shadow_fades.gd"
## Actual composed shaders, not an injected copy of the correction. The same
## tool can run on a frozen export as a negative control. --light-pass-cost
## measures viewport submission/GPU time in a larger controlled fill workload;
## it is not a whole-game or physical-mobile benchmark.

var cost_mode := false
var rows := []

func pass_fixture(situation: String) -> Dictionary:
	var f := rendered_fixture()
	if situation == "small-atlas":
		f.view.positional_shadow_atlas_size = 1024
	var source := EIFigure.OBJECT_SHADER
	if situation.begins_with("emission"):
		source = source.replace("ROUGHNESS = 1.0;", "ROUGHNESS = 1.0; EMISSION = vec3(0.3, 0.01, 0.2);")
	if situation == "transparent":
		source = source.replace("ALPHA_SCISSOR_THRESHOLD = 0.5;", "ALPHA = 0.55;")
	var terrain := situation == "terrain-lighting"
	if terrain:
		source = source.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_LIGHT")
	var shader := Gfx.make_shader(source, true, terrain)
	for n: Node in f.view.get_children():
		if n is MeshInstance3D:
			var material := n.material_override as ShaderMaterial
			material.shader = shader
			if situation == "surface":
				material.set_shader_parameter("surface_profile", Vector4(0.8, 0.35, 0.6, 0))
		if n is WorldEnvironment and situation == "glow":
			n.environment.glow_enabled = true
		if n is DirectionalLight3D and situation == "sun-shadow":
			n.shadow_enabled = true
			Gfx.sync_sun_pass(n)
	if situation in ["fog", "emission-fog"]:
		RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(2, 14, 0))
	elif situation == "fog-full":
		RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(1, 2, 0))
	elif situation == "fog-dense":
		RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(1, 8.5, 0))
	elif situation == "fog-bright-edge":
		RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(1, 8.005, 0))
		f.pair[0].light_energy = 12.0
	if situation in ["single", "no-local"]:
		for record: Dictionary in f.fx.lights:
			record.light.visible = situation == "single" and record.light == f.pair[0]
	if situation.begins_with("original"):
		var original := OmniLight3D.new()
		original.light_specular = 0.0
		original.light_energy = 0.7
		original.light_color = Color(0.2, 0.5, 1.0)
		original.position = Vector3(-1, 1, 3)
		original.omni_attenuation = 0.0
		original.omni_range = 10
		if situation == "original-far":
			original.omni_range = 30
			original.position = Vector3(1, 1, 1.1)
			original.light_energy = 3.0
		f.world.add_child(original)
	if situation == "crowded":
		for x in 8:
			var light := fire(f, Vector3(-3.5 + x, 0.5, 2.5))
			light.light_energy = 0.04 + x * 0.01
			light.omni_attenuation = 0.0
	scan(f, 0, -2)
	# Test one flag boundary without changing any other light between images.
	# Keep <= 3 other flags even when the crowded scene selects another set.
	var others := 0
	for d: Dictionary in f.fx.lights:
		if d.light != f.pair[0] and d.light.shadow_enabled:
			others += 1
			if others > 3:
				Gfx.set_local_shadow(d.light, false)
	return f

func timing(view: SubViewport) -> Dictionary:
	view.size = Vector2i(1280, 960)
	var rid := view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var old_loop := RenderingServer.is_render_loop_enabled()
	RenderingServer.set_render_loop_enabled(false)
	var old_fps := Engine.max_fps
	Engine.max_fps = 0
	var old_vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var wall: Array[float] = []
	# A minimized X11 window suppresses automatic drawing. This static shader
	# workload needs no frame-count-dependent occlusion: explicitly submit each
	# frame and sample its viewport timers, not process-loop/wall-clock FPS.
	for i in 160:
		await get_tree().process_frame
		var started := Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		var elapsed := Time.get_ticks_usec() - started
		if i >= 64:
			wall.append(elapsed / 1000.0)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	cpu.sort()
	gpu.sort()
	wall.sort()
	Engine.max_fps = old_fps
	DisplayServer.window_set_vsync_mode(old_vsync)
	RenderingServer.set_render_loop_enabled(old_loop)
	RenderingServer.viewport_set_measure_render_time(rid, false)
	check(cpu[cpu.size() / 2] > 0 and gpu[gpu.size() / 2] > 0, "viewport cost timers contain rendered samples")
	return {"cpu_median_ms": cpu[cpu.size() / 2], "gpu_median_ms": gpu[gpu.size() / 2],
			"force_draw_median_ms": wall[wall.size() / 2], "samples": cpu.size(), "forced_draws": 160,
			"draw_calls": view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires a rendered viewport.")
		get_tree().quit(1)
		return
	GameData.options["gfx_firelight"] = 1
	GameData.options["gfx_lava_light"] = 1
	GameData.options["vsync"] = 0
	GameData.options["fps_limit"] = 0
	cost_mode = OS.get_cmdline_user_args().has("--light-pass-cost")
	var situations := ["single", "five", "sun-shadow", "fog", "surface", "crowded", "original",
			"emission", "fog-full", "fog-dense", "fog-bright-edge", "emission-fog", "original-far", "transparent", "glow", "no-local", "terrain-lighting", "small-atlas"]
	if cost_mode:
		situations = ["no-local", "five", "crowded", "fog"]
	for situation: String in situations:
		var f := pass_fixture(situation)
		f.pair[0].shadow_opacity = 0.0
		Gfx.set_local_shadow(f.pair[0], true)
		var row := {"situation": situation}
		if cost_mode:
			print("LOCAL_LIGHT_PASS_COST begin=", situation)
			row["timing"] = await timing(f.view)
		else:
			var zero := await capture(f.view, "pass-" + situation + "-zero")
			Gfx.set_local_shadow(f.pair[0], false)
			var disabled := await capture(f.view, "pass-" + situation + "-disabled")
			row.merge(delta(zero, disabled))
			check(row.max_channel_delta <= 2, "%s pass boundary stays within output quantization" % situation)
		rows.append(row)
		print("LOCAL_LIGHT_PASS_ROW ", JSON.stringify(row))
		dispose(f)
		f.view.free()
		RenderingServer.global_shader_parameter_set(&"ei_sun_pass", Vector3.ZERO)
	var report := {"checks": checks, "failures": failures, "rows": rows, "cost_mode": cost_mode,
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
			"light_limit": ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object"),
			"adapter": RenderingServer.get_video_adapter_name()}
	var path := "user://local-light-passes-" + RenderingServer.get_current_rendering_method() + ("-cost" if cost_mode else "") + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	else:
		check(false, "pass report saved")
	print("LOCAL_LIGHT_PASSES ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
