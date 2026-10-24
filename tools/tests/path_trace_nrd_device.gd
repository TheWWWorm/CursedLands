extends "res://tools/tests/path_trace_quality.gd"
## Execute NRD's real native planner + GPU passes, including cold/steady state,
## resize, light reset and return from progressive accumulation.
var progressive := false
class FailingNrd extends "res://src/game/fx/path_trace_nrd.gd":
	var attempts := 0
	var freed := true
	func render(_frame: PackedByteArray) -> bool:
		attempts+=1;return false
	func dispose() -> void:
		var images: Array[RID]=_textures.duplicate();var rd:=_rd
		super.dispose()
		if rd!=null:freed=images.all(func(rid: RID):return not rd.texture_is_valid(rid))
signal replaced
func replace_nrd(replacement: RefCounted) -> void:
	device.nrd.dispose();device.nrd=replacement
	replaced.emit.call_deferred()
func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(145*4,256.0 if progressive else 8.0)
	return bytes

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified NRD test device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	sun_energy=0.0;sky_energy=0.2
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-1,2,-1),Vector3(1,2,-1),Vector3(1,2,1),Vector3(-1,2,1)],Vector3.DOWN,Vector3(2,1,0.5))
	for i in 2:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	check(await build_fixture(),"build actual ray-traced NRD fixture")
	check(device.nrd.available,"native NRD 4.18 runtime and compute shaders loaded")
	if not device.nrd.available:finish();return
	await render_many(36)
	check(device.nrd_active and not device._nrd_failed,"NRD ran without custom fallback")
	check(device.nrd.rendered_frames==36 and device.nrd.last_dispatch_count>=6,"native dispatch planner and GPU passes execute every frame")
	var value:=mean(device.output)
	check(value.r>value.g and value.g>value.b and value.b>0.01,"NRD preserves coloured emission and positive indirect light")
	check(value.a>=6.0,"stationary surface reuses NRD history")
	check(value.r<10.0 and value.g<10.0 and value.b<10.0,"NRD output remains finite and bounded")
	device.output.get_image().save_png(out.path_join("nrd-light.png"))
	device.guide.get_image().save_exr(out.path_join("nrd-guide.exr"))
	var backing:=device.output.texture_rd_rid
	await render_many(2)
	check(device.output.texture_rd_rid==backing,"NRD presents stable public texture handles")
	progressive=true;await render_many(12)
	check(not device.nrd_active and mean(device.output).a>=11.0,"progressive mode keeps exact long accumulation")
	progressive=false;await render_many(8)
	check(device.nrd_active and mean(device.output).a>=5.0,"return to NRD restarts and converges")
	size=Vector2i(193,109);await render_many(8)
	check(device.nrd_active and device.output.get_width()==193,"odd-sized resize rebuilds NRD pools")
	sky_energy=0.0
	var ceiling:=mesh_data.slice(6*16,12*16)
	for vertex in 6:
		for channel in 3:ceiling[vertex*16+12+channel]=0.0
	await render_many(1,{"poses":[{"geometry":1,"data":ceiling.to_byte_array()}]})
	check(mean(device.output).r<0.001,"lighting reset removes extinguished emission immediately")
	var failing:=FailingNrd.new()
	RenderingServer.call_on_render_thread(replace_nrd.bind(failing));await replaced
	sky_energy=0.2;await render_many(12)
	check(device._nrd_failed and not device.nrd_active and device.output_ready(),"NRD dispatch failure falls back to usable custom lighting")
	check(mean(device.output).r>0.01 and mean(device.output).a>=7.0,"fallback accumulates current illumination after NRD failure")
	check(failing.attempts==1 and failing.freed,"NRD failure releases all pool images and is not retried every frame")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device.output.get_width()==0 and device.nrd._textures.is_empty() and device.nrd._owned.is_empty(),"NRD pools, descriptors and pipelines are released")
	FileAccess.open(out.path_join("nrd-device.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"mean":str(value)},"\t"))
	camera.queue_free();await frames();finish()
