extends "res://tools/tests/path_trace_quality.gd"
const SkyPalette = preload("res://src/game/fx/path_trace_sky.gd")
var directional := true
var textured := false
var relief := 0.0
var uv_mirror := false
var degenerate_uv := false
var uv_scale := 1.0
var fixture_normal := Vector3.UP
var transform := Transform3D.IDENTITY

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(77*4,4.0)
	bytes.encode_float(147*4,float(directional))
	# RGB axes distinguish zenith (blue), horizon (red), ground (green).
	bytes.encode_float(166*4,1.0);bytes.encode_float(168*4,1.0);bytes.encode_float(173*4,1.0)
	return bytes

func build_plane() -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new();mesh_data.clear()
	var tangent:=Vector3.RIGHT if absf(fixture_normal.x)<0.9 else Vector3.FORWARD
	var bitangent:=fixture_normal.cross(tangent)
	var corners: Array[Vector3]=[-tangent*4-bitangent*4,tangent*4-bitangent*4,tangent*4+bitangent*4,-tangent*4+bitangent*4]
	quad(mesh_data,corners,fixture_normal,Vector3.ZERO)
	for i in 6:
		var point:=Vector3(mesh_data[i*16],mesh_data[i*16+1],mesh_data[i*16+2])
		mesh_data[i*16+3]=0.5+point.dot(tangent)/8.0*uv_scale*(-1.0 if uv_mirror else 1.0)
		mesh_data[i*16+7]=0.5 if degenerate_uv else 0.5+point.dot(bitangent)/8.0*uv_scale
	var texture:=Image.create(64,64,true,Image.FORMAT_RGBA8)
	texture.fill(Color.WHITE)
	if textured:
		for y in 64:
			for x in 64:
				var v:=0.5+0.25*sin(TAU*x/16.0)
				texture.set_pixel(x,y,Color(v,v,v,1))
	texture.generate_mipmaps()
	var images: Array[Image]=[texture]
	var geometry: Array=[{"offset":0,"count":6,"opaque":true,"standard":true,"surface":Vector3(1,0,0),"relief":relief}]
	var placement: Array=[{"geometry":0,"transform":transform,"mask":7}]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometry,placement))
	return await device.prepared

func normals() -> Dictionary:
	var im:=device.guide.get_image();var energy:=0.0;var minimum:=1.0;var finite:=true;var count:=0
	for y in range(size.y/4,3*size.y/4):
		for x in range(size.x/4,3*size.x/4):
			var c:=im.get_pixel(x,y);var n:=Vector3(c.r,c.g,c.b)
			energy+=absf(n.x)+absf(n.z);minimum=minf(minimum,n.y);finite=finite and n.is_finite();count+=1
	return {"tilt":energy/count,"minimum_up":minimum,"finite":finite}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified path tracing")
	if not PathDevice.supported():finish();return
	for c: Color in [Color.WHITE,Color(0.8,0.4,0.1),Color(0.1,0.15,0.3)]:
		var p:=SkyPalette.palette(Color(0.4,0.5,0.6),c,Color.BLACK,false)
		check(p.size()==12 and p[2]>p[10] and p[2]>0.0,"day/evening/night palette stays finite and directional: "+str(c))
	check(SkyPalette.palette(Color.WHITE,Color.WHITE,Color.WHITE,true)==PackedFloat32Array([0,0,0,0,0,0,0,0,0,0,0,0]),"cave has no sky environment")
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.current=true;size=Vector2i(256,144);sun_energy=0;sky_energy=1;bounces=1
	for n: Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.DOWN]:
		fixture_normal=n;camera.position=n*2+Vector3(0,0,0.001);camera.look_at(Vector3.ZERO)
		check(await build_plane(),"build diffuse receiver: "+str(n))
		await render_many(48)
		var c:=mean(device.output);report[str(n)]=[c.r,c.g,c.b]
		if n==Vector3.UP:
			check(absf(c.r-1.0/3)<0.015 and c.g<0.005 and absf(c.b-2.0/3)<0.015,"upward irradiance matches analytic hemisphere integral: "+str(c))
		elif n==Vector3.DOWN:
			check(absf(c.r-1.0/48)<0.01 and absf(c.g-47.0/48)<0.015 and c.b<0.005,"downward irradiance matches piecewise analytic integral: "+str(c))
		else:
			check(absf(c.b-2.0/(3.0*PI))<0.015 and c.g>0.3 and c.r>0.25,"vertical receiver sees both hemispheres: "+str(c))
		directional=false;await render_many(16)
		var uniform:=mean(device.output)
		check(absf(uniform.r-1)<0.01 and absf(uniform.g-1)<0.01 and absf(uniform.b-1)<0.01,"isotropic fixtures retain their energy")
		directional=true
	fixture_normal=Vector3.UP;camera.position=Vector3(0,2,0.001);camera.look_at(Vector3.ZERO)
	textured=true;directional=false;sun_energy=1;sky_energy=0;sun_direction=Vector3(1,1,0).normalized()
	var guides: Array[Image]=[]
	for strength in [0.0,1.0]:
		relief=strength;check(await build_plane(),"build relief "+str(strength));await render_many(4)
		var value:=normals();report["relief_"+str(strength)]=value;guides.append(device.guide.get_image())
		check(value.finite and value.minimum_up>0.98,"relief normals stay outside the geometric surface")
		check(value.tilt>0.03 if strength>0 else value.tilt<0.0001,"surface relief changes shading only when requested")
		device.output.get_image().save_png(out.path_join("relief-%s-lighting.png"%strength))
	uv_mirror=true;check(await build_plane(),"build mirrored UVs");await render_many(4)
	var mirrored:=device.guide.get_image();var error:=0.0
	for y in range(size.y/4,3*size.y/4):
		for x in range(size.x/4,3*size.x/4):error+=absf(mirrored.get_pixel(x,y).r+guides[1].get_pixel(size.x-1-x,y).r)
	check(error/(size.x*size.y/4)<0.003,"mirrored UVs reverse the relief slope")
	degenerate_uv=true;check(await build_plane(),"build degenerate UVs");await render_many(3)
	check(normals().tilt<0.0001,"degenerate UVs keep the geometric normal")
	degenerate_uv=false;uv_mirror=false
	uv_scale=64.0;check(await build_plane(),"build minified texture");await render_many(3)
	check(normals().tilt<0.0001,"subpixel surface detail fades before it can shimmer")
	uv_scale=1.0
	transform=Transform3D(Basis.from_scale(Vector3(-1.4,0.7,0.8)),Vector3.ZERO)
	check(await build_plane(),"build nonuniform mirrored placement");await render_many(4)
	check(normals().finite and normals().minimum_up>0.98 and normals().tilt>0.02,"transformed relief remains finite and outward")
	camera.position=Vector3(0,42,0.001);camera.look_at(Vector3.ZERO);await render_many(4)
	check(normals().tilt<0.0001,"distant relief fades out")
	RenderingServer.call_on_render_thread(device.dispose);await frames(4);camera.queue_free()
	FileAccess.open(out.path_join("path-daylight.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":report},"\t"))
	finish()
