extends "res://tools/tests/path_trace_rr_resources.gd"
## Real native resource retirement remains bounded and fully cancellable.
class RetiringPath extends MeasuredPath:
	var freed_resources:=0
	var freed_ids: Dictionary={}
	var duplicate_free:=false
	var extra_images: Array[RID]=[]
	var feature_ids: Dictionary={}
	var feature_sets: Array[RID]=[]
	var feature_compute: Array[RID]=[]
	var feature_rays: Array[RID]=[]
	var shared_compute: Array[RID]=[]
	var shared_rays: Array[RID]=[]
	func _free_retired_rid(rid: RID) -> void:
		duplicate_free=duplicate_free or freed_ids.has(rid)
		freed_ids[rid]=true;freed_resources+=1;_rd.free_rid(rid)
	func live_images() -> int:
		var count:=0
		for allocation in allocations:
			if _rd.texture_is_valid(allocation.rid):count+=1
		for rid in extra_images:
			if _rd.texture_is_valid(rid):count+=1
		return count

var retirement_rows:=[]
var retirement_state:={}
var feature_cache:=false

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows)
	data.encode_float(190*4,float(feature_cache))
	return data

func build_retiring(shared_programs: RefCounted=null) -> bool:
	device=RetiringPath.new()
	device.programs=shared_programs
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func add_owned_images(target: RetiringPath) -> void:
	for i in 96:target._own(target._lighting_texture(Vector2i(4,4)))
	resources_inspected.emit.call_deferred()

func begin_retirement(target: RetiringPath) -> void:
	target.extra_images.assign(target.nrd._textures)
	var before:=target.live_bytes();var rendered:=target.completed_renders
	if target.has_method("begin_retirement"):target.call("begin_retirement")
	else:target.dispose()
	target.render(size,PackedByteArray())
	retirement_state={"before":before,"after":target.live_bytes(),"closed":target._closed,
		"ready":target.output_ready(),"rendered":target.completed_renders-rendered}
	retirement_rows.append(retirement_state.duplicate());resources_inspected.emit.call_deferred()

func retirement_step(target: RetiringPath) -> void:
	var before:=target.freed_resources;var images:=target.live_images()
	if target.has_method("retire_step"):target.call("retire_step")
	retirement_state={"freed":target.freed_resources-before,"freed_images":images-target.live_images(),"live_bytes":target.live_bytes(),
		"complete":target.call("retirement_complete") if target.has_method("retirement_complete") else true,
		"duplicate_free":target.duplicate_free,"public_detached":target.output.get_width()==0
			and target.guide.get_width()==0 and target.shadow0.get_width()==0 and target.shadow1.get_width()==0
			and target.direct_sun.get_width()==0 and target.transmission.colour.get_width()==0 and target.transmission.guide.get_width()==0}
	retirement_state.merge(feature_status(target))
	retirement_rows.append(retirement_state.duplicate());resources_inspected.emit.call_deferred()

func finish_retirement(target: RetiringPath) -> void:
	var before:=target.freed_resources
	target.dispose();target.dispose()
	retirement_state={"live_bytes":target.live_bytes(),"duplicate_free":target.duplicate_free,
		"live_images":target.live_images(),
		"complete":target.call("retirement_complete") if target.has_method("retirement_complete") else true,
		"width":target.output.get_width(),"ready":target.output_ready(),"freed":target.freed_resources-before}
	retirement_state.merge(feature_status(target))
	retirement_rows.append(retirement_state.duplicate());resources_inspected.emit.call_deferred()

