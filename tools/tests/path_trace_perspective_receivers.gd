extends "res://tools/tests/scene_raytrace_device.gd"
## A slowly moving perspective camera far from the world origin must keep a
## flat wall matched to its half-float trace guide. This is the snow-fort
## trailer camera, including its small near plane and long view distance.
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
var observations := []

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	GameData.options.merge({"rtx_upscaling":0,"fsr_upscaling":0,"q_aa":0,"render_scale":4},true)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	GameData._apply_window();get_window().borderless=true;get_window().size=Vector2i(1280,720)
	camera=Camera3D.new();add_child(camera);camera.fov=55;camera.near=0.05;camera.far=2000;camera.current=true
	var mesh:=QuadMesh.new();mesh.size=Vector2(160,120)
	var material:=ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="shader_type spatial; render_mode unshaded,cull_disabled,fog_disabled;\nconst vec3 ei_ambient=vec3(0);\nvec3 ei_lin(vec3 c){return c;}\n"+Receiver.COMMON+"""
void fragment(){
    vec3 world=(INV_VIEW_MATRIX*vec4(VERTEX,1)).xyz;
    vec3 normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0)).xyz);
    vec3 gi;vec4 a,b;bool valid=ei_rt_sample(world,normal,gi,a,b);
    ALBEDO=valid?vec3(0,1,0):vec3(1,0,0);
}
"""
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=material;add_child(object)
	object.rotation.y=deg_to_rad(120.0)
	var wall_normal:=object.basis.z
	await frames(12)
	check(get_viewport().get_visible_rect().size==Vector2(1280,720),"perspective receiver fixture uses native calibrated output")
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	var poses:=[0,17,24,25,27,28,29,30,31,33,38,41,44,48,59,64,65,66,80,85,96,119,127,154]
	for translated in [false,true]:
		var focus:=Vector3(329,11.7528085708618,-261) if translated else Vector3.ZERO
		object.position=focus
		RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(focus.x,focus.y,focus.z,0))
		for width in [320,640]:
			var target:=Vector2i(width,width*720/1280)
			var light_image:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH);light_image.fill(Color(0.2,0.2,0.2,1))
			var light:=ImageTexture.create_from_image(light_image)
			for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,light)
			for pose: int in poses:
				camera.position=focus+Vector3(18,9,20)+Vector3(-1.5,-0.5,-0.5)*(float(pose)/179.0)
				camera.look_at(focus)
				var view:=Projection(camera.global_transform.affine_inverse())
				var projection:=camera.get_camera_projection();var vp:=projection*view
				for row in [[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view_projection",vp],[&"ei_rt_view",view],[&"ei_rt_eye",camera.position]]:
					RenderingServer.global_shader_parameter_set(row[0],row[1])
				var guide:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH)
				var inverse:=projection.inverse()
				# Intersect the analytic world plane in camera-relative coordinates.
				# Do not use the receiver's inverse world-view-projection calculation
				# to manufacture its expected guide: that would repeat its error.
				for y in target.y:
					for x in target.x:
						var ray:=inverse*Vector4((x+0.5)/target.x*2.0-1.0,1.0-(y+0.5)/target.y*2.0,-1,1)
						var direction:=camera.basis*Vector3(ray.x,ray.y,ray.z)
						var relative:=direction*((focus-camera.position).dot(wall_normal)/direction.dot(wall_normal))
						var depth:=-relative.dot(camera.basis.z)
						guide.set_pixel(x,y,Color(wall_normal.x,wall_normal.y,wall_normal.z,maxf(depth,0.0)))
				var texture:=ImageTexture.create_from_image(guide)
				RenderingServer.global_shader_parameter_set(&"ei_rt_guide",texture)
				await frames(3);await RenderingServer.frame_post_draw
				var capture:=get_viewport().get_texture().get_image();var holes:=0;var count:=0
				# A grazing plane extends beyond the snapshot radius at the screen
				# edges. Measure the visible interior, inside that intentional bound.
				for y in range(260,460,2):
					for x in range(560,720,2):
						var color:=capture.get_pixel(x,y)
						if color.g<=color.r+0.5:holes+=1
						count+=1
				var fraction:=float(holes)/count
				check(fraction<0.005,"perspective wall %s, trace %d, pose %d: %.5f fallback"%[focus,width,pose,fraction])
				observations.append({"translated":translated,"width":width,"pose":pose,"fallback_fraction":fraction})
				if fraction>=0.005 or pose in [65,85]:capture.save_png(out.path_join("wall-%s-%d-%d.png"%[translated,width,pose]))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("perspective-receivers.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	object.queue_free();camera.queue_free();await frames(8);finish()
