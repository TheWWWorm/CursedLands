extends "clouds.gd"
## Real sky, original terrain/water and live material controls for the optional
## volumetric modes. Run from an isolated export/profile with frozen sources.
const Volume = preload("res://src/game/fx/cloud_volume.gd")
const VolumeNoise = preload("res://src/game/fx/cloud_volume_noise.gd")


func policy() -> void:
	var a:=Volume.new();var b:=Volume.new();a.reset(17);b.reset(17)
	var wind:=Vector4(.7,-.7,.8,.2)
	a.sample(0,wind,0,.62,"Gipat");b.sample(0,wind,0,.62,"Gipat")
	for i in 120: a.sample(1.0/60,wind,0,.62,"Gipat")
	for i in 60: b.sample(1.0/30,wind,0,.62,"Gipat")
	var maximum:=0.0
	for i in 6:
		for axis in 3:maximum=maxf(maximum,absf(a.phases[i][axis]-b.phases[i][axis]))
	check(maximum<1e-12,"all six volume phases are independent of update cadence")
	var initial:Dictionary=a.frame.duplicate(true)
	var before:Dictionary=a.sample(0,wind,1,.62,"Gipat")
	check(before.storm.y==0,"zero elapsed game time cannot advance storm closure")
	check(before.phases==initial.phases,"zero elapsed time preserves every volume phase")
	var halfway:Dictionary=a.sample(45,wind,1,.62,"Gipat")
	check(is_equal_approx(halfway.storm.y,.5),"storm banks close over ninety game seconds")
	check(a.sample(45,wind,1,.62,"Gipat").storm.y==1,"storm closure reaches its target")
	check(is_equal_approx(a.sample(60,wind,0,.62,"Gipat").storm.y,.5),"storm banks reopen over one hundred twenty game seconds")
	a.sample(100000000,wind,0,.62,"Gipat")
	var late:Dictionary=a.frame.duplicate(true);a.sample(.001,wind,0,.62,"Gipat")
	check(a.frame.phases!=late.phases,"large game-time jumps retain millisecond phase motion")
	var bounded:=true
	for layer in a.phases:
		for phase in layer: bounded=bounded and is_finite(phase) and phase>=0 and phase<1
	check(bounded,"wrapped phase storage remains finite and bounded")
	for region in ["Gipat","Ingos","Suslanger"]:
		var v:=Volume.new();v.reset(0);var frame:Dictionary=v.sample(0,wind,0,Clouds.coverage(region,0,0),region)
		check(frame.weather.x>=.44999 and frame.weather.x<=.62001 and frame.weather.y>=.84999 and frame.weather.y<=1,"regional coverage and density remain bounded: "+region)
	rows.append({"case":"volume-policy","cadence_phase_error":maximum,"late_phases":str(a.frame.phases)})
	check(GfxDetect.base_values().gfx_clouds==0,"cloud volumes keep the established default off")
	for tier in range(GfxDetect.LAST+1):
		check(GfxDetect.tier_values(tier,GfxDetect.base_values()).gfx_clouds==0,"automatic preset never enables volume "+str(tier))
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang
		var choices:=GameData.option_choices("gfx_clouds")
		check(choices.size()==4 and (lang=="en" or choices[2]!="Volume: Low"),"four localized cloud qualities "+lang)
		var panel:=OptionsPanel.new();add_child(panel)
		for label:String in choices:check(panel.text_width(label)<=160,"cloud value fits its column: "+lang+" "+label)
		panel.free()
	RemakeText.lang="en"
	GameData.options.gfx_clouds=3;GameData.save_settings()
	var saved:=ConfigFile.new()
	check(saved.load(GameData.CONFIG_PATH)==OK and saved.get_value("options","gfx_clouds",-1)==3,"volume quality persists under the existing key")
	if DisplayServer.get_name()=="headless":
		check(Clouds.mode()==1 and not VolumeNoise.new().prepare(),"headless mode keeps the sheet and allocates no native noise")
	GameData.options.gfx_clouds=0;GameData.save_settings()


