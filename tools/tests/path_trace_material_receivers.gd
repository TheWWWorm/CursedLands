extends "res://tools/tests/scene_raytrace_device.gd"
## SCENE_RT_DEVICE summary comes from the shared device-fixture base.
## Both halves share one geometric plane. Only the production material guide
## can stop reduced-resolution glossy light crossing the material boundary.
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
var observations:=[]

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	# This measures the PT receiver's raw material rejection. Temporal output
	# reconstruction intentionally mixes the artificial one-pixel colour edge
	# and cannot be included in this receiver-only leakage measurement.
	GameData.options.merge({"rtx_upscaling":0,"fsr_upscaling":0,"q_aa":0,"render_scale":4},true)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	GameData._apply_window()
	check(get_tree().root.scaling_3d_mode==Viewport.SCALING_3D_MODE_BILINEAR and not get_tree().root.use_taa \
		and is_equal_approx(get_tree().root.scaling_3d_scale,1.0),"receiver test uses native unfiltered output")
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8;camera.position=Vector3(0,0,6);camera.current=true
	var mesh:=QuadMesh.new();mesh.size=Vector2(16,10)
	var material:=ShaderMaterial.new();material.shader=Shader.new()
	var lookup:="ei_rt_sample_surface(world,normal,target,gi,a,b)" if Receiver.COMMON.contains("bool ei_rt_sample_surface(") else "ei_rt_sample(world,normal,gi,a,b)"
	material.shader.code="shader_type spatial; render_mode unshaded,cull_disabled,fog_disabled;\nconst vec3 ei_ambient=vec3(0);\nvec3 ei_lin(vec3 c){return c;}\n"+Receiver.COMMON+"""
uniform bool rough_only=false;
void fragment(){
    vec3 world=(INV_VIEW_MATRIX*vec4(VERTEX,1)).xyz;
    vec3 normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0)).xyz);
    vec2 target=world.x<0.0?vec2(0.10,rough_only?0.0:0.9):vec2(0.92,0.0);
    vec3 gi;vec4 a,b;bool valid=LOOKUP;
    ALBEDO=valid?vec3(gi.r,a.g,0.0):vec3(0.0,0.0,1.0);
}
""".replace("LOOKUP",lookup)
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=material;add_child(object)
	await frames(12);get_window().size=Vector2i(1280,720);await frames(4)
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	for row in [[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view_projection",vp],[&"ei_rt_view",view],
		[&"ei_rt_eye",camera.position],[&"ei_rt_center",Vector4.ZERO],[&"ei_rt_state",Vector4(1,1,1,72)],[&"ei_pt_active",1.0]]:
		RenderingServer.global_shader_parameter_set(row[0],row[1])
	for width in [320,640,960]:
		for rough_only in [false,true]:
			var target:=Vector2i(width,width*720/1280)
			var guide:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH);guide.fill(Color(0,0,1,6))
			var diffuse:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH)
			var glossy:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH)
			var surface:=Image.create(target.x,target.y,false,Image.FORMAT_RGBAH)
			for x in target.x:
				var left:=x<target.x/2
				var code:=int(roundf((0.1 if left else 0.92)*63))|(int(roundf(0.9*31))<<6 if left and not rough_only else 0)
				for y in target.y:
					diffuse.set_pixel(x,y,Color(1 if left else 0,0,0,1))
					glossy.set_pixel(x,y,Color(0,0 if left else 1,0,1))
					surface.set_pixel(x,y,Color(1,1,1,code))
			var textures: Array[ImageTexture]=[]
			for row in [[&"ei_rt_guide",guide],[&"ei_rt_gi",diffuse],[&"ei_rt_shadow0",glossy],[&"ei_rt_shadow1",surface]]:
				textures.append(ImageTexture.create_from_image(row[1]));RenderingServer.global_shader_parameter_set(row[0],textures.back())
			material.set_shader_parameter("rough_only",rough_only)
			await frames(12);await RenderingServer.frame_post_draw
			var capture:=get_viewport().get_texture().get_image();var leakage:=0.0;var holes:=0
			for y in range(300,420):
				for x in range(636,644):
					var c:=capture.get_pixel(x,y);leakage=maxf(leakage,c.g if x<640 else c.r)
					if c.b>0.5:holes+=1
			check(leakage<0.02 and holes==0,"%d-pixel %s edge preserves material lighting: leak %.3f, holes %d"%[width,"roughness" if rough_only else "metal",leakage,holes])
			observations.append({"width":width,"roughness_only":rough_only,"leakage":leakage,"holes":holes})
			capture.save_png(out.path_join("material-edge-%d-%s.png"%[width,rough_only]))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("path-material-receivers.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	object.queue_free();camera.queue_free();await frames(8);finish()
