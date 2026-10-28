extends RefCounted
## Private CPU-only terrain-cache builder. Each step consumes bounded records;
## no RenderingDevice resources, callbacks, threads or scene nodes are retained.
const PHASES := ["poses","geometry","placements","topology and samples","components","sample finalization",
	"header","instance table","corner table","component table","sample table","finish"]
var terrain := {}
var placements: Array=[]
var component_corners := PackedInt32Array()
var bases := PackedInt32Array()
var components := 0
var corner_capacity := 0
var samples := 0
var data := PackedByteArray()
var _source := PackedByteArray()
var _geometry: Array=[]
var _source_placements: Array=[]
var _source_poses: Array=[]
var _poses := {}
var _parents := PackedInt32Array()
var _ranks := PackedInt32Array()
var _topology_welded := {}
var _dense := {}
var _points: Array[Vector3]=[]
var _errors := PackedFloat32Array()
var _supports := PackedFloat32Array()
var _sample_components := PackedInt32Array()
var _sample_active := PackedByteArray()
var _active_components := {}
var _corners := PackedInt32Array()
var _phase := -1
var _cursor := 0
var _triangle_at := 0
var _map_start := 0
var _component_start := 0
var _samples_start := 0
var _failed := false
var _steps := 0
var _last_work := 0
var _total_work := 0
var _last_us := 0
var _max_us := 0
var _total_us := 0
var _phase_us := PackedInt64Array()

func begin(source: PackedByteArray,geometry: Array,source_placements: Array,poses: Array=[]) -> void:
	cancel()
	# All arguments are private immutable build snapshots. Retain references;
	# copying/decoding records happens inside step(), never in begin().
	_source=source;_geometry=geometry;_source_placements=source_placements;_source_poses=poses
	if _source_placements.is_empty():_source_placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":255}]
	_phase=0;_phase_us.resize(PHASES.size());_phase_us.fill(0)

func cancel() -> void:
	terrain={};placements=[];component_corners=PackedInt32Array();bases=PackedInt32Array()
	components=0;corner_capacity=0;samples=0;data=PackedByteArray()
	_source=PackedByteArray();_geometry=[];_source_placements=[];_source_poses=[];_poses={}
	_parents=PackedInt32Array();_ranks=PackedInt32Array();_topology_welded={};_dense={}
	_points=[];_errors=PackedFloat32Array();_supports=PackedFloat32Array();_sample_components=PackedInt32Array()
	_sample_active=PackedByteArray();_active_components={};_corners=PackedInt32Array();_phase=-1;_cursor=0;_triangle_at=0;_failed=false
	_steps=0;_last_work=0;_total_work=0;_last_us=0;_max_us=0;_total_us=0;_phase_us=PackedInt64Array()

func pending() -> bool:return _phase>=0 and _phase<PHASES.size() and not _failed

func stats() -> Dictionary:
	var phases := {}
	for i in _phase_us.size():phases[PHASES[i]]=_phase_us[i]/1000.0
	return {"last_work":_last_work,"total_work":_total_work,"steps":_steps,"last_us":_last_us,
		"max_us":_max_us,"total_us":_total_us,"phase":PHASES[_phase] if pending() else "failed" if _failed else "complete" if _phase>=PHASES.size() else "idle","phase_ms":phases}

func step(budget_us:=1500,work_limit:=4096) -> Error:
	if _failed:return ERR_INVALID_DATA
	if not pending():return OK if _phase>=PHASES.size() else ERR_UNCONFIGURED
	var started:=Time.get_ticks_usec();var phase_started:=started;var measured_phase:=_phase
	var work:=0;var limit:=maxi(work_limit,1);var deadline:=started+maxi(budget_us,1)
	while pending() and work<limit and (work==0 or Time.get_ticks_usec()<deadline):
		match _phase:
			3:work+=_topology_step(limit-work,deadline)
			4:work+=_component_step(limit-work,deadline)
			8:work+=_corner_step(limit-work)
			9:work+=_component_table_step(limit-work,deadline)
			10:work+=_sample_table_step(limit-work,deadline)
			_:_one();work+=1
		if _phase!=measured_phase:
			var now:=Time.get_ticks_usec();_phase_us[measured_phase]+=now-phase_started
			measured_phase=_phase;phase_started=now
	var ended:=Time.get_ticks_usec()
	if measured_phase<PHASES.size():_phase_us[measured_phase]+=ended-phase_started
	_last_work=work;_total_work+=work;_steps+=1;_last_us=ended-started;_total_us+=_last_us;_max_us=maxi(_max_us,_last_us)
	return ERR_INVALID_DATA if _failed else ERR_BUSY if pending() else OK

