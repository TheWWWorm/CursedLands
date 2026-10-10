extends "cloud_shadow_field.gd"
## Independent sky / shadow / reflection settings on live original materials.
var reference_dir := ""
var reference: Array = []

func settings() -> void:
	for key in ["gfx_cloud_shadows","gfx_cloud_reflections"]:
		check(GameData.option(key)==0 and key in GameData.OPTIONS_APPLIED,"optional consumer starts off: "+key)
		for preset in [1,2,3,4]:check(GfxPresets.values(preset)[key]==0,"presets leave cloud consumer opt-in: "+key)
	var image:=Image.create(800,600,false,Image.FORMAT_RGB8);image.fill(Color(.04,.04,.04))
	var panel:=OptionsPanel.new();add_child(panel);panel.open(image)
	panel._show_group(OptionsPanel.EFFECTS_GROUP)
	for pair in [[7,"gfx_clouds"],[8,"gfx_cloud_shadows"],[9,"gfx_cloud_reflections"],[10,"gfx_weather_mist"]]:
		check(panel._rows[pair[0]].name==pair[1],"distinct visible settings row: "+str(pair[1]))
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang;panel._show_group(OptionsPanel.EFFECTS_GROUP)
		for key in ["gfx_clouds","gfx_cloud_shadows","gfx_cloud_reflections"]:
			var words: Array=GameData.REMAKE_OPTIONS[key]
			check(panel.text_width(RemakeText.t(words[0]))<=260,"label fits: "+lang+" "+key)
			check(lang=="en" or (RemakeText.t(words[0])!=words[0] and RemakeText.t(words[1])!=words[1]),"label and help localized: "+lang+" "+key)
		await frames(4)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png("user://cloud-controls-"+lang+".png")==OK,"capture settings "+lang)
	RemakeText.lang="en"
	panel._set_value("gfx_clouds",3);panel._set_value("gfx_cloud_shadows",1);panel._set_value("gfx_cloud_reflections",0)
	check(panel._values.graphics_preset==0 and panel._values.gfx_clouds==3,"manual shadow choice keeps sky quality and marks Custom")
	panel._accept()
	var cfg:=ConfigFile.new();check(cfg.load(GameData.CONFIG_PATH)==OK,"saved settings readable")
	check(cfg.get_value("options","gfx_clouds",-1)==3 and cfg.get_value("options","gfx_cloud_shadows",-1)==1 and cfg.get_value("options","gfx_cloud_reflections",-1)==0,"independent values persist")
	panel.open(image);panel._set_value("gfx_cloud_reflections",1);panel._restore();panel._close()
	check(GameData.option("gfx_cloud_reflections")==0 and GameData.option("gfx_cloud_shadows")==1,"discard leaves independent choices intact")
	panel.free()

func image_for(view: SubViewport,label: String) -> Image:
	await frames(150);var img:=view.get_texture().get_image()
	check(img.save_png("user://split-"+label+".png")==OK,"capture "+label)
	await frames(20);check(difference(img,view.get_texture().get_image()).changed_pixels==0,"held view exact "+label)
	return img

