extends RefCounted
## Reconstruct terrain self visibility from shared world-space vertices;
## disconnected terrain and objects retain exact per-pixel shadow queries.
const Programs = preload("res://src/game/fx/raytrace_programs.gd")
const CpuBuild = preload("path_trace_terrain_sun_build.gd")
const BackgroundJob = preload("path_trace_terrain_sun_job.gd")
const PREFIX := "res://src/game/fx/shaders/path_trace_terrain_sun_"
const INVALID := 0xffffffff
var _rd: RenderingDevice
var _host: RefCounted
var _programs: RefCounted
var _own_programs := false
var _owned: Array[RID] = []
var _input := RID()
var _output := RID()
var _control := RID()
var _shader := RID()
var _pipeline := RID()
var _sbt := RID()
var _set := RID()
var _terrain := {}
var _placements: Array = []
var _component_corners := PackedInt32Array()
var _bases := PackedInt32Array()
var _parents := PackedInt32Array()
var _ranks := PackedInt32Array()
var _components := 0
var _topology_ready := false
var _topology_failed := false
var _topology_dirty := false
var _corner_capacity := 0
var _input_capacity := 0
var _samples := 0
var _geometry_dirty := true
var _valid := false
var _signature := PackedByteArray()
var refreshes := 0
var _cpu_builder: RefCounted
var _prepared_input := PackedByteArray()
var _initial_poses: Array=[]
var _gpu_build_phase := -1
var _upload_cursor := 0
var _synchronous_stats := {}
var _background_job: RefCounted
var _background_last: Dictionary={}
var _background_started:=0
var _background_joined:=0

func capture_initial_poses(poses: Array) -> void:
	# Base build clears its array after upload. Its pose dictionaries/bytes are
	# immutable snapshots, so retaining a shallow array copy does no mesh work.
	_initial_poses=poses.duplicate()

func begin_background_prepare(data: PackedByteArray,geometry: Array,placements: Array,poses: Array=[]) -> Error:
	cancel_prepare();_background_last={}
	_topology_ready=false;_topology_failed=false
	_background_job=BackgroundJob.new()
	var result: Error=_background_job.start(data,geometry,placements,poses)
	if result==OK:_background_started+=1
	else:
		# Thread creation failure keeps the existing bounded caller-thread path.
		_background_last=_background_job.snapshot()
		_cpu_builder=_background_job.take_builder();_background_job=null
	return result

func background_ready() -> bool:return _background_job==null or not _background_job.is_running()

func background_state() -> Dictionary:
	var state: Dictionary=_background_job.snapshot() if _background_job!=null else _background_last.duplicate()
	state["started"]=_background_started;state["joined_count"]=_background_joined
	state["pending"]=_background_job!=null
	state["running"]=state.get("running",false) if _background_job!=null else false
	return state

func begin_prepare(data: PackedByteArray,geometry: Array,placements: Array,poses: Array=[]) -> void:
	cancel_prepare()
	_cpu_builder=CpuBuild.new();_cpu_builder.begin(data,geometry,placements,poses)
	_topology_ready=false;_topology_failed=false

func prepare_step(budget_us:=1500,work_limit:=4096) -> Error:
	if _background_job!=null:
		var status: Error=_background_job.poll()
		if status==ERR_BUSY:return ERR_BUSY
		_background_last=_background_job.snapshot()
		if _background_last.joined:_background_joined+=1
		_cpu_builder=_background_job.take_builder();_background_job=null
		if status!=OK:_topology_failed=true;return status
	if _cpu_builder==null:return ERR_UNCONFIGURED
	var result: Error=_cpu_builder.step(budget_us,work_limit)
	if result==OK and not _topology_ready:
		_terrain=_cpu_builder.terrain;_placements=_cpu_builder.placements
		_component_corners=_cpu_builder.component_corners;_bases=_cpu_builder.bases
		_components=_cpu_builder.components;_corner_capacity=_cpu_builder.corner_capacity;_samples=_cpu_builder.samples
		_prepared_input=_cpu_builder.data
		_topology_ready=true;_topology_dirty=false;_geometry_dirty=true;_valid=false
	return result

func cancel_prepare() -> void:
	if _background_job!=null:
		_background_job.cancel();_background_last=_background_job.snapshot()
		if _background_last.joined:_background_joined+=1
		_background_job=null
	if _cpu_builder!=null:_cpu_builder.cancel()
	_cpu_builder=null;_prepared_input=PackedByteArray()

