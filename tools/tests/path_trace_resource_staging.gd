extends "res://tools/tests/path_trace_device.gd"
## Native construction must remain private and bounded before the first trace.
## The synchronous path supplies an independent GPU byte/pixel oracle.
const WaterDevice = preload("res://src/game/fx/water_raytrace_device.gd")
const PathWaterDevice = preload("res://src/game/fx/path_trace_water_device.gd")
signal inspected
var state: Dictionary={}
var rows: Array=[]
var build_images: Array[Image]=[]
var shared_programs: RefCounted
var fault_script: GDScript

class ObservedPath extends PathDevice:
	var notifications: Array=[]
	func _create_colour_array(format: RDTextureFormat,layers: Array[PackedByteArray]) -> RID:
		format.usage_bits|=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		return super._create_colour_array(format,layers)
	func _notify(name: StringName,arguments: Array) -> void:
		if name==&"prepared":notifications.append(arguments[0])
		super._notify(name,arguments)

class ObservedWater extends WaterDevice:
	var notifications: Array=[]
	func _create_colour_array(format: RDTextureFormat,layers: Array[PackedByteArray]) -> RID:
		format.usage_bits|=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		return super._create_colour_array(format,layers)
	func _notify(name: StringName,arguments: Array) -> void:
		if name==&"prepared":notifications.append(arguments[0])
		super._notify(name,arguments)

class ObservedPathWater extends PathWaterDevice:
	var notifications: Array=[]
	func _notify(name: StringName,arguments: Array) -> void:
		if name==&"prepared":notifications.append(arguments[0])
		super._notify(name,arguments)

func native_state(target: RefCounted) -> Dictionary:
	return {"ready":target._ready,"building":target._building,"closed":target._closed,
		"owned":target._owned.size(),"public_width":target.output.get_width(),
		"prepared":target.notifications.duplicate(),"timings":target.build_timings.duplicate(),
		"instances":target._instances.size(),"materials_packed":target.get("_build_material_cursor") if target.has_method("_build_resource_phase") else -1,
		"buffers":target._rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS),
		"textures":target._rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)}

func start_build(target: RefCounted,mutate_inputs:=false,large:=false) -> void:
	var descriptions:=geometries.duplicate(true);var instances:=placements.duplicate(true)
	var pose:=mesh_data.slice(0,6*16)
	for i in 6:pose[i*16]+=.125
	target.initial_poses=[{"geometry":0,"data":pose.to_byte_array()}]
	if large:
		while descriptions.size()<1100:descriptions.append(descriptions[0].duplicate(true))
		while instances.size()<2050:instances.append({"geometry":instances.size()%1100,"transform":Transform3D.IDENTITY,"mask":0})
	target.build(mesh_data.to_byte_array(),build_images,descriptions,instances)
	if mutate_inputs:
		descriptions[0].offset=999999;instances[0].mask=0
	state=native_state(target);rows.append(state.duplicate(true));inspected.emit.call_deferred()

func step_build(target: RefCounted) -> void:
	target.build_step();state=native_state(target)
	rows.append(state.duplicate(true));inspected.emit.call_deferred()

func inspect_build(target: RefCounted) -> void:
	state=native_state(target);inspected.emit.call_deferred()

func drain_build(target: RefCounted,active: RefCounted=null) -> int:
	var steps:=0
	for i in 128:
		if not target._building:break
		if active!=null:RenderingServer.call_on_render_thread(active.render.bind(size,frame(false),{"ray_reconstruction":true}))
		RenderingServer.call_on_render_thread(step_build.bind(target));await inspected
		steps+=1;await frames(1)
	return steps

