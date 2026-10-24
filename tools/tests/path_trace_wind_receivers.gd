extends "res://tools/tests/scene_raytrace_device.gd"
## The visible wind-deformed leaf must retain light from its traced rest pose.
## An unrelated depth layer must still be rejected.
var results:=[]
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	GameData.options.merge({"auto_graphics":0,"q_aa":0,"pt_mode":1,"gfx_wind":1,"gfx_materials":0,"gfx_foliage_light":0},true)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=10;camera.position=Vector3(0,4,8);camera.current=true
	await frames(12);get_window().size=Vector2i(1280,720);Gfx.apply_quality(get_viewport());await frames(4)
	var vp:=camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.global_transform.affine_inverse()))
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	var guide:=Image.create(320,180,false,Image.FORMAT_RGBAH);guide.fill(Color(0,0,1,8))
	var light:=Image.create(320,180,false,Image.FORMAT_RGBAH);light.fill(Color(.2,.2,.2,1))
	var guide_texture:=ImageTexture.create_from_image(guide);var light_texture:=ImageTexture.create_from_image(light)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide_texture)
	for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,light_texture)
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var mesh:=QuadMesh.new();mesh.size=Vector2(4,8);mesh.center_offset=Vector3(0,4,0)
	var material:=ShaderMaterial.new();material.shader=Gfx.make_shader(EIFigure.FOLIAGE_SHADER)
	var shader:=Shader.new();shader.code=Gfx._function_tail(material.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","\n EMISSION=vec3(0);ALBEDO=ei_pt_blend>0.5?vec3(0,1,0):vec3(1,0,0);\n")
	material.shader=shader;material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(white))
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=material;add_child(object)
	for i in 7:
		var foreground:=i==6
		guide.fill(Color(0,0,1,6 if foreground else 8));guide_texture.update(guide)
		material.set_shader_parameter("wind",0.0 if i==0 else 1.0)
		RenderingServer.global_shader_parameter_set(&"ei_wind_state",Vector4(.6,.8,1,1))
		RenderingServer.global_shader_parameter_set(&"ei_wind_phases",Vector4(i*.7,i*1.3,i*.4,i*1.7))
		await frames(10);await RenderingServer.frame_post_draw
		var capture:=get_viewport().get_texture().get_image();var accepted:=0;var count:=0
		for y in range(220,500):
			for x in range(580,700):
				var c:=capture.get_pixel(x,y)
				if c.g>c.r+.3:accepted+=1
				count+=1
		var fraction:=float(accepted)/count
		check(fraction<.001 if foreground else fraction>.995,"wind phase %d, foreground %s: %.5f valid"%[i,foreground,fraction])
		results.append({"phase":i,"foreground":foreground,"fraction":fraction})
		capture.save_png(out.path_join("wind-%d.png"%i))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("wind-receivers.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"\t"))
	object.queue_free();camera.queue_free();await frames(8);finish()