func is_preparing() -> bool:return _background_job!=null or (_cpu_builder!=null and _cpu_builder.pending())
func prepared_data() -> PackedByteArray:return _prepared_input
func preparation_stats() -> Dictionary:
	if _background_job!=null:
		return {"last_work":0,"total_work":0,"steps":0,"last_us":0,"max_us":0,"total_us":0,
			"phase":"background","phase_ms":{},"background":background_state()}
	if _cpu_builder!=null:
		var stats: Dictionary=_cpu_builder.stats()
		if not _background_last.is_empty():stats["background"]=background_state()
		return stats
	if not _synchronous_stats.is_empty():return _synchronous_stats
	return {"last_work":0,"total_work":0,"steps":0,"last_us":0,"max_us":0,"total_us":0,"phase":"idle","phase_ms":{}}

func _own(rid: RID) -> RID:
	if rid.is_valid():_owned.append(rid)
	return rid

func prepare(data: PackedByteArray,geometry: Array,placements: Array,poses: Array=[]) -> bool:
	# Synchronous startup/reference path. Connectivity is the actual shared-
	# position graph, including native terrain T-junctions. Live terrain
	# changes replan this graph before the next ray dispatch.
	_terrain.clear();_placements=placements.duplicate(true)
	if _placements.is_empty():_placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":255}]
	_corner_capacity=0;_topology_failed=false
	for i in geometry.size():
		if bool(geometry[i].get("terrain",false)):
			var start: int=int(geometry[i].offset)*64
			_terrain[i]=data.slice(start,start+int(geometry[i].count)*64)
	# Base build uploads these bytes before creating its BLAS, then clears the
	# initial-pose array. Derive components/cache records from that same state.
	for pose: Dictionary in poses:
		if _terrain.has(pose.geometry):
			if pose.data.size()!=_terrain[pose.geometry].size():return false
			_terrain[pose.geometry]=pose.data.duplicate()
	return _plan_topology()

func _plan_topology() -> bool:
	_components=0;_component_corners.clear();_parents.clear();_ranks.clear()
	_bases.resize(_placements.size());_bases.fill(-1)
	var welded := {}
	for instance in _placements.size():
		var placement: Dictionary=_placements[instance]
		if not _terrain.has(placement.geometry):continue
		var bytes: PackedByteArray=_terrain[placement.geometry]
		if bytes.size()%192!=0:return false
		var transform: Transform3D=placement.transform
		# Absent/non-shadow-casting placements must not connect otherwise
		# independent live terrain through an invisible bridge.
		var group: int=0 if (int(placement.get("mask",255))&2)!=0 else instance+1
		if not welded.has(group):welded[group]={}
		_bases[instance]=_component_corners.size()
		for at in range(0,bytes.size(),192):
			var triangle := PackedInt32Array()
			for corner in 3:
				var point: Vector3=transform*_position(bytes,at+corner*64)
				var index: int=int(welded[group].get(point,-1))
				if index<0:
					index=_parents.size();welded[group][point]=index;_parents.append(index);_ranks.append(0)
				triangle.append(index);_component_corners.append(index)
			_join(triangle[0],triangle[1]);_join(triangle[0],triangle[2])
	var dense := {}
	for i in _component_corners.size():
		var root:=_root(_component_corners[i])
		if not dense.has(root):dense[root]=dense.size()
		_component_corners[i]=dense[root]
	_components=dense.size();_corner_capacity=_component_corners.size()
	_parents.clear();_ranks.clear()
	_topology_ready=true;_topology_dirty=false;_geometry_dirty=true;_valid=false
	return true

func _root(index: int) -> int:
	var root:=index
	while _parents[root]!=root:root=_parents[root]
	while _parents[index]!=index:
		var next:=_parents[index];_parents[index]=root;index=next
	return root

func _join(a: int,b: int) -> void:
	a=_root(a);b=_root(b)
	if a==b:return
	if _ranks[a]<_ranks[b]:_parents[a]=b
	else:
		_parents[b]=a
		if _ranks[a]==_ranks[b]:_ranks[a]+=1