func _next() -> void:
	_phase+=1;_cursor=0;_triangle_at=0

func _position(bytes: PackedByteArray,at: int) -> Vector3:
	return Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8))

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

func _support(t: Transform3D) -> float:
	var x:=t.basis.x;var y:=t.basis.y;var z:=t.basis.z
	var xy:=absf(x.dot(y));var xz:=absf(x.dot(z));var yz:=absf(y.dot(z))
	# Same contour support as the synchronous terrain-cache preparation.
	return 3.2*sqrt(maxf(x.length_squared()+xy+xz,maxf(y.length_squared()+xy+yz,z.length_squared()+xz+yz)))

func _max_abs(p: Vector3) -> float:return maxf(absf(p.x),maxf(absf(p.y),absf(p.z)))

func _one() -> void:
	match _phase:
		0:
			if _cursor>=_source_poses.size():_next();return
			var pose: Dictionary=_source_poses[_cursor];_cursor+=1
			if pose.geometry>=0 and pose.geometry<_geometry.size() and bool(_geometry[pose.geometry].get("terrain",false)):_poses[pose.geometry]=pose.data
		1:
			if _cursor>=_geometry.size():_next();return
			var i:=_cursor;var description: Dictionary=_geometry[i];_cursor+=1
			if not bool(description.get("terrain",false)):return
			var size:=int(description.count)*64
			if size%192!=0:_failed=true;return
			if _poses.has(i):
				if _poses[i].size()!=size:_failed=true;return
				terrain[i]=_poses[i]
			else:terrain[i]=_source.slice(int(description.offset)*64,int(description.offset)*64+size)
		2:
			if _cursor>=_source_placements.size():_next();return
			var placement: Dictionary=_source_placements[_cursor].duplicate();_cursor+=1
			placements.append(placement);bases.append(-1)
			if terrain.has(placement.geometry):corner_capacity+=terrain[placement.geometry].size()/64
		5:
			samples=_points.size();_next()
		6:
			if _corners.size()!=corner_capacity or samples>corner_capacity:_failed=true;return
			_map_start=32+bases.size()*4;_component_start=_map_start+_corners.size()*4
			_samples_start=_component_start+(_corners.size()/3)*4
			data.resize(_map_start)
			data.encode_u32(0,bases.size());data.encode_u32(4,_map_start);data.encode_u32(8,_samples_start);data.encode_u32(12,samples)
			data.encode_u32(16,components);data.encode_u32(20,_component_start)
			data.encode_u32(24,_active_components.size())
			data.encode_u32(28,int(_active_components.keys()[0]) if _active_components.size()==1 else 0xffffffff);_next()
		7:
			if _cursor>=bases.size():_next();return
			data.encode_u32(32+_cursor*4,0xffffffff if bases[_cursor]<0 else bases[_cursor]);_cursor+=1
		11:
			# Release one native container per work item. No worker/callback can
			# outlive cancellation, and retained fields form the complete result.
			match _cursor:
				0:_source=PackedByteArray()
				1:_geometry=[];_source_placements=[];_source_poses=[];_poses={}
				2:_parents=PackedInt32Array();_ranks=PackedInt32Array()
				3:_topology_welded={}
				4:_dense={}
				5:_sample_active=PackedByteArray();_active_components={}
				6:_points=[];_errors=PackedFloat32Array();_supports=PackedFloat32Array();_sample_components=PackedInt32Array();_corners=PackedInt32Array()
				_:_next();return
			_cursor+=1

