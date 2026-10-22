extends Node
## Exercise real RT/compute dispatch, shadow occlusion, emissive transport,
## alpha testing, history rejection and resource replacement on both APIs.
const Device = preload("res://src/game/fx/scene_raytrace_device.gd")
var out := "user://scene-rt-device"
var checks := 0
var failures := []
var camera: Camera3D
var device: Device
var size := Vector2i(320,180)
var tick := 0
var sun_direction := Vector3(1,1,0).normalized()
var sun_energy := 1.0
var points := false

func check(ok: bool, label: String) -> void:
	checks += 1; print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void: run.call_deferred()

func quad(data: PackedFloat32Array, points: Array[Vector3], normal: Vector3, emission: Vector3) -> void:
	for i in [0,1,2,0,2,3]:
		var p: Vector3 = points[i]
		data.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,normal.x,normal.y,normal.z,0.5,1,1,1,1,emission.x,emission.y,emission.z,0]))

func frame(history := true, gi := true, shadows := true) -> PackedByteArray:
	var data := PackedFloat32Array()
	var view := camera.global_transform.affine_inverse()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform),camera.get_camera_projection()*Projection(view),Projection(view)]:
		for axis in 4:
			var v: Vector4 = matrix[axis]; data.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	var sun := sun_direction
	data.append_array(PackedFloat32Array([sun_energy,sun_energy,sun_energy,float(shadows),sun.x,sun.y,sun.z,0.00465,0,0,0,float(gi),tick,16,4,camera.near,1,100,float(history),80,0,0,0,96]))
	data.resize(144); tick += 1
	if points:
		for i in 7:
			data[88+i*4+1]=2.0;data[88+i*4+3]=6.0
			data[116+i*4+1]=1.0
	return data.to_byte_array()

func sample(texture: Texture2DRD, point: Vector3) -> Color:
	var screen := camera.unproject_position(point)/get_viewport().get_visible_rect().size
	var image := texture.get_image()
	return image.get_pixel(clampi(int(screen.x*size.x),0,size.x-1),clampi(int(screen.y*size.y),0,size.y-1))