func measured_cost(view:SubViewport,label:String) -> void:
	var gpu:=PackedFloat64Array();var cpu:=PackedFloat64Array()
	await frames(6)
	for i in 60:
		await frames(1)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
	gpu.sort();cpu.sort()
	rows.append({"case":"cost","mode":label,"viewport":str(view.size),"samples":gpu.size(),
		"gpu_ms_p50":gpu[30],"gpu_ms_p95":gpu[57],"cpu_ms_p50":cpu[30],"cpu_ms_p95":cpu[57]})


static func rid_probe(job:Dictionary) -> void:
	var rd:=RenderingServer.get_rendering_device()
	job.valid=[]
	for rid:RID in job.rids:job.valid.append(rd.texture_is_valid(rid))
	job.done.post()


func textures_valid(rids:Array) -> Array:
	var job:={"rids":rids,"valid":[],"done":Semaphore.new()}
	RenderingServer.call_on_render_thread(rid_probe.bind(job));job.done.wait()
	return job.valid


func resource_lifecycle(frame:Dictionary) -> void:
	if not VolumeNoise.supported(): return
	for cycle in 3:
		GameData.options.gfx_clouds=2;Gfx.apply_surface_options();Gfx.set_cloud_frame(91,frame)
		var noise:=Gfx._cloud_volume_noise
		check(noise!=null,"volume noise prepares for ownership cycle "+str(cycle))
		if noise==null:return
		var rids:=noise._backings.duplicate();var shape:=noise.shape;var detail:=noise.detail
		check(rids.size()==2 and textures_valid(rids)==[true,true],"both shape and erosion RIDs are live")
		Gfx.clear_clouds(90)
		check(Gfx._cloud_owner==91 and Gfx._cloud_volume_noise==noise,"retained world cannot release the active volume")
		Gfx.set_cloud_frame(92,frame)
		check(Gfx._cloud_volume_noise==noise,"new active world reuses bounded immutable noise")
		Gfx.clear_clouds(91)
		check(Gfx._cloud_owner==92 and Gfx._cloud_volume_noise==noise,"old active-world teardown cannot erase its successor")
		if cycle==1:
			GameData.options.gfx_clouds=1;Gfx.apply_surface_options()
		else:Gfx.clear_clouds(92)
		await frames(3)
		check(Gfx._cloud_volume_noise==null and textures_valid(rids)==[false,false],"disable or active-world teardown frees both native backing RIDs")
		check(shape.get_width()==0 and detail.get_width()==0,"released shared texture views are detached before RID disposal")
	Gfx.clear_clouds();GameData.options.gfx_clouds=0;Gfx.apply_surface_options()


func vol_image(view:SubViewport,label:String) -> Image:
	await frames(20);await RenderingServer.frame_post_draw
	var img:=view.get_texture().get_image();img.save_png("user://volume-"+label+".png");return img


