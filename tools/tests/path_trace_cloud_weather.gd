extends "res://tools/tests/path_trace_daylight.gd"
var cloud_mode := 0

func retire_cloud_descriptor() -> void:
	# RD automatically invalidates descriptors when their external viewport
	# texture disappears. Reproduce that lifetime without owning its texture.
	device._rd.free_rid(device._set)
	device.set_cloud_texture(device._cloud_texture)

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(68*4,0.0);bytes.encode_float(69*4,1.0);bytes.encode_float(70*4,0.0)
	bytes.encode_float(147*4,0.0)
	var cloud:=PackedFloat32Array([0.5,0.6,160,float(cloud_mode),0,0,0,0,-50,-50,100,4])
	for i in 12:bytes.encode_float((176+i)*4,cloud[i])
	return bytes

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var amb:=Color(0.5,0.55,0.6);var sun:=Color.WHITE
	var clear:=SkyPalette.overcast(amb,sun,0.0,false)
	var rain:=SkyPalette.overcast(amb,sun,1.0,false)
	check(clear==[amb,sun],"clear weather retains the authored palette exactly")
	check(rain[1].srgb_to_linear().r<0.2 and rain[0].srgb_to_linear().r>amb.srgb_to_linear().r*0.6,
		"rain suppresses direct sun while retaining readable diffuse skylight")
	check(SkyPalette.overcast(amb,sun,1.0,true)==clear,"caves ignore outdoor weather")
	var night:=Color(0.1,0.2,0.3)
	check(SkyPalette.overcast(amb,night,1.0,false)==[amb,night],"night brightness remains unchanged")
	var previous:=1.0
	for i in 21:
		var amount:=(1.0-cos(PI*float(i)/20.0))*0.5
		var value:=SkyPalette.overcast(amb,sun,amount,false)[1].srgb_to_linear().r
		check(value<=previous+0.00001,"rain fades monotonically with precipitation %d"%i);previous=value
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,2,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(128,72);sun_energy=1;sky_energy=0;bounces=1;directional=false
	check(await build_plane(),"cloud transport receiver builds")
	await render_many(8);var unshadowed:=mean(device.output).r
	var im:=Image.create(4,4,true,Image.FORMAT_RGBA8);im.fill(Color(0.25,0.25,0.25,1));im.generate_mipmaps()
	var tex:=ImageTexture.create_from_image(im)
	RenderingServer.call_on_render_thread(device.set_cloud_texture.bind(tex));cloud_mode=2
	await render_many(8);var field:=mean(device.output).r
	check(absf(field/unshadowed-0.25)<0.01,"volume field attenuates traced solar energy to quarter strength")
	cloud_mode=0;await render_many(8)
	check(absf(mean(device.output).r-unshadowed)<0.01,"disabling clouds restores traced solar energy")
	im.fill(Color.WHITE);im.generate_mipmaps();var dense:=ImageTexture.create_from_image(im)
	RenderingServer.call_on_render_thread(device.set_cloud_texture.bind(dense));cloud_mode=1
	await render_many(8);var sheet:=mean(device.output).r
	check(absf(sheet/unshadowed-0.4)<0.01,"dense sheet agrees with raster shadow transmission")
	RenderingServer.call_on_render_thread(retire_cloud_descriptor);await render_many(4)
	check(absf(mean(device.output).r/unshadowed-0.4)<0.01,"retired external descriptor is safely rebuilt")
	cloud_mode=0;RenderingServer.call_on_render_thread(device.set_cloud_texture.bind(null));await render_many(4)
	check(absf(mean(device.output).r-unshadowed)<0.01,"removing the cloud texture restores the fallback binding")
	report["clouds"]={"clear":unshadowed,"volume":field,"sheet":sheet}
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device._cloud_texture==null and not device._cloud_image.is_valid(),"cloud bindings release on teardown")
	FileAccess.open(out.path_join("path-cloud-weather.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
