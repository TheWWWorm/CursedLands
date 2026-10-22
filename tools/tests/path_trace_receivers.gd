extends "res://tools/tests/scene_raytrace_device.gd"
## Render the production receiver lookup itself. Green means a matching traced
## surface; red means conventional fallback. A steep plane must stay covered
## at each tracing scale without borrowing lighting from a nearer layer.
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
var results := []

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size=Vector2i(1280,720);Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8;camera.position=Vector3(0,0,12);camera.current=true
	var n:=Vector3(0.99875,0,0.0499844).normalized()
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var corners:=[Vector3(-2,-5,2*n.x/n.z),Vector3(2,-5,-2*n.x/n.z),Vector3(2,5,-2*n.x/n.z),Vector3(-2,5,2*n.x/n.z)]
	for i in [0,2,1,0,3,2]:vertices.append(corners[i]);normals.append(n)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="shader_type spatial; render_mode unshaded,cull_disabled;\nconst vec3 ei_ambient=vec3(0);\nvec3 ei_lin(vec3 c){return c;}\n"+Receiver.COMMON+"\nuniform float normal_sign=1.0;\nvoid fragment(){vec3 gi;vec4 a,b;bool valid=ei_rt_sample((INV_VIEW_MATRIX*vec4(VERTEX,1)).xyz,normalize((INV_VIEW_MATRIX*vec4(NORMAL*normal_sign,0)).xyz),gi,a,b);ALBEDO=valid?vec3(0,1,0):vec3(1,0,0);}\n"
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=material;add_child(object)
	await frames(4)
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	if not Receiver.COMMON.contains("global uniform mat4 ei_rt_inverse_view_projection;"):
		RenderingServer.global_shader_parameter_add(&"ei_rt_inverse_view_projection",RenderingServer.GLOBAL_VAR_TYPE_MAT4,vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",view)
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	for variation in [[640,1.0],[960,1.0],[1280,1.0],[640,-1.0],[960,-1.0],[1280,-1.0]]:
		var width: int=variation[0]
		material.set_shader_parameter("normal_sign",variation[1])
		var target:=Vector2i(width,width*720/1280)
		for edge: bool in [false,true]:
			var guide_image:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAF)
			var data_image:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAF);data_image.fill(Color(0.2,0.2,0.2,1))
			var extent:=camera.get_camera_projection().inverse().x.x
			for x in target.x:
				var wx: float=((x+0.5)/target.x*2.0-1.0)*extent
				var depth:=12.0+wx*n.x/n.z-(2.0 if edge and x>=target.x/2 else 0.0)
				for y in target.y:guide_image.set_pixel(x,y,Color(n.x,n.y,n.z,maxf(depth,0.0)))
			var guide_texture:=ImageTexture.create_from_image(guide_image);var data_texture:=ImageTexture.create_from_image(data_image)
			RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide_texture)
			for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,data_texture)
			await frames(12);await RenderingServer.frame_post_draw
			var capture:=get_viewport().get_texture().get_image();var correct:=0;var count:=0
			for y in range(300,420):
				for x in range(600,680):
					if absi(x-640)<4:continue
					var colour:=capture.get_pixel(x,y)
					var green:=colour.g>colour.r+0.5
					if green==not(edge and x>=640):correct+=1
					count+=1
			var fraction:=float(correct)/count
			results.append({"width":width,"normal_sign":variation[1],"depth_edge":edge,"correct_fraction":fraction})
			check(fraction>0.995,"steep receiver at %d pixels, normal sign %s, depth discontinuity %s: %.4f"%[width,variation[1],edge,fraction])
			capture.save_png(out.path_join("receiver-%d-%s-%s.png"%[width,variation[1],edge]))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("path-receivers.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"\t"))
	object.queue_free();camera.queue_free();await frames(8);finish()
