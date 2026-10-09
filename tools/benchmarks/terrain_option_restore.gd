extends Node
## Read-only control for terrain option shader specialization, including packs
## predating biome mounds. Prints image differences; it does not relax tests.
func frames(n := 12) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
func snap(view: SubViewport,label: String) -> Image:
	await frames(); var image := view.get_texture().get_image(); image.save_png("user://terrain-restore-"+label+".png"); return image
func delta(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed+=int(d>0); over+=int(d>2); peak=maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}
func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=0; GameData.options["gfx_soft_ground"]=1
	if OS.get_cmdline_user_args().has("--restore-hd"): GameData.options["gfx_hd_textures"]=1
	if OS.get_cmdline_user_args().has("--restore-detail"): GameData.options["gfx_terrain"]=1
	Engine.max_fps=120; Engine.time_scale=0; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	var view := SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true; view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var desert := OS.get_cmdline_user_args().has("--restore-desert")
	world.zone=CampaignMap.load_from(GameData.texts).zone("gz15h" if desert else "gz11k")
	var map := EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false); world.add_child(map); world.map=map; world.terrain=map.terrain
	var t := map.terrain; t.set_process(false); t.details.set_process(false); t.details.soft_ground.set_process(false)
	var rng := RandomNumberGenerator.new(); rng.seed=hash("zone15:mounds:17:24" if desert else "zone11:mounds:49:21")
	var rx := rng.randf_range(-0.45,0.45); var ry := rng.randf_range(-0.45,0.45)
	var p := (Vector2(138,194) if desert else Vector2(394,170))+Vector2(rx,ry); var focus := Vector3(p.x,t.height_at(p.x,p.y)+0.1,-p.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=focus+Vector3(2.7,2.6,3.5); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment); env.environment.background_mode=Environment.BG_COLOR; view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.shadow_enabled=true; view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized()); RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(120); var base := await snap(view,"base"); var rows := [{"case":"stable","difference":delta(base,await snap(view,"stable"))}]
	var hard: Image
	for i in 4:
		GameData.options["gfx_soft_ground"]=i%2
		Gfx._set_vol_fog(false); t.apply_gfx()
		if t.details.soft_ground: t.details.soft_ground.set_process(false)
		var image := await snap(view,str(i))
		if i==0: hard=image
		rows.append({"case":str(i),"difference":delta(base if i%2 else hard,image)})
	view.free(); TexUpscale.shutdown(); await frames()
	var out := {"point":[p.x,p.y],"rows":rows}
	FileAccess.open("user://terrain-option-restore.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t"));print("TERRAIN_RESTORE ",JSON.stringify(out));get_tree().quit()
