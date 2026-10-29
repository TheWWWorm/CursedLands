extends "res://tools/tests/path_trace_device.gd"
## Native light-sampling energy/variance, dynamic placement IDs, cutout area,
## occlusion and bounded-proposal fallback. No denoising in variance metrics.
signal captured
var raw: Image
var report := {}
var baseline := false
var spp := 1
var light_transform := Transform3D.IDENTITY
var light_emission := Vector3(100,0,0)
var light_standard := true
var light_opaque := false
var light_texture := Color.WHITE
var cutout_half := false
var timing := false
var times := []
var last_gpu_frame := -1

func gpu_time() -> void:
	var rd: RenderingDevice=device._rd
	var current:=rd.get_captured_timestamps_frame()
	if current==last_gpu_frame:return
	last_gpu_frame=current
	var start: int=-1
	for i in rd.get_captured_timestamps_count():
		if rd.get_captured_timestamp_name(i)=="Scene RT begin":start=rd.get_captured_timestamp_gpu_time(i)
		elif rd.get_captured_timestamp_name(i)=="Scene RT end" and start>=0:
			accept_time.call_deferred((rd.get_captured_timestamp_gpu_time(i)-start)/1000000.0)

func accept_time(ms: float) -> void:
	if timing:times.append(ms)

func benchmark(label: String) -> void:
	for i in 124:
		if i==24:times.clear();timing=true
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(false)))
		RenderingServer.call_on_render_thread(gpu_time)
		await frames(1)
	timing=false;times.sort()
	check(times.size()>80,label+": GPU timing covers at least eighty warmed frames")
	if not times.is_empty():report[label]["rt_gpu_ms"]={"n":times.size(),"median":times[times.size()/2],"p95":times[int(times.size()*0.95)]}

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(77*4,spp)
	return bytes

func read_raw(channel:=0) -> void:
	raw=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[channel],0))
	captured.emit.call_deferred()

func statistics(image: Image) -> Dictionary:
	# GDScript scalars accumulate in double precision; Vector3 sums lose too
	# much precision when measuring very small variance over 147,456 pixels.
	var red:=0.0;var green:=0.0;var blue:=0.0;var red2:=0.0;var green2:=0.0;var blue2:=0.0
	var dark:=0;var peak:=0.0
	var pixels:=image.get_width()*image.get_height()
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			red+=c.r;green+=c.g;blue+=c.b;red2+=c.r*c.r;green2+=c.g*c.g;blue2+=c.b*c.b;peak=maxf(peak,c.r)
			if c.r<0.0001:dark+=1
	var average: Array=[red/pixels,green/pixels,blue/pixels]
	return {"mean":average,"variance":[red2/pixels-average[0]*average[0],green2/pixels-average[1]*average[1],blue2/pixels-average[2]*average[2]],"peak":peak,"dark_fraction":float(dark)/pixels,"pixels":pixels}

func capture(label: String,changes: Dictionary={},history:=false,channel:=0) -> Dictionary:
	RenderingServer.call_on_render_thread(device.render.bind(size,frame(history),changes))
	await frames(2);await RenderingServer.frame_post_draw
	RenderingServer.call_on_render_thread(read_raw.bind(channel));await captured
	var row:=statistics(raw);report[label]=row
	raw.save_png(out.path_join(label+".png"))
	return row

func reference(transform:=Transform3D.IDENTITY,half:=false) -> float:
	# Midpoint area quadrature, independent of the CDF, triangle sampler and
	# production PDFs. Evaluate the receiver at the centre of its tiny view.
	var sum:=0.0
	var normal: Vector3=(transform.basis*Vector3.RIGHT).cross(transform.basis*Vector3.BACK).normalized()
	var area: float=(transform.basis*Vector3(0.3,0,0)).cross(transform.basis*Vector3(0,0,0.3)).length()
	for z in 192:
		for x in 192:
			if half and x>=96:continue
			var p: Vector3=transform*Vector3(0.2+0.3*(x+0.5)/192.0,2.0,-0.15+0.3*(z+0.5)/192.0)
			# Integrate at the physical receiver. A numerical ray-origin offset
			# should converge to this surface, not redefine the reference plane.
			var delta:=p;var distance2:=delta.length_squared();var l:=delta.normalized()
			var fresnel: float=pow(1.0-Vector3.UP.dot((Vector3.UP+l).normalized()),5)
			sum+=(1.0-fresnel)*maxf(l.y,0.0)*absf(normal.dot(l))/distance2
	return sum*area/(PI*192.0*192.0)

