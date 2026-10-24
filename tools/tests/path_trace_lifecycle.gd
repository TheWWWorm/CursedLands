extends "res://tools/tests/path_trace_motion.gd"
## Real resource replacement and dispatch with controlled failure points.
## Faults return normal API failure results without exhausting GPU memory.
class FaultDevice extends PathDevice:
	func _init() -> void:nrd.available=false
	var fail_image_in := 0
	var fail_set_in := 0
	var fail_compile := false
	var fail_upload := false
	var fail_copy := false
	var fail_pose := false
	var uploads := 0
	var images_created: Array[RID] = []
	var sets_created: Array[RID] = []
	func _lighting_texture(size: Vector2i,format:=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT) -> RID:
		if fail_image_in>0:
			fail_image_in-=1
			if fail_image_in==0:return RID()
		var rid:=super._lighting_texture(size,format)
		if rid.is_valid():images_created.append(rid)
		return rid
	func _target_set(bindings: Array[RDUniform],shader: RID) -> RID:
		if fail_set_in>0:
			fail_set_in-=1
			if fail_set_in==0:return RID()
		var rid:=super._target_set(bindings,shader)
		if rid.is_valid():sets_created.append(rid)
		return rid
	func _compile() -> RDPipelineShader:
		if fail_compile:fail_compile=false;return null
		return super._compile()
	func _upload_frame(bytes: PackedByteArray) -> bool:
		uploads+=1
		if fail_upload:fail_upload=false;return false
		return super._upload_frame(bytes)
	func _copy_history() -> bool:
		if fail_copy:fail_copy=false;return false
		return super._copy_history()
	func _upload_pose(pose: Dictionary) -> bool:
		if fail_pose:fail_pose=false;return false
		return super._upload_pose(pose)

class DetachedDevice extends PathDevice:
	var evidence: Dictionary
	func build(data: PackedByteArray,images: Array[Image],geometry_data: Array=[],placements: Array=[]) -> void:
		super.build(data,images,geometry_data,placements)
		evidence.events.append("build");evidence.built=_ready
		evidence.render_thread=OS.get_thread_caller_id()
	func render(size: Vector2i,bytes: PackedByteArray,changes: Dictionary={},texture_filter:=4) -> void:
		super.render(size,bytes,changes,texture_filter)
		evidence.events.append("render");evidence.rendered=output_ready()
	func dispose() -> void:
		var images: Array[RID]=_raw+_history+_filter_auxiliary+_retired_outputs+_spatial_images
		super.dispose()
		evidence.events.append("dispose")
		evidence.disposed=_closed and _owned.is_empty() and _raw.is_empty() and not output_ready()
		evidence.images_freed=images.all(func(rid: RID):return not _rd.texture_is_valid(rid))

signal probed
var probe := {}
var failure_events := 0

static func _hold_render_queue(entered: Semaphore,resume: Semaphore) -> void:
	entered.post();resume.wait()

static func _queue_drained(done: Semaphore) -> void:
	done.post()

static func _weak_alive(reference: WeakRef) -> bool:
	return reference.get_ref()!=null

static func _ordinary_callable() -> Dictionary:
	var owner:=RefCounted.new()
	return {"owner":weakref(owner),"callback":owner.get_reference_count}

func _queue_detached(evidence: Dictionary,bytes: PackedByteArray,images: Array[Image]) -> WeakRef:
	# Return synchronously so neither a coroutine local nor a compiler member
	# temporary can keep the last main-thread device reference alive.
	var owner:=DetachedDevice.new();owner.evidence=evidence
	var reference: WeakRef=weakref(owner)
	PathDevice.dispatch(owner,&"build",[mesh_data.to_byte_array(),images,geometries,placements])
	PathDevice.dispatch(owner,&"render",[size,bytes])
	PathDevice.dispatch(owner,&"dispose")
	return reference

