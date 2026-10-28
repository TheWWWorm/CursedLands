extends "res://tools/tests/path_trace_device.gd"
const Dielectric = preload("res://src/game/fx/path_trace_dielectric.gd")
func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows);data.encode_float(145*4,8);return data

var terminal_image: Image
signal inspected
func inspect() -> void:
	terminal_image=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device.transmission._images[2],0))
	inspected.emit.call_deferred()
func read_terminal() -> void:
	RenderingServer.call_on_render_thread(inspect);await inspected
func centre(texture: Texture2DRD) -> Color:return texture.get_image().get_pixel(size.x/2,size.y/2)
func new_scene(kind: int,sigma: Vector3,depth: float,ior:=1.333) -> bool:
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	quad(mesh_data,[Vector3(-20,-depth,-20),Vector3(20,-depth,-20),Vector3(20,-depth,20),Vector3(-20,-depth,20)],Vector3.UP,Vector3.ONE)
	for i in 6:
		for c in 3:mesh_data[i*16+8+c]=0.0
	quad(mesh_data,[Vector3(-20,0,-20),Vector3(20,0,-20),Vector3(20,0,20),Vector3(-20,0,20)],Vector3.UP,Vector3.ZERO)
	if kind==2:
		quad(mesh_data,[Vector3(-20,-1,-20),Vector3(20,-1,-20),Vector3(20,-1,20),Vector3(-20,-1,20)],Vector3.DOWN,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true},
		{"offset":6,"count":12 if kind==2 else 6,"standard":true,"opaque":true,"dielectric":PackedFloat32Array([sigma.x,sigma.y,sigma.z,ior,kind,1,0,0])}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":5}]
	return await build_fixture()
