extends Node
## Same tool against frozen baseline/candidate packs. Only normal frames; fixed
## shader time, camera, lighting and terrain. Timing is not an FPS comparison.
var checks := 0
var failures := 0
var map_name := "bz2g"
var hd := true
var candidate := false
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func stats(texture: TextureLayered) -> Dictionary:
	if texture == null: return {}
	var w := texture.get_width(); var h := texture.get_height(); var pixels := 0
	var top := w*h*4*texture.get_layers()
	while true:
		pixels += w*h
		if w == 1 and h == 1: break
		w = maxi(1,w>>1); h = maxi(1,h>>1)
	return {"resident":texture is Texture2DArrayRD,"width":texture.get_width(),"height":texture.get_height(),
		"layers":texture.get_layers(),"top_bytes":top,"mip_bytes":pixels*4*texture.get_layers()}

func liquid_focus(terrain: EITerrain) -> Vector3:
	var width := terrain.sectors_x*EITerrain.SECTOR
	var best := -1; var score := INF
	var middle := Vector2(terrain.size_ei()*0.5)
	for i in terrain.water_base.size():
		if not is_finite(terrain.water_base[i]): continue
		var p := Vector2(i%width,i/width)
		var d := p.distance_squared_to(middle)
		if d < score: score = d; best = i
	if best < 0: return Vector3(INF,INF,INF)
	var x := float(best%width)+0.5; var y := float(best/width)+0.5
	return Vector3(x,maxf(terrain.water_base[best],terrain.height_at(x,y)),-y)

func capture(view: SubViewport, camera: Camera3D, center: Vector3, label: String, warm: int) -> void:
	for i in 2:
		camera.position = center+(Vector3(10,14,12) if i == 0 else Vector3(30,38,34))
		camera.look_at(center)
		await frames(warm if i == 0 else 24)
		var shot := view.get_texture().get_image()
		var file := "terrain-atlas-%s-%s-%d.png" % [map_name,label,i]
		check(shot.save_png("user://"+file) == OK,"capture "+label+str(i))
		rows.append({"file":file,"label":label,"view":i,
			"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})

func _ready() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--atlas-map="): map_name = arg.trim_prefix("--atlas-map=")
		if arg == "--atlas-hd-off": hd = false
		if arg == "--atlas-candidate": candidate = true
	for key: String in ["gfx_volumetric","gfx_ground_contact","gfx_soft_ground","gfx_grass","gfx_wind","gfx_water","gfx_terrain","gfx_weather_surfaces","gfx_heat_haze","gfx_torch_glow","confine_mouse","vsync"]:
		GameData.options[key] = 0
	GameData.options["gfx_hd_textures"] = int(hd)
	Engine.time_scale = 0; Engine.max_fps = 120
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals()
	var view := SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var started := Time.get_ticks_usec()
	var terrain := EITerrain.load_map(map_name)
	var loading_us := Time.get_ticks_usec()-started
	check(terrain != null,"authored terrain loads")
	if terrain == null: get_tree().quit(1); return
	terrain.process_mode = Node.PROCESS_MODE_DISABLED; view.add_child(terrain)
	var camera := Camera3D.new(); camera.far = 180; camera.fov = CameraRig.MODERN_FOV
	view.add_child(camera); camera.current = true
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.3,0.3,0.3),Color(0.7,0.7,0.7))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(150,180,0))
	var x := terrain.size_ei().x*0.5; var y := terrain.size_ei().y*0.5
	var center := Vector3(x,terrain.height_at(x,y),-y)
	await capture(view,camera,center,"original",120)
	GameData.options["gfx_terrain"] = 1; terrain.apply_gfx()
	await capture(view,camera,center,"detail",120)
	var water := liquid_focus(terrain)
	if water.is_finite():
		await capture(view,camera,water,"water-original",48)
		GameData.options["gfx_water"] = 1; terrain.apply_gfx()
		await capture(view,camera,water,"water-effects",120)
	var arrays := {"original":stats(terrain._atlases),"detail":stats(terrain._detail_atlases)}
	var local_device := TexUpscale._rd != null
	if candidate:
		var supported := hd and RenderingServer.get_rendering_device() != null
		check(arrays.original.resident == supported and arrays.detail.resident == supported,"both terrain arrays use expected path")
		if supported: check(not local_device,"map/late detail use no local device")
	view.free()
	await frames(8)
	check(TexUpscaleTexture._live.is_empty(),"world releases array owners")
	TexUpscale.shutdown(); await frames(24)
	var report := {"checks":checks,"failures":failures,"map":map_name,"hd":hd,"renderer":RenderingServer.get_current_rendering_method(),
		"loading_us":loading_us,"arrays":arrays,"local_device":local_device,"views":rows}
	FileAccess.open("user://terrain-atlas-scene.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_ATLAS_SCENE ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
