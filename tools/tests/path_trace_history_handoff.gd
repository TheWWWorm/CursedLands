extends "res://tools/tests/path_trace_nrd_device.gd"
var cache := PathDevice.Programs.new()
func make_device(staged: bool) -> RefCounted:
	var result := PathDevice.new();result.programs=cache;result.incremental_build=staged;result.defer_nrd=staged
	var white := Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	PathDevice.dispatch(result,&"build",[mesh_data.to_byte_array(),images,geometries,placements])
	return result
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified history handoff device")
	if not PathDevice.supported():finish();return
	size=Vector2i(192,108);sun_energy=0.0;sky_energy=0.3
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4;camera.position=Vector3(0,2,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	for x in [-2.0,0.0]:
		quad(mesh_data,[Vector3(x,0,-3),Vector3(x+2,0,-3),Vector3(x+2,0,3),Vector3(x,0,3)],Vector3.UP,Vector3.ZERO)
	for i in 2:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	device=make_device(false);check(await device.prepared,"prepare original region")
	await render_many(36)
	var previous := device;var denoiser: RefCounted=previous.nrd
	var pool: Array[RID]=denoiser._permanent.duplicate();var count: int=denoiser.rendered_frames
	var compiled := cache.compilations
	device=make_device(true);await frames(2)
	check(not device.output_ready() and device._building,"staged replacement remains private")
	var preparation := []
	device.prepared.connect(func(ok: bool):preparation.append(ok))
	for i in 120:
		PathDevice.dispatch(device,&"build_step");await frames(1)
		if not preparation.is_empty():break
	check(preparation==[true],"bounded preparation finishes the replacement")
	if preparation!=[true]:finish();return
	await render_many(1)
	check(device.output_ready() and not device.nrd_active,"private candidate validates its output without allocating a second NRD pool")
	check(cache.compilations==compiled and cache.hits>0,"replacement reuses immutable ray pipelines")
	PathDevice.dispatch(device,&"adopt_history",[previous,PackedInt32Array([0,-1])])
	await frames(2)
	check(not device._direct_valid,"private direct-light history resets when adopting a different scene's motion and identities")
	var updates := []
	for i in 2:updates.append({"index":i,"transform":Transform3D.IDENTITY,"mask":7})
	PathDevice.dispatch(device,&"render",[size,frame(true),{"instances":updates}])
	await frames(4);await RenderingServer.frame_post_draw
	check(device.nrd==denoiser and device.nrd._permanent==pool,"handoff retains the exact NRD owner and permanent textures")
	check(device.nrd.rendered_frames==count+1 and device.nrd_active,"handoff continues the native denoiser frame sequence")
	var image := device.output.get_image()
	var kept := image.get_pixel(size.x/4,size.y/2).a
	var changed := image.get_pixel(size.x*3/4,size.y/2).a
	check(kept>=5.0,"matching ground retains converged history on the first replacement frame")
	check(changed<kept*0.6,"changed surface rejects stale history independently")
	PathDevice.dispatch(previous,&"dispose");await frames(4)
	PathDevice.dispatch(device,&"render",[size,frame(true)]);await frames(4)
	check(device.nrd_active and device.output_ready(),"retiring the old scene cannot free the adopted denoiser")
	PathDevice.dispatch(device,&"dispose");PathDevice.dispatch(cache,&"dispose");await frames(4)
	check(cache._owned.is_empty() and denoiser._textures.is_empty(),"final retirement releases shared pipelines and adopted history")
	FileAccess.open(out.path_join("history-handoff.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"kept_history":kept,"changed_history":changed},"\t"))
	camera.queue_free();await frames();finish()
