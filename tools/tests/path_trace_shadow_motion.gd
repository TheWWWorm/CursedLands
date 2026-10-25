extends "res://tools/tests/path_trace_nrd_device.gd"
## A small moving caster changes sunlight on an unchanged receiver. Keep
## valid receiver history throughout: resetting it would hide the failure.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified moving-shadow runtime")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	sun_direction=Vector3.UP;sun_energy=1;sky_energy=0
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-0.18,2,-0.3),Vector3(0.18,2,-0.3),Vector3(0.18,2,0.3),Vector3(-0.18,2,0.3)],Vector3.DOWN,Vector3.ZERO)
	for i in 2:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D(Basis.IDENTITY,Vector3(-0.7,0,0) if i==1 else Vector3.ZERO),"mask":7})
	check(await build_fixture(),"build small sun caster above an unchanged floor")
	await render_many(40)
	check(device.nrd_active,"real NRD indirect reconstruction is active")
	check(sample(device.output,Vector3(-0.7,0,0)).r<0.1,"small stationary shadow retains its umbra")
	check(sample(device.output,Vector3(0.7,0,0)).r>0.9,"unoccluded floor retains sunlight")
	var measurements:=[]
	for side in 2:
		var x:=0.7 if side==0 else -0.7
		for i in 16:
			var changes:={"instances":[{"index":1,"transform":Transform3D(Basis.IDENTITY,Vector3(x,0,0)),"mask":7}]} if i==0 else {}
			Device.dispatch(device,&"render",[size,frame(true),changes])
			await frames(2);await RenderingServer.frame_post_draw
			if i==2:
				var old:=sample(device.output,Vector3(-x,0,0)).r
				var current:=sample(device.output,Vector3(x,0,0)).r
				var direct:=sample(device.direct_sun,Vector3(x,0,0)).r
				check(old>0.9,"move %d clears the previous shadow within three frames"%side)
				check(current<0.1,"move %d places the new shadow within three frames"%side)
				check(absf(current-direct)<0.03,"move %d full light and terrain sun use consistent shadow history"%side)
				measurements.append({"move":side,"old_shadow":old,"new_shadow":current,"direct_sun":direct})
				device.output.get_image().save_png(out.path_join("moving-shadow-%d.png"%side))
	check(sample(device.output,Vector3(0,0,0.7)).r>0.9,"moving shadows preserve unrelated sunlight")
	Device.dispatch(device,&"dispose");await frames(6)
	FileAccess.open(out.path_join("shadow-motion.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"\t"))
	print("PT_SHADOW_MOTION ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if failures else 0)
