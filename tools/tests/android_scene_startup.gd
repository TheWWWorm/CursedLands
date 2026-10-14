extends Node
## Held Original menu. Use identical game packs and alternate engine runs.
## Clear only the isolated QA shader cache for cold measurements; CPU asset
## caches remain warm. This measures startup/readback, not gameplay FPS.
var view: SubViewport
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2); return
	print("EI_MENU_BENCH_BEGIN")
	seed(0)
	var started := Time.get_ticks_usec()
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "q_aa":0, "q_shadows":0, "volume_sfx":0, "volume_stream":0, "volume_voice":0}, true)
	Gfx._compact_figures = false
	Gfx.ensure_globals(); Gfx.apply_surface_options(); Gfx.set_foliage_wind(false)
	Engine.time_scale = 0
	Engine.max_fps = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = SubViewport.new()
	view.size = Vector2i(640, 480)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var scene := MenuScene.create()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(scene)
	scene.set_hour(12.0)
	scene.camera.current = true
	var built := Time.get_ticks_usec()
	for i in 4: await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var drawn := Time.get_ticks_usec()
	print("EI_MENU_BENCH_END")
	image.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	var pixels_hash := hash.finish().hex_encode()
	image.save_png("user://engine-menu.png")
	var meshes := scene.find_children("*", "MeshInstance3D", true, false).size()
	scene.free(); view.free()
	TexUpscale.shutdown(); UnitWounds.shutdown()
	for i in 4: await RenderingServer.frame_post_draw
	var result := {"checks":3, "failures":int(meshes < 160) + int(image.is_empty()) + int(RenderingServer.get_current_rendering_method() != "gl_compatibility"), "meshes":meshes, "build_ms":float(built-started)/1000, "first_readback_ms":float(drawn-started)/1000, "pixels_sha256":pixels_hash, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://android-scene-startup.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t")+"\n")
	print("EI_ENGINE_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if result.failures == 0 else 1)