func fixture(metal:=false,blocker:=false) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array()
	quad(mesh_data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(0.2,2,-0.15),Vector3(0.5,2,-0.15),Vector3(0.5,2,0.15),Vector3(0.2,2,0.15)],Vector3.DOWN,light_emission)
	var uv: Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]
	for i in 6:
		mesh_data[(6+i)*16+3]=uv[i].x;mesh_data[(6+i)*16+7]=uv[i].y;mesh_data[(6+i)*16+15]=1.0
	quad(mesh_data,[Vector3(-5,1,-5),Vector3(5,1,-5),Vector3(5,1,5),Vector3(-5,1,5)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.25,1,0.5) if metal else Vector3(1,0,0)},
		{"offset":6,"count":6,"standard":light_standard,"opaque":light_opaque,"cutoff":0.5,"surface":Vector3(1,0,0)},
		{"offset":12,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)}]
	# Duplicate geometry has different stable placement IDs. The fourth
	# placement blocks indirect rays without casting conventional shadows.
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},
		{"geometry":1,"transform":light_transform,"mask":5},
		{"geometry":1,"transform":Transform3D(Basis.IDENTITY,Vector3(-0.7,0,0)),"mask":0},
		{"geometry":2,"transform":Transform3D.IDENTITY,"mask":4 if blocker else 0}]
	var white:=Image.create(32,32,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var glow:=Image.create(32,32,false,Image.FORMAT_RGBA8);glow.fill(light_texture)
	if cutout_half:
		for y in 32:
			for x in range(16,32):glow.set_pixel(x,y,Color(light_texture,0.0))
	var images: Array[Image]=[white,glow]
	device=PathDevice.new();RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func disable_proposal() -> void:
	# Simulate an omitted light without changing geometry or its emission.
	device._rd.buffer_update(device.get("_emitters"),0,4,PackedInt32Array([0]).to_byte_array())
	captured.emit.call_deferred()

func check_table() -> void:
	var table: RefCounted=device.get("emitters")
	var bytes: PackedByteArray=table.records;var lookup: PackedByteArray=table.lookup
	var found:=0;var probability:=0.0
	for i in int(table.count):
		var start:=16+i*64;var instance:=bytes.decode_u32(start+48);var primitive:=bytes.decode_u32(start+52)
		var slot: int=table.hash_slot(instance,primitive)
		for probe in 8192:
			var key:=lookup.decode_u32(slot*16)
			if key==0:break
			if key==instance+1 and lookup.decode_u32(slot*16+4)==primitive:
				if lookup.decode_u32(slot*16+8)==i:found+=1
				break
			slot=(slot+1)&8191
		probability+=bytes.decode_float(start+28)
	check(found==table.count and absf(probability-1.0)<0.000001,"every selected triangle has a matching hit PDF and normalized probability")

func bounded_table() -> void:
	var Table: GDScript=load("res://src/game/fx/path_trace_emitters.gd")
	var table: RefCounted=Table.new();var instances:=[]
	for i in 2051:
		instances.append({"geometry":0,"transform":Transform3D(Basis.IDENTITY,Vector3(i,0,0)),"mask":4})
	var data:=mesh_data.slice(6*16,12*16).to_byte_array()
	table.setup(data,[{"offset":0,"count":6,"standard":true,"opaque":false}],instances)
	check(table.count==4096 and table.candidates==4102,"light proposal caps 4102 candidates at 4096 with bounded GPU storage")
	check(table.records.size()==16+4096*64 and table.lookup.size()==8192*16,"proposal and hit lookup stay within 384 KiB plus header")
	var cumulative:=0.0;var valid:=true
	for i in int(table.count):
		var cdf: float=table.records.decode_float(16+i*64+44)
		var pmf: float=table.records.decode_float(16+i*64+28)
		valid=valid and cdf>cumulative and absf(cdf-cumulative-pmf)<1e-7;cumulative=cdf
	check(valid and cumulative==1.0,"bounded CDF and hit PMFs agree at float precision")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--emitter-baseline":baseline=true
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native emitter sampler")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.1
	camera.position=Vector3(0,0.5,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	sun_energy=0;sky_energy=0;bounces=1;size=Vector2i(512,288)
	check(await fixture(),"build small bright emitter above diffuse floor")
	if not device._ready:finish();return
	var expected:=reference()*light_emission.x
	var row:=await capture("small-emitter");row["reference"]=expected
	check(absf(row.mean[0]-expected)<expected*0.09,"one-sample emitter energy agrees with independent area quadrature")
	await benchmark("small-emitter")
	# Both packages run the identical fixture for an honest A/B noise measure.
	if not baseline:
		check(row.dark_fraction<0.001,"directly sampled small emitter no longer leaves black one-sample pixels")
		check(row.variance[0]<0.01,"small-emitter raw variance remains below 0.01")
		check_table()
		RenderingServer.call_on_render_thread(disable_proposal);await captured
		var fallback:=await capture("omitted-emitter");fallback["reference"]=expected
		check(absf(fallback.mean[0]-expected)<expected*0.09,"an emitter omitted from the proposal retains its BSDF-hit energy")
		check(await fixture(),"restore emitter proposal")
		var lit_pipeline: RID=device._pipeline;var scene_handle: RID=device._tlas
		var posed:=mesh_data.slice(6*16,12*16)
		for i in 6:posed[i*16]+=0.4;posed[i*16+1]+=0.2
		var pose_row:=await capture("posed-emitter",{"poses":[{"geometry":1,"data":posed.to_byte_array()}]},true)
		var pose_expected:=reference(Transform3D(Basis.IDENTITY,Vector3(0.4,0.2,0)))*light_emission.x
		pose_row["reference"]=pose_expected
		check(absf(pose_row.mean[0]-pose_expected)<pose_expected*0.03,"emissive vertex deformation updates the sampled surface")
		for i in 6:posed[i*16+12]=0.0
		var extinguished:=await capture("extinguished-emitter",{"poses":[{"geometry":1,"data":posed.to_byte_array()}]},true)
		check(extinguished.mean[0]==0 and mean(device.output).a<1.1,"extinguishing emission through vertex updates clears accumulated light")
		check(not device.get("_uses_emitters") and device._pipeline!=lit_pipeline and device._tlas==scene_handle,"last emitter removal selects the lean raygen without replacing the scene")
		var stable_output: RID=device.output.texture_rd_rid
		var relit:=await capture("relit-emitter",{"poses":[{"geometry":1,"data":mesh_data.slice(6*16,12*16).to_byte_array()}]},true)
		check(absf(relit.mean[0]-expected)<expected*0.03,"newly emissive snapshot geometry enters the light proposal")
		check(device.get("_uses_emitters") and device._pipeline==lit_pipeline and device.output.texture_rd_rid==stable_output,"relighting reuses the cached emitter pipeline and stable output textures")
		var two:=await capture("two-instances",{"instances":[{"index":2,"transform":placements[2].transform,"mask":5}]})
		check(absf(two.mean[0]-expected*2)<expected*0.05,"two placements of one mesh contribute independently")
		check_table()
		await render_many(12)
		var one:=await capture("hidden-instance",{"instances":[{"index":1,"transform":light_transform,"mask":0}]},true)
		check(absf(one.mean[0]-expected)<expected*0.03 and mean(device.output).a<1.1,"hiding an emitter rebuilds the compact TLAS and clears its lighting history")
		var table: RefCounted=device.get("emitters");var revision: int=table.revision
		await capture("hidden-emitter-movement",{"instances":[{"index":1,"transform":Transform3D(Basis.IDENTITY,Vector3(10,0,0)),"mask":0}]},true)
		check(table.revision==revision and mean(device.output).a>1.9,"hidden emissive movement preserves valid scene accumulation")
		await capture("ordinary-movement",{"instances":[{"index":3,"transform":Transform3D(Basis.IDENTITY,Vector3(0,5,0)),"mask":0}]},true)
		check(table.revision==revision,"non-emissive movement does not rebuild the light proposal")
		var moved:=Transform3D(Basis.from_scale(Vector3(2,1,3)),Vector3(1,1,0))
		var moved_row:=await capture("scaled-moved-instance",{"instances":[{"index":2,"transform":moved,"mask":5}]},true)
		var moved_expected:=reference(moved)*light_emission.x;moved_row["reference"]=moved_expected
		check(absf(moved_row.mean[0]-moved_expected)<moved_expected*0.03,"non-uniform scaling and movement update emitter area, placement and PDF")
		var dark:=await capture("indirect-hidden",{"instances":[{"index":2,"transform":moved,"mask":1}]},true)
		check(dark.mean[0]==0 and table.count==0 and mean(device.output).a<1.1,"primary-only emitter has no indirect contribution or stale history")
		revision=table.revision
		await capture("camera-only-pose",{"poses":[{"geometry":1,"data":posed.to_byte_array()}]},true)
		check(table.revision==revision and mean(device.output).a>1.9,"deforming camera-only or hidden emission does not reset history")
		check(await fixture(false,true),"build non-shadow-casting occluder")
		var blocked:=await capture("blocked-emitter")
		check(blocked.mean[0]==0,"emitter visibility matches continuation geometry even without a shadow mask")
		cutout_half=true
		check(await fixture(),"build partially cutout emissive surface")
		var alpha:=await capture("cutout-emitter");var alpha_expected:=reference(Transform3D.IDENTITY,true)*light_emission.x
		alpha["reference"]=alpha_expected
		check(absf(alpha.mean[0]-alpha_expected)<alpha_expected*0.04,"cutout samples remain zero, preserving only the emitting area")
		cutout_half=false;light_standard=false;light_emission=Vector3(2,1,0.5);light_texture=Color(0.5,1,1)
		check(await fixture(),"build texture-modulated shader emission")
		var textured:=await capture("textured-emitter");var energy:=reference()
		check(absf(textured.mean[0]/energy-1.0)<0.025 and absf(textured.mean[1]/energy-1.0)<0.025 and absf(textured.mean[2]/energy-0.21404)<0.01,"shader emission keeps the existing texture modulation and linear conversion")
		# Opaque constant emission keeps linear colour independently of the
		# diffuse texture; opaque textured emitters retain modulation.
		light_opaque=true;light_standard=true;light_emission=Vector3(2,1,0.5)
		light_texture=Color(0.1,0.2,0.3)
		check(await fixture(),"build opaque constant emitter with a dark diffuse texture")
		var constant:=await capture("opaque-constant-emitter")
		check(absf(constant.mean[0]/energy-2.0)<0.05 and absf(constant.mean[1]/energy-1.0)<0.025 and absf(constant.mean[2]/energy-0.5)<0.015,"opaque constant emission stays linear and independent of diffuse texture")
		light_standard=false;light_texture=Color(0.5,1,1)
		check(await fixture(),"build opaque textured emitter")
		var opaque_textured:=await capture("opaque-textured-emitter")
		check(absf(opaque_textured.mean[0]/energy-1.0)<0.025 and absf(opaque_textured.mean[1]/energy-1.0)<0.025 and absf(opaque_textured.mean[2]/energy-0.21404)<0.01,"opaque shader emission retains texture modulation and linear conversion")
		light_opaque=false
		bounded_table()
	# A narrow glossy lobe should retain energy when BSDF sampling is better
	# than the area proposal; compare both binaries against each other as well.
	cutout_half=false;light_standard=true;light_emission=Vector3(100,0,0);light_texture=Color.WHITE
	check(await fixture(true),"build glossy emitter reflection")
	spp=16
	var glossy:=await capture("glossy-emitter",{},false,2)
	check(glossy.mean[0]>1 and glossy.mean[1]<0.001,"small emitter preserves its colour in glossy reflections")
	await benchmark("glossy-emitter")
	var glossy_two:=await capture("glossy-two-instances",{"instances":[{"index":2,"transform":placements[2].transform,"mask":5}]},false,2)
	check(absf(glossy_two.mean[0]-2.0*glossy.mean[0])<glossy.mean[0]*0.04,"BSDF-hit MIS weights distinguish two glossy reflections of one shared mesh")
	spp=4
	var high:=await capture("glossy-emitter-4spp",{"instances":[{"index":2,"transform":placements[2].transform,"mask":0}]},false,2)
	check(absf(high.mean[0]-glossy.mean[0])<glossy.mean[0]*0.03,"four-sample quality preserves the same glossy energy")
	await benchmark("glossy-emitter-4spp")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device._owned.is_empty(),"emitter buffers are freed with their scene")
	FileAccess.open(out.path_join("path-emitters.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report,"baseline":baseline},"\t"))
	camera.queue_free();finish()
