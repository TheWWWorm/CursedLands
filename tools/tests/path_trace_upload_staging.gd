extends "res://tools/tests/path_trace_nrd_device.gd"
## Real array uploads, mip readback and cancellation between render frames.
## The failure case injects one failed upload without exhausting GPU memory.
class UploadDevice extends PathDevice:
	var fail_after := -1
	var uploaded := 0
	var freed_array := false
	func _create_colour_array(format: RDTextureFormat, layers: Array[PackedByteArray]) -> RID:
		# Readback is test-only; production keeps the sampled/uploadable usage.
		format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		return super._create_colour_array(format,layers)
	func _upload_colour_layer(layer: int, bytes: PackedByteArray) -> bool:
		if uploaded==fail_after:return false
		if not super._upload_colour_layer(layer,bytes):return false
		uploaded+=1;return true
	func dispose() -> void:
		var colours := _colours
		super.dispose()
		freed_array=colours.is_valid() and not _rd.texture_is_valid(colours)

signal readback_done
var readback := {}
var cache := PathDevice.Programs.new()
var pixels: Array[Image] = []

func make_upload_device(events: Array, fail_after := -1) -> UploadDevice:
	var result := UploadDevice.new()
	result.programs=cache;result.incremental_build=true;result.fail_after=fail_after
	result.prepared.connect(func(ok: bool):events.append(ok))
	PathDevice.dispatch(result,&"build",[mesh_data.to_byte_array(),pixels,geometries,placements])
	return result

func wait_upload_resources(target: UploadDevice) -> bool:
	# Texture upload assertions begin at the same actual stage on both eager
	# and staged resource builders. Do not consume the first array upload.
	for i in 120:
		if target._closed or target._ready:return false
		var resources_done:=not target.has_method("_build_resource_phase") or int(target.get("_build_resource_stage"))<0
		if target._building and target._colours.is_valid() and resources_done:
			return target.uploaded==0 and not target._pending_images.is_empty()
		if target._building:PathDevice.dispatch(target,&"build_step")
		await frames(1)
	return false

func read_layers(target: UploadDevice, expected: Array[Image]) -> void:
	var matching := 0
	for i in expected.size():
		if target._rd.texture_get_data(target._colours,i)==expected[i].get_data():matching+=1
	readback={"layers":expected.size(),"matching":matching,"mipmaps":expected[0].get_mipmap_count()+1}
	readback_done.emit.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified staged-upload device")
	if not PathDevice.supported():finish();return
	size=Vector2i(96,54);sun_energy=0.0;sky_energy=0.3
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4;camera.position=Vector3(0,2,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries.append({"offset":0,"count":6,"standard":true,"opaque":true})
	placements.append({"geometry":0,"transform":Transform3D.IDENTITY,"mask":7})
	for i in 19:
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
		image.fill(Color.from_hsv(i/19.0,0.5,1.0));image.set_pixel(i,i,Color.WHITE);image.generate_mipmaps()
		pixels.append(image)
	var prepared := []
	device=make_upload_device(prepared);await frames(3)
	var resources_ready:=await wait_upload_resources(device as UploadDevice)
	check(resources_ready and prepared.is_empty() and not device.output_ready(),"allocated but unuploaded scene remains private")
	PathDevice.dispatch(device,&"build_step")
	PathDevice.dispatch(device,&"render",[size,frame(false)]);await frames(3)
	check(device.uploaded>0 and device.uploaded<=4 and prepared.is_empty(),"one frame uploads only a bounded part of the array")
	check(device.completed_renders==0 and not device.output_ready(),"partially uploaded scene cannot render or publish")
	for i in 120:
		PathDevice.dispatch(device,&"build_step");await frames(1)
		if not prepared.is_empty():break
	check(prepared==[true],"staged uploads and acceleration structures finish once")
	if prepared!=[true]:PathDevice.dispatch(device,&"dispose");await frames(3);finish();return
	RenderingServer.call_on_render_thread(read_layers.bind(device,pixels));await readback_done
	check(readback.matching==pixels.size() and readback.mipmaps==6,"all array layers and six mip levels match the CPU source byte for byte")
	await render_many(8)
	check(device.output_ready() and device.nrd_active and mean(device.output).r>0.01,"completed upload renders usable native NRD lighting")
	var live_output := device.output.texture_rd_rid
	var cancelled_events := []
	var cancelled := make_upload_device(cancelled_events);await frames(3)
	var cancel_resources_ready:=await wait_upload_resources(cancelled)
	PathDevice.dispatch(cancelled,&"build_step")
	PathDevice.dispatch(cancelled,&"dispose")
	PathDevice.dispatch(cancelled,&"build_step");await frames(4)
	check(cancel_resources_ready and cancelled.uploaded>0 and cancelled.uploaded<pixels.size(),"cancellation interrupts a real partial upload")
	check(cancelled_events.is_empty() and not cancelled.output_ready() and not cancelled._building,"queued work cannot promote a cancelled scene")
	check(cancelled._pending_images.is_empty() and cancelled._owned.is_empty() and cancelled.freed_array,"cancellation releases CPU snapshots and the incomplete GPU array")
	var failed_events := []
	var failing := make_upload_device(failed_events,2);await frames(3)
	var fail_resources_ready:=await wait_upload_resources(failing)
	for i in 10:
		PathDevice.dispatch(failing,&"build_step");await frames(1)
		if not failed_events.is_empty():break
	check(fail_resources_ready and failed_events==[false] and not failing.output_ready() and not failing._building,"upload failure rejects the private candidate exactly once")
	PathDevice.dispatch(failing,&"dispose");await frames(3)
	check(failing._pending_images.is_empty() and failing._owned.is_empty() and failing.freed_array,"failed upload releases pending CPU and GPU resources")
	await render_many(2)
	check(device.output_ready() and device.nrd_active and device.output.texture_rd_rid==live_output,"failed and cancelled candidates leave the live scene and denoiser usable")
	PathDevice.dispatch(device,&"dispose");PathDevice.dispatch(cache,&"dispose");await frames(4)
	check(device._owned.is_empty() and cache._owned.is_empty(),"completed scene and cached programs retire cleanly")
	FileAccess.open(out.path_join("upload-staging.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"readback":readback},"\t"))
	camera.queue_free();await frames();finish()
