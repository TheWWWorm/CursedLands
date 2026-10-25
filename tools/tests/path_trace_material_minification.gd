extends "res://tools/tests/path_trace_surface_maps.gd"
## A known subpixel material pattern must retain its average during camera
## motion. Inspect the native material guide, independently of NRD or DLSS.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);GameData.options.gfx_materials=1
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.size=4;camera.fov=65
	size=Vector2i(96,54);sun_energy=0;sky_energy=1;bounces=1
	var colour:=Image.create(512,512,false,Image.FORMAT_RGBA8);colour.fill(Color.WHITE)
	var mask:=Image.create(512,512,false,Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512:mask.set_pixel(x,y,Color(0.5,0.1 if x%4<2 else 0.9,0 if x%4<2 else 1))
	var material:=ShaderMaterial.new();material.shader=Shader.new();material.shader.code=MATERIAL_SHADER
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(colour))
	material.set_shader_parameter("surface_tex",ImageTexture.create_from_image(mask))
	var mesh:=QuadMesh.new();mesh.size=Vector2(3,3)
	check(await build_map(collect(mesh,material)),"build minified mixed-material receiver")
	for projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE]:
		for grazing in [false,true]:
			camera.projection=projection
			var values:=[]
			for i in 16:
				camera.position=Vector3((4.0 if grazing else 0.0)+float(i)*3.0/512.0/8.0,0,6)
				camera.look_at(Vector3.ZERO)
				await render_many(1)
				var c:=material_at(Vector3.ZERO);values.append([c.x,c.y])
			var lo:=Vector2.ONE;var hi:=Vector2.ZERO;var error:=0.0
			for v: Array in values:
				var p:=Vector2(v[0],v[1]);lo=lo.min(p);hi=hi.max(p);error=maxf(error,(p-Vector2(0.5,0.5)).abs().x);error=maxf(error,(p-Vector2(0.5,0.5)).abs().y)
			var label:="%s %s"%["orthographic" if projection==Camera3D.PROJECTION_ORTHOGONAL else "perspective","grazing" if grazing else "front"]
			check(error<0.04,label+" preserves the subpixel material average: %.4f"%error)
			check((hi-lo).length()<0.05,label+" remains stable under subtexel camera motion: "+str(hi-lo))
			observations.append({"case":label,"max_error":error,"range":[hi.x-lo.x,hi.y-lo.y],"values":values})
	RenderingServer.call_on_render_thread(device.dispose);await frames(6);camera.queue_free()
	FileAccess.open(out.path_join("material-minification.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"));finish()
