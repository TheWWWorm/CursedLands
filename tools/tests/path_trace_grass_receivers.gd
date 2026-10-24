extends "res://tools/tests/scene_raytrace_device.gd"
const Receiver=preload("res://src/game/fx/scene_raytrace_shader.gd")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	Gfx.ensure_globals();GameData.options.pt_mode=1;GameData.options.gfx_cloud_shadows=0
	camera=Camera3D.new();add_child(camera);camera.position=Vector3(0,3,6);camera.look_at(Vector3(0,0.6,0));camera.current=true
	await frames(12)
	get_window().size=Vector2i(1280,720);Gfx.apply_quality(get_viewport());await frames(4)
	check(get_viewport().get_visible_rect().size==Vector2(1280,720),"grass fixture uses calibrated resolution")
	var vp:=camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.global_transform.affine_inverse()))
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	var guide:=Image.create(640,360,false,Image.FORMAT_RGBAF)
	var light:=Image.create(640,360,false,Image.FORMAT_RGBAF)
	for y in 360:
		for x in 640:
			var uv:=Vector2(x+0.5,y+0.5)*2
			var ray:=camera.project_ray_normal(uv);var eye:=camera.project_ray_origin(uv)
			if ray.y>=-0.001:continue
			var hit:=eye+ray*(-eye.y/ray.y);var depth:=-(camera.global_transform.affine_inverse()*hit).z
			guide.set_pixel(x,y,Color(0,1,0,depth));light.set_pixel(x,y,Color(0.02,0.02,0.02,1) if hit.x<0 else Color(0.8,0.8,0.8,1))
	var guide_texture:=ImageTexture.create_from_image(guide);var light_texture:=ImageTexture.create_from_image(light)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide_texture)
	for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,light_texture)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-0.3,0,0),Vector3(0.3,1.2,0),Vector3(0.3,0,0),Vector3(-0.3,0,0),Vector3(-0.3,1.2,0),Vector3(0.3,1.2,0)])
	var normals:=PackedVector3Array();var colours:=PackedColorArray();var uvs:=PackedVector2Array()
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:normals.append(Vector3.BACK);colours.append(Color.WHITE);uvs.append(Vector2(0,v.y/1.2))
	arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var objects:=[]
	var shader:=Gfx.make_shader(TerrainDetails.GRASS_SHADER)
	for x in [-1,1]:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.position.x=x
		var material:=ShaderMaterial.new();material.shader=shader;node.material_override=material;add_child(node);objects.append(node)
	await frames(20);await RenderingServer.frame_post_draw
	var capture:=get_viewport().get_texture().get_image();capture.save_png(out.path_join("grass-traced-shadow.png"))
	var dark:=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0))))
	var bright:=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(1,0.6,0))))
	check(bright.r>dark.r+0.25,"raised grass inherits the traced dark and lit ground roots")
	# Production lookup must reject a vertical foreground face at the root.
	var debug:=Shader.new();debug.code=Gfx._function_tail(shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","\n vec3 audit_light;vec4 audit_a,audit_b;bool valid=ei_rt_ground_sample(audit_light,audit_a,audit_b);ALBEDO=valid?vec3(0,1,0):vec3(1,0,0);EMISSION=vec3(0);\n")
	for node: MeshInstance3D in objects:node.material_override.shader=debug
	await frames(12);await RenderingServer.frame_post_draw
	capture=get_viewport().get_texture().get_image()
	check(capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0)))).g>0.9,"ground root is a valid receiver")
	guide.fill(Color(0,0,1,6));guide_texture.update(guide)
	await frames(12);await RenderingServer.frame_post_draw
	capture=get_viewport().get_texture().get_image()
	check(capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0)))).r>0.9,"grass rejects unrelated foreground walls")
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	for node: MeshInstance3D in objects:node.queue_free()
	camera.queue_free();await frames(6);finish()
