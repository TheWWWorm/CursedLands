extends "ground_contact.gd"
func tick()->void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
func frames(n:int)->void:
	for i in n:await tick()
func _ready()->void:
	await frames(24)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(320,320)
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_terrain":2,"gfx_ground_contact":1,"gfx_materials":1,"gfx_soft_ground":1,"q_aa":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
	EIFigure.set_wind(false);Gfx.ensure_globals();Gfx.apply_surface_options()
	Engine.time_scale=0;process_mode=Node.PROCESS_MODE_ALWAYS;Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Gfx.set_light(Color(.3,.3,.3),Color(.7,.7,.7));RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	var names:=["gz17h"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-map="):names=arg.trim_prefix("--contact-map=").split(",")
	for map_name:String in names:await scene(map_name)
	FileAccess.open("user://contact-candidates.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"checks":checks,"failures":failures,"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	TexUpscale.shutdown();get_tree().quit(int(failures>0))
func scene(map_name:String)->void:
	var view:=SubViewport.new();view.size=Vector2i(3840,2160);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var z:=CampaignMap.load_from(GameData.texts).zone(map_name)
	var map:=EIMapScene.load_map(z.get("mpr",map_name),z.get("mob",z.get("mpr",map_name)),false)
	if map==null:check(false,"map loads");return
	view.add_child(map);map.terrain.set_process(false)
	if is_instance_valid(map.terrain.details.soft_ground):map.terrain.details.soft_ground.set_process(false)
	map.terrain._water_mat.set_shader_parameter("waves",0.0)
	var target:=focus(map);check(not target.is_empty(),map_name+" scenery fixture")
	var p:Vector3=target.point
	var cam:=Camera3D.new();cam.far=120;cam.near=.05;view.add_child(cam);cam.current=true
	var env:=Environment.new();Gfx.setup_original_env(env);env.background_mode=Environment.BG_COLOR;cam.environment=env
	var sun:=DirectionalLight3D.new();sun.light_specular=Gfx.SUN_MARK;view.add_child(sun);sun.rotation_degrees=Vector3(-40,-35,0);sun.shadow_enabled=true
	Gfx.setup_sun_casters(sun);Gfx.sync_sun_pass(sun);RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	var owner:GroundContact=map.terrain.contact;owner.refresh()
	var mask:=owner.surface.candidates
	check(mask!=null,"Forward+ broad-phase texture exists")
	var pairs:=[]
	for shader:Shader in owner._shaders.values():
		var original:=shader.code
		check(original.contains("#define EI_CONTACT_QUERY_MASK"),"production shader uses broad phase")
		pairs.append([shader,original.replace("#define EI_CONTACT_QUERY_MASK",""),original])
	for angle in range(2):
		cam.position=p+(Vector3(8,6,10) if angle==0 else Vector3(-10,6,-8));cam.position.y=maxf(cam.position.y,map.terrain.height_at(cam.position.x,-cam.position.z)+6);cam.look_at(p+Vector3.UP)
		var reference:Image
		for pass_id in range(4):
			var optimized:=pass_id in [1,2]
			for pair:Array in pairs:pair[0].code=pair[2] if optimized else pair[1]
			for family:Dictionary in owner._variants.values():
				for material:ShaderMaterial in family.values():material.set_shader_parameter("query_candidates",mask)
			await frames(36)
			var gpu:=[]
			for i in 90:
				await tick();gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			gpu.sort()
			var img:=view.get_texture().get_image();img.convert(Image.FORMAT_RGBA8)
			var difference:={"peak":0,"changed":0,"mean":0.0}
			if pass_id==0:reference=img
			else:
				difference=compare(reference,img)
				check(difference.peak<=1,"pixels match within one byte: "+str([map_name,angle,pass_id])+" "+str(difference))
			img.save_png("user://contact-candidates-%s-%d-%d.png"%[map_name,angle,pass_id])
			var row:={"map":map_name,"angle":angle,"optimized":optimized,"pass":pass_id,"gpu_ms":gpu[45],"image_difference":difference,"focus":str(p)}
			rows.append(row);print("CONTACT_CANDIDATES ",JSON.stringify(row))
	view.free();await frames(6)
