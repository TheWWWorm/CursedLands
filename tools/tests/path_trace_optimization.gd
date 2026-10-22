extends "res://tools/tests/path_trace_contacts.gd"
## Compare the raw estimator against a saved pre-optimization package. Fixed
## first/last/sparse point-light cases also have an independent additive oracle.
var slots: Array[int]=[]
var reference_path:=""

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	for i in 7:
		for c in 4:
			bytes.encode_float((88+i*4+c)*4,0.0)
			bytes.encode_float((116+i*4+c)*4,0.0)
	for slot in slots:
		bytes.encode_float((88+slot*4+1)*4,1.0)
		bytes.encode_float((88+slot*4+3)*4,10.0)
		for c in 3:bytes.encode_float((116+slot*4+c)*4,1.0)
	return bytes

func room(albedo: float,metal: bool,point: bool) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[];slots.clear()
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(-2,2,2)],Vector3.DOWN,Vector3.ZERO if point else Vector3(2,0.4,0.1))
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(-2,2,2),Vector3(-2,0,2)],Vector3.RIGHT,Vector3.ZERO)
	quad(mesh_data,[Vector3(2,0,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.LEFT,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,0,-2)],Vector3.BACK,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,2),Vector3(-2,2,2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.FORWARD,Vector3.ZERO)
	for vertex in mesh_data.size()/16:
		for c in 3:mesh_data[vertex*16+8+c]=albedo
	for i in 6:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.25,1,0.5) if i==0 and metal else Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	if point:slots=[6]
	camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO)
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new();RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func estimate(label: String) -> Dictionary:
	var means: Array=[0.0,0.0];var variance: Array=[0.0,0.0]
	tick=0
	for sample_index in 16:
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(false)))
		await frames(2)
		for channel in 2:
			RenderingServer.call_on_render_thread(read_raw.bind(channel*2));await captured
			var measured:=statistics(raw)
			means[channel]+=measured.mean[0]/16.0;variance[channel]+=measured.variance[0]/16.0
	var row:={"mean":means,"variance":variance,"samples_per_pixel":spp*16}
	check(is_finite(means[0]) and is_finite(means[1]),label+": finite raw diffuse and specular")
	report[label]=row;return row

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--pt-reference="):reference_path=arg.trim_prefix("--pt-reference=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified optimization fixture")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.1
	sun_energy=0;sky_energy=0;bounces=1;spp=1;size=Vector2i(192,108)
	check(await contact_fixture(0,Transform3D.IDENTITY,"lamp"),"build finite point-light receiver")
	var one:=0.0
	for lights: Array in [[0],[3],[6],[1,3,6],[0,1,2,3,4,5,6],[]]:
		slots.assign(lights)
		var label:="point-slots-"+str(lights);var row:=await capture(label)
		if lights==[0]:one=row.mean[0];check(one>0.98,"point light agrees with inverse-range attenuation near the origin")
		check(absf(row.mean[0]-one*lights.size())<0.005,label+": disabled holes and last slot preserve summed illumination")
	slots.clear();spp=16;sun_energy=0;sky_energy=0
	for material in [[0.2,false,false],[0.6,false,false],[0.6,true,false],[0.6,false,true]]:
		check(await room(material[0],material[1],material[2]),"build closed energy fixture "+str(material))
		var short_pipeline:=RID()
		for depth in [2,4]:
			bounces=depth
			await estimate("room-%s-%s-%d"%[material[0],material[1],depth]+("-point" if material[2] else ""))
			if depth==2:short_pipeline=device._pipeline
			elif device.get("_deep_paths")!=null:
				check(device._deep_paths and device._pipeline!=short_pipeline,"four-bounce mode selects its deep-path pipeline")
		if device.get("_deep_paths")!=null:
			var scene_handle: RID=device._tlas;var output_handle: RID=device.output.texture_rd_rid
			bounces=2;await render_many(1)
			check(not device._deep_paths and device._pipeline==short_pipeline,"two-bounce mode reuses its original cached pipeline")
			check(device._tlas==scene_handle and device.output.texture_rd_rid==output_handle,"bounce-mode switches retain scene and output allocations")
			check(mean(device.output).a<1.1,"bounce-mode switches discard incompatible lighting history")
	if not reference_path.is_empty():
		var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(reference_path))
		for label in report:
			if not label.begins_with("room-"):continue
			check(reference.metrics.has(label),"reference includes "+label)
			if not reference.metrics.has(label):continue
			for channel in 2:
				var expected: float=reference.metrics[label].mean[channel]
				check(absf(report[label].mean[channel]-expected)<maxf(0.0002,expected*0.02),label+": raw energy within 2% of full-path reference, channel "+str(channel))
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	FileAccess.open(out.path_join("path-optimization.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