func scene() -> void:
	var view:=SubViewport.new();view.size=Vector2i(800,600);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var terrain:=EITerrain.load_map("zone1");view.add_child(terrain);terrain.set_process(false);terrain.apply_gfx();terrain._water_mat.set_shader_parameter("waves",0.0)
	var p:=centre(terrain)
	var camera:=Camera3D.new();view.add_child(camera);camera.current=true
	var env:=Environment.new();Gfx.setup_original_env(env);env.background_color=Color(.12,.15,.17)
	env.sky=Sky.new();env.sky.radiance_size=Sky.RADIANCE_SIZE_256;env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	var sky:=EISky.material(false);env.sky.sky_material=sky
	var node:=WorldEnvironment.new();node.environment=env;view.add_child(node)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-60,-90,0);view.add_child(sun)
	Gfx.set_light(Color(.3,.3,.3),Color(.9,.9,.9));RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO);RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var field:=Clouds.new();field.sample(0,"split-clouds","Ingos",Vector4(.8,.6,.8,1),.52,0,12,false)
	field.sample(420,"split-clouds","Ingos",Vector4(.8,.6,.8,1),.52,0,12,false)
	GameData.options.gfx_clouds=0;Gfx.apply_surface_options()
	var native_land:=terrain._land_mat.shader.code;var native_water:=terrain._water_mat.shader.code
	var baseline: Image
	for quality in [1,2,3]:
		var sky_images: Array[Image]=[];var surface_images: Array[Image]=[]
		GameData.options.gfx_clouds=quality
		Gfx.apply_surface_options();EISky.update(sky,null,12,false,true,env)
		var sky_source:=sky.shader.code
		var noise: RefCounted
		for flags in [0,1,2,3,0]:
			GameData.options.gfx_cloud_shadows=int(flags&1>0);GameData.options.gfx_cloud_reflections=int(flags&2>0)
			Gfx.apply_surface_options();EISky.update(sky,null,12,false,true,env)
			Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame);await frames(4);Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame)
			check(sky.shader.code==sky_source,"consumer toggle keeps exact sky program")
			check(Gfx._cloud_frame==field.frame,"consumer toggle keeps phases and weather")
			var land:=terrain._land_mat.shader.code;var water:=terrain._water_mat.shader.code
			check(land.contains("ei_cloud_sun")==bool(flags&1),"land only samples enabled cloud shadows")
			check(water.contains("vec3 R = ei_lin(ei_cloud_sky")==bool(flags&2),"water only marches enabled cloud reflections")
			check(water.contains("ei_cloud_sun(wpos)")==bool(flags&1),"water sunlight follows shadow setting")
			if flags==0:check(land==native_land and water==native_water,"sky-only uses exact cloud-free surface programs")
			if Clouds.mode()>1:
				if not noise:noise=Gfx._cloud_volume_noise
				check(noise!=null and Gfx._cloud_volume_noise==noise,"consumer toggles retain the sky noise")
			if RenderingServer.get_current_rendering_method()=="forward_plus" and Clouds.mode()>1:
				check((Gfx._cloud_shadow_field!=null)==bool(flags&1),"shared field exists only for enabled shadows")
			if flags==3 and not reference.is_empty():
				var ref: Dictionary=reference[quality-1]
				check(land.sha256_text()==ref.land and water.sha256_text()==ref.water and sky_source.sha256_text()==ref.sky,"all consumers retain pre-split shader sources")
			for path in ["sky","surface"]:
				if path=="sky":
					terrain.hide();env.background_mode=Environment.BG_SKY;camera.position=Vector3(100,10,-100);camera.rotation_degrees=Vector3(9,0,0)
				else:
					terrain.show();env.background_mode=Environment.BG_COLOR;camera.position=p+Vector3(0,5,16);camera.look_at(p+Vector3(0,2,0))
				var label:="%s-q%d-flags%d-%d"%[path,quality,flags,sky_images.size()]
				var img:=await image_for(view,label)
				if path=="sky":
					if not sky_images.is_empty():check(difference(sky_images[0],img).changed_pixels==0,"sky pixels survive independent consumer choices")
					sky_images.append(img)
				else:
					if flags==0:
						if not baseline:baseline=img
						check(difference(baseline,img).changed_pixels==0,"sky-only surface pixels remain exact across qualities and restore")
					surface_images.append(img)
				if flags==3 and not reference_dir.is_empty():
					var ref_img:=Image.load_from_file(reference_dir+"/reference-%s-%d.png"%[path,quality])
					var delta:=difference(ref_img,img);rows.append({"case":"pre-split-parity","path":path,"quality":quality,"delta":delta})
					check(delta.changed_pixels==0,"all consumers retain pre-split pixels "+path)
			if flags==3 and Gfx._cloud_shadow_field:
				var old_view:=weakref(Gfx._cloud_shadow_field.view)
				var rid:=RenderingServer.texture_get_rd_texture(Gfx._cloud_shadow_field.view.get_texture().get_rid())
				GameData.options.gfx_cloud_shadows=0;Gfx.apply_surface_options();await frames(5)
				check(Gfx._cloud_shadow_field==null and old_view.get_ref()==null and not texture_live(rid),"shadow disable releases producer and its GPU texture")
				check(Gfx._cloud_volume_noise==noise and Gfx._cloud_frame==field.frame,"shadow release preserves sky resources and motion")
		check(difference(surface_images[0],surface_images[1]).pixels_over_2>20,"shadows alone visibly affect surfaces")
		check(difference(surface_images[0],surface_images[2]).pixels_over_2>20,"reflections alone visibly affect water")
		check(difference(surface_images[1],surface_images[3]).pixels_over_2>20,"reflections remain independent when shadows are on")
		GameData.options.gfx_clouds=0;Gfx.apply_surface_options();await frames(8)
		check(Gfx._cloud_shadow_field==null and Gfx._cloud_volume_noise==null,"master off frees both optional resources")
	GameData.options.merge({"gfx_clouds":3,"gfx_cloud_shadows":0,"gfx_cloud_reflections":1,"gfx_water":0},true);Gfx.apply_surface_options();terrain.apply_gfx()
	check(not Clouds.reflections_enabled() and not terrain._water_mat.shader.code.contains("ei_cloud"),"original water avoids unused cloud reflection code")
	Gfx.clear_clouds();view.free();await frames(8)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cloud-reference="):
			reference_dir=arg.trim_prefix("--cloud-reference=")
			reference=JSON.parse_string(FileAccess.get_file_as_string(reference_dir+"/cloud-reference.json")).rows
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
	await settings()
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_water":1,"gfx_materials":1,"q_aa":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;Engine.max_fps=0;process_mode=Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		await scene()
	Gfx.clear_clouds();TexUpscale.shutdown();await frames(12)
	FileAccess.open("user://cloud-controls.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("CLOUD_CONTROLS checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
