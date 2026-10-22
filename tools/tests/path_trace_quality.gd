extends "res://tools/tests/path_trace_device.gd"
## Compare native integrator variance against a deterministic hemispherical
## integral, then exercise reconstruction with known subpixel/sloped histories.
var report := {}
signal filtered
var raw_result: Image
var filtered_result: Image
var filtered_specular: Image
var filtered_noise: Image

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(77*4,1.0)
	bytes.encode_float(80*4,float(camera.projection==Camera3D.PROJECTION_ORTHOGONAL))
	return bytes

func read_raw() -> void:
	raw_result=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[2],0))
	filtered.emit.call_deferred()

func reference(roughness: float,albedo: Vector3,nv: float) -> Vector3:
	# Independent midpoint quadrature of BRDF*cos(theta) over solid angle.
	# No sampling PDF or production sampling routine participates here.
	var alpha2:=pow(roughness,4);var v:=Vector3(sqrt(1.0-nv*nv),0,nv)
	var result:=Vector3.ZERO
	for z in 192:
		var nl: float=(z+0.5)/192.0
		var gl: float=2.0*nl/(nl+sqrt(alpha2+(1.0-alpha2)*nl*nl))
		var gv: float=2.0*nv/(nv+sqrt(alpha2+(1.0-alpha2)*nv*nv))
		for azimuth in 384:
			var phi: float=TAU*(azimuth+0.5)/384.0
			var l:=Vector3(sqrt(1.0-nl*nl)*cos(phi),sqrt(1.0-nl*nl)*sin(phi),nl)
			var h:=(v+l).normalized();var d: float=alpha2/(PI*pow(h.z*h.z*(alpha2-1.0)+1.0,2))
			var fresnel:=albedo+(Vector3.ONE-albedo)*pow(1.0-v.dot(h),5)
			result+=fresnel*(d*gv*gl/(4.0*nv))*TAU/(192.0*384.0)
	return result

func statistics(image: Image) -> Dictionary:
	var sum:=Vector3.ZERO;var squares:=Vector3.ZERO;var peak:=0.0;var count:=0
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y);var v:=Vector3(c.r,c.g,c.b)
			sum+=v;squares+=v*v;peak=maxf(peak,maxf(c.r,maxf(c.g,c.b)));count+=1
	var average:=sum/count;var variance:=squares/count-average*average
	return {"mean":[average.x,average.y,average.z],"variance":[variance.x,variance.y,variance.z],"peak":peak,"pixels":count}

func reconstruct(bytes: PackedByteArray,inputs: Array[Image]) -> void:
	var rd:=device._rd
	device._targets(size,device._samplers[0])
	for i in 8:
		var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
		format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		# RD creates an image view even for this temporary upload texture.
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var source:=rd.texture_create(format,RDTextureView.new(),[inputs[i].get_data()])
		var target: RID=device._raw[i] if i<4 else device._history[i]
		rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(size.x,size.y,1),0,0,0,0)
		rd.free_rid(source)
	if device.has_method("filter_auxiliary_formats") and not device._filter_auxiliary.is_empty():
		# Synthetic inputs must not inherit uninitialised or unrelated variance.
		if inputs.size()>8:
			var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
			format.format=RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
			format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			var source:=rd.texture_create(format,RDTextureView.new(),[inputs[8].get_data()])
			rd.texture_copy(source,device._filter_auxiliary[0],Vector3.ZERO,Vector3.ZERO,Vector3(size.x,size.y,1),0,0,0,0)
			rd.free_rid(source)
		else:rd.texture_clear(device._filter_auxiliary[0],Color(0,0,0,0),0,1,0,1)
	rd.buffer_update(device._frame,0,bytes.size(),bytes)
	var compute:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute,device._filter_pipeline)
	rd.compute_list_bind_uniform_set(compute,device._filter_sets[0],0)
	rd.compute_list_dispatch(compute,ceili(size.x/8.0),ceili(size.y/8.0),1)
	rd.compute_list_end()
	filtered_result=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(device._history[0],0))
	filtered_specular=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(device._history[2],0))
	if device.has_method("filter_auxiliary_formats") and not device._filter_auxiliary.is_empty():
		filtered_noise=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGH,rd.texture_get_data(device._filter_auxiliary[1],0))
	filtered.emit.call_deferred()

func plane_point(x: int,y: int,normal: Vector3,pose: Transform3D) -> Vector3:
	var uv:=(Vector2(x,y)+Vector2(0.5,0.5))/Vector2(size)
	var near:=camera.get_camera_projection().inverse()*Vector4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1,1);near/=near.w
	var origin:=pose*Vector3(near.x,near.y,near.z) if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else pose.origin
	var direction:=-pose.basis.z if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else pose.basis*Vector3(near.x,near.y,near.z)
	return origin+direction*(-normal.dot(origin)/normal.dot(direction))