func setup(host: RefCounted,data: PackedByteArray,geometry: Array,placements: Array) -> bool:
	var started:=Time.get_ticks_usec()
	_host=host;_rd=host._rd
	if not _topology_ready and not prepare(data,geometry,placements,_initial_poses):return false
	_initial_poses=[]
	var planned:=Time.get_ticks_usec()
	# Fixed-capacity storage also supports transformed and posed terrain without
	# invalidating any main/transmission descriptors. Unique samples <= corners.
	_input_capacity=32+_placements.size()*4+_corner_capacity*36+(_corner_capacity/3)*4
	_input=_own(_rd.storage_buffer_create(maxi(_input_capacity,16)))
	_output=_own(_rd.storage_buffer_create(maxi(_corner_capacity*4,4)))
	_control=_own(_rd.uniform_buffer_create(32))
	if not _input.is_valid() or not _output.is_valid() or not _control.is_valid():return false
	var allocated:=Time.get_ticks_usec()
	var ok:=_rebuild_inputs();var ended:=Time.get_ticks_usec()
	_synchronous_stats={"last_work":0,"total_work":0,"steps":1,"last_us":ended-started,"max_us":ended-started,
		"total_us":ended-started,"phase":"synchronous","phase_ms":{"topology":(planned-started)/1000.0,
		"allocation":(allocated-planned)/1000.0,"pack_upload":(ended-allocated)/1000.0}}
	return ok

func build_step(host: RefCounted,source: PackedByteArray,geometry: Array,placements: Array,budget_us:=1500) -> Error:
	# Only private incremental scene generations use this entry. Synchronous
	# startup/tests retain setup(), while GPU calls stay on the render thread.
	var started:=Time.get_ticks_usec()
	if _gpu_build_phase<0:
		_host=host;_rd=host._rd
		if _background_job==null and _cpu_builder==null:begin_prepare(source,geometry,placements,_initial_poses)
		_initial_poses=[]
		_gpu_build_phase=0;_upload_cursor=0
	if _gpu_build_phase==0:
		var result:=prepare_step(maxi(1,budget_us-(Time.get_ticks_usec()-started)))
		if result!=OK:return result
		_input_capacity=32+_placements.size()*4+_corner_capacity*36+(_corner_capacity/3)*4
		_gpu_build_phase=1
		return ERR_BUSY
	# Allocate one native resource per turn. Native allocations cannot be
	# interrupted; neither one performs the former full terrain GDScript loop.
	if _gpu_build_phase==1:
		_input=_own(_rd.storage_buffer_create(maxi(_input_capacity,16)))
		if not _input.is_valid():return ERR_CANT_CREATE
		_gpu_build_phase=2;return ERR_BUSY
	if _gpu_build_phase==2:
		_output=_own(_rd.storage_buffer_create(maxi(_corner_capacity*4,4)))
		if not _output.is_valid():return ERR_CANT_CREATE
		_gpu_build_phase=3;return ERR_BUSY
	if _gpu_build_phase==3:
		_control=_own(_rd.uniform_buffer_create(32))
		if not _control.is_valid():return ERR_CANT_CREATE
		_gpu_build_phase=4;return ERR_BUSY
	while _upload_cursor<_prepared_input.size() and Time.get_ticks_usec()-started<budget_us:
		var size:=mini(65536,_prepared_input.size()-_upload_cursor)
		if _rd.buffer_update(_input,_upload_cursor,size,_prepared_input.slice(_upload_cursor,_upload_cursor+size))!=OK:return ERR_CANT_CREATE
		_upload_cursor+=size
	if _upload_cursor<_prepared_input.size():return ERR_BUSY
	_geometry_dirty=false;_valid=false;_gpu_build_phase=5
	return OK

func _position(data: PackedByteArray,at: int) -> Vector3:
	return Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8))

func _max_abs(p: Vector3) -> float:
	return maxf(absf(p.x),maxf(absf(p.y),absf(p.z)))

func _point_error(p: Vector3,world: Vector3,t: Transform3D,edge_extent: float) -> float:
	# Only transformation/roundoff uncertainty is removed. This is not the
	# previous metre-scale back-exit exemption. Use the maximum at shared corners.
	var absolute_product: Vector3=t.basis.x.abs()*absf(p.x)+t.basis.y.abs()*absf(p.y)+t.basis.z.abs()*absf(p.z)+t.origin.abs()
	return maxf(0.00001,5.9604644775390625e-8*(8.0*_max_abs(absolute_product)+4.0*_max_abs(world))+1.7881398e-7*edge_extent)