func capture_features(target: RetiringPath,shared: bool) -> void:
	var transmission:=target.transmission
	var pools: Dictionary={"transmission":transmission._images+[transmission._set,transmission._sbt,transmission._metadata,transmission._control],
		"sharc":target.sharc._owned+[target.sharc._update_set],
		"rtxdi":[target.rtxdi._reservoirs,target.rtxdi._surfaces,target.rtxdi._neighbors,target.rtxdi._control,target.rtxdi._previous_frame]}
	var valid:=transmission._own_programs!=shared
	if transmission._own_programs and transmission._programs!=null:
		pools["transmission_programs"]=transmission._programs._owned.duplicate()
		target.feature_rays.append(transmission._pipeline)
	elif shared and target.programs!=null:
		for pipeline: RID in target.programs._pipelines.values():target.shared_rays.append(pipeline)
		for pair: Array in target.programs._compute.values():target.shared_compute.append(pair[1])
	var counts: Dictionary={}
	for name: String in pools:
		counts[name]=pools[name].size()
		for rid: RID in pools[name]:
			valid=valid and rid.is_valid()
			if rid.is_valid():target.feature_ids[rid]=name
	for rid in [transmission._set,target.sharc._resolve_set,target.sharc._update_set]:
		valid=valid and target._rd.uniform_set_is_valid(rid)
		if rid.is_valid():target.feature_sets.append(rid)
	for rid in transmission._images:valid=valid and target._rd.texture_is_valid(rid)
	if not shared:target.feature_compute.append(target.sharc._resolve_pipeline)
	for rid in target.feature_compute+target.shared_compute:valid=valid and target._rd.compute_pipeline_is_valid(rid)
	for rid in target.feature_rays+target.shared_rays:valid=valid and target._rd.raytracing_pipeline_is_valid(rid)
	# RD has no non-erroring buffer-is-valid query. Verify real native storage
	# before retirement, then require one actual free callback per captured RID.
	var buffers: Array=target.sharc._buffers+[target.sharc._constants,target.sharc._stats,
		target.rtxdi._reservoirs,target.rtxdi._surfaces,target.rtxdi._neighbors,target.rtxdi._control,target.rtxdi._previous_frame,
		transmission._metadata,transmission._control]
	for rid: RID in buffers:
		if rid.is_valid():valid=valid and target._rd.buffer_get_data(rid,0,4).size()==4
		else:valid=false
	retirement_state={"features_valid":valid,"pool_counts":counts,"private_resources":target.feature_ids.size(),
		"shared_programs":shared,"native_buffers":buffers.size()}
	retirement_rows.append(retirement_state.duplicate());resources_inspected.emit.call_deferred()

func feature_status(target: RetiringPath) -> Dictionary:
	var remaining:=0;var invalid_before_free:=false;var sets_live:=0;var pipelines_live:=0;var shared_valid:=true
	for rid: RID in target.feature_ids:
		if not target.freed_ids.has(rid):remaining+=1
	for rid in target.feature_sets:
		var valid:=target._rd.uniform_set_is_valid(rid)
		if valid:sets_live+=1
		elif not target.freed_ids.has(rid):invalid_before_free=true
	for rid in target.feature_compute:
		if target._rd.compute_pipeline_is_valid(rid):pipelines_live+=1
	for rid in target.feature_rays:
		if target._rd.raytracing_pipeline_is_valid(rid):pipelines_live+=1
	for rid in target.shared_compute:shared_valid=shared_valid and target._rd.compute_pipeline_is_valid(rid) and not target.freed_ids.has(rid)
	for rid in target.shared_rays:shared_valid=shared_valid and target._rd.raytracing_pipeline_is_valid(rid) and not target.freed_ids.has(rid)
	return {"feature_resources_remaining":remaining,"feature_sets_live":sets_live,"feature_pipelines_live":pipelines_live,
		"feature_dependency_invalidated_early":invalid_before_free,"shared_programs_valid":shared_valid}