# The topology weld already gives each exact shared position a canonical node.
# Accumulate its cache record in this same pass; a second world transform and
# dictionary weld would repeat all triangle work during camera-travel builds.
func _topology_step(limit: int,deadline: int) -> int:
	if _cursor>=placements.size():_next();return 1
	var placement: Dictionary=placements[_cursor]
	if not terrain.has(placement.geometry):_cursor+=1;_triangle_at=0;return 1
	var bytes: PackedByteArray=terrain[placement.geometry]
	if _triangle_at==0:bases[_cursor]=component_corners.size()
	if _triangle_at>=bytes.size():_cursor+=1;_triangle_at=0;return 1
	var transform: Transform3D=placement.transform;var support:=_support(transform)
	var group: int=0 if (int(placement.get("mask",255))&2)!=0 else _cursor+1
	if not _topology_welded.has(group):_topology_welded[group]={}
	var welded: Dictionary=_topology_welded[group]
	var ax:=transform.basis.x.abs();var ay:=transform.basis.y.abs();var az:=transform.basis.z.abs();var origin:=transform.origin.abs()
	var work:=0
	while _triangle_at<bytes.size() and work<limit:
		if work>0 and work%8==0 and Time.get_ticks_usec()>=deadline:break
		var local: Array[Vector3]=[_position(bytes,_triangle_at),_position(bytes,_triangle_at+64),_position(bytes,_triangle_at+128)]
		var world: Array[Vector3]=[transform*local[0],transform*local[1],transform*local[2]]
		var extent: float=maxf((world[1]-world[0]).length(),(world[2]-world[0]).length())*2.0
		var triangle:=PackedInt32Array()
		for corner in 3:
			var point: Vector3=world[corner];var position: Vector3=local[corner]
			var product: Vector3=ax*absf(position.x)+ay*absf(position.y)+az*absf(position.z)+origin
			var error:=maxf(0.00001,5.9604644775390625e-8*(8.0*_max_abs(product)+4.0*_max_abs(point))+1.7881398e-7*extent)
			var index: int=int(welded.get(point,-1))
			if index<0:
				index=_parents.size();welded[point]=index;_parents.append(index);_ranks.append(0)
				_points.append(point);_errors.append(error);_supports.append(support);_sample_components.append(-1);_sample_active.append(int(group==0))
			else:_errors[index]=maxf(_errors[index],error);_supports[index]=maxf(_supports[index],support)
			triangle.append(index);component_corners.append(index);_corners.append(index)
		_join(triangle[0],triangle[1]);_join(triangle[0],triangle[2]);_triangle_at+=192;work+=1
	return work

func _component_step(limit: int,deadline: int) -> int:
	if _cursor>=component_corners.size():components=_dense.size();_next();return 1
	var end:=mini(component_corners.size(),_cursor+limit);var work:=0
	while _cursor<end:
		if work>0 and work%32==0 and Time.get_ticks_usec()>=deadline:break
		var node:=_corners[_cursor];var component:=_sample_components[node]
		if component<0:
			var root:=_root(node)
			if not _dense.has(root):_dense[root]=_dense.size()
			component=_dense[root];_sample_components[node]=component
			if _sample_active[node]!=0:_active_components[component]=true
		component_corners[_cursor]=component;_cursor+=1;work+=1
	return work

func _corner_step(limit: int) -> int:
	if _cursor>=_corners.size():_next();return 1
	# At most16KiB per native copy with the production4096-record cap.
	var end:=mini(_corners.size(),_cursor+limit)
	data.append_array(_corners.slice(_cursor,end).to_byte_array())
	var work:=end-_cursor;_cursor=end;return work

func _component_table_step(limit: int,deadline: int) -> int:
	if _cursor>=_corners.size()/3:_next();return 1
	var count:=mini(_corners.size()/3-_cursor,limit);var rows:=PackedInt32Array();rows.resize(count)
	var work:=0
	while work<count:
		if work>0 and work%32==0 and Time.get_ticks_usec()>=deadline:break
		rows[work]=component_corners[_cursor*3];_cursor+=1;work+=1
	rows.resize(work);data.append_array(rows.to_byte_array());return work

func _sample_table_step(limit: int,deadline: int) -> int:
	if _cursor>=samples:_next();return 1
	if _cursor==0:data.resize(_samples_start+samples*32)
	var end:=mini(samples,_cursor+limit);var work:=0
	while _cursor<end:
		if work>0 and work%16==0 and Time.get_ticks_usec()>=deadline:break
		var at:=_samples_start+_cursor*32;var p: Vector3=_points[_cursor]
		data.encode_float(at,p.x);data.encode_float(at+4,p.y);data.encode_float(at+8,p.z);data.encode_float(at+12,_errors[_cursor])
		data.encode_float(at+16,_supports[_cursor]);data.encode_u32(at+20,_sample_components[_cursor])
		data.encode_u32(at+24,int(_sample_active[_cursor]));_cursor+=1;work+=1
	return work
