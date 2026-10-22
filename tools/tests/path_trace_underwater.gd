extends "res://tools/tests/scene_raytrace_device.gd"
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
## Exercise the production PT receiver with controlled reflected/emitted
## radiance, including the legacy terrain depth coefficient.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4;camera.position=Vector3(0,0,5);camera.current=true
	var object:=MeshInstance3D.new();object.mesh=QuadMesh.new();object.mesh.size=Vector2(8,8);add_child(object)
	var material:=ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="""shader_type spatial;
render_mode ambient_light_disabled, cull_disabled;
uniform float ei_k=0.0;
const vec3 ei_ambient=vec3(0.0),ei_e=vec3(0.1,0.0,0.0);
const vec4 ei_material_diffuse=vec4(1.0);
vec3 ei_lin(vec3 c){return c;}
vec3 ei_srgb(vec3 c){return c;}
"""+Receiver.COMMON+"\nvoid fragment(){ALBEDO=vec3(0.5);EMISSION=vec3(0.0);"+Receiver.CAPTURE+"ALBEDO=vec3(0.0);}\n"
	object.material_override=material;await frames(4)
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",view)
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	var textures: Array[ImageTexture]=[]
	for value: Color in [Color(0,0,1,5),Color(0.4,0.4,0.4,1),Color(0.1,0.1,0.1,1),Color(0,0,0,1)]:
		var im:=Image.create(320,180,false,Image.FORMAT_RGBAF);im.fill(value);textures.append(ImageTexture.create_from_image(im))
	var keys: Array[StringName]=[&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]
	for i in 4:RenderingServer.global_shader_parameter_set(keys[i],textures[i])
	var results:=[]
	for depth in [0.0,0.5,1.0,2.0]:
		material.set_shader_parameter("ei_k",depth);await frames(8);await RenderingServer.frame_post_draw
		var im:=get_viewport().get_texture().get_image();var c:=im.get_pixel(im.get_width()/2,im.get_height()/2).srgb_to_linear()
		var expected:=0.3*maxf(1.0-depth,0.0)
		check(absf(c.r-expected-0.05)<0.012 and absf(c.g-expected)<0.012 and absf(c.b-expected)<0.012,
			"underwater factor attenuates reflection and preserves emission at %s: %s"%[depth,c])
		results.append({"depth":depth,"linear":[c.r,c.g,c.b]})
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",0.0)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in keys:RenderingServer.global_shader_parameter_set(key,null)
	object.queue_free();camera.queue_free();await frames(8)
	FileAccess.open(out.path_join("path-underwater.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"\t"))
	finish()