func _support(t: Transform3D) -> float:
	var x:=t.basis.x;var y:=t.basis.y;var z:=t.basis.z
	var xy:=absf(x.dot(y));var xz:=absf(x.dot(z));var yz:=absf(y.dot(z))
	# Two metre-grid cells plus both 0.6 m contour offsets. The Gram row
	# sum conservatively bounds the largest scale, including shear.
	return 3.2*sqrt(maxf(x.length_squared()+xy+xz,maxf(y.length_squared()+xy+yz,z.length_squared()+xz+yz)))

func _pack_inputs() -> PackedByteArray:
	var points: Array[Vector3]=[]
	var errors := PackedFloat32Array()
	var supports := PackedFloat32Array()
	var sample_components := PackedInt32Array()
	var active_components := {}
	var welded: Array[Dictionary]=[]
	for i in _components:welded.append({})
	var corners := PackedInt32Array()
	for instance in _placements.size():
		var placement: Dictionary=_placements[instance]
		if not _terrain.has(placement.geometry):continue
		var data: PackedByteArray=_terrain[placement.geometry]
		var transform: Transform3D=placement.transform
		var support:=_support(transform)
		for at in range(0,data.size(),192):
			var local: Array[Vector3]=[_position(data,at),_position(data,at+64),_position(data,at+128)]
			var world: Array[Vector3]=[transform*local[0],transform*local[1],transform*local[2]]
			var extent: float=maxf((world[1]-world[0]).length(),(world[2]-world[0]).length())*2.0
			for corner in 3:
				var component: int=_component_corners[corners.size()]
				if corner==0 and (int(placement.get("mask",255))&2)!=0:active_components[component]=true
				var point: Vector3=world[corner]
				var error: float=_point_error(local[corner],point,transform,extent)
				var index: int=int(welded[component].get(point,-1))
				if index<0:
					index=points.size();welded[component][point]=index
					points.append(point);errors.append(error);supports.append(support);sample_components.append(component)
				else:
					errors[index]=maxf(errors[index],error);supports[index]=maxf(supports[index],support)
				corners.append(index)
	_samples=points.size()
	if corners.size()!=_corner_capacity or _samples>_corner_capacity:return PackedByteArray()
	var map_start:=32+_bases.size()*4
	var component_start:=map_start+corners.size()*4
	var samples_start:=component_start+(corners.size()/3)*4
	var bytes:=PackedByteArray();bytes.resize(samples_start+points.size()*32)
	bytes.encode_u32(0,_bases.size());bytes.encode_u32(4,map_start)
	bytes.encode_u32(8,samples_start);bytes.encode_u32(12,_samples)
	bytes.encode_u32(16,_components);bytes.encode_u32(20,component_start)
	bytes.encode_u32(24,active_components.size())
	bytes.encode_u32(28,int(active_components.keys()[0]) if active_components.size()==1 else INVALID)
	for i in _bases.size():bytes.encode_u32(32+i*4,INVALID if _bases[i]<0 else _bases[i])
	for i in corners.size():bytes.encode_u32(map_start+i*4,corners[i])
	for i in corners.size()/3:bytes.encode_u32(component_start+i*4,_component_corners[i*3])
	for i in points.size():
		var at:=samples_start+i*32;var p: Vector3=points[i]
		bytes.encode_float(at,p.x);bytes.encode_float(at+4,p.y);bytes.encode_float(at+8,p.z);bytes.encode_float(at+12,errors[i])
		bytes.encode_float(at+16,supports[i])
		bytes.encode_u32(at+20,sample_components[i])
		bytes.encode_u32(at+24,int(active_components.has(sample_components[i])))
	return bytes

func _rebuild_inputs() -> bool:
	var bytes:=_pack_inputs()
	if bytes.is_empty():return false
	if _rd.buffer_update(_input,0,bytes.size(),bytes)!=OK:return false
	_geometry_dirty=false;_valid=false
	return true

func update(changes: Dictionary) -> void:
	for pose: Dictionary in changes.get("poses",[]):
		if _terrain.has(pose.geometry):
			if pose.data.size()!=_terrain[pose.geometry].size():
				push_error("Terrain topology changed without rebuilding the scene")
				_topology_failed=true
				continue
			_terrain[pose.geometry]=pose.data;_topology_dirty=true;_geometry_dirty=true
	for placement: Dictionary in changes.get("instances",[]):
		var old: Dictionary=_placements[placement.index]
		if _terrain.has(old.geometry) and (old.transform!=placement.transform or old.get("mask",255)!=placement.mask):
			old.transform=placement.transform;old.mask=placement.mask;_topology_dirty=true;_geometry_dirty=true

