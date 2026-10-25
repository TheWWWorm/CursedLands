extends "res://tools/tests/path_trace_device.gd"
## Read the actual ray integrator AOV: later bounces must not alter the
## first-hit distances supplied to the denoiser.
signal readback
var distances: Image
func read_distance() -> void:
	distances=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGH,device._rd.texture_get_data(device._raw[4],0))
	readback.emit.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(64,36);sun_energy=0;sky_energy=.2
	quad(mesh_data,[Vector3(-100,0,-100),Vector3(100,0,-100),Vector3(100,0,100),Vector3(-100,0,100)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-100,2,-100),Vector3(100,2,-100),Vector3(100,2,100),Vector3(-100,2,100)],Vector3.DOWN,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true},{"offset":6,"count":6,"standard":true,"opaque":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":6}]
	check(await build_fixture(),"build parallel diffuse surfaces")
	var reference: Image
	for depth in [1,2,4]:
		bounces=depth;tick=0
		await render_many(1)
		RenderingServer.call_on_render_thread(read_distance);await readback
		if depth==1:reference=distances.duplicate()
		var error:=0.0;var valid:=0
		for y in size.y:
			for x in size.x:
				var a:=distances.get_pixel(x,y);var b:=reference.get_pixel(x,y)
				if b.r>1.9 and b.r<100:
					valid+=1;error=maxf(error,absf(a.r-b.r));error=maxf(error,absf(a.g-b.g))
		check(valid>size.x*size.y*.95,"bounded secondary hits are present at %d bounces"%depth)
		check(error<.01,"first secondary distance is independent of %d-bounce continuation: %.5f"%[depth,error])
		observations.append({"bounces":depth,"valid":valid,"max_distance_error":error})
	RenderingServer.call_on_render_thread(device.dispose);await frames(6);camera.queue_free()
	FileAccess.open(out.path_join("hit-distance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	finish()
