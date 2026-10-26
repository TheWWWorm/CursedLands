extends "res://tools/tests/path_trace_rr_resources.gd"
## Exercise real RD allocation, cancellation and publication. Allocation
## counts bound each preparation step without a hardware-speed threshold.
class StagedPath extends MeasuredPath:
	var render_allocations: Array[int] = []
	func render(dimensions: Vector2i,data: PackedByteArray,changes: Dictionary = {},texture_filter := 4) -> void:
		var before:=allocations.size()
		super.render(dimensions,data,changes,texture_filter)
		render_allocations.append(allocations.size()-before)

var staging_rows := []
var staging_state := {}

func build_staged() -> bool:
	device=StagedPath.new()
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func stage_step(data: PackedByteArray,changes: Dictionary) -> void:
	var staged:=device as StagedPath;var before:=staged.allocations.size()
	changes["ray_reconstruction"]=true
	if staged.has_method("render_candidate"):staged.call("render_candidate",size,data,changes,0)
	else:staged.render(size,data,changes,0)
	staging_state={"new_images":staged.allocations.size()-before,"total_images":staged.allocations.size(),
		"live_bytes":staged.live_bytes(),"ready":staged.output_ready(),"build_ready":staged._ready,
		"completed":staged.completed_renders,"public_backing":staged.output.texture_rd_rid.is_valid(),
		"render_allocations":staged.render_allocations.duplicate()}
	staging_rows.append(staging_state.duplicate());resources_inspected.emit.call_deferred()

func step_candidate(changes: Dictionary = {}) -> void:
	RenderingServer.call_on_render_thread(stage_step.bind(frame(false),changes))
	await resources_inspected;await frames(1)

func finish_candidate() -> Dictionary:
	var bounded:=true;var private_until_render:=true;var steps:=0
	for i in 20:
		await step_candidate();steps+=1
		bounded=bounded and staging_state.new_images<=3
		private_until_render=private_until_render and (staging_state.completed>0 or not staging_state.public_backing)
		if staging_state.ready or not staging_state.build_ready:break
	return {"bounded":bounded,"private":private_until_render,"steps":steps}

func dispose_candidate() -> void:
	var staged:=device as StagedPath
	RenderingServer.call_on_render_thread(func():
		staged.dispose()
		# A queued preparation callback may arrive after cancellation.
		if staged.has_method("render_candidate"):staged.call("render_candidate",size,PackedByteArray(),{"ray_reconstruction":true},0)
		# Texture2DRD clears its RS backing and dimensions on RID(), but the
		# qualified engine retains its cached RD handle. RID.is_valid() only
		# means nonzero; verify the actual RD lifetime for every public image.
		var public_live:=false
		for rid in staged.published_targets():
			public_live=public_live or (rid.is_valid() and staged._rd.texture_is_valid(rid))
		staging_state={"event":"dispose","live_bytes":staged.live_bytes(),"public_backing":public_live,
			"cached_handle_nonempty":staged.output.texture_rd_rid.is_valid(),"ready":staged.output_ready(),
			"public_width":staged.output.get_width(),"public_height":staged.output.get_height()}
		staging_rows.append(staging_state.duplicate())
		resources_inspected.emit.call_deferred())
	await resources_inspected;await frames(2)

func old_images_released(images: Array[Dictionary]) -> bool:
	var released:=true
	for allocation in images: released=released and not device._rd.texture_is_valid(allocation.rid)
	return released

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified staged RR device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_staged(),"build private candidate")
	if not device._ready:finish();return
	var completed:=await finish_candidate()
	check(completed.bounded and completed.steps>=6,"private candidate allocates at most three images per preparation step")
	check(completed.private and staging_state.completed==1,"preparation never publishes an incomplete raw frame")
	check(staging_state.ready and staging_state.render_allocations==[0],"first complete candidate render allocates zero lighting images")
	RenderingServer.call_on_render_thread(inspect_resources.bind("staged-published"));await resources_inspected
	check(resource_state.raw_equal and resource_state.lighting_bytes==size.x*size.y*100,"staged pool retains exact raw GPU output and compact resident bytes")
	await dispose_candidate()
	check(staging_state.live_bytes==0 and not staging_state.public_backing and not staging_state.ready
		and staging_state.public_width==0 and staging_state.public_height==0,"published staged pool tears down completely")

	check(await build_staged(),"build partial candidate for cancellation")
	await step_candidate()
	check(staging_state.new_images>0 and staging_state.new_images<=3 and not staging_state.public_backing,"first bounded allocation remains private")
	await dispose_candidate()
	check(staging_state.live_bytes==0 and not staging_state.public_backing,"cancellation and a late queued callback release every partial image")

	check(await build_staged(),"build partial candidate for allocation failure")
	await step_candidate();(device as StagedPath).fail_after=0
	await step_candidate()
	check(not staging_state.build_ready and not staging_state.ready and staging_state.live_bytes==0,"failed staged allocation frees its earlier successful images")
	check(not staging_state.public_backing and staging_state.completed==0,"failed preparation cannot become display ready")
	(device as StagedPath).fail_after=-1;await dispose_candidate()

	check(await build_staged(),"build partial candidate for resize")
	await step_candidate({"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]})
	var old_images: Array[Dictionary]=(device as StagedPath).allocations.duplicate()
	size=Vector2i(173,99);await step_candidate()
	RenderingServer.call_on_render_thread(func():staging_state["old_released"]=old_images_released(old_images);resources_inspected.emit.call_deferred())
	await resources_inspected
	check(staging_state.old_released and staging_state.new_images<=3 and not staging_state.public_backing,"resize discards old partial dimensions and restarts within the allocation budget")
	completed=await finish_candidate()
	RenderingServer.call_on_render_thread(inspect_resources.bind("staged-resized"));await resources_inspected
	check(completed.bounded and resource_state.raw_equal and resource_state.lighting_bytes==size.x*size.y*100
		and (device as StagedPath).render_allocations==[0],"resized candidate publishes only a complete exact-sized raw pool")
	check(mean(device.output).r==0 and mean(device.shadow0).r==0,"visibility deltas consumed during preparation remain applied to the first complete trace")
	await dispose_candidate()

	check(await build_staged(),"build partial candidate for RR to NRD change")
	await step_candidate();old_images=(device as StagedPath).allocations.duplicate()
	await render_many(4,{"ray_reconstruction":false,"nrd_directional":true})
	RenderingServer.call_on_render_thread(func():staging_state["old_released"]=old_images_released(old_images);resources_inspected.emit.call_deferred())
	await resources_inspected
	check(staging_state.old_released and device.nrd_active and device.output_ready(),"changing reconstruction mode retires partial raw resources and completes NRD normally")
	await dispose_candidate()
	check(staging_state.live_bytes==0,"mode-change teardown retains no staged or filtered lighting images")
	FileAccess.open(out.path_join("rr-staging.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"steps":staging_rows},"\t"))
	camera.queue_free();finish()