func volume_scene() -> void:
	var view:=SubViewport.new();view.size=Vector2i(800,600);view.own_world_3d=true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--volume-size="):
			var dimensions:=argument.trim_prefix("--volume-size=").split("x")
			view.size=Vector2i(int(dimensions[0]),int(dimensions[1]))
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var world:=GameWorld.new();view.add_child(world);world.set_process(false);world.set_physics_process(false)
	var map_name:="zone1";var allod:="Gipat"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--volume-map="):map_name=argument.trim_prefix("--volume-map=")
		if argument.begins_with("--volume-allod="):allod=argument.trim_prefix("--volume-allod=")
	var terrain:=EITerrain.load_map(map_name);world.add_child(terrain);world.terrain=terrain;terrain.set_process(false)
	var p:=centre(terrain)
	terrain._water_mat.set_shader_parameter("waves",0.0)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=p+Vector3(0,7,18);camera.look_at(p+Vector3(0,6,-12));camera.current=true
	if OS.get_cmdline_user_args().has("--volume-close-water"):
		camera.position=p+Vector3(0,2,3);camera.look_at(p+Vector3(0,1,-20))
	rows.append({"case":"scene","map":map_name,"allod":allod,"water_centre":str(p),"camera":str(camera.transform)})
	var position:=p+Vector3(-2,0,6);position.y=terrain.height_at(position.x,-position.z)
	var actor:=unit(world,9722,position)
	var env:=Environment.new();Gfx.setup_original_env(env);env.background_mode=Environment.BG_SKY;env.sky=Sky.new()
	env.sky.radiance_size=Sky.RADIANCE_SIZE_256;env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	var sky:=EISky.material(false);env.sky.sky_material=sky;EISky.update(sky,null,12,false,true)
	var env_node:=WorldEnvironment.new();env_node.environment=env;view.add_child(env_node)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-60,-90,0);view.add_child(sun)
	Gfx.set_light(Color(.3,.3,.3),Color(.9,.9,.9));RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO);RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(100)
	var off:=await vol_image(view,"off")
	await measured_cost(view,"off")
	var field:=Clouds.new();var wind:=Vector4(.7,-.7,.8,.3)
	field.sample(0,map_name,allod,wind,0,0,12,false)
	for quality in [1,2,3]:
		GameData.options["gfx_clouds"]=quality;Gfx.apply_surface_options();EISky.update(sky,null,12,false,true)
		Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame)
		await frames(100)
		var active:bool=quality>1 and VolumeNoise.supported()
		check(Clouds.mode()==quality if active else Clouds.mode()==1,"quality activates only on supported desktop renderer: "+str(quality))
		if active:
			check(Gfx._cloud_volume_noise!=null and Gfx._cloud_volume_noise.shape.get_width()==128 and Gfx._cloud_volume_noise.detail.get_width()==32,"bounded native shape and erosion textures are resident")
		if active:
			var empty:Dictionary=field.frame.duplicate(true);empty.volume.weather.y=0
			Gfx.set_cloud_frame(terrain.get_instance_id(),empty)
			var empty_image:=await vol_image(view,"quality%d-empty"%quality)
			var empty_delta:=difference(off,empty_image)
			check(empty_delta.pixels_over_2==0,"empty density preserves the original sky and reflection: "+str(quality))
			rows.append({"case":"empty","quality":quality,"difference":empty_delta})
			Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame)
		var img:=await vol_image(view,"quality%d"%quality)
		var held:=await vol_image(view,"quality%d-held"%quality)
		var delta:=difference(img,held)
		check(delta.pixels_over_2==0,"held volume sky and reflections preserve pixels: "+str(quality))
		check(difference(off,img).pixels_over_2>1000,"visible volume sky, shadows and reflected colour: "+str(quality))
		rows.append({"case":"quality","value":quality,"mode":Clouds.mode(),"difference":difference(off,img),"held":delta,"noise_setup_ms":Gfx._cloud_volume_noise.setup_ms if Gfx._cloud_volume_noise else 0})
		await measured_cost(view,str(quality))
	var initial:=await vol_image(view,"fair")
	if OS.get_cmdline_user_args().has("--volume-gameplay-views"):
		var transform_before:=camera.transform;var fov_before:=camera.fov
		for degrees in [9.0,20.0,35.0]:
			camera.fov=CameraRig.MODERN_FOV
			camera.rotation_degrees=Vector3(-degrees,0,0)
			await vol_image(view,"gameplay-pitch%d"%int(degrees))
		camera.transform=transform_before;camera.fov=fov_before

	for i in 120:field.sample((i+1)*.5,map_name,allod,wind,0,0,12,false)
	Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame)
	var moved:=await vol_image(view,"moved")
	check(difference(initial,moved).pixels_over_2>500,"game wind evolves visible cloud banks")
	var snowing:=OS.get_cmdline_user_args().has("--volume-snow")
	var precipitation_label:="snow" if snowing else "rain"
	for i in 180:field.sample(60+(i+1)*.5,map_name,allod,wind,0 if snowing else 1,1 if snowing else 0,12,false)
	Gfx.set_cloud_frame(terrain.get_instance_id(),field.frame)
	var rain:=await vol_image(view,precipitation_label)
	check(difference(moved,rain).pixels_over_2>1000,precipitation_label+" builds a different connected cloud deck")
	rows.append({"case":"precipitation","kind":precipitation_label,"storm":str(field.frame.volume.storm),"difference":difference(moved,rain)})
	if VolumeNoise.supported():
		var empty_storm:Dictionary=field.frame.duplicate(true);empty_storm.volume.weather.y=0
		Gfx.set_cloud_frame(terrain.get_instance_id(),empty_storm)
		var storm_empty:=await vol_image(view,"storm-empty")
		check(difference(off,storm_empty).pixels_over_2==0,"zero-density storm haze preserves original sky and reflected colour")
	var lights:=EILights.load_for(allod,false)
	check(lights!=null,"original regional light table is available for night")
	EISky.update(sky,lights,0,false,true)
	Gfx.set_light(lights.sample("ambient",0),lights.sample("sunlight",0))
	var night_field:=Clouds.new()
	Gfx.set_cloud_frame(terrain.get_instance_id(),night_field.sample(0,map_name,allod,wind,0,0,0,false))
	check(sky.get_shader_parameter("night")==1.0 and not sky.shader.code.contains("TIME"),"volume night and stars use only the game clock")
	var night:=await vol_image(view,"night");var held_night:=await vol_image(view,"night-held")
	check(difference(night,held_night).changed_pixels==0,"paused night holds sky clouds, stars and reflected water exactly")
	EISky.update(sky,null,12,false,true);Gfx.set_light(Color(.3,.3,.3),Color(.9,.9,.9))
	var reflection_field:=Clouds.new()
	var reflection_frame:Dictionary=reflection_field.sample(0,map_name,allod,wind,0,0,12,false).duplicate(true)
	reflection_frame.state.y=0 # isolate the water reflection from cloud sunlight shadows
	var saved_sky:=env.sky;env.sky=null;env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.15,.17)
	var inactive:Dictionary=reflection_frame.duplicate(true);inactive.state.w=0
	Gfx.set_cloud_frame(terrain.get_instance_id(),inactive)
	var reflected_off:=await vol_image(view,"reflection-off")
	Gfx.set_cloud_frame(terrain.get_instance_id(),reflection_frame)
	var reflected_on:=await vol_image(view,"reflection-on")
	var reflected_delta:=difference(reflected_off,reflected_on)
	check(reflected_delta.pixels_over_2>20,"original water reflects volume density without sky background or sunlight shadow changes")
	rows.append({"case":"isolated-reflection","difference":reflected_delta,"native_capability":OS.has_feature("ei_sky_subpass_alpha")})
	env.sky=saved_sky;env.background_mode=Environment.BG_SKY
	Gfx.set_cloud_frame(terrain.get_instance_id(),field.sample(150,map_name,allod,wind,1,0,12,true))
	check(Gfx._cloud_volume_noise==null,"cave entry releases volume resources at held time")
	var cave:=await vol_image(view,"cave-cleared")
	check(difference(off,cave).pixels_over_2==0,"cave global clearing restores original pixels")
	GameData.options["gfx_clouds"]=0;Gfx.apply_surface_options();EISky.update(sky,null,12,false,true)
	check(sky.shader.code==EISky.SHADER,"off removes both volume and low-resolution sky program")
	var restored:=await vol_image(view,"restored")
	check(difference(off,restored).pixels_over_2==0,"off restores terrain water and sky together")
	world.erase_unit(actor.uid);actor.free();view.free();await frames(20)
	check(Gfx._cloud_owner==0 and Gfx._cloud_volume_noise==null,"exit retains no cloud owner or volume noise")
	await resource_lifecycle(field.sample(151,map_name,allod,wind,0,0,12,false))


func _ready() -> void:
	get_window().size=Vector2i(800,600)
	await frames(3)
	for option in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options["gfx_water"]=1;GameData.options["gfx_materials"]=1
	GameData.options["gfx_water_reflections"]=1;GameData.options["confine_mouse"]=0;GameData.options["vsync"]=0
	Gfx.ensure_globals();Engine.time_scale=0;Engine.max_fps=60;process_mode=Node.PROCESS_MODE_ALWAYS
	policy();analytical()
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		await volume_scene()
	Gfx.clear_clouds();TexUpscale.shutdown();UnitWounds.shutdown();await frames(12)
	FileAccess.open("user://cloud-volume.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("CLOUD_VOLUME checks=",checks," failures=",failures);get_tree().quit(1 if failures else 0)
