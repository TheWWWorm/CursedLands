extends "res://tools/tests/path_trace_device.gd"
## Real GPU transport in a reflected view, including geometry that the old
## plane-clipped snapshot could not use for secondary transport or shadows.
const WaterDevice = preload("res://src/game/fx/path_trace_water_device.gd")
const LegacyWater = preload("res://src/game/fx/water_raytrace_device.gd")
var water_plane:=0.0
var fog_start:=90.0
var fog_end:=100.0
var fog_colour:=Color(0.2,0.3,0.5)
var history_limit:=256.0
var measured: Dictionary={}

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(77*4,1.0)
	bytes.encode_float(80*4,float(camera.projection==Camera3D.PROJECTION_ORTHOGONAL))
	bytes.encode_float(145*4,history_limit)
	for i in 8:bytes.encode_float((704+i)*4,[water_plane,fog_start,fog_end,0,fog_colour.r,fog_colour.g,fog_colour.b,0][i])
	return bytes

func water_mean() -> Color: return mean(device.reflection_output())

func add_quad(points: Array[Vector3],normal: Vector3,emission: Vector3,mask:=7) -> void:
	var index:=geometries.size()
	quad(mesh_data,points,normal,emission)
	geometries.append({"offset":index*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
	placements.append({"geometry":index,"transform":Transform3D.IDENTITY,"mask":mask})

func update_mask(index: int,mask: int) -> Dictionary:
	return {"instances":[{"index":index,"transform":Transform3D.IDENTITY,"mask":mask}]}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(WaterDevice.supported(),"qualified PT water runtime")
	if not WaterDevice.supported():finish_water();return
	size=Vector2i(128,128);sun_energy=0;sky_energy=0
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.position=Vector3(0,-1,3);camera.look_at(Vector3(0,1.5,0))
	add_quad([Vector3(-2,0.4,0),Vector3(2,0.4,0),Vector3(2,3.5,0),Vector3(-2,3.5,0)],Vector3.BACK,Vector3.ZERO)
	add_quad([Vector3(-3,4,0),Vector3(3,4,0),Vector3(3,4,4),Vector3(-3,4,4)],Vector3.DOWN,Vector3(3,0,0))
	add_quad([Vector3(-3,-0.5,0),Vector3(3,-0.5,0),Vector3(3,-0.5,4),Vector3(-3,-0.5,4)],Vector3.UP,Vector3(0,3,0),0)
	add_quad([Vector3(-3,-0.25,0),Vector3(3,-0.25,0),Vector3(3,-0.25,4),Vector3(-3,-0.25,4)],Vector3.UP,Vector3.ZERO,0)
	for vertex in 24:
		for c in 3:mesh_data[vertex*16+8+c]=0.6 if vertex<18 else 0.0
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=WaterDevice.new();device.nrd.directional=false
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await device.prepared,"build shared PT materials and reflected-camera pipeline")
	if not device._ready:finish_water();return
	await render_many(32)
	var red:=water_mean();measured["red_bounce"]=str(red)
	check(red.r>0.08 and red.g<0.001 and red.b<0.001,"water receives red emissive bounce with no sun or ambient: "+str(red))
	check(device.output!=device.reflection_output(),"water HDR composition has its own stable texture")
	var image:=device.reflection_output().get_image();image.duplicate().save_png(out.path_join("red-bounce.png"))
	var partial:=0;var empty:=0;var finite:=true
	for y in size.y:
		for x in size.x:
			var c:=image.get_pixel(x,y)
			if c.a>0.01 and c.a<0.99:partial+=1
			if c.a<0.01:empty+=1;finite=finite and c.r==0 and c.g==0 and c.b==0
			finite=finite and is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and c.a>=0 and c.a<=1
	check(partial>10,"four spatial samples preserve fractional silhouette coverage: "+str(partial))
	check(empty>100 and finite,"misses clear HDR colour and coverage without stale history")
	# Identical reflected camera and unlit bank under the original RT shader.
	var legacy:=LegacyWater.new()
	RenderingServer.call_on_render_thread(legacy.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await legacy.prepared,"build RT reflection comparison")
	var old:=PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			for c in 4:old.append(matrix[axis][c])
	old.append_array(PackedFloat32Array([0,0,0,2,0,0,0,1,0,1,0,0,90,100,100,0,0.2,0.3,0.5,0]))
	old.resize(88)
	RenderingServer.call_on_render_thread(legacy.render.bind(size,old.to_byte_array()));await frames(8)
	var old_colour:=mean(legacy.reflection_output());measured["legacy_bank"]=str(old_colour)
	check(old_colour.r<0.001 and red.r>old_colour.r+0.08,"PT adds reflected illumination absent from RT direct lighting")
	RenderingServer.call_on_render_thread(legacy.dispose);await frames(4)
	await render_many(1,update_mask(1,0))
	check(water_mean().r<0.001,"extinguishing an emitter immediately removes reflected history")
	await render_many(32,update_mask(2,6))
	var green:=water_mean();measured["underwater_emission"]=str(green)
	check(green.g>0.03 and green.r<0.001,"underwater emission reaches above-water reflected surfaces: "+str(green))
	await render_many(16,update_mask(3,6))
	check(water_mean().g<green.g*0.1,"underwater geometry blocks secondary light without entering primary reflections")
	await render_many(1,update_mask(2,0))
	var wall:=mesh_data.slice(0,6*16)
	for vertex in 6:
		wall[vertex*16+12]=2;wall[vertex*16+13]=0.5;wall[vertex*16+14]=0.25
	await render_many(2,{"poses":[{"geometry":0,"data":wall.to_byte_array()}]})
	var glowing:=water_mean();measured["primary_emission"]=str(glowing)
	check(absf(glowing.r-2.0)<0.02 and absf(glowing.g-0.5)<0.02,"primary reflected emission stays HDR and is added exactly once: "+str(glowing))
	history_limit=8
	await render_many(3,{"nrd_directional":true})
	check(device.nrd_active and device.nrd._description.directional,"reflected view supports the actual SH denoiser")
	await render_many(3,{"nrd_directional":false})
	check(device.nrd_active and not device.nrd._description.directional,"reflected view returns to radiance NRD")
	fog_start=0;fog_end=0.1;await render_many(1)
	var fogged:=water_mean()
	check(absf(fogged.r-fog_colour.r)<0.002 and absf(fogged.b-fog_colour.b)<0.002,"water fog applies in linear light after HDR composition")
	fog_start=90;fog_end=100;water_plane=10;await render_many(1)
	check(water_mean().a==0 and water_mean().r==0,"raising the water plane clears previous reflection coverage immediately")
	water_plane=0
	var binding:=device.reflection_output().get_rid()
	size=Vector2i(192,108);await render_many(2)
	check(device.reflection_output().get_rid()==binding and device.reflection_output().get_width()==192,"resize preserves the reflection binding and replaces complete output")
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;await render_many(2)
	check(water_mean().a>0.99 and water_mean().r>1.9,"orthographic reflected camera preserves primary clipping and HDR")
	size=Vector2i(3840,2160);await render_many(1)
	check(device.reflection_output().get_size()==Vector2(3840,2160) and device.reflection_output().get_rid()==binding,"4K allocates native PT reflection targets without changing the material binding")
	check(water_mean().r>1.9 and device.nrd_active,"4K HDR composition and NRD retain reflected detail")
	size=Vector2i(128,128);water_plane=10;await render_many(1)
	check(device.reflection_output().get_width()==128 and water_mean().a==0,"returning from 4K clears retired targets and previous coverage")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device.reflection_output().get_width()==0 and device._raw.is_empty() and not device._reflection_image.is_valid() and device._owned.is_empty(),"water composition, denoisers and shared PT resources release together")
	camera.queue_free();await frames(4);finish_water()

func finish_water() -> void:
	FileAccess.open(out.path_join("pt-water.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measured":measured},"\t"))
	TexUpscale.shutdown()
	print("PATH_TRACE_WATER ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
