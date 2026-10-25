extends "res://tools/tests/path_trace_device.gd"
## A smooth hillside's shading normal crosses the camera horizon while its
## geometric face remains visible. Tiny camera motion must not flip lighting.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2;camera.current=true;size=Vector2i(64,36);sun_energy=1;sky_energy=0;bounces=1
	var normal:=Vector3(.95,0,.31225).normalized()
	quad(mesh_data,[Vector3(-20,-20,0),Vector3(20,-20,0),Vector3(20,20,0),Vector3(-20,20,0)],normal,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_fixture(),"build smooth grazing hillside")
	sun_direction=Vector3.BACK
	var previous:=Vector3.ZERO;var previous_light:=0.0
	var max_normal_step:=0.0;var max_light_step:=0.0
	for i in 41:
		camera.position=Vector3(-3.1-i*.01,0,10);camera.look_at(Vector3.ZERO)
		await render_many(1)
		var guide:=device.guide.get_image().get_pixel(size.x/2,size.y/2)
		var n:=Vector3(guide.r,guide.g,guide.b)
		var value:=device.output.get_image().get_pixel(size.x/2,size.y/2).r
		check(guide.a>0 and n.dot(camera.global_basis.z)>0,"grazing hit stays visible: %d"%i)
		if i>0:
			max_normal_step=maxf(max_normal_step,n.distance_to(previous))
			max_light_step=maxf(max_light_step,absf(value-previous_light))
		previous=n;previous_light=value
	check(max_normal_step<.02,"small camera steps retain continuous normals: %.6f"%max_normal_step)
	check(max_light_step<.03,"small camera steps retain continuous direct light: %.6f"%max_light_step)
	RenderingServer.call_on_render_thread(device.dispose);await frames(6);camera.queue_free()
	FileAccess.open(out.path_join("grazing-normals.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"max_normal_step":max_normal_step,"max_light_step":max_light_step},"\t"))
	finish()
