extends "res://tools/tests/path_trace_quality.gd"
## Real traced first moments and REBLUR SH dispatches. The flat receiver makes
## a normal-as-direction shortcut fail; opposing lights detect normalization
## of a multi-sample moment. Exercise both reconstruction modes on one device.
var lamps: Array[Vector3]=[Vector3(2,2,0)]
var captured: Array[Image]=[]
signal captured_frame

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(145*4,8.0)
	bytes.encode_float(188*4,lamps.size());bytes.encode_float(191*4,1.0)
	for i in lamps.size():
		for c in 3:
			bytes.encode_float((192+i*4+c)*4,lamps[i][c])
			bytes.encode_float((448+i*4+c)*4,1.0)
		bytes.encode_float((195+i*4)*4,10.0)
	return bytes

func capture() -> void:
	captured.clear()
	for i in [0,1,2,7,8]:
		captured.append(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[i],0)))
	captured_frame.emit.call_deferred()

func centre(index: int) -> Color:
	return captured[index].get_pixel(size.x/2,size.y/2)

func build_direction_fixture() -> bool:
	device=PathDevice.new()
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified directional NRD device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=1
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.6,0,0.5)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_direction_fixture(),"build flat receiver and off-axis lamp")
	if not device._ready:finish();return
	check(device.nrd.available,"native NRD loaded")
	await render_many(24)
	check(device._raw.size()==9,"tracer supplies both directional targets")
	if device._raw.size()!=9:
		RenderingServer.call_on_render_thread(device.dispose);await frames();camera.queue_free();finish();return
	check(device.nrd_active and device.nrd._description.get("directional",false),"actual SH planner and GPU passes execute")
	check(device.nrd._external.size()==13,"both SH1 inputs and both SH1 outputs are bound")
	RenderingServer.call_on_render_thread(capture);await captured_frame
	var d:=centre(3);var direction:=Vector3(d.r,d.g,d.b)
	check(direction.x>0.6 and direction.y>0.6 and absf(direction.z)<0.03,"diffuse direction points to the lamp, not the up-facing normal: "+str(d))
	check(absf(direction.length()-1.0)<0.01,"one deterministic light has a unit first moment")
	check(centre(4).is_equal_approx(Color(0,0,0,0)),"analytic specular stays out of the indirect SH signal")
	var sh_energy:=mean(device.output).r
	check(is_finite(sh_energy) and sh_energy>0.1 and sh_energy<2.0,"directional reconstruction has finite, bounded energy")
	device.output.get_image().save_exr(out.path_join("off-axis-sh.exr"))
	await render_many(24,{"nrd_directional":false})
	check(device.nrd_active and not device.nrd._description.directional,"same device switches to the radiance planner")
	check(device.nrd._external.size()==9,"switching to radiance frees the directional external images")
	var scalar_energy:=mean(device.output).r
	check(absf(sh_energy-scalar_energy)<scalar_energy*0.35,"SH resolve preserves diffuse energy within its documented approximation: %s / %s"%[sh_energy,scalar_energy])
	lamps=[Vector3(-2,2,0)];await render_many(16,{"nrd_directional":true})
	RenderingServer.call_on_render_thread(capture);await captured_frame
	d=centre(3)
	check(device.nrd_active and device.nrd._description.directional and d.r< -0.6,"return to SH follows a lamp moved across the receiver")
	lamps=[Vector3(-2,2,0),Vector3(2,2,0)];await render_many(16)
	RenderingServer.call_on_render_thread(capture);await captured_frame
	d=centre(3);direction=Vector3(d.r,d.g,d.b)
	check(absf(d.r)<0.03 and d.g>0.68 and d.g<0.74 and direction.length()<0.75,"opposing lights retain a broad first moment rather than normalizing it: "+str(d))
	# Remove all local light; only indirect sky remains, including glossy paths.
	lamps=[];sky_energy=1.0;await render_many(24)
	RenderingServer.call_on_render_thread(capture);await captured_frame
	d=centre(4)
	check(d.a>0 and d.g>0 and Vector3(d.r,d.g,d.b).length()<=1.002,"glossy continuation emits a finite upper-hemisphere first moment")
	check(mean(device.shadow0).r>0 and is_finite(mean(device.shadow0).r),"SG specular reconstruction retains sky reflection")
	# Newly exposed sky must clear both moment targets and denoised radiance.
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]})
	RenderingServer.call_on_render_thread(capture);await captured_frame
	check(centre(3).is_equal_approx(Color(0,0,0,0)) and centre(4).is_equal_approx(Color(0,0,0,0)),"miss clears both directional targets")
	check(mean(device.output).r==0 and mean(device.shadow0).r==0,"miss cannot present stale SG lighting")
	size=Vector2i(129,73)
	await render_many(2,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":7}]})
	check(device.nrd_active and device.nrd._description.directional and device.output.get_width()==129,"odd-sized resize rebuilds the SH pools")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device.nrd._textures.is_empty() and device.nrd._external.is_empty() and device._raw.is_empty(),"directional images and NRD history are released")
	FileAccess.open(out.path_join("nrd-directional.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"sh_energy":sh_energy,"radiance_energy":scalar_energy},"\t"))
	camera.queue_free();finish()
