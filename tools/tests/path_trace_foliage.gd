extends "res://tools/tests/path_trace_quality.gd"
## Thin diffuse leaf transport with an authored mask. White lighting fixtures
## distinguish hemispheres, solid bark, real occlusion and conserved energy.
var back_surface := 0 # 0 empty, 1 opaque blocker, 2 red emitter
var leaves := true

func build_leaf() -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new();mesh_data.clear()
	quad(mesh_data,[Vector3(-4,0,-4),Vector3(4,0,-4),Vector3(4,0,4),Vector3(-4,0,4)],Vector3.UP,Vector3.ZERO)
	for i in 6:
		mesh_data[i*16+3]=(mesh_data[i*16]+4.0)/8.0
		mesh_data[i*16+7]=(mesh_data[i*16+2]+4.0)/8.0
	var white:=Image.create(64,64,true,Image.FORMAT_RGBA8);white.fill(Color.WHITE);white.generate_mipmaps()
	var mask:=Image.create(64,64,true,Image.FORMAT_RGBA8);mask.fill(Color.BLACK)
	for y in 64:
		for x in 32:mask.set_pixel(x,y,Color.RED)
	mask.generate_mipmaps()
	var images: Array[Image]=[white,mask]
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0),
		"foliage_layer":1,"leaf_light":leaves}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	if back_surface>0:
		quad(mesh_data,[Vector3(-20,-1,-20),Vector3(20,-1,-20),Vector3(20,-1,20),Vector3(-20,-1,20)],Vector3.UP,Vector3(2,0,0) if back_surface==2 else Vector3.ZERO)
		geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":1,"transform":Transform3D.IDENTITY,"mask":6})
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func halves() -> Array[Color]:
	var im:=device.output.get_image();var result: Array[Color]=[]
	for half in 2:
		var sum:=Color(0,0,0,0);var count:=0
		for y in range(size.y/3,2*size.y/3):
			for x in range(size.x/8+half*size.x/2,3*size.x/8+half*size.x/2):
				sum+=im.get_pixel(x,y);count+=1
		result.append(sum/float(count))
	return result

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified leaf transport device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,2,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(256,144);sun_energy=1;sky_energy=0;bounces=1
	check(await build_leaf(),"build masked leaf and solid bark")
	sun_direction=Vector3.DOWN;await render_many(8);var transmitted:=halves()
	check(absf(transmitted[0].r-0.4)<0.01 and transmitted[1].r<0.001,"backlighting passes through leaves while bark stays solid: "+str(transmitted))
	sun_direction=Vector3.UP;await render_many(8);var reflected:=halves()
	check(absf(reflected[0].r-0.6)<0.01 and absf(reflected[1].r-1.0)<0.01,"leaf reflection gives up the transmitted share: "+str(reflected))
	check(absf(reflected[0].r+transmitted[0].r-reflected[1].r)<0.01,"reflection plus transmission preserves the diffuse energy budget")
	sun_energy=0;sky_energy=1;await render_many(64);var uniform:=halves()
	check(absf(uniform[0].r-uniform[1].r)<0.02 and uniform[0].r>0.96 and uniform[0].r<1.02,"both hemisphere sampling PDFs conserve uniform-environment energy: "+str(uniform))
	leaves=false;sun_energy=1;sky_energy=0;sun_direction=Vector3.DOWN
	check(await build_leaf(),"build with leaf backlighting disabled");await render_many(8)
	check(halves()[0].r<0.001,"turning leaf lighting off restores opaque shading")
	leaves=true;back_surface=1
	check(await build_leaf(),"build blocker behind the leaves");await render_many(8)
	check(halves()[0].r<0.001,"transmitted sunlight respects real geometry behind the leaf")
	back_surface=2;sun_energy=0
	check(await build_leaf(),"build emissive surface behind the leaves");await render_many(64)
	var emitted:=halves()
	check(emitted[0].r>0.7 and emitted[0].r<0.82 and emitted[0].g<0.001,"emissive MIS and BSDF paths cross the leaf without self-intersection or duplicate energy: "+str(emitted))
	check(emitted[1].r<0.001,"solid bark does not leak the back emitter")
	report={"transmitted":str(transmitted),"reflected":str(reflected),"uniform":str(uniform),"emission":str(emitted)}
	RenderingServer.call_on_render_thread(device.dispose);await frames(4);camera.queue_free()
	FileAccess.open(out.path_join("path-foliage.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":report},"\t"))
	finish()