func uniforms() -> Array[RDUniform]:
	return [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,42,_input),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,43,_output)]

func _uniform(kind: int,binding: int,rid: RID) -> RDUniform:
	var result:=RDUniform.new();result.uniform_type=kind;result.binding=binding;result.add_id(rid);return result

func _program() -> bool:
	if _pipeline.is_valid():return _set.is_valid() and _rd.uniform_set_is_valid(_set)
	_programs=_host.programs
	if _programs==null:_programs=Programs.new();_own_programs=true
	var paths: Dictionary={}
	for stage: int in _host.STAGES:paths[stage]=PREFIX+_host.STAGES[stage]
	_shader=_programs.program(_rd,paths,RenderingServer.get_current_rendering_driver_name()=="d3d12")
	if not _shader.is_valid():return false
	var program:=RDPipelineShader.new();program.shader=_shader
	_pipeline=_programs.pipeline(program)
	if not _pipeline.is_valid():return false
	_sbt=_own(_rd.hit_sbt_create(_pipeline,1))
	if not _sbt.is_valid():return false
	var hit_range:=_rd.hit_sbt_range_alloc(_sbt,1)
	_rd.hit_sbt_range_update(_sbt,hit_range,0,[0])
	var bindings:=uniforms()
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE,0,_host._tlas))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,_host._vertices))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,_host._materials))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,10,_host._instance_geometry))
	bindings.append(_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,44,_control))
	_set=_own(_rd.uniform_set_create(bindings,_shader,0))
	return _set.is_valid()

func _frame_control(frame: PackedByteArray) -> PackedByteArray:
	var control:=frame.slice(272,284);control.append_array(frame.slice(332,336))
	control.append_array(frame.slice(284,288))
	control.append_array(PackedFloat32Array([0,0,0]).to_byte_array())
	return control

## The campaign clock turns the sun about 0.005 degrees per frame. Retracing
## every terrain vertex for that drift costs a full dispatch each frame and
## moves a 50 m terminator by millimetres. Keep the cached visibility until
## the direction has turned this far; reach and angular radius stay exact.
const SUN_DIRECTION_TOLERANCE := 0.00175   # radians, 0.1 degrees

static func _same_sun(control: PackedByteArray,cached: PackedByteArray) -> bool:
	if cached.size()!=control.size():return false
	if control.slice(12)!=cached.slice(12):return false
	var now:=Vector3(control.decode_float(0),control.decode_float(4),control.decode_float(8))
	var before:=Vector3(cached.decode_float(0),cached.decode_float(4),cached.decode_float(8))
	if now==before:return true
	if not now.is_finite() or not before.is_finite() or now.is_zero_approx() or before.is_zero_approx():return false
	return now.normalized().dot(before.normalized())>=cos(SUN_DIRECTION_TOLERANCE)

func render(frame: PackedByteArray) -> bool:
	if _topology_failed:return false
	if _topology_dirty and not _plan_topology():return false
	if _geometry_dirty and not _rebuild_inputs():return false
	if _samples==0:return true
	# Include angular radius: terrain integrates a deterministic seven-tap
	# disk; point-sun scenes retain one ray. Main BRDF/object samples stay intact.
	var control:=_frame_control(frame)
	if _valid and _same_sun(control,_signature):return true
	if not _program() or _rd.buffer_update(_control,0,control.size(),control)!=OK:return false
	var list:=_rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(list,_pipeline)
	_rd.raytracing_list_bind_uniform_set(list,_set,0)
	_rd.raytracing_list_trace_rays(list,0,_sbt,_samples,1,1)
	_rd.raytracing_list_end()
	# RD tracks the output write -> closest-hit read dependency between lists.
	_signature=control;_valid=true;refreshes+=1
	return true

func dispose(release: Callable=Callable()) -> void:
	cancel_prepare();_initial_poses=[];_gpu_build_phase=-1
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):
			if release.is_valid():release.call(_owned[i])
			else:_rd.free_rid(_owned[i])
	if _own_programs and _programs!=null:_programs.dispose(release)
	_owned.clear();_terrain.clear();_placements.clear();_host=null;_programs=null
	_input=RID();_output=RID();_control=RID();_shader=RID();_pipeline=RID();_sbt=RID();_set=RID()