func primary_ray() -> Dictionary:
	var uv: Vector2=(Vector2(size/2)+Vector2(.5,.5))/Vector2(size)
	var p: Vector4=camera.get_camera_projection().inverse()*Vector4(uv.x*2-1,1-uv.y*2,-1,1);p/=p.w
	return {"origin":camera.global_transform*Vector3(p.x,p.y,p.z),"direction":-camera.global_basis.z}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	check(PathDevice.supported(),"qualified dielectric renderer")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2;camera.position=Vector3(0,4,4);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=1
	check(await new_scene(1,Vector3(.4,.1,.02),2),"build water surface and emissive underwater reference")
	await render_many(4,{"transmission":true})
	if not device.transmission.active:
		check(false,"dielectric pass must initialize before readback")
		RenderingServer.call_on_render_thread(device.dispose);await frames(8);finish();return
	await read_terminal()
	check(device.transmission.active and not device.transmission_failed,"actual dielectric dispatch is active")
	check(device._instances[1].mask==8 and device._instances[0].mask==(7|16),
		"dielectrics keep a separate primary mask while opaque geometry retains visibility bits and the object-shadow selector")
	var ray:=primary_ray();var entry: Vector3=ray.origin+ray.direction*(-ray.origin.y/ray.direction.y)
	var eta:=1.0/1.333;var bent:=Vector3(ray.direction.x*eta,-sqrt(1.0-eta*eta*(1.0-ray.direction.y*ray.direction.y)),ray.direction.z*eta)
	var distance:=2.0/-bent.y;var expected: Vector3=entry+bent*distance
	var endpoint:=terminal_image.get_pixel(size.x/2,size.y/2)
	check(Vector3(endpoint.r,endpoint.g,endpoint.b).distance_to(expected)<.015,"Snell refraction reaches the analytic underwater point")
	var value:=centre(device.transmission.colour)
	var expected_colour:=Vector3(exp(-.4*distance),exp(-.1*distance),exp(-.02*distance))*eta*eta
	observations.append({"water":str(value),"beer":str(expected_colour),"endpoint":str(endpoint),"expected_endpoint":str(expected)})
	check(Vector3(value.r,value.g,value.b).distance_to(expected_colour)<.007,"Beer absorption uses actual refracted distance and radiance eta squared")
	check(value.b>value.g and value.g>value.r,"water loses red sooner than green and blue")
	check(device.output_ready() and centre(device.guide).a>centre(device.transmission.guide).a,"opaque guides still describe the submerged receiver")
	var opaque:=centre(device.output);var opaque_guide:=centre(device.guide)
	var public_rid: int=device.transmission.colour.get_instance_id();var backing: RID=device.transmission.colour.texture_rd_rid
	await render_many(4,{"transmission":false})
	check(not device.transmission.active and device.transmission.bytes==0,"Off frees transmission resources")
	var after_off:=centre(device.output)
	check(Vector3(after_off.r,after_off.g,after_off.b).is_equal_approx(Vector3(opaque.r,opaque.g,opaque.b)) and centre(device.guide).is_equal_approx(opaque_guide),"refraction does not change opaque lighting or primary guides")
	await render_many(4,{"transmission":true})
	check(device.transmission.colour.get_instance_id()==public_rid and device.transmission.colour.texture_rd_rid!=backing,"On restores the stable public texture with new private storage")
	check(device.transmission.history>=3,"stationary transmission accumulates without reprojection guesses")
	camera.position.x+=.2;await render_many(1)
	check(device.transmission.history==1,"camera motion resets transparent history")
	var reset: int=device.transmission.resets
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D(Basis.IDENTITY,Vector3(0,-2,0)),"mask":7}]})
	check(device.transmission.resets>reset and centre(device.transmission.colour).r<value.r*.5,"moving the bed changes optical depth immediately")
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D(Basis.IDENTITY,Vector3(0,3,0)),"mask":7}]})
	check(centre(device.transmission.guide).a==0,"opaque foreground prevents hidden water from being displayed")
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(centre(device.transmission.colour).r==0,"missing submerged geometry uses the current black environment")
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":7},{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(centre(device.transmission.guide).a==0,"hiding a dielectric removes its output immediately")
	await render_many(1,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":5}]})
	check(centre(device.transmission.guide).a>0,"showing a dielectric restores only its dedicated mask")
	size=Vector2i(173,99);await render_many(2)
	check(device.transmission.colour.get_width()==173 and device.transmission.guide.get_height()==99,"odd viewport resize replaces transmission images")
	await render_many(3,{"ray_reconstruction":true,"rtxdi":true,"nrd_directional":true})
	check(device.ray_reconstruction and device.transmission.active and not device.nrd_active,"independent transmission survives raw Ray Reconstruction input mode")
	await render_many(3,{"ray_reconstruction":false,"rtxdi":false})
	check(device.transmission.active and device.nrd_active,"directional NRD and transmission coexist")
	# Looking up from inside water beyond the critical angle must reflect.
	camera.position=Vector3(0,-1,0);camera.look_at(Vector3(0,0,-3))
	await render_many(1,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]});await read_terminal()
	endpoint=terminal_image.get_pixel(size.x/2,size.y/2)
	check(endpoint.g<-.5 and centre(device.transmission.guide).a>0,"total internal reflection stays below the water interface")
	camera.look_at(Vector3(0,2,-.1));await render_many(1);await read_terminal()
	endpoint=terminal_image.get_pixel(size.x/2,size.y/2)
	check(endpoint.g>1,"subcritical rays leave the medium through its back face")
	# Normal incidence isolates two interfaces and a known one-metre medium.
	camera.position=Vector3(0,4,.001);camera.look_at(Vector3.ZERO);size=Vector2i(160,90)
	check(await new_scene(2,Vector3(.6,.1,0),3,1.5),"build solid glass with an ordered entry and exit")
	await render_many(96,{"transmission":true});value=mean(device.transmission.colour)
	# Fresnel is sampled independently; compare a patch against the analytic
	# infinite slab series, including absorption during internal reflections.
	var A:=Vector3(exp(-.6),exp(-.1),1);var T:=Vector3.ZERO
	for c in 3:T[c]=.96*.96*A[c]/(1.0-.04*.04*A[c]*A[c])
	check(Vector3(value.r,value.g,value.b).distance_to(T)<.025,"solid glass matches analytic two-interface absorption within sampling tolerance")
	observations.append({"glass":str(value),"slab_transmission":str(T)})
	check(await new_scene(2,Vector3(.2,0,0),4,1),"build nested absorption reference")
	for i in range(12,18):mesh_data[i*16+1]=-3
	quad(mesh_data,[Vector3(-20,-1,-20),Vector3(20,-1,-20),Vector3(20,-1,20),Vector3(-20,-1,20)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-20,-2,-20),Vector3(20,-2,-20),Vector3(20,-2,20),Vector3(-20,-2,20)],Vector3.DOWN,Vector3.ZERO)
	geometries.append({"offset":18,"count":12,"standard":true,"opaque":true,"dielectric":PackedFloat32Array([.6,0,0,1,2,0,0,0])})
	placements.append({"geometry":2,"transform":Transform3D.IDENTITY,"mask":5})
	check(await build_fixture(),"build two nested closed media with distinct placement identities")
	await render_many(4,{"transmission":true});value=centre(device.transmission.colour)
	check(absf(value.r-exp(-1))<.002 and absf(value.g-1)<.002,"medium stack excludes inner distance from the surrounding absorption")
	check(await new_scene(3,Vector3(.6,.1,0),3,1.5),"build a one-metre parallel thin-pane model")
	await render_many(64,{"transmission":true});value=mean(device.transmission.colour)
	check(Vector3(value.r,value.g,value.b).distance_to(T)<.025,"thin pane preserves the two-interface transmission series")
	camera.position=Vector3(0,4,4);camera.look_at(Vector3.ZERO)
	await render_many(32);await read_terminal()
	endpoint=terminal_image.get_pixel(size.x/2,size.y/2)
	check(endpoint.a==3 and is_finite(endpoint.b),"oblique thin panes terminate without indefinite bending")
	var material:=Dielectric.material(1.5,Color(.5,.8,1),2,true,.2)
	var optical: PackedFloat32Array=material.get_meta("pt_dielectric")
	check(absf(optical[0]+log(.5)/2)<.00001 and optical[4]==3 and absf(optical[5]-.2)<.00001,"explicit glass authoring encodes tint distance and pane thickness")
	device.transmission.colour.get_image().save_exr(out.path_join("thin-glass.exr"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(not device.transmission.active and device.transmission.bytes==0 and device.transmission.colour.get_width()==0,"teardown releases all transparent pass resources")
	camera.queue_free();await frames()
	FileAccess.open(out.path_join("transmission.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	finish()
