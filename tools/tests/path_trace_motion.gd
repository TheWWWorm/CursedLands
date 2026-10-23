extends "res://tools/tests/path_trace_quality.gd"
## Known noise/history fields measure rigid reprojection independently of the
## integrator. Real primary hits then cover identity, stop/start and rejection.
var motion_index := 0
var native_identity: Image
signal motion_ready

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(77*4,1.0)
	bytes.encode_float(145*4,8.0)
	return bytes

func previous_matrices(bytes: PackedByteArray,pose: Transform3D) -> void:
	var view:=Projection(pose.affine_inverse())
	var vp:=camera.get_camera_projection()*view
	for pair: Array in [[32,vp],[48,view],[148,vp.inverse()]]:
		for axis in 4:
			for c in 4:bytes.encode_float((pair[0]+axis*4+c)*4,pair[1][axis][c])

func identity_code(index: int) -> float:
	# Independent IEEE-754 half decoding over the normal-number ID range.
	var bits:=0x3c00+index
	return pow(2.0,float((bits>>10)&31)-15.0)*(1.0+float(bits&1023)/1024.0)

func surface_point(x: int,y: int,surface: Transform3D,eye: Transform3D) -> Vector3:
	var uv:=(Vector2(x,y)+Vector2(0.5,0.5))/Vector2(size)
	var near:=camera.get_camera_projection().inverse()*Vector4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1,1);near/=near.w
	var origin:=eye*Vector3(near.x,near.y,near.z) if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else eye.origin
	var direction:=-eye.basis.z if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else eye.basis*Vector3(near.x,near.y,near.z)
	var normal:=(surface.basis.inverse().transposed()*Vector3.BACK).normalized()
	return origin+direction*(normal.dot(surface.origin-origin)/normal.dot(direction))

func inputs_for(previous: Transform3D,current: Transform3D,old_camera: Transform3D,wrong_identity:=false) -> Array[Image]:
	var inputs: Array[Image]=[]
	for i in 8:inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGBAH))
	inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGH))
	inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RH))
	inputs[8].fill(Color(0,0,0,0))
	inputs[9].fill(Color(identity_code(motion_index+1 if wrong_identity else motion_index),0,0,0))
	var normal:=(current.basis.inverse().transposed()*Vector3.BACK).normalized()
	var old_normal:=(previous.basis.inverse().transposed()*Vector3.BACK).normalized()
	for y in size.y:
		for x in size.x:
			var point:=surface_point(x,y,current,camera.global_transform)
			var old_point:=surface_point(x,y,previous,old_camera)
			var depth:=(point-camera.position).dot(-camera.basis.z)
			var old_depth:=(old_point-old_camera.origin).dot(-old_camera.basis.z)
			inputs[0].set_pixel(x,y,Color(float(x%2),0,0,identity_code(motion_index)))
			inputs[1].set_pixel(x,y,Color(normal.x,normal.y,normal.z,depth))
			inputs[2].set_pixel(x,y,Color(float(x%2),0,0,1))
			inputs[3].set_pixel(x,y,Color(0.6,0.6,0.6,63))
			inputs[4].set_pixel(x,y,Color(0.8,0,0,7))
			inputs[5].set_pixel(x,y,Color(old_normal.x,old_normal.y,old_normal.z,old_depth))
			inputs[6].set_pixel(x,y,Color(0.8,0,0,7))
			inputs[7].set_pixel(x,y,Color(0.6,0.6,0.6,63))
	return inputs

func prepare_motion(previous: Transform3D,current: Transform3D,enabled: bool,old_mask:=7,deformed:=false) -> void:
	device._rigid_history=enabled
	device.update_scene({"instances":[{"index":motion_index,"transform":previous,"mask":old_mask}]})
	var changes:={"instances":[{"index":motion_index,"transform":current,"mask":7}]}
	if deformed:changes.poses=[{"geometry":0,"data":mesh_data.to_byte_array()}]
	device.update_scene(changes)
	motion_ready.emit.call_deferred()

func motion_case(label: String,previous: Transform3D,current: Transform3D,perspective:=false,
		camera_motion:=Vector3.ZERO,wrong_identity:=false,old_mask:=7,deformed:=false) -> void:
	size=Vector2i(96,54);camera.size=8;camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	var old_camera:=camera.global_transform;camera.position+=camera_motion
	var inputs:=inputs_for(previous,current,old_camera,wrong_identity)
	var bytes:=frame(false);previous_matrices(bytes,old_camera)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var spatial:=filtered_result.get_pixel(size.x/2,size.y/2).r
	bytes.encode_float(82*4,1.0)
	RenderingServer.call_on_render_thread(prepare_motion.bind(previous,current,false,old_mask,deformed));await motion_ready
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var baseline:=filtered_result.get_pixel(size.x/2,size.y/2)
	RenderingServer.call_on_render_thread(prepare_motion.bind(previous,current,true,old_mask,deformed));await motion_ready
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var value:=filtered_result.get_pixel(size.x/2,size.y/2)
	var reject:=wrong_identity or (old_mask&1)==0 or deformed
	var expected:=spatial if reject else lerpf(spatial,0.8,7.0/8.0)
	var error:=absf(value.r-expected)
	report[label]={"actual":value.r,"expected":expected,"error":error,"history_age":value.a,
		"camera_only":baseline.r,"camera_only_age":baseline.a,"camera_only_error":absf(baseline.r-expected),
		"reference_error":absf(value.r-0.8),"camera_only_reference_error":absf(baseline.r-0.8)}
	check(error<0.006,label+" matches independently weighted reference")
	check(value.a<1.01 if reject else value.a>7.5,label+" has correct historical confidence")
	if not reject and previous!=current:
		check(absf(value.r-0.8)<absf(baseline.r-0.8)*0.25,label+" reduces error versus camera-only reprojection by at least 75 percent")