func dispatch_lifetime() -> void:
	var separate:=not RenderingServer.is_on_render_thread()
	var entered:=Semaphore.new();var resume:=Semaphore.new();var drained:=Semaphore.new()
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	var bytes:=frame(false)
	var evidence:={"events":[],"built":false,"rendered":false,"disposed":false,"images_freed":false}
	if separate:
		RenderingServer.call_on_render_thread(_hold_render_queue.bind(entered,resume))
		entered.wait()
	# Block and resume within this one synchronous main-thread section: an
	# await/process frame here would deadlock RenderingServer's frame sync.
	var retired:=_queue_detached(evidence,bytes,images)
	var queued_alive:=_weak_alive(retired)
	var ordinary:=_ordinary_callable()
	if separate:resume.post()
	RenderingServer.call_on_render_thread(_queue_drained.bind(drained));drained.wait()
	check(not _weak_alive(ordinary.owner) and not ordinary.callback.is_valid(),"negative control proves an ordinary method Callable does not retain its target")
	if separate:check(queued_alive,"bound dispatch retains the last device owner while the render queue is blocked")
	check(evidence.events==["build","render","dispose"],"abandoned device completes queued build, render and disposal in order")
	check(evidence.built and evidence.rendered,"abandoned native device builds and publishes a complete image before retirement")
	check(evidence.disposed and evidence.images_freed,"abandoned native device releases all scene and output resources")
	check((evidence.render_thread!=OS.get_main_thread_id())==separate,"retained dispatch executes on the actual configured render thread")
	# Deferred prepared/emitter notifications must retain their owner too,
	# then release it when the main thread consumes those notifications.
	check(_weak_alive(retired),"queued native notifications retain the disposed owner until main-thread delivery")
	await frames(4)
	check(not _weak_alive(retired),"device owner releases after render work and main-thread notifications drain")
	evidence["separate_thread"]=separate;evidence["retained_before_execution"]=queued_alive
	report["dispatch_lifetime"]=evidence

func failed(ok: bool) -> void:
	if not ok:failure_events+=1

func new_device(prewarm := true) -> void:
	if device!=null:
		RenderingServer.call_on_render_thread(device.dispose);await frames(3)
		RenderingServer.call_on_render_thread(device.dispose);await frames(2)
		check(device._owned.is_empty() and device._raw.is_empty() and device._retired_outputs.is_empty() \
			and not device._filter_pipeline.is_valid(),"retired device tolerates repeated disposal")
		RenderingServer.call_on_render_thread(live_image_probe);await probed
		check(probe.live_images==0,"retirement frees all created work and previously published images")
	device=FaultDevice.new();failure_events=0;bounces=2;motion_index=0;size=Vector2i(96,54)
	check(not device.output_ready(),"new device cannot be promoted before producing output")
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	check(await device.prepared,"build isolated lifecycle device")
	check(not device.output_ready(),"prepared acceleration structures are not yet display-ready")
	device.prepared.connect(failed)
	if not prewarm:return
	for i in 8:await native_frame({},i>0)
	check(device.output_ready(),"completed lighting and history copies make the device display-ready")

func target_probe(kind: String) -> void:
	var old_raw: Array[RID]=device._raw.duplicate();var old_history: Array[RID]=device._history.duplicate()
	var old_auxiliary: Array[RID]=device._filter_auxiliary.duplicate();var old_sets: Array[RID]=device._filter_sets.duplicate()
	var old_ray: RID=device._set;var old_size: Vector2i=device._size;var old_sampler: RID=device._sampler
	var old_output: RID=device.output.texture_rd_rid
	var old_pixels: PackedByteArray=device._rd.texture_get_data(old_output,0)
	var old_valid: bool=device._history_valid
	var image_start: int=device.images_created.size();var set_start: int=device.sets_created.size()
	var next_size:=old_size+Vector2i(16,9)
	var sampler: RID=device._samplers[0]
	match kind:
		"image":device.fail_image_in=5
		"filter_set":device.fail_set_in=1
		"ray_set":device.fail_set_in=2
		"sampler":device.fail_set_in=1;next_size=old_size;sampler=device._samplers[1]
	var accepted: bool=device._targets(next_size,sampler)
	var cleaned:=true
	for i in range(image_start,device.images_created.size()):
		cleaned=cleaned and not device._rd.texture_is_valid(device.images_created[i])
	for i in range(set_start,device.sets_created.size()):
		cleaned=cleaned and not device._rd.uniform_set_is_valid(device.sets_created[i])
	probe={"rejected":not accepted,"cleaned":cleaned,
		"unchanged":device._raw==old_raw and device._history==old_history and device._filter_auxiliary==old_auxiliary \
			and device._filter_sets==old_sets and device._set==old_ray and device._size==old_size and device._sampler==old_sampler \
			and device.output.texture_rd_rid==old_output and device._history_valid==old_valid,
		"retry":device._targets(next_size,sampler),"next_size":next_size}
	probe["reset"]=not device._history_valid
	probe["private"]=device.output.texture_rd_rid==old_output
	probe["ready_during_reset"]=device.output_ready()
	probe["published_unchanged"]=device._rd.texture_get_data(device.output.texture_rd_rid,0)==old_pixels
	probed.emit.call_deferred()

