extends "res://tools/tests/path_trace_quality.gd"
## Known histories isolate reflection motion from diffuse reprojection. A native
## deterministic sun highlight then measures lag against the current raw signal.
var baseline:=false
var sequence_previous:=Transform3D.IDENTITY
var sequence:=false
var sequence_still:=false

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(71*4,0.0) # Point sun: deterministic direct BRDF reference.
	bytes.encode_float(145*4,256.0 if sequence_still else 8.0)
	if sequence:previous_matrices(bytes,sequence_previous)
	return bytes

func previous_matrices(bytes: PackedByteArray,pose: Transform3D) -> void:
	var view:=Projection(pose.affine_inverse())
	var vp:=camera.get_camera_projection()*view
	for pair: Array in [[32,vp],[48,view],[148,vp.inverse()]]:
		for axis in 4:
			for c in 4:bytes.encode_float((pair[0]+axis*4+c)*4,pair[1][axis][c])

func packed_surface(roughness: float,metalness: float) -> float:
	if baseline:return roughness+2.0*metalness
	return float(int(roundf(roughness*63.0)) | (int(roundf(metalness*31.0))<<6))

func known_history(label: String,roughness: float,motion: Vector3,ortho:=false,
		old_roughness:=-1.0,metalness:=0.0,old_metalness:=-1.0,
		specular_age:=7.0,progressive:=false,normal_change:=0.0,diffuse_age:=7.0,old_depth:=6.0) -> Dictionary:
	size=Vector2i(64,36);camera.size=8;camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	var previous_pose:=camera.global_transform
	camera.position+=motion
	var bytes:=frame();previous_matrices(bytes,previous_pose)
	bytes.encode_float(145*4,256 if progressive else 8)
	bytes.encode_float(146*4,float(motion==Vector3.ZERO))
	var inputs: Array[Image]=[]
	for i in 8:inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGBAH))
	var old_normal:=Vector3(sin(normal_change),0,cos(normal_change))
	for y in size.y:
		for x in size.x:
			var value:=float(x%2)
			inputs[0].set_pixel(x,y,Color(value,0,0,1))
			inputs[1].set_pixel(x,y,Color(0,0,1,6))
			inputs[2].set_pixel(x,y,Color(value,0,0,1))
			inputs[3].set_pixel(x,y,Color(0.6,0.6,0.6,packed_surface(roughness,metalness)))
			inputs[4].set_pixel(x,y,Color(0.8,0,0,diffuse_age))
			inputs[5].set_pixel(x,y,Color(old_normal.x,0,old_normal.z,old_depth))
			inputs[6].set_pixel(x,y,Color(0.8,0,0,specular_age))
			inputs[7].set_pixel(x,y,Color(0.6,0.6,0.6,packed_surface(
				roughness if old_roughness<0 else old_roughness,metalness if old_metalness<0 else old_metalness)))
	bytes.encode_float(82*4,0)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var current_d:=filtered_result.get_pixel(32,18)
	var current_s:=filtered_specular.get_pixel(32,18)
	bytes.encode_float(82*4,1)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	var d:=filtered_result.get_pixel(32,18);var s:=filtered_specular.get_pixel(32,18)
	var row:={"diffuse":d.r,"diffuse_age":d.a,"specular":s.r,"specular_age":s.a,
		"current_diffuse":current_d.r,"current_specular":current_s.r,"specular_residue":absf(s.r-current_s.r)}
	report[label]=row
	return row

func native_materials() -> void:
	mesh_data.clear();geometries.clear();placements.clear()
	var surfaces: Array[Vector2]=[Vector2(0.08,0),Vector2(0.2,0.4),Vector2(0.6,0.2),Vector2(0.5,0.5),Vector2(1,1)]
	for i in surfaces.size():
		var x:=float(i-2)*1.2
		quad(mesh_data,[Vector3(x-0.5,-1,0),Vector3(x+0.5,-1,0),Vector3(x+0.5,1,0),Vector3(x-0.5,1,0)],Vector3.BACK,Vector3.ZERO)
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(surfaces[i].x,surfaces[i].y,0.5)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8
	camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	device=PathDevice.new()
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await device.prepared,"build mixed-metalness material guide fixture")
	await render_many(1)
	var encoded:=[]
	for i in surfaces.size():
		var value:=sample(device.shadow1,Vector3((i-2)*1.2,0,0)).a
		encoded.append(value)
		if not baseline:
			var r:=float(int(roundf(value))&63)/63.0;var m:=float(int(roundf(value))>>6)/31.0
			check(absf(r-surfaces[i].x)<=0.01 and absf(m-surfaces[i].y)<=0.019,"native half-float guide preserves roughness and fractional metalness "+str(surfaces[i]))
	report["material_codes"]=encoded
	if not baseline:check(encoded[1]!=encoded[2],"formerly colliding material combinations have distinct guides")

