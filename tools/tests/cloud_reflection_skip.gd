extends "clouds.gd"
## Exact rendered comparisons for cloud reflection work that cannot contribute.
## The reference restores the original placement of the cloud/SSR composition.
func helper() -> GDScript:
	return load("res://src/game/fx/cloud_reflection_shader.gd")

func reference(code: String) -> String:
	var patch := helper()
	if not code.contains("vec4 r = vec4(0.0);"): return code
	code=code.replace(patch.START+"\n\t\tvec4 r = vec4(0.0);","vec3 R = "+patch.SKY+";")
	code=code.replace("r = water_ssr(",patch.TRACE)
	code=code.replace("\t\t\t\n\t\t\tw = mix(w,", "\t\t\t"+patch.MIX+"\n\t\t\tw = mix(w,")
	var delayed: String=patch.WEIGHT+"\n\t\tif (w != 0.0 && (!reflections || r.a != 1.0)) { R = "+patch.SKY+"; }\n\t\tif (reflections) { "+patch.MIX+" }"
	return code.replace(delayed,patch.WEIGHT)

func pipeline_counts() -> Vector2i:
	return Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))

func source_contracts() -> void:
	var patch := helper(); var raw := EITerrain.WATER_FX_SHADER
	var legacy: String=raw.replace(patch.START,"vec3 R = "+patch.SKY+";")
	check(patch.inject(raw,false)==legacy,"unchanged sheet and unqualified backend injection")
	var optimized: String=patch.inject(raw,true)
	check(optimized!=legacy and reference(optimized)==legacy,"reference reconstructs exact original composition")
	check(optimized.count("ei_cloud_sky(ei_sky,wpos,")==1,"one cloud call without duplicate ray march")
	check(optimized.count("r = water_ssr(")==1,"one original SSR trace")
	for marker: String in [patch.START,patch.TRACE,patch.MIX,patch.WEIGHT]:
		var unsupported := raw.replace(marker,marker+marker)
		check(patch.inject(unsupported,true)==patch.inject(unsupported,false),"unsupported composition keeps legacy injection")