func pipeline_probe() -> void:
	var old_shader: RID=device._shader;var old_pipeline: RID=device._pipeline;var old_set: RID=device._set
	var old_history: bool=device._history_valid
	device.fail_compile=true
	var accepted: bool=device._select_pipeline(false,true)
	probe={"rejected":not accepted,"unchanged":device._shader==old_shader and device._pipeline==old_pipeline \
		and device._set==old_set and not device._uses_emitters and not device._deep_paths and device._history_valid==old_history,
		"retry":device._select_pipeline(false,true)}
	probe["ready_during_reset"]=device.output_ready() and not device._history_valid
	probed.emit.call_deferred()

func emitter_history_probe() -> void:
	var published: RID=device.output.texture_rd_rid
	var pixels: PackedByteArray=device._rd.texture_get_data(published,0)
	var revision: int=device.emitters.revision
	var accepted: bool=device.update_scene({"instances":[{"index":1,
		"transform":Transform3D(Basis.IDENTITY,Vector3(0.1,0,0)),"mask":4}]})
	probe={"accepted":accepted,"emitter_updated":device.emitters.revision>revision,"history_reset":not device._history_valid,
		"ready":device.output_ready(),"published_unchanged":device.output.texture_rd_rid==published \
		and device._rd.texture_get_data(published,0)==pixels}
	probed.emit.call_deferred()

func invalid_frame_probe(bytes: PackedByteArray) -> void:
	var pose: Transform3D=device._instances[0].transform
	var calls: int=device.uploads
	var valid: bool=device._history_valid
	var change:={"instances":[{"index":0,"transform":Transform3D(Basis.IDENTITY,Vector3(0,0,0.6)),"mask":7}]}
	device.render(Vector2i.ZERO,bytes,change)
	device.render(size,PackedByteArray(),change)
	probe={"unchanged":device._instances[0].transform==pose and device.uploads==calls and device._history_valid==valid}
	probed.emit.call_deferred()

func failure_probe(kind: String,bytes: PackedByteArray) -> void:
	var published: Array[RID]=[device.output.texture_rd_rid,device.guide.texture_rd_rid,device.shadow0.texture_rd_rid,device.shadow1.texture_rd_rid]
	var changes:={}
	var target:=size
	match kind:
		"frame_upload","first_frame_upload":device.fail_upload=true
		"history_copy","first_history_copy":device.fail_copy=true
		"resize_frame_upload":device.fail_upload=true;target+=Vector2i(16,9)
		"resize_history_copy":device.fail_copy=true;target+=Vector2i(16,9)
		"pose_upload":device.fail_pose=true;changes={"poses":[{"geometry":0,"data":mesh_data.slice(0,6*16).to_byte_array()}]}
		"resize":device.fail_image_in=1;target+=Vector2i(16,9)
		"spatial_image":device._release_spatial();device.fail_image_in=2
		"spatial_set":device._release_spatial();device.fail_set_in=2
	device.render(target,bytes,changes)
	var calls: int=device.uploads
	device.render(size,bytes,{})
	var current: Array[RID]=[device.output.texture_rd_rid,device.guide.texture_rd_rid,device.shadow0.texture_rd_rid,device.shadow1.texture_rd_rid]
	probe={"stopped":not device._ready and not device._history_valid and not device.output_ready(),"no_more_uploads":device.uploads==calls,
		"preserved_output":current==published and published.all(func(rid: RID):return not rid.is_valid() or device._rd.texture_is_valid(rid))}
	probed.emit.call_deferred()

func live_image_probe() -> void:
	var live_images:=0
	for rid: RID in device.images_created:
		if device._rd.texture_is_valid(rid):live_images+=1
	probe={"live_images":live_images}
	probed.emit.call_deferred()