func read_native(target: RefCounted) -> void:
	var buffers: Dictionary={}
	for key in ["_vertices","_materials","_instance_geometry","_lighting_offsets","_motion","_terrain_data","_emitters","_emitter_lookup"]:
		buffers[key]=target._rd.buffer_get_data(target.get(key))
	var layers: Array=[]
	for i in build_images.size():layers.append(target._rd.texture_get_data(target._colours,i))
	var instances: Array=[]
	for instance: RDAccelerationStructureInstance in target._instances:
		instances.append([instance.id,instance.transform,instance.mask,instance.flags,instance.blas.is_valid()])
	state={"buffers":buffers,"layers":layers,"instances":instances,"motion":target._motion_data.duplicate(),
		"geometry_placements":target._geometry_placements.duplicate(true),"emitters":target.emitters.count,
		"emitter_defined_bytes":target.emitters.records.size(),
		"emitter_authored":buffers._emitters.slice(0,target.emitters.records.size())==target.emitters.records
			and buffers._emitter_lookup==target.emitters.lookup}
	inspected.emit.call_deferred()

func defined_buffers_equal(actual: Dictionary,reference: Dictionary) -> bool:
	for key: String in actual.buffers:
		var a: PackedByteArray=actual.buffers[key];var b: PackedByteArray=reference.buffers[key]
		if a.size()!=b.size():return false
		if key=="_emitters":
			# The allocation reserves LIMIT entries, but shaders only read the
			# header and live count. Vulkan confirmed differences solely in the
			# never-uploaded tail; all defined bytes remain an exact oracle.
			var defined: int=actual.emitter_defined_bytes
			if defined!=reference.emitter_defined_bytes or defined<PathDevice.Emitters.HEADER or defined>a.size():return false
			a=a.slice(0,defined);b=b.slice(0,defined)
		if a!=b:return false
	return actual.emitter_authored and reference.emitter_authored

func buffer_diagnostics(actual: Dictionary,reference: Dictionary) -> Dictionary:
	var report: Dictionary={}
	for key: String in actual.buffers:
		var a: PackedByteArray=actual.buffers[key];var b: PackedByteArray=reference.buffers[key]
		var first:=-1;var last:=-1;var different:=0;var defined_different:=0
		var defined: int=actual.emitter_defined_bytes if key=="_emitters" else a.size()
		if a!=b:
			for i in mini(a.size(),b.size()):
				if a[i]==b[i]:continue
				if first<0:first=i
				last=i;different+=1
				if i<defined:defined_different+=1
		report[key]={"actual_bytes":a.size(),"reference_bytes":b.size(),"defined_bytes":defined,
			"first_difference":first,"last_difference":last,"different_bytes":different,"defined_different_bytes":defined_different}
	return report

func cancelled(target: RefCounted) -> void:
	var texture: RID=target._colours
	var count: int=target.notifications.size()
	target.dispose();target.build_step();target.dispose()
	# A callback queued before cancellation must never restart allocation.
	target.build(mesh_data.to_byte_array(),build_images,geometries,placements);target.build_step()
	state=native_state(target)
	state["texture_freed"]=not texture.is_valid() or not target._rd.texture_is_valid(texture)
	state["notification_delta"]=target.notifications.size()-count
	state["inputs_empty"]=not target.has_method("_build_resource_phase") or (target.get("_build_data").is_empty()
		and target.get("_build_placements").is_empty() and target.get("_build_material_data").is_empty())
	rows.append(state.duplicate(true));inspected.emit.call_deferred()

func memory_snapshot() -> void:
	var rd:=RenderingServer.get_rendering_device()
	state={"buffers":rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS),"textures":rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)}
	inspected.emit.call_deferred()

func phase_key(target: RefCounted) -> String:
	var phase: int=target.get("_build_resource_stage")
	if phase<0:return "complete"
	return str(phase)+("/"+str(target.get("_build_extra_phase")) if phase==5 else "")

func prepare_fault_injector() -> bool:
	fault_script=GDScript.new()
	fault_script.source_code="extends \"res://src/game/fx/path_trace_device.gd\"\nvar notifications: Array=[]\nvar fail_phase: String=\"\"\nfunc _notify(name: StringName,args: Array) -> void:\n\tif name==&\"prepared\":notifications.append(args[0])\n\tsuper._notify(name,args)\nfunc _build_resource_phase(phase: int) -> int:\n\tvar key:=str(phase)+(\"/\"+str(_build_extra_phase) if phase==5 else \"\")\n\tvar result:=super._build_resource_phase(phase)\n\treturn ERR_CANT_CREATE if key==fail_phase else result\n"
	return fault_script.reload()==OK

