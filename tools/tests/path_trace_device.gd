extends "res://tools/tests/scene_raytrace_device.gd"
const PathDevice = preload("res://src/game/fx/path_trace_device.gd")
var bounces:=2
var sky_energy:=0.0
var mesh_data:=PackedFloat32Array()
var geometries:=[]
var placements:=[]
var observations:=[]

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	for i in 3:bytes.encode_float((72+i)*4,sky_energy)
	bytes.append_array(PackedFloat32Array([bounces,256,1,0]).to_byte_array())
	# The size check also permits comparison with saved 592-byte prototypes.
	if device.frame_bytes()>592:
		var inverse:=(camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())).inverse()
		for axis in 4:
			var v: Vector4=inverse[axis];bytes.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]).to_byte_array())
	return bytes

func mean(texture: Texture2DRD) -> Color:
	var image:=texture.get_image();var sum:=Vector4.ZERO;var count:=0
	for y in range(size.y/2-12,size.y/2+12):
		for x in range(size.x/2-12,size.x/2+12):
			var c:=image.get_pixel(x,y);sum+=Vector4(c.r,c.g,c.b,c.a);count+=1
	return Color(sum.x/count,sum.y/count,sum.z/count,sum.w/count)

func build_fixture(metal:=false) -> bool:
	if device!=null:
		RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new()
	geometries[0].surface=Vector3(0.08,1,0.5) if metal else Vector3(1,0,0)
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified path-tracing device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	sun_energy=0.0
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(-2,2,2)],Vector3.DOWN,Vector3(2,0,0))
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(-2,2,2),Vector3(-2,0,2)],Vector3.RIGHT,Vector3.ZERO)
	quad(mesh_data,[Vector3(2,0,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.LEFT,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,0,-2)],Vector3.BACK,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,2),Vector3(-2,2,2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.FORWARD,Vector3.ZERO)
	for vertex in mesh_data.size()/16:
		for c in 3:mesh_data[vertex*16+8+c]=0.6
	for i in 6:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	check(await build_fixture(),"build closed diffuse room with red emissive ceiling")
	if not device._ready:finish();return
	var values:=[]
	for depth in [1,2,4]:
		bounces=depth;tick=0;await render_many(64)
		var value:=mean(device.output);values.append(value.r)
		observations.append({"bounces":depth,"diffuse":[value.r,value.g,value.b],"history":value.a})
		check(value.r>0.1 and value.g<0.002 and value.b<0.002,"emission transports only red light at depth "+str(depth))
		check(value.a>60.0,"still-scene accumulation exceeds the old eight-frame limit")
		device.output.get_image().save_png(out.path_join("diffuse-%d-bounces.png"%depth))
	check(values[1]>values[0]*1.08,"second bounce adds occluded reflected energy: "+str(values))
	check(values[2]>values[1]*1.04,"four bounces gather paths absent from two: "+str(values))
	check(await build_fixture(true),"build glossy metallic receiver")
	bounces=4;await render_many(32)
	var diffuse:=mean(device.output);var specular:=mean(device.shadow0)
	check(diffuse.r<0.001,"metal has no diffuse lobe")
	check(specular.r>0.8 and specular.g<0.002,"metal reflects the emissive ceiling through glossy paths: "+str(specular))
	device.shadow0.get_image().save_png(out.path_join("glossy-reflection.png"))
	var backing:=device.output.texture_rd_rid
	await render_many(2)
	check(device.output.texture_rd_rid==backing,"path tracing retains stable output bindings")
	var ceiling:=mesh_data.slice(6*16,12*16)
	for vertex in 6:ceiling[vertex*16+12]=0.0
	await render_many(1,{"poses":[{"geometry":1,"data":ceiling.to_byte_array()}]})
	check(mean(device.output).r<0.001 and mean(device.shadow0).r<0.001,"history reset removes an extinguished emitter immediately")
	size=Vector2i(192,108);await render_many(2)
	check(device.output.get_width()==192 and device.guide.get_width()==192,"resizing reallocates path targets")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device.output.get_width()==0 and device._history.is_empty(),"path targets are released")
	FileAccess.open(out.path_join("path-device.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	camera.queue_free();await frames();finish()
