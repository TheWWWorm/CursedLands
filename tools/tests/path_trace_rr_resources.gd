extends "res://tools/tests/path_trace_rr_raw.gd"
## Count bytes of real, still-live RD textures, then check the raw AOVs and
## transactional failures. A compact container alone cannot satisfy this.
class MeasuredPath extends PathDevice:
	var allocations: Array[Dictionary] = []
	var fail_after := -1
	func _lighting_texture(dimensions: Vector2i,format := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT) -> RID:
		if fail_after==0:
			fail_after=-1
			return RID()
		if fail_after>0: fail_after-=1
		var rid := super._lighting_texture(dimensions,format)
		var stride := 8
		if format==RenderingDevice.DATA_FORMAT_R16G16_SFLOAT: stride=4
		elif format==RenderingDevice.DATA_FORMAT_R16_SFLOAT: stride=2
		if rid.is_valid(): allocations.append({"rid":rid,"bytes":dimensions.x*dimensions.y*stride})
		return rid
	func live_bytes() -> int:
		var result := 0
		for allocation in allocations:
			if _rd.texture_is_valid(allocation.rid): result+=allocation.bytes
		return result

signal resources_inspected
var resource_state := {}
var resource_rows := []

func inspect_resources(label: String) -> void:
	var measured := device as MeasuredPath
	resource_state={"label":label,"lighting_bytes":measured.live_bytes(),"nrd_targets":device.nrd._textures.size(),
		"direct_targets":device._direct_images.size(),"public_valid":true,"raw_equal":true}
	for i in 4:
		resource_state.public_valid=resource_state.public_valid and device._rd.texture_is_valid(device._history[i])
		resource_state.raw_equal=resource_state.raw_equal and device._rd.texture_get_data(device._raw[i],0)==device._rd.texture_get_data(device._history[i],0)
	resource_rows.append(resource_state.duplicate())
	resources_inspected.emit.call_deferred()

func fail_targets(dimensions: Vector2i,raw: bool) -> void:
	var measured := device as MeasuredPath
	var before := measured.live_bytes()
	var published := device.published_targets().slice(0,4)
	var contents := device._rd.texture_get_data(published[0],0)
	device.ray_reconstruction=raw;measured.fail_after=2
	var success: bool=device._targets(dimensions,device._samplers[0])
	# The old implementation already allocated these unused images. Its
	# same-size transition allocates nothing; do not arm a later test frame.
	measured.fail_after=-1
	resource_state={"failed":not success,"bytes_before":before,"bytes_after":measured.live_bytes(),
		"public_unchanged":device.published_targets().slice(0,4)==published,
		"contents_unchanged":device._rd.texture_get_data(published[0],0)==contents,"ready":device.output_ready()}
	resource_rows.append(resource_state.duplicate())
	resources_inspected.emit.call_deferred()

func build_measured() -> bool:
	device=MeasuredPath.new()
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified RR resource device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_measured(),"build real receiver with measured RD allocations")
	if not device._ready:finish();return
	await render_many(2,{"ray_reconstruction":true})
	RenderingServer.call_on_render_thread(inspect_resources.bind("initial-raw"));await resources_inspected
	# Nine integrator AOVs total 68 bytes/pixel; four public RGBA16F images
	# add 32. The former unused history/auxiliary pool added 44 bytes/pixel.
	check(resource_state.lighting_bytes==size.x*size.y*100,"raw RR owns only current AOVs and published images: %d bytes"%resource_state.lighting_bytes)
	check(resource_state.raw_equal and resource_state.public_valid,"compact RR outputs retain exact current GPU bytes")
	var published:=device.published_targets().slice(0,4)
	RenderingServer.call_on_render_thread(fail_targets.bind(Vector2i(173,99),true));await resources_inspected
	check(resource_state.failed and resource_state.bytes_before==resource_state.bytes_after,"failed raw resize frees every partial RD allocation")
	check(resource_state.public_unchanged and resource_state.contents_unchanged and resource_state.ready,"failed raw resize retains complete public lighting")
	RenderingServer.call_on_render_thread(fail_targets.bind(size,false));await resources_inspected
	check(resource_state.failed and resource_state.bytes_before==resource_state.bytes_after,"failed same-size denoiser transition frees only its partial pool")
	check(resource_state.public_unchanged and resource_state.contents_unchanged and resource_state.ready,"failed denoiser transition preserves the previous complete raw frame")
	for cycle in 3:
		await render_many(4,{"ray_reconstruction":false,"nrd_directional":true})
		check(device.nrd_active and device.output_ready() and device.published_targets().slice(0,4)==published,"same-size NRD restoration preserves public handles: %d"%cycle)
		await render_many(1,{"ray_reconstruction":true})
		RenderingServer.call_on_render_thread(inspect_resources.bind("raw-cycle-%d"%cycle));await resources_inspected
		check(resource_state.lighting_bytes==size.x*size.y*100 and resource_state.nrd_targets==0 and resource_state.direct_targets==0,"RR releases previous denoiser pools without accumulating textures: %d"%cycle)
		check(resource_state.raw_equal and device.published_targets().slice(0,4)==published,"restored RR retains fresh raw bytes and public handles: %d"%cycle)
	size=Vector2i(173,99);await render_many(1)
	RenderingServer.call_on_render_thread(inspect_resources.bind("resized-raw"));await resources_inspected
	check(resource_state.lighting_bytes==size.x*size.y*100 and resource_state.raw_equal,"successful odd-size RR resize retires the old pool")
	var measured:=device as MeasuredPath
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	RenderingServer.call_on_render_thread(func():resource_state={"live_bytes":measured.live_bytes()};resources_inspected.emit.call_deferred())
	await resources_inspected
	check(resource_state.live_bytes==0,"teardown frees every tracked lighting image")
	FileAccess.open(out.path_join("rr-resources.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"resources":resource_rows},"\t"))
	camera.queue_free();finish()