func sustained_switches() -> void:
	# Exercise all four emitter/deep combinations before measuring ownership.
	for combination in 4:
		bounces=4 if combination&2 else 2
		await native_frame({"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":4 if combination&1 else 0}]})
	var resources: int=device._owned.size()
	check(device._variants.size()==4,"all emitter and path-depth pipeline variants are available")
	var successful:=true
	for cycle in 24:
		bounces=2 if cycle%2==0 else 4
		size=[Vector2i(96,54),Vector2i(128,72),Vector2i(160,90)][cycle%3]
		var pose:=Transform3D(Basis(Vector3.UP,sin(cycle*0.2)*0.12),Vector3(0,0,sin(cycle*0.3)*0.1))
		var value:=await native_frame({"instances":[{"index":0,"transform":pose,"mask":7},
			{"index":1,"transform":Transform3D.IDENTITY,"mask":4 if cycle%4<2 else 0}]})
		successful=successful and is_finite(value.r) and value.a==1.0 and device._ready and device._history_valid
		for i in 2:await native_frame()
		check(device._owned.size()==resources,"cycle "+str(cycle)+" retains the bounded pipeline and scene resource pool")
	check(successful,"repeated resize, emitter and bounce changes produce finite fresh histories")
	RenderingServer.call_on_render_thread(live_image_probe);await probed
	check(probe.live_images==20,"only the current twenty lighting, guide, auxiliary and spatial images remain live")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified lifecycle reconstruction device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8;camera.position=Vector3(0,0,6)
	sun_energy=0;sky_energy=1;bounces=2
	quad(mesh_data,[Vector3(-30,-30,0),Vector3(30,-30,0),Vector3(30,30,0),Vector3(-30,30,0)],Vector3.BACK,Vector3.ZERO)
	quad(mesh_data,[Vector3(8,0,2),Vector3(8.2,0,2),Vector3(8.2,0.2,2),Vector3(8,0.2,2)],Vector3.FORWARD,Vector3(0.2,0.2,0.2))
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"emissive":false,"surface":Vector3(1,0,0)},
		{"offset":6,"count":6,"standard":true,"opaque":true,"emissive":true,"surface":Vector3(1,0,0)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":0}]
	await new_device()
	await dispatch_lifetime()
	RenderingServer.call_on_render_thread(pipeline_probe);await probed
	report["pipeline_failure"]=probe.duplicate()
	check(probe.rejected and probe.unchanged,"failed mode compilation preserves the active shader, flags and history")
	check(probe.retry,"failed mode compilation can be retried without a false success")
	check(probe.ready_during_reset,"successful pipeline change preserves display readiness while temporal history resets")
	bounces=4;await native_frame()
	for kind: String in ["image","filter_set","ray_set","sampler"]:
		RenderingServer.call_on_render_thread(target_probe.bind(kind));await probed
		report[kind]=probe.duplicate();size=probe.next_size
		check(probe.rejected and probe.unchanged,kind+" failure preserves every live resource and output binding")
		check(probe.cleaned,kind+" failure frees all staged resources")
		check(probe.retry and probe.reset,kind+" failure permits a complete retry with reset history")
		check(probe.private,kind+" retry keeps unpublished output private until a successful render")
		check(probe.ready_during_reset and probe.published_unchanged,kind+" retry preserves ready, unchanged display pixels through the history reset")
		await native_frame()
		check(device.output_ready() and device.output.get_size()==Vector2(size),kind+" successful retry publishes the complete resized output")
	RenderingServer.call_on_render_thread(invalid_frame_probe.bind(frame()));await probed
	check(probe.unchanged,"invalid frame dimensions/data do not consume transforms or change history")
	await native_frame({"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":4}]})
	RenderingServer.call_on_render_thread(emitter_history_probe);await probed
	report["emitter_history_reset"]=probe.duplicate()
	check(probe.accepted and probe.emitter_updated and probe.history_reset,"moving a real emissive placement invalidates its previous lighting history")
	check(probe.ready and probe.published_unchanged,"emissive history reset preserves the complete published image and readiness")
	var resumed:=await native_frame()
	check(device.output_ready() and device._history_valid and resumed.a==1.0,"render after emissive motion publishes a fresh valid estimate")
	await sustained_switches()
	for kind: String in ["frame_upload","history_copy","pose_upload","resize","resize_frame_upload","resize_history_copy","first_frame_upload","first_history_copy","spatial_image","spatial_set"]:
		await new_device(not kind.begins_with("first_"))
		RenderingServer.call_on_render_thread(failure_probe.bind(kind,frame()));await probed;await frames(2)
		report[kind+"_render"]=probe.duplicate()
		check(probe.stopped and probe.no_more_uploads,kind+" failure clears confidence and blocks queued dispatch")
		check(probe.preserved_output,kind+" failure retains the complete display resource")
		check(failure_events==1,kind+" failure signals fallback exactly once")
	await new_device()
	check(device._ready and device._history_valid,"a fresh scene device renders after prior device failures")
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	check(device._owned.is_empty() and device._raw.is_empty() and device._filter_auxiliary.is_empty() and not device.output_ready(),"final disposal releases scene and reconstruction resources")
	RenderingServer.call_on_render_thread(live_image_probe);await probed
	check(probe.live_images==0,"final disposal frees all current and retired output images")
	FileAccess.open(out.path_join("path-lifecycle.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