func render_many(count := 12, changes := {}, gi := true, shadows := true) -> void:
	for i in count:
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(i>0,gi,shadows),changes if i==0 else {}))
		await frames(2)
	await RenderingServer.frame_post_draw

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"qualified scene RT device")
	if not Device.supported(): finish(); return
	camera = Camera3D.new(); add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 8
	camera.position = Vector3(0,6,0.001); camera.look_at(Vector3.ZERO); camera.current = true
	var data := PackedFloat32Array()
	quad(data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
	quad(data,[Vector3(-0.3,1,-0.6),Vector3(0.3,1,-0.6),Vector3(0.3,1,0.6),Vector3(-0.3,1,0.6)],Vector3.UP,Vector3.ZERO)
	quad(data,[Vector3(1,0,-3),Vector3(1,3,-3),Vector3(1,3,3),Vector3(1,0,3)],Vector3.LEFT,Vector3(3,0,0))
	quad(data,[Vector3(0,0,-4),Vector3(0,4,-4),Vector3(0,4,4),Vector3(0,0,4)],Vector3.LEFT,Vector3.ZERO)
	for vertex in range(18,24):
		for channel in 3: data[vertex*16+8+channel]=0.0
	var white := Image.create(2,2,false,Image.FORMAT_RGBA8); white.fill(Color.WHITE)
	var geometries := [{"offset":0,"count":6,"standard":true,"opaque":true},
		{"offset":6,"count":6,"standard":true,"opaque":true},{"offset":12,"count":6,"standard":true,"opaque":true},
		{"offset":18,"count":6,"standard":true,"opaque":true}]
	var placements := []
	for i in 3: placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	# This fixture isolates the roof's sun shadow from the emissive wall.
	placements[2].mask = 5
	placements.append({"geometry":3,"transform":Transform3D.IDENTITY,"mask":0})
	device = Device.new()
	var images: Array[Image] = [white]
	RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images,geometries,placements))
	var ready: bool = await device.prepared
	check(ready,"build main-view scene and native RT pipeline")
	if ready:
		await render_many()
		var shadowed := sample(device.shadow0,Vector3(-1,0,0))
		var lit := sample(device.shadow0,Vector3(-2.5,0,0))
		check(shadowed.r<0.15 and lit.r>0.95,"sun rays distinguish occluded and unoccluded floor: %s / %s"%[shadowed,lit])
		var bounced := sample(device.output,Vector3(-1.5,0,1.8))
		check(bounced.r>bounced.g+0.2,"red emissive wall transports indirect light to white floor: "+str(bounced))
		check(device.guide.get_image().get_format()==Image.FORMAT_RGBAH,"normal/depth guide preserves HDR precision")
		device.output.get_image().save_png(out.path_join("emissive-bounce.png"))
		device.shadow0.get_image().save_png(out.path_join("sun-shadows.png"))
		var first_rid := device.output.get_rid()
		var backing_rid := device.output.texture_rd_rid
		points=true;await render_many(3,{},false)
		check(device.output.texture_rd_rid==backing_rid,"lighting output keeps the same backing texture across frames")
		var local0:=sample(device.shadow0,Vector3(-0.4,0,0));var local1:=sample(device.shadow1,Vector3(-0.4,0,0))
		check(local0.g<0.15 and local0.b<0.15 and local0.a<0.15 and local1.r<0.15 and local1.g<0.15 and local1.b<0.15 and local1.a<0.15,"all seven local-light shadow channels trace the roof")
		check(sample(device.shadow0,Vector3(-1,0,0)).g>0.95,"local-light rays stop at the emitter and preserve lit receivers")
		await render_many(3,{"instances":[{"index":1,"transform":Transform3D(Basis.IDENTITY,Vector3(0,2,0)),"mask":7}]},false)
		check(sample(device.shadow0,Vector3(-0.4,0,0)).g>0.95,"geometry beyond a point light cannot shadow its receiver")
		await render_many(3,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":7}]},false)
		points=false;sun_energy=0.0
		await render_many(12,{"instances":[{"index":3,"transform":Transform3D.IDENTITY,"mask":6}]})
		check(sample(device.output,Vector3(-1.5,0,1.8)).r<0.01,"opaque partition blocks indirect emission")
		await render_many(12,{"instances":[{"index":3,"transform":Transform3D.IDENTITY,"mask":0}]})
		check(sample(device.output,Vector3(-1.5,0,1.8)).r>0.2,"emissive surfaces illuminate receivers without direct lights")
		var diffuse_wall:=data.slice(12*16,18*16)
		for vertex in 6:
			diffuse_wall[vertex*16+9]=0;diffuse_wall[vertex*16+10]=0
			for channel in 3: diffuse_wall[vertex*16+12+channel]=0
		sun_direction=Vector3(-1,1,0).normalized();sun_energy=1.0
		await render_many(12,{"poses":[{"geometry":2,"data":diffuse_wall.to_byte_array()}]})
		var diffuse_bounce:=sample(device.output,Vector3(-1.5,0,1.8))
		check(diffuse_bounce.r>diffuse_bounce.g+0.04,"sunlight bounces from a non-emissive red wall: "+str(diffuse_bounce))
		sun_energy=0.0;await render_many()
		check(sample(device.output,Vector3(-1.5,0,1.8)).r<0.01,"turning off the sun removes its diffuse bounce")
		sun_energy=1.0;sun_direction=Vector3(1,1,0).normalized()
		await render_many(3,{"instances":[{"index":1,"transform":Transform3D(Basis.IDENTITY,Vector3(3,0,0)),"mask":7}]})
		check(sample(device.shadow0,Vector3(-1,0,0)).r>0.95,"moving a caster removes its old shadow without history residue")
		await render_many(3,{},false,false)
		check(sample(device.output,Vector3(-1.5,0,1.8)).r<0.001 and sample(device.shadow0,Vector3(-1,0,0)).r>0.99,"disabled GI and shadows clear previous lighting")
		size = Vector2i(192,108); await render_many(3)
		check(device.output.get_width()==192 and device.output.get_rid()==first_rid,"resize preserves material binding and replaces history")
	RenderingServer.call_on_render_thread(device.dispose); await frames(8)
	check(device.output.get_width()==0 and device.guide.get_width()==0 and device._owned.is_empty() and device._history.is_empty(),"teardown detaches all scene lighting targets and resources")
	camera.queue_free(); await frames()
	finish()

func finish() -> void:
	FileAccess.open(out.path_join("scene-device-results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown()
	print("SCENE_RT_DEVICE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