func history_case(slope: bool,edge: bool,perspective:=false) -> float:
	size=Vector2i(64,36);camera.size=8;camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	var previous_pose:=camera.global_transform
	var bytes:=frame();var previous_vp:=camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())
	var step_x: float=2.0*camera.get_camera_projection().inverse().x.x/size.x*(6.0 if perspective else 1.0)
	camera.position.x=step_x*0.25
	var transform:=Projection(camera.global_transform)
	for axis in 4:
		for c in 4:bytes.encode_float((16+axis*4+c)*4,transform[axis][c])
	bytes.encode_float(145*4,8)
	# Keep the fixture usable against a saved pre-change package for A/B runs.
	if device.frame_bytes()>592:
		var inverse:=previous_vp.inverse()
		bytes.resize(device.frame_bytes())
		for axis in 4:
			for c in 4:bytes.encode_float((148+axis*4+c)*4,inverse[axis][c])
	var inputs: Array[Image]=[]
	for i in 8:inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGBAH))
	var n:=Vector3(0.97,0,0.2431049).normalized() if slope else Vector3.BACK
	for y in size.y:
		for x in size.x:
			var depth:=6.0-plane_point(x,y,n,camera.global_transform).z
			var old_depth:=6.0-plane_point(x,y,n,previous_pose).z
			# Alternating current samples provide a broad valid clipping envelope.
			inputs[0].set_pixel(x,y,Color(float(x%2),0,0,1))
			inputs[1].set_pixel(x,y,Color(n.x,n.y,n.z,depth))
			inputs[2].set_pixel(x,y,Color.BLACK);inputs[3].set_pixel(x,y,Color(0.6,0.6,0.6,1))
			inputs[4].set_pixel(x,y,Color(0.2 if x%2==0 else 0.8,0,0,7))
			inputs[5].set_pixel(x,y,Color(n.x,n.y,n.z,old_depth+(2.0 if edge else 0.0)))
			inputs[6].set_pixel(x,y,Color.BLACK);inputs[7].set_pixel(x,y,Color(0.6,0.6,0.6,1))
	# Capture the current-only spatial estimate as an independent reference.
	bytes.encode_float(82*4,0)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var current:=filtered_result.get_pixel(32,18).r
	bytes.encode_float(82*4,1)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var value:=filtered_result.get_pixel(32,18)
	var point:=plane_point(32,18,n,camera.global_transform)
	var clip:=previous_vp*Vector4(point.x,point.y,point.z,1)
	var coordinate: float=(clip.x/clip.w*0.5+0.5)*size.x-0.5
	var old:=lerpf(0.2 if int(floorf(coordinate))%2==0 else 0.8,0.8 if int(floorf(coordinate))%2==0 else 0.2,fposmod(coordinate,1.0))
	var expected:=current if edge else lerpf(current,old,7.0/8.0)
	var error:=absf(value.r-expected)
	report[("perspective_" if perspective else "")+("slope" if slope else "flat")+("_edge" if edge else "_history")]={"actual":value.r,"expected":expected,"error":error,"age":value.a}
	return error

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified path quality device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8
	camera.position=Vector3(0,8,64);camera.look_at(Vector3.ZERO);camera.current=true
	sun_energy=0;sky_energy=1;bounces=1;size=Vector2i(512,288)
	quad(mesh_data,[Vector3(-200,0,-200),Vector3(200,0,-200),Vector3(200,0,200),Vector3(-200,0,200)],Vector3.UP,Vector3.ZERO)
	var albedo:=Vector3(0.6,0.5,0.4)
	for vertex in 6:
		for c in 3:mesh_data[vertex*16+8+c]=albedo[c]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	for roughness: float in [0.35,0.65,1.0]:
		device=PathDevice.new()
		geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(roughness,1,0.5)}]
		RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
		check(await device.prepared,"build grazing metal "+str(roughness))
		await render_many(1)
		RenderingServer.call_on_render_thread(read_raw);await filtered
		var row:=statistics(raw_result)
		var expected:=reference(roundf(roughness*255)/255,albedo,camera.global_basis.z.y)
		row["reference"]=[expected.x,expected.y,expected.z];report[str(roughness)]=row
		check(absf(row.mean[0]-expected.x)<0.03,"grazing metal energy agrees with independent integral "+str(roughness))
		raw_result.save_png(out.path_join("grazing-metal-%s.png"%roughness))
		if roughness<1.0:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	check(await history_case(false,false)<0.005,"flat history interpolates a quarter-pixel camera translation")
	check(await history_case(true,false)<0.005,"sloped history retains matching surface samples")
	check(await history_case(false,true)<0.005,"depth discontinuity rejects unrelated history")
	check(await history_case(true,true)<0.005,"sloped receiver rejects history from an offset surface")
	check(await history_case(true,false,true)<0.005,"perspective slope retains bilinear history")
	check(await history_case(true,true,true)<0.005,"perspective slope rejects unrelated depth layers")
	FileAccess.open(out.path_join("path-quality.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	camera.queue_free();finish()
