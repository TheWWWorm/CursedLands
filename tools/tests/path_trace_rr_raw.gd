extends "res://tools/tests/path_trace_nrd_directional.gd"
## The SDK must receive current noisy light. A temporal denoiser with a one-
## frame blend still changes samples, so the ray programs must write the
## published images themselves: the raw slots are never filtered in between.
var raw_checks:=[]
var dielectric_specular:=0.0
signal raw_inspected
func inspect_raw() -> void:
	raw_checks.clear()
	var targets: Array[RID]=device.ray_targets()
	for i in 4:raw_checks.append(targets[i]==device._history[i] and device._rd.texture_is_valid(device._history[i]))
	var raw_spec:=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[5],0))
	dielectric_specular=raw_spec.get_pixel(size.x/2,size.y/2).a
	raw_inspected.emit.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified PT device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_direction_fixture(),"build glossy receiver")
	if not device._ready:finish();return
	await render_many(12,{"nrd_directional":true})
	check(device.nrd_active,"baseline denoises through actual NRD")
	var published:=device.published_targets().slice(0,4)
	await render_many(1,{"ray_reconstruction":true})
	check(device.ray_reconstruction and not device.nrd_active and not device._direct_valid,"RR disables temporal/spatial/direct-light filters")
	RenderingServer.call_on_render_thread(inspect_raw);await raw_inspected
	check(raw_checks.all(func(value: bool):return value),"RR traces current diffuse, guide, specular and albedo straight into the published images")
	check(absf(dielectric_specular-.75)<.01,"RR guide source preserves the material dielectric reflectance")
	check(device.raw_reconstruction_frames==1,"raw frame counter follows actual rendering")
	check(device.published_targets().slice(0,4)==published,"RR switches preserve public texture handles")
	check(device.direct_sun.texture_rd_rid==device._raw[6],"terrain and grass receive current unfiltered direct sun")
	var noisy:=device.output.get_image().get_data()
	await render_many(1)
	check(device.output.get_image().get_data()!=noisy,"a new path sample is not replaced by stale history")
	size=Vector2i(173,99);await render_many(1)
	RenderingServer.call_on_render_thread(inspect_raw);await raw_inspected
	check(raw_checks.all(func(value: bool):return value) and device.output.get_width()==173,"odd-sized resize retains the direct published-output contract")
	await render_many(16,{"ray_reconstruction":false,"nrd_directional":true})
	check(not device.ray_reconstruction and device.nrd_active and device.nrd.directional,"RR Off resets and restores directional NRD")
	check(device.ray_targets()[0]==device._raw[0] and device._raw[0]!=device._history[0],"RR Off traces into the raw images again for the denoiser")
	await render_many(1,{"ray_reconstruction":true,"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(mean(device.output).r==0 and mean(device.shadow0).r==0,"disappearing receiver clears raw lighting immediately")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device._raw.is_empty() and device._history.is_empty(),"RR bypass retains ordinary device teardown")
	FileAccess.open(out.path_join("rr-raw.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	camera.queue_free();finish()