func private_lifecycle() -> void:
	# Load the new fault hook only when available. The old build's negative
	# assertions are native allocations at enqueue, not a missing-method error.
	if not device.has_method("_build_resource_phase"):
		print("Legacy build has no partial resource phases; eager allocation assertions still run.")
		return
	check(prepare_fault_injector(),"native partial-allocation fault injector parses")
	for key in ["0","1","2","3","4","5/0","5/1","5/2"]:
		for fail in [false,true]:
			await frames(8)
			RenderingServer.call_on_render_thread(memory_snapshot);await inspected
			var before:=state.duplicate()
			var target: RefCounted=fault_script.new();target.programs=shared_programs;target.incremental_build=true
			if fail:target.set("fail_phase",key)
			RenderingServer.call_on_render_thread(start_build.bind(target,false,key=="2" or key=="3"));await inspected
			for i in 32:
				if phase_key(target)==key:break
				RenderingServer.call_on_render_thread(step_build.bind(target));await inspected
			# Exercise disposal after this phase's allocations have occurred.
			RenderingServer.call_on_render_thread(step_build.bind(target));await inspected
			var private_ok: bool=not state.ready and state.public_width==0 and state.prepared==([false] if fail else [])
			if key=="2":private_ok=private_ok and state.materials_packed>0 and state.materials_packed<=1024 and state.materials_packed<1100
			if key=="3":private_ok=private_ok and state.instances>0 and state.instances<=1024 and state.instances<2050
			RenderingServer.call_on_render_thread(cancelled.bind(target));await inspected
			check(private_ok and state.closed and not state.ready and state.owned==0 and state.public_width==0
				and state.texture_freed and state.notification_delta==0 and state.inputs_empty,
				("failed" if fail else "canceled")+" phase "+key+" releases partial state and ignores late callbacks")
			await frames(8)
			RenderingServer.call_on_render_thread(memory_snapshot);await inspected
			check(state.buffers==before.buffers and state.textures==before.textures,
				("failed" if fail else "canceled")+" phase "+key+" returns native buffer/image bytes to baseline")

func water_control() -> void:
	var targets: Array=[];var pixels: Array=[];var has_hits:=true
	var packet:=PackedFloat32Array()
	# Water rays start at the mirrored camera below the clipping plane and
	# travel upward into reflected geometry, as in the established RT fixture.
	var transform:=Transform3D(Basis.IDENTITY,Vector3(0,-2,3)).looking_at(Vector3.ZERO)
	var projection:=Projection.create_perspective(70.0,float(size.x)/size.y,.05,100.0)
	for matrix: Projection in [projection.inverse(),Projection(transform)]:
		for axis in 4:
			var vector: Vector4=matrix[axis];packet.append_array(PackedFloat32Array([vector.x,vector.y,vector.z,vector.w]))
	packet.append_array(PackedFloat32Array([1,1,1,0,0,0,0,0,0,1,0,-1,90,100,100,0,0.2,0.3,0.5,0]))
	packet.resize(WaterDevice.FRAME_BYTES/4)
	for incremental in [false,true]:
		var target:=ObservedWater.new();target.programs=shared_programs;target.incremental_build=incremental
		targets.append(target)
		RenderingServer.call_on_render_thread(start_build.bind(target));await inspected
		if incremental:check(state.owned==0 and not state.ready and state.prepared.is_empty(),"water replacement also allocates no native resources at enqueue")
		await drain_build(target)
		check(target._ready and target.notifications==[true],"water build completes once: incremental="+str(incremental))
		RenderingServer.call_on_render_thread(target.render.bind(size,packet.to_byte_array()))
		await frames(6);await RenderingServer.frame_post_draw
		var result:=target.output.get_image()
		has_hits=has_hits and result.get_pixel(size.x/2,size.y/2).a>.5
		rows.append({"water_incremental":incremental,"center":str(result.get_pixel(size.x/2,size.y/2)),"image_bytes":result.get_data().size()})
		pixels.append(result.get_data())
	check(has_hits and not pixels[0].is_empty() and pixels[0]==pixels[1],"staged water build preserves exact reflected hit image bytes")
	for target in targets:RenderingServer.call_on_render_thread(target.dispose)
	await frames(8)

