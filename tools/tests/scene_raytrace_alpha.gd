extends "res://tools/tests/scene_raytrace_device.gd"
## Alpha-tested foliage must agree in primary, sun and secondary rays.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"qualified alpha-test RT device")
	if not Device.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8
	camera.position=Vector3(0,6,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	for cutout: bool in [false,true]:
		var data:=PackedFloat32Array()
		quad(data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
		quad(data,[Vector3(-0.3,1,-0.6),Vector3(0.3,1,-0.6),Vector3(0.3,1,0.6),Vector3(-0.3,1,0.6)],Vector3.UP,Vector3(3,0,0))
		for vertex in range(6,12):data[vertex*16+15]=1.0
		var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
		var leaf:=Image.create(2,2,false,Image.FORMAT_RGBA8);leaf.fill(Color(1,1,1,0 if cutout else 1))
		var images: Array[Image]=[white,leaf]
		var geometries:=[{"offset":0,"count":6,"standard":true,"opaque":true},{"offset":6,"count":6,"standard":true,"opaque":false,"cutoff":0.5}]
		var placements:=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":7}]
		device=Device.new();RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images,geometries,placements))
		var ready: bool=await device.prepared;check(ready,"build alpha fixture "+str(cutout))
		if ready:
			await render_many()
			var depth:=sample(device.guide,Vector3.ZERO).a
			check(absf(depth-(6.0 if cutout else 5.0))<0.03,"primary rays respect material alpha cutoff "+str(cutout))
			var visibility:=sample(device.shadow0,Vector3(-1,0,0)).r
			check(visibility>0.95 if cutout else visibility<0.05,"sun rays respect the same alpha cutoff "+str(cutout))
			var gi:=sample(device.output,Vector3(-1,0,0))
			check(gi.r<0.001 if cutout else gi.r>0.05,"secondary rays respect the same alpha cutoff "+str(cutout))
		RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	camera.queue_free();await frames();finish()
