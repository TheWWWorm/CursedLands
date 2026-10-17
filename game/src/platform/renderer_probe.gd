extends Node
## Isolated early-entry process. Autoloads explicitly skip initialization for
## --renderer-probe, and --log-file keeps the player's session log untouched.
var output := ""
var token := ""
var expected := ""

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): output = arg.trim_prefix("--probe-output=")
		if arg.begins_with("--probe-token="): token = arg.trim_prefix("--probe-token=")
		if arg.begins_with("--probe-driver="): expected = arg.trim_prefix("--probe-driver=")
	if not OS.get_cmdline_user_args().has("--renderer-probe") or output.is_empty() or token.is_empty():
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var root := get_tree().root
	var raw_driver := RenderingServer.get_current_rendering_driver_name()
	var driver := "opengl3" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else raw_driver
	if DisplayServer.get_name() == "headless" or driver != expected:
		get_tree().quit(3)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(320, 200)
	root.content_scale_size = Vector2i(320, 200)
	RenderingServer.directional_shadow_atlas_set_size(512, true)
	root.title = "Cursed Lands"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.2, 4)
	camera.look_at(Vector3.ZERO)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.02, 0.04, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.4
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.9, 0.2)
	mesh.material_override = material
	world.add_child(mesh)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.scale = Vector3(4, 1, 4)
	floor_mesh.position.y = -0.7
	world.add_child(floor_mesh)
	# Exercise submitted 3D frames, shadow pipelines and a GPU readback.
	for frame in 48:
		mesh.rotation.y += 0.04
		await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	if pixels == null or pixels.is_empty():
		get_tree().quit(4)
		return
	var center := pixels.get_pixel(pixels.get_width() / 2, pixels.get_height() / 2)
	if center.g < center.r + 0.05 or center.g < center.b + 0.05:
		get_tree().quit(5)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		get_tree().quit(6)
		return
	file.store_string(JSON.stringify({"token": token, "driver": driver, "actual_driver": raw_driver, "frames": 48, "rendered": true}))
	file.close()
	get_tree().quit(0)
