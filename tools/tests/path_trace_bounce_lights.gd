extends "res://tools/tests/path_trace_many_lights.gd"
## Continuation vertices draw one local light in proportion to its reach.
## Bounce lighting must keep the summed energy of every source: a wall lit
## only through the floor compares the all-lights estimate with the sum of
## single-light renders, which trace the same one shadow ray deterministically.
var wall_rows: Array[int]=[]

func wall_mean() -> Color:
	var image:=device.output.get_image()
	var sum:=Color(0,0,0,0);var count:=0
	for y in wall_rows:
		for x in image.get_width():
			sum+=image.get_pixel(x,y);count+=1
	return sum/maxf(count,1)

func measure_bounce(count: int,samples: int) -> void:
	var reference:=Color(0,0,0,0)
	for single in count:
		selected.assign([single]);await render_many(samples);reference+=wall_mean()
	selected.assign(range(count));await render_many(samples*2)
	var sampled:=wall_mean()
	var error:=0.0
	for c in 3:error=maxf(error,absf(sampled[c]-reference[c])/maxf(reference[c],0.001))
	check(reference.r>0.002,"%d lights reach the wall through the floor: %s"%[count,str(reference)])
	check(error<0.06,"%d lights preserve summed bounce illumination within 6%%: %.4f"%[count,error])
	observations.append({"lights":count,"reference":str(reference),"sampled":str(sampled),"relative_error":error})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	# Look along -Z at a wall standing on the lit floor. The lights sit behind
	# the wall, so its camera-facing side receives floor bounce only.
	camera.size=4;camera.position=Vector3(0,1,6);camera.look_at(Vector3(0,1,0));camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=2
	await collection()
	check(PathDevice.supported(),"qualified bounce-light GPU")
	if PathDevice.supported():
		quad(mesh_data,[Vector3(-6,0,-6),Vector3(6,0,-6),Vector3(6,0,6),Vector3(-6,0,6)],Vector3.UP,Vector3.ZERO)
		quad(mesh_data,[Vector3(-1.5,0,0),Vector3(-1.5,2,0),Vector3(1.5,2,0),Vector3(1.5,0,0)],Vector3.BACK,Vector3.ZERO)
		geometries=[{"offset":0,"count":12,"standard":true,"opaque":true}]
		placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
		check(await build_fixture(),"build bounce-light transport scene")
		# Wall rows: the orthographic frame spans y in [-1,3]; the wall covers [0,2].
		for y in size.y:
			var world_y:=3.0-4.0*(y+0.5)/size.y
			if world_y>0.25 and world_y<1.75:wall_rows.append(y)
		for i in 64:
			var angle:=i*TAU/64
			lights.append(Vector4(cos(angle)*2.0,1.5+i%3*0.2,-2.5-(i%4)*0.4,7))
			colours.append(Color(0.5+0.1*(i%3),0.4+0.2*(i%5),0.6+0.1*(i%7),0.04))
		for count in [2,7,16]:await measure_bounce(count,24)
		RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	FileAccess.open(out.path_join("path-bounce-lights.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	camera.queue_free();await frames();finish()