func native_read() -> void:
	native_identity=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RH,device._rd.texture_get_data(device._filter_auxiliary[3],0))
	motion_ready.emit.call_deferred()

func native_frame(changes: Dictionary={},history:=true) -> Color:
	RenderingServer.call_on_render_thread(device.render.bind(size,frame(history),changes))
	await frames(2);await RenderingServer.frame_post_draw
	return device.output.get_image().get_pixel(size.x/2,size.y/2)

func native_sequence() -> void:
	size=Vector2i(160,90);camera.size=8;camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var ages:=[]
	for i in 8:
		var value:=await native_frame({"instances":[{"index":motion_index,"transform":Transform3D.IDENTITY,"mask":7}]} if i==0 else {},i>0)
		ages.append(value.a)
	check(ages[-1]>7.5,"native static primary hits accumulate to eight frames")
	var moved:=Transform3D(Basis(Vector3.UP,0.35),Vector3(0.35,0,0.45))
	var value:=await native_frame({"instances":[{"index":motion_index,"transform":moved,"mask":7}]})
	ages.append(value.a)
	check(value.a>7.5,"native translated and rotated primary retains diffuse history")
	value=await native_frame();ages.append(value.a)
	check(value.a>7.5,"stopping motion retires its transform on the next rendered frame")
	check(device._motion_pending.is_empty(),"stationary native frame leaves no pending placement upload")
	var restarted:=Transform3D(Basis(Vector3.UP,-0.1),Vector3(-0.2,0,0.1))
	value=await native_frame({"instances":[{"index":motion_index,"transform":restarted,"mask":7}]});ages.append(value.a)
	check(value.a>7.5,"restarted motion uses the immediately previous rendered transform")
	await native_frame({"instances":[{"index":motion_index,"transform":restarted,"mask":0}]})
	value=await native_frame({"instances":[{"index":motion_index,"transform":restarted,"mask":7}]})
	check(value.a<1.01,"newly visible native placement rejects its old illumination")
	for i in 7:await native_frame()
	value=await native_frame({"poses":[{"geometry":0,"data":mesh_data.to_byte_array()}]})
	check(value.a<1.01,"unsupported deformation history is rejected on affected native surfaces")
	value=await native_frame()
	check(value.a>1.9 and value.a<2.1,"deformation rejection retires once the new surface is stationary")
	# Hide low IDs; exercise adjacent IDs above FP16's exact integer range.
	for index in [2048,2049,4095]:
		var swaps:=[{"index":motion_index,"transform":restarted,"mask":0},{"index":index,"transform":Transform3D.IDENTITY,"mask":7}]
		value=await native_frame({"instances":swaps});motion_index=index
		check(value.a<1.01,"native placement swap rejects history for ID "+str(index))
		RenderingServer.call_on_render_thread(native_read);await motion_ready
		check(native_identity.get_pixel(size.x/2,size.y/2).r==identity_code(index),"native FP16 guide keeps exact identity "+str(index))
		for i in 7:await native_frame()
		value=await native_frame()
		check(value.a>7.5,"high placement ID can accumulate history "+str(index))
	report["native_motion_ages"]=ages
	var identity_target: RID=device._filter_auxiliary[3]
	size=Vector2i(128,72);value=await native_frame()
	check(value.a<1.01 and device._filter_auxiliary[3]!=identity_target,"resize replaces identity history and resets confidence")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified rigid motion reconstruction device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8;camera.position=Vector3(0,0,6)
	sun_energy=0;sky_energy=1;bounces=1
	quad(mesh_data,[Vector3(-30,-30,0),Vector3(30,-30,0),Vector3(30,30,0),Vector3(-30,30,0)],Vector3.BACK,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)}]
	for i in 4096:placements.append({"geometry":0,"transform":Transform3D.IDENTITY,"mask":7 if i==0 else 0})
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white];device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await device.prepared,"build shared geometry with the full 4096 stable placement IDs")
	if not device._ready:finish();return
	var translated:=Transform3D(Basis.IDENTITY,Vector3(0.3,0,0.4))
	var rotated:=Transform3D(Basis(Vector3.UP,0.4),Vector3(0.3,0,0.4))
	var scaled:=Transform3D(Basis(Vector3.UP,0.4).scaled(Vector3(1.3,0.7,0.6)),Vector3(0.3,0,0.4))
	for perspective: bool in [false,true]:
		var prefix:="perspective_" if perspective else "orthographic_"
		await motion_case(prefix+"translation",Transform3D.IDENTITY,translated,perspective)
		await motion_case(prefix+"rotation",Transform3D.IDENTITY,rotated,perspective)
		await motion_case(prefix+"nonuniform_scale",Transform3D.IDENTITY,scaled,perspective)
		await motion_case(prefix+"camera_and_object",Transform3D.IDENTITY,rotated,perspective,Vector3(0.2,0.1,0.15))
		await motion_case(prefix+"camera_only",Transform3D.IDENTITY,Transform3D.IDENTITY,perspective,Vector3(0.02,0,0))
	await motion_case("unrelated_identity",Transform3D.IDENTITY,Transform3D.IDENTITY,false,Vector3.ZERO,true)
	await motion_case("new_visibility",Transform3D.IDENTITY,translated,false,Vector3.ZERO,false,0)
	await motion_case("deformation",Transform3D.IDENTITY,translated,false,Vector3.ZERO,false,7,true)
	await native_sequence()
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device._filter_auxiliary.is_empty() and not device._motion.is_valid() and device._motion_data.is_empty(),"teardown releases motion and identity resources")
	FileAccess.open(out.path_join("path-motion.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
