extends "res://tools/tests/path_trace_contacts.gd"
## A shifted camera receiver overlaps its authored full-body shadow copy.
## Lighting must return to the authored surface without moving camera depth,
## skipping the world's real occluders or casting a second body shadow.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native body-lighting device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.8
	# One continuation isolates the blocker. This thin synthetic plate is
	# not a closed body; a second glossy bounce can escape below its rim.
	size=Vector2i(256,144);spp=4;bounces=1
	for mode: String in ["sun","sky"]:
		check(await contact_fixture(0.04,Transform3D.IDENTITY,mode,false),"build overlapping body representations: "+mode)
		var blocked:=await capture(mode+"-overlap")
		check(blocked.mean[0]<0.001,"uncorrected presentation starts inside its authored shadow copy: "+mode)
		var shifted:={"index":0,"transform":Transform3D.IDENTITY,"mask":1,"lighting_offset":Vector3(0,0.04,0)}
		var lit:=await capture(mode+"-authored-lighting",{"instances":[shifted]})
		check(lit.mean[0]>0.97 and lit.mean[0]<1.03,"body receives lighting at its matching authored surface: "+mode)
		check(absf(mean(device.guide).a-2.0)<0.001,"camera depth retains the displayed body position: "+mode)
		var external:={"index":1,"transform":Transform3D(Basis.IDENTITY,Vector3(0,0.01,0)),"mask":6}
		var occluded:=await capture(mode+"-external-blocker",{"instances":[external]})
		check(occluded.mean[0]<0.001,"world geometry still blocks the corrected body lighting: "+mode)
		external.transform=Transform3D.IDENTITY;shifted.erase("lighting_offset")
		var restored:=await capture(mode+"-offset-cleared",{"instances":[external,shifted]})
		check(restored.mean[0]<0.001,"ordinary placement update clears the first-person lighting offset: "+mode)
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	check(device._owned.is_empty() and device._raw.is_empty(),"body-lighting fixture releases its GPU resources")
	camera.queue_free();await frames(2)
	FileAccess.open(out.path_join("body-illumination.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":report},"\t"))
	finish()