func highlight_sequence(roughness: float,step: float) -> Dictionary:
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data.clear();geometries.clear();placements.clear()
	quad(mesh_data,[Vector3(-100,0,-100),Vector3(100,0,-100),Vector3(100,0,100),Vector3(-100,0,100)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(roughness,1,0.5)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await device.prepared,"build deterministic glossy motion fixture "+str(roughness))
	size=Vector2i(640,360);camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=Vector3(0,4,-3);camera.look_at(Vector3.ZERO)
	sun_direction=Vector3(0,0.8,0.6);sun_energy=0.005;sky_energy=0;bounces=1
	sequence=true;sequence_previous=camera.global_transform
	var errors:=[];var raw_energy:=[];var filtered_energy:=[]
	for i in 44:
		if i>=16:camera.position.x+=step
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(i>0)))
		await frames(2);await RenderingServer.frame_post_draw
		sequence_previous=camera.global_transform
		if i<16:continue
		RenderingServer.call_on_render_thread(read_raw);await filtered
		var output:=device.shadow0.get_image()
		var absolute_error:=0.0;var reference_sum:=0.0;var actual_sum:=0.0
		for y in range(40,size.y-40):
			for x in range(80,size.x-80):
				var reference_value:=raw_result.get_pixel(x,y).r;var actual:=output.get_pixel(x,y).r
				absolute_error+=absf(reference_value-actual);reference_sum+=reference_value;actual_sum+=actual
		errors.append(absolute_error/maxf(reference_sum,0.0001));raw_energy.append(reference_sum);filtered_energy.append(actual_sum)
		if i==43:
			raw_result.save_png(out.path_join("highlight-%s-reference.png"%roughness))
			output.save_png(out.path_join("highlight-%s-filtered.png"%roughness))
	var error:=0.0
	for value: float in errors:error+=value
	sequence=false
	return {"roughness":roughness,"camera_step":step,"frames":errors.size(),"mean_relative_absolute_error":error/errors.size(),
		"error_per_frame":errors,"raw_energy":raw_energy,"filtered_energy":filtered_energy}

