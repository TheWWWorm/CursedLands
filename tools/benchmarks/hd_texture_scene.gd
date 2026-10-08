extends Node
## Frozen real-map HD scenery comparison. Run against both exported packs.
## No gameplay simulation or local effects; timing is not an FPS claim.
var checks := 0
var failures := 0
var map_name := "bz2g"
var rows := []
var gpu_script: Script

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func texture_stats() -> Dictionary:
	var resident := 0; var ordinary := 0; var payload := 0
	for texture: Texture2D in Gfx._hd.values():
		if texture == null: continue
		resident += int(texture is Texture2DRD); ordinary += int(texture is ImageTexture)
		var w := texture.get_width(); var h := texture.get_height()
		while true:
			payload += w*h*4
			if w == 1 and h == 1: break
			w = maxi(1,w>>1); h = maxi(1,h>>1)
	return {"resident_textures":resident,"image_textures":ordinary,"rgba_mip_payload_bytes":payload}

func focus(map: EIMapScene) -> Vector3:
	var density := {}
	for object: Node3D in map.object_nodes:
		var record: Dictionary = object.get_meta("ei")
		if record.kind != "OBJECT" or record.template.begins_with("ef"): continue
		for mesh: MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null: continue
			var cell := Vector2i(floori(mesh.global_position.x/16.0),floori(mesh.global_position.z/16.0))
			density[cell] = int(density.get(cell,0))+1
	var best := Vector2i.ZERO; var count := 0
	for cell: Vector2i in density:
		if density[cell] > count: best = cell; count = density[cell]
	var x := best.x*16.0+8.0; var z := best.y*16.0+8.0
	return Vector3(x,map.terrain.height_at(x,-z),z)

func _ready() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hd-map="): map_name = arg.trim_prefix("--hd-map=")
	for key: String in ["gfx_volumetric","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_wind","gfx_water","gfx_weather_surfaces","gfx_heat_haze","gfx_torch_glow","confine_mouse","vsync"]:
		GameData.options[key] = 0
	GameData.options["gfx_hd_textures"] = 1
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals(); EIFigure.set_wind(false)
	if ResourceLoader.exists("res://src/game/tex_upscale_texture.gd"):
		gpu_script = load("res://src/game/tex_upscale_texture.gd")
	var view := SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var start := Time.get_ticks_usec()
	var map := EIMapScene.load_map(map_name,map_name,false)
	var loading_us := Time.get_ticks_usec()-start
	check(map != null,"authored map loads")
	if map == null: get_tree().quit(1); return
	map.process_mode = Node.PROCESS_MODE_DISABLED; view.add_child(map)
	var center := focus(map)
	var camera := Camera3D.new(); camera.far = 150; camera.fov = CameraRig.MODERN_FOV
	view.add_child(camera); camera.current = true
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment); view.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.3,0.3,0.3),Color(0.7,0.7,0.7))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(130,150,0))
	for i in 2:
		camera.position = center + (Vector3(9,8,11) if i == 0 else Vector3(24,22,28))
		camera.look_at(center+Vector3.UP*2.0)
		await frames(120 if i == 0 else 24)
		var image := view.get_texture().get_image()
		check(image.save_png("user://hd-scene-"+map_name+"-"+str(i)+".png") == OK,"capture saved")
		rows.append({"view":i,"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var textures := texture_stats()
	if gpu_script:
		var supported := RenderingServer.get_rendering_device() != null
		check(textures.resident_textures > 0 if supported else textures.image_textures > 0,"map uses expected HD texture path")
	view.free()
	DataSwitch.clear_caches()
	await frames(8)
	var remaining := (gpu_script.get("_live") as Dictionary).size() if gpu_script else 0
	if gpu_script: check(remaining == 0,"data-source cache clear releases resident textures")
	var foliage_entries := EIFigure._foliage.size() + EIFigure._foliage_local.size()
	if gpu_script: check(foliage_entries == 0,"data-source switch clears foliage material owners")
	# Also record whether the central figure cleanup releases a missed cache.
	EIFigure.clear_cache()
	await frames(4)
	var after_figure_clear := (gpu_script.get("_live") as Dictionary).size() if gpu_script else 0
	# Let pending native work finish while the renderer/pool are still running.
	TexUpscale.shutdown()
	await frames(24)
	var report := {"checks":checks,"failures":failures,"map":map_name,"renderer":RenderingServer.get_current_rendering_method(),
		"load_setup_us":loading_us,"textures":textures,"views":rows,"live_after_clear":remaining,
		"foliage_entries_after_clear":foliage_entries,"live_after_figure_clear":after_figure_clear}
	FileAccess.open("user://hd-texture-scene.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("HD_TEXTURE_SCENE ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