func inspect_water_frame(target: RefCounted) -> void:
	var rid: RID=target._water_frame
	var bytes:=PackedByteArray()
	if rid.is_valid():bytes=target._rd.buffer_get_data(rid)
	state={"valid":rid.is_valid() and target._owned.has(rid) and bytes.size()==32,"bytes":bytes}
	inspected.emit.call_deferred()

func path_water_control() -> void:
	var targets: Array=[];var pixels: Array=[];var current_parameters:=true;var has_hits:=true
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.position=Vector3(0,-2,3);camera.look_at(Vector3.ZERO)
	for incremental in [false,true]:
		var target:=ObservedPathWater.new();target.programs=shared_programs;target.incremental_build=incremental
		targets.append(target);device=target
		RenderingServer.call_on_render_thread(start_build.bind(target));await inspected
		await drain_build(target)
		RenderingServer.call_on_render_thread(inspect_water_frame.bind(target));await inspected
		check(target._ready and target.notifications==[true] and state.valid,
			"PT water construction includes its real private 32-byte parameter buffer: incremental="+str(incremental))
		# Diagnose a missing dependent resource without submitting invalid GPU
		# descriptors; the output-equivalence assertion below still fails.
		if not state.valid:continue
		tick=0;var packet:=frame(false);packet.encode_float(77*4,1.0);packet.encode_float(80*4,0.0)
		var parameters:=PackedFloat32Array([-1,90,100,0,.2,.3,.5,0]).to_byte_array()
		for i in parameters.size():packet[2816+i]=parameters[i]
		RenderingServer.call_on_render_thread(target.render.bind(size,packet,{"ray_reconstruction":true}))
		await frames(6);await RenderingServer.frame_post_draw
		RenderingServer.call_on_render_thread(inspect_water_frame.bind(target));await inspected
		current_parameters=current_parameters and state.bytes==parameters and target.output_ready()
		var result:=target.reflection_output().get_image()
		has_hits=has_hits and result.get_pixel(size.x/2,size.y/2).a>.5
		pixels.append(result.get_data())
	check(pixels.size()==2 and has_hits and current_parameters and pixels[0]==pixels[1],
		"staged PT water preserves current parameter bytes and exact reflected hit radiance")
	for target in targets:RenderingServer.call_on_render_thread(target.dispose)
	await frames(8)
	var released:=true
	for target in targets:released=released and target._owned.is_empty() and not target._water_frame.is_valid() and target.reflection_output().get_width()==0
	check(released,"both PT water construction paths release their additional private resources")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native resource staging device")
	if not PathDevice.supported():finish();return
	size=Vector2i(128,72);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,2,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,3,-2),Vector3(2,3,-2),Vector3(2,3,2),Vector3(-2,3,2)],Vector3.DOWN,Vector3(.4,.1,.2))
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)},
		{"offset":6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7,"lighting_offset":Vector3(.1,0,.2)},
		{"geometry":1,"transform":Transform3D.IDENTITY,"mask":7},
		{"geometry":1,"transform":Transform3D(Basis.IDENTITY,Vector3(0,4,0)),"mask":0}]
	var image:=Image.create(8,8,true,Image.FORMAT_RGBA8);image.fill(Color(.7,.6,.5));image.generate_mipmaps();build_images=[image]
	shared_programs=PathDevice.Programs.new()
	device=ObservedPath.new();device.programs=shared_programs
	RenderingServer.call_on_render_thread(start_build.bind(device));await inspected
	check(state.ready and state.prepared==[true],"initial PT construction retains synchronous readiness")
	if not state.ready:finish();return
	await render_many(1,{"ray_reconstruction":true})
	var active:=device;var active_renders:=active.completed_renders;var bindings:=active.published_targets()
	RenderingServer.call_on_render_thread(read_native.bind(active));await inspected
	var reference:=state.duplicate(true)
	var candidate:=ObservedPath.new();candidate.programs=shared_programs;candidate.incremental_build=true
	RenderingServer.call_on_render_thread(start_build.bind(candidate,true));await inspected
	check(state.owned==0 and not state.ready and state.prepared.is_empty() and state.public_width==0,
		"private PT enqueue performs no native allocation, readiness or publication")
	var steps:=await drain_build(candidate,active)
	check(candidate._ready and candidate.notifications==[true] and steps>=8,"PT resources are prepared across separate callbacks before one readiness notification")
	check(active.output_ready() and active.published_targets()==bindings and active.completed_renders>=active_renders+steps,
		"every preparation frame keeps rendering the active scene with stable bindings")
	RenderingServer.call_on_render_thread(read_native.bind(candidate));await inspected
	var comparison:={"buffers":buffer_diagnostics(state,reference),"mips_equal":state.layers==reference.layers,
		"mips_authored":state.layers==[build_images[0].get_data()],"instances_equal":state.instances==reference.instances,
		"geometry_placements_equal":state.geometry_placements==reference.geometry_placements,"emitter_count_equal":state.emitters==reference.emitters}
	rows.append({"native_equivalence":comparison});print("RESOURCE_STAGING_EQUIVALENCE ",JSON.stringify(comparison))
	check(defined_buffers_equal(state,reference) and state.layers==reference.layers and state.layers==[build_images[0].get_data()] and state.instances==reference.instances
		and state.geometry_placements==reference.geometry_placements and state.emitters==reference.emitters and state.emitters>0,
		"staged initialized buffers, all mip bytes, masks, transforms and emitters exactly match synchronous construction")
	var expected_vertices:=mesh_data.duplicate()
	for i in 6:expected_vertices[i*16]+=.125
	check(state.buffers._vertices==expected_vertices.to_byte_array(),"deferred initial poses reach the vertex buffer before acceleration structures")
	var neutral:=PackedByteArray();neutral.resize(placements.size()*PathDevice.MOTION_STRIDE)
	for i in placements.size():
		for offset in [0,20,40,48,60,68,88]:neutral.encode_float(i*PathDevice.MOTION_STRIDE+offset,1.0)
	check(state.motion==neutral,"neutral motion records retain exact transform, normal and validity bytes")
	var packet:=frame(false)
	RenderingServer.call_on_render_thread(active.render.bind(size,packet,{"ray_reconstruction":true}))
	RenderingServer.call_on_render_thread(candidate.render.bind(size,packet,{"ray_reconstruction":true}))
	await frames(6);await RenderingServer.frame_post_draw
	var same:=true
	for key in ["output","guide","shadow0","shadow1","direct_sun"]:
		same=same and active.get(key).get_image().get_data()==candidate.get(key).get_image().get_data()
	check(same and candidate.output_ready(),"first staged RR trace publishes exact current radiance and guide bytes")
	device=candidate
	RenderingServer.call_on_render_thread(active.dispose);await frames(8)
	await private_lifecycle()
	RenderingServer.call_on_render_thread(candidate.dispose);await frames(8)
	await water_control()
	await path_water_control()
	RenderingServer.call_on_render_thread(shared_programs.dispose);await frames(8)
	FileAccess.open(out.path_join("resource-staging.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"steps":steps,"observations":rows},"\t"))
	camera.queue_free();finish()

func finish() -> void:
	TexUpscale.shutdown()
	print("PT_RESOURCE_STAGING ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