func rendered_matrix() -> void:
	var view:=SubViewport.new(); view.size=Vector2i(640,360); view.own_world_3d=true
	view.use_hdr_2d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.current=true
	var environment:=Environment.new();Gfx.setup_original_env(environment)
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.12,.15,.17)
	var env:=WorldEnvironment.new();env.environment=environment;view.add_child(env)
	var terrain:=EITerrain.load_map("zone1");view.add_child(terrain);terrain.set_process(false)
	var p:=centre(terrain);check(p.is_finite(),"real river focus")
	camera.position=p+Vector3(0,2,3);camera.look_at(p+Vector3(0,1,-20))
	var normal_camera:=camera.transform
	# A small flat water patch supplies an exact normal for the zero-weight
	# edge case; the remaining cases use the authored river unchanged.
	var width:=terrain.sectors_x*32
	var water_material:int=terrain.water_mat[int(-p.z)*width+int(p.x)]
	var flat:=MeshInstance3D.new();var mesh:=ArrayMesh.new();var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	var tile:=Vector2(0,water_material);arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([tile,tile,tile,tile])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	flat.mesh=mesh;flat.position=p+Vector3.UP;flat.hide();view.add_child(flat)
	var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.mesh.size=Vector3(12,8,1)
	var colour:=StandardMaterial3D.new();colour.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;colour.albedo_color=Color(.3,.18,.06)
	box.material_override=colour;box.position=p+Vector3(1,4,-15);view.add_child(box)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-60,-90,0);view.add_child(sun)
	Gfx.set_light(Color(.3,.3,.3),Color(.9,.9,.9))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var patch:=helper();var visible_clouds:=false
	for quality:int in [1,2,3]:
		GameData.options.gfx_clouds=quality
		for mode:int in [0,1,2]:
			GameData.options.gfx_water_reflections=mode;Gfx.apply_surface_options();terrain.apply_gfx()
			var material:ShaderMaterial=terrain._water_mat;flat.material_override=material
			var before_code:=reference(material.shader.code)
			var raw: String=before_code.replace("vec3 R = "+patch.SKY+";",patch.START)
			check(patch.inject(raw,false)==before_code,"reference keeps entire composed shader")
			var skip: bool=Clouds.mode()>1 and RenderingServer.get_current_rendering_method()=="forward_plus"
			var before:=Shader.new();before.code=before_code
			var after:=Shader.new();after.code=patch.inject(raw,skip)
			check((after.code!=before.code)==skip,"qualified backend and volume routing")
			var normal_ripple:PackedFloat32Array=material.get_shader_parameter("ripple")
			check(normal_ripple.size()==64,"real per-material ripple array")
			var no_ripple:=PackedFloat32Array();no_ripple.resize(64)
			for state:int in 4:
				var clock:=432.0+state*7.37
				var field:=Clouds.new();field.sample(0,"reflection-contract","Ingos",Vector4(.8,.6,.8,1),.52,0,12,false)
				var frame:Dictionary=field.sample(clock,"reflection-contract","Ingos",Vector4(.8,.6,.8,1),.52,0,12,false)
				Gfx.set_cloud_frame(terrain.get_instance_id(),frame)
				terrain._waves.advance(7.37);terrain._update_wave_parameters()
				material.set_shader_parameter("waves",1.0 if state in [1,2] else 0.0)
				material.set_shader_parameter("ripple",no_ripple if state==3 else normal_ripple)
				camera.projection=Camera3D.PROJECTION_ORTHOGONAL if state==3 else Camera3D.PROJECTION_PERSPECTIVE
				if state==3:
					camera.size=1;camera.far=20000;camera.position=p+Vector3.UP*10000;camera.look_at(p,Vector3.FORWARD)
					flat.show();RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100000,110000,0))
				else:
					camera.transform=normal_camera;camera.far=4000;flat.hide()
					RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
				Gfx.set_surface_weather(.7 if state==1 else 0.0,.8 if state==1 else 0.0)
				if state==2:
					for m in terrain.materials.size():terrain.set_water_offset(m,.23)
				else:
					for m in terrain.materials.size():terrain.set_water_offset(m,0.0)
				if state==0:
					# Preheat both complete programs with their live textures. Initial
					# driver specialization may outlast a short frame-count-only wait.
					for warm:Shader in [before,after]:
						material.shader=warm
						var deadline:=Time.get_ticks_msec()+2500
						while Time.get_ticks_msec()<deadline:await frames(1)
				var held_clock:=terrain._waves.time_ticks()
				var pipelines:=pipeline_counts()
				material.shader=before;await frames(90);var a:=view.get_texture().get_image()
				material.shader=after;await frames(90);var b:=view.get_texture().get_image()
				await frames(8);var held:=view.get_texture().get_image()
				material.shader=before;await frames(90);var restored:=view.get_texture().get_image()
				var label:="q%d-ssr%d-state%d"%[quality,mode,state]
				check(a.get_data()==b.get_data(),"exact rendered bytes "+label)
				check(b.get_data()==held.get_data(),"held candidate "+label)
				check(a.get_data()==restored.get_data(),"restored reference "+label)
				check(terrain._waves.time_ticks()==held_clock,"held water clock "+label)
				# Verify a positive cloud contribution, not just identical empty renders.
				if quality==3 and mode==0 and state==0:
					var empty:=frame.duplicate(true);empty.state.w=0.0;Gfx.set_cloud_frame(terrain.get_instance_id(),empty)
					await frames(90);visible_clouds=a.get_data()!=view.get_texture().get_image().get_data()
					Gfx.set_cloud_frame(terrain.get_instance_id(),frame)
				rows.append({"quality":quality,"ssr":mode,"state":state,"format":a.get_format(),"bytes":a.get_data().size(),"exact":a.get_data()==b.get_data(),"held":b.get_data()==held.get_data(),"restored":a.get_data()==restored.get_data(),"optimized":skip,"pipelines_start":str(pipelines),"pipelines_end":str(pipeline_counts())})
				if quality==3 and mode==0 and state==3:
					var mask:=Shader.new();mask.code=patch.inject(raw,true).replace("ambient_light_disabled","unshaded,fog_disabled").replace("ALPHA = A;","ALBEDO=vec3(w==0.0?1.0:0.0,0.0,1.0);EMISSION=vec3(0);ALPHA=1.0;FOG=vec4(0);")
					material.shader=mask;await frames(90);var im:=view.get_texture().get_image();var zeros:=0
					for y in im.get_height():
						for x in im.get_width():
							var c:=im.get_pixel(x,y);zeros+=int(c.r>.99 and c.g<.01 and c.b>.99)
					check(zeros>250,"flat top-down case positively exercises exactly zero reflection weight")
					rows.back().zero_weight_pixels=zeros;im.save_png("user://zero-weight-mask.png");material.shader=before
				check(a.save_png("user://cloud-reflection-"+label+".png")==OK,"save comparison reference "+label)
	check(visible_clouds,"clouds positively affect an unoccluded water reflection")
	Gfx.clear_clouds();view.free();await frames(8)

func _ready() -> void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_clouds":3,"gfx_cloud_reflections":1,"gfx_cloud_shadows":0,"gfx_water":1,"gfx_materials":1,"gfx_weather_surfaces":1,"auto_graphics":0,"confine_mouse":0,"vsync":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;Engine.max_fps=120;process_mode=Node.PROCESS_MODE_ALWAYS
	source_contracts()
	if DisplayServer.get_name()!="headless":await rendered_matrix()
	Gfx.clear_clouds();TexUpscale.shutdown()
	if DisplayServer.get_name()=="headless":await get_tree().process_frame
	else:await frames(8)
	FileAccess.open("user://cloud-reflection-contract.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("CLOUD_REFLECTION_CONTRACT checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