func feature_retirement(shared: bool) -> void:
	var label:="shared programs" if shared else "private programs"
	var programs: RefCounted=PathDevice.Programs.new() if shared else null
	check(await build_retiring(programs),"build transmission/SHARC/RTXDI scene with "+label)
	await render_many(3,{"ray_reconstruction":true,"transmission":true,"rtxdi":true})
	var retired:=device as RetiringPath
	check(retired.output_ready() and retired.transmission.active and retired.sharc.active and retired.rtxdi.active
		and retired.transmission.frames>=3 and retired.sharc.frames>=3 and retired.rtxdi.frames>=3,
		"all optional passes dispatch before retirement: "+label)
	RenderingServer.call_on_render_thread(capture_features.bind(retired,shared));await resources_inspected
	check(retirement_state.features_valid and retirement_state.pool_counts.transmission==7
		and retirement_state.pool_counts.sharc>=8 and retirement_state.pool_counts.rtxdi==5 and retirement_state.native_buffers==13,
		"retirement captures valid native images, descriptors, buffers and program ownership: "+label)
	check(await build_retiring(programs),"build a surviving optional-pass replacement: "+label)
	await render_many(3,{"ray_reconstruction":true,"transmission":true,"rtxdi":true})
	var published:=device.published_targets();var render_count:=device.completed_renders
	RenderingServer.call_on_render_thread(begin_retirement.bind(retired));await resources_inspected
	var bounded:=true;var steps:=0
	for i in 80:
		RenderingServer.call_on_render_thread(retirement_step.bind(retired));await resources_inspected
		steps+=1;bounded=bounded and retirement_state.freed<=16 and retirement_state.freed_images<=retirement_state.freed \
			and retirement_state.public_detached and not retirement_state.feature_dependency_invalidated_early and retirement_state.shared_programs_valid
		if retirement_state.complete:break
		await frames(1)
	check(bounded and steps>1,"optional images, descriptors and programs retire in dependency order within each batch: "+label)
	check(retirement_state.complete and retirement_state.feature_resources_remaining==0 and retirement_state.feature_sets_live==0
		and retirement_state.feature_pipelines_live==0 and retirement_state.live_bytes==0 and not retirement_state.duplicate_free,
		"staged retirement frees every optional private resource exactly once: "+label)
	await render_many(1)
	check(device.output_ready() and device.published_targets()==published and device.completed_renders==render_count+1
		and device.transmission.active and device.sharc.active and device.rtxdi.active,
		"replacement still renders every optional pass after old resources retire: "+label)
	RenderingServer.call_on_render_thread(finish_retirement.bind(retired));await resources_inspected
	check(retirement_state.freed==0 and retirement_state.live_images==0 and retirement_state.feature_resources_remaining==0
		and retirement_state.feature_sets_live==0 and retirement_state.feature_pipelines_live==0 and retirement_state.shared_programs_valid
		and not retirement_state.duplicate_free,"repeated disposal preserves shared programs and never frees optional resources twice: "+label)
	RenderingServer.call_on_render_thread(device.dispose);await frames(2)
	if programs!=null:RenderingServer.call_on_render_thread(programs.dispose);await frames(2)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified incremental retirement device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_retiring(),"build native retirement candidate")
	await render_many(1,{"ray_reconstruction":true})
	var retired:=device as RetiringPath
	RenderingServer.call_on_render_thread(add_owned_images.bind(retired));await resources_inspected
	check(await build_measured(),"build independently visible replacement")
	await render_many(1,{"ray_reconstruction":true})
	var published:=device.published_targets();var pixels:=device.output.get_image().get_data()
	RenderingServer.call_on_render_thread(begin_retirement.bind(retired));await resources_inspected
	check(retirement_state.closed and not retirement_state.ready and retirement_state.rendered==0,"retirement immediately stops old rendering and readiness")
	check(retirement_state.after==retirement_state.before and retirement_state.after>0,"promotion defers native destruction instead of freeing the whole old pool")
	var bounded:=true;var steps:=0
	for i in 32:
		RenderingServer.call_on_render_thread(retirement_step.bind(retired));await resources_inspected
		steps+=1;bounded=bounded and retirement_state.freed<=16 and retirement_state.freed_images<=retirement_state.freed and retirement_state.public_detached
		if retirement_state.complete:break
		await frames(1)
	check(bounded and steps>1,"all native resources including actual RR images retire in batches of at most sixteen after public detachment")
	check(retirement_state.complete and retirement_state.live_bytes==0 and not retirement_state.duplicate_free,"bounded retirement releases every tracked image exactly once")
	check(device.output_ready() and device.published_targets()==published and device.output.get_image().get_data()==pixels,"retiring the old scene leaves the replacement image and handles unchanged")
	RenderingServer.call_on_render_thread(finish_retirement.bind(retired));await resources_inspected
	check(retirement_state.live_bytes==0 and retirement_state.width==0 and not retirement_state.ready
		and not retirement_state.duplicate_free,"finished retirement tolerates repeated immediate disposal")
	RenderingServer.call_on_render_thread(device.dispose);await frames(2)

	check(await build_retiring(),"build native candidate for interrupted retirement")
	await render_many(2,{"ray_reconstruction":false,"nrd_directional":true});retired=device as RetiringPath
	check(device.nrd_active and not device.nrd._textures.is_empty(),"interrupted retirement owns actual NRD image pools and descriptors")
	RenderingServer.call_on_render_thread(add_owned_images.bind(retired));await resources_inspected
	RenderingServer.call_on_render_thread(begin_retirement.bind(retired));await resources_inspected
	RenderingServer.call_on_render_thread(retirement_step.bind(retired));await resources_inspected
	check(not retirement_state.complete and retirement_state.live_bytes>0 and retirement_state.freed<=16
		and retirement_state.freed_images<=retirement_state.freed,"partial retirement bounds both denoiser and ordinary image destruction")
	RenderingServer.call_on_render_thread(finish_retirement.bind(retired));await resources_inspected
	check(retirement_state.complete and retirement_state.live_bytes==0 and retirement_state.live_images==0
		and not retirement_state.duplicate_free,"shutdown drains partial retirement without leaks or duplicate frees")
	# A separate water interface allocates transmission's real image, SBT and
	# metadata pool. Run once with private programs and once with the shared
	# cache used by live scene generations; all three optional passes execute.
	quad(mesh_data,[Vector3(-3,.5,-3),Vector3(3,.5,-3),Vector3(3,.5,3),Vector3(-3,.5,3)],Vector3.UP,Vector3.ZERO)
	geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,
		"dielectric":PackedFloat32Array([.2,.1,.02,1.333,1,1,0,0])})
	placements.append({"geometry":1,"transform":Transform3D.IDENTITY,"mask":5})
	feature_cache=true;bounces=4
	await feature_retirement(false)
	await feature_retirement(true)
	FileAccess.open(out.path_join("retirement.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"steps":retirement_rows},"\t"))
	camera.queue_free();finish()