func stationary_noise() -> void:
	# Reuse the roughness-.35 metal floor, with a uniform environment and an
	# orthographic grazing view. Spatial signal variation is now exactly zero;
	# the measured variance comes from path sampling, not highlight structure.
	size=Vector2i(320,180);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8
	camera.position=Vector3(0,8,64);camera.look_at(Vector3.ZERO)
	sun_energy=0;sky_energy=1;sequence=true;sequence_previous=camera.global_transform
	for i in 32:
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(i>0)))
		await frames(2)
	await RenderingServer.frame_post_draw
	RenderingServer.call_on_render_thread(read_raw);await filtered
	var output:=device.shadow0.get_image()
	var raw:=statistics(raw_result);var reconstructed:=statistics(output)
	var age:=output.get_pixel(size.x/2,size.y/2).a
	var integral:=reference(roundf(0.35*255.0)/255.0,Vector3.ONE,camera.global_basis.z.y)
	# Neighbourhood clamping is biased. Record that bias against an independent
	# integral and compare it with the saved baseline; variance alone is not an
	# energy-conservation test. The native unfiltered signal must still agree.
	report["stationary_noise"]={"raw":raw,"filtered":reconstructed,"centre_age":age,
		"integral":integral.x,"filtered_relative_bias":(reconstructed.mean[0]-integral.x)/integral.x}
	check(reconstructed.variance[0]<raw.variance[0]*0.25,"stationary glossy reconstruction reduces sampling variance by at least 75 percent")
	check(absf(raw.mean[0]-integral.x)<0.01,"native stationary glossy energy agrees with independent hemisphere integration")
	check(age>7.9,"native stationary glossy confidence reaches eight frames")
	raw_result.save_png(out.path_join("stationary-noise-raw.png"));output.save_png(out.path_join("stationary-noise-filtered.png"))
	sequence=false

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--glossy-baseline":baseline=true
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified glossy reconstruction device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	sun_energy=0;sky_energy=0;bounces=1
	await native_materials()
	var still:=await known_history("stationary",0.08,Vector3.ZERO)
	check(still.diffuse_age>7.9 and still.specular_age>7.9,"stationary glossy and diffuse histories both accumulate")
	var moved:=await known_history("glossy_motion",0.08,Vector3(0.4,0,0))
	var rough:=await known_history("rough_motion",0.9,Vector3(0.4,0,0))
	var ortho:=await known_history("orthographic_translation",0.08,Vector3(0.4,0,0),true)
	check(moved.diffuse_age>7.9 and rough.diffuse_age>7.9,"camera motion retains matching diffuse history")
	check(ortho.specular_age>7.9,"orthographic translation retains an unchanged reflection direction")
	if not baseline:
		check(moved.specular_age<1.1 and moved.specular_residue<0.02,"smooth perspective reflections discard changed viewing directions")
		check(rough.specular_age>7.0,"rough reflection lobes keep useful history during the same movement")
	var independent:=await known_history("independent_age",0.9,Vector3.ZERO,false,-1,0,-1,1)
	if not baseline:check(independent.diffuse_age>7.9 and absf(independent.specular_age-2)<0.02,"glossy confidence recovers independently of diffuse age")
	var invalid:=await known_history("invalid_specular",0.9,Vector3.ZERO,false,-1,0,-1,0)
	if not baseline:check(invalid.diffuse_age>7.9 and invalid.specular_age==1,"invalid glossy history does not invalidate diffuse history")
	var invalid_diffuse:=await known_history("invalid_diffuse",0.9,Vector3.ZERO,false,-1,0,-1,7,false,0,0)
	if not baseline:check(invalid_diffuse.diffuse_age==1 and invalid_diffuse.specular_age>7.9,"invalid diffuse history does not invalidate glossy history")
	var depth:=await known_history("depth_discontinuity",0.9,Vector3.ZERO,false,-1,0,-1,7,false,0,7,8)
	check(depth.diffuse_age==1 and depth.specular_age==1,"unrelated depth layer rejects both histories")
	var collision:=await known_history("material_collision",0.2,Vector3.ZERO,false,0.6,0.4,0.2)
	if not baseline:check(collision.diffuse_age==1 and collision.specular_age==1,"different roughness/metalness combinations reject aliased history")
	var curved:=await known_history("normal_change",0.08,Vector3.ZERO,false,-1,0,-1,7,false,0.08)
	if not baseline:check(curved.diffuse_age>7.9 and curved.specular_age<1.1,"normal changes reject glossy history within diffuse normal tolerance")
	var progressive:=await known_history("progressive_stationary",0.08,Vector3.ZERO,false,-1,0,-1,128,true)
	if not baseline:check(absf(progressive.specular_age-129)<0.05,"still-scene glossy history continues beyond the responsive limit")
	var full:=await known_history("progressive_full",0.08,Vector3.ZERO,false,-1,0,-1,255,true)
	if not baseline:check(full.specular_age==256,"still-scene glossy confidence reaches its full 256-frame budget")
	var cut:=await known_history("progressive_motion",0.08,Vector3(0.4,0,0),false,-1,0,-1,128,true)
	check(cut.diffuse_age==1 and cut.specular_age==1,"still-scene camera motion resets both histories")
	for roughness: float in [0.12,0.35]:
		var row:=await highlight_sequence(roughness,0.04)
		report["highlight_"+str(roughness)]=row
		check(is_finite(row.mean_relative_absolute_error),"native highlight measurement remains finite "+str(roughness))
		if not baseline:check(row.mean_relative_absolute_error<(0.28 if roughness<0.2 else 0.18),"moving native highlight remains within its reconstruction error budget "+str(roughness))
	await stationary_noise()
	FileAccess.open(out.path_join("path-glossy.json"),FileAccess.WRITE).store_string(JSON.stringify({"baseline":baseline,"checks":checks,"failures":failures,"metrics":report},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	camera.queue_free();finish()
