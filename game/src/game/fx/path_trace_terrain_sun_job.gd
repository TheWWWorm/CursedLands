extends RefCounted
## A private CPU task. No scene node, RenderingDevice, callback or device owner
## crosses into the worker; the caller joins before taking its result.
const CpuBuild=preload("path_trace_terrain_sun_build.gd")
var _builder: RefCounted
var _thread: Thread
var _mutex:=Mutex.new()
var _cancelled:=false
var _result:=ERR_INVALID_DATA # A worker abort must fail instead of remaining busy forever.
var _joined:=false
var _worker_thread_id:=0
var _launch_thread_id:=0
var _snapshot_us:=0
var _worker_us:=0
var _cancel_wait_us:=0

func _snapshot_geometry(entries: Array) -> Array:
	var copy: Array=[]
	for entry: Dictionary in entries:
		copy.append({"offset":int(entry.offset),"count":int(entry.count),"terrain":bool(entry.get("terrain",false))})
	return copy

func _snapshot_placements(entries: Array) -> Array:
	var copy: Array=[]
	for entry: Dictionary in entries:
		var transform: Transform3D=entry.transform
		copy.append({"geometry":int(entry.geometry),"transform":transform,"mask":int(entry.get("mask",255))})
	return copy

func _snapshot_poses(entries: Array) -> Array:
	var copy: Array=[]
	for entry: Dictionary in entries:
		var data: PackedByteArray=entry.data
		copy.append({"geometry":int(entry.geometry),"data":data})
	return copy

func start(data: PackedByteArray,geometry: Array,placements: Array,poses: Array=[]) -> Error:
	var started:=Time.get_ticks_usec()
	# Keep only scalar/value fields needed by topology; arbitrary descriptor
	# metadata cannot retain Nodes, resources, devices or their owners.
	_builder=CpuBuild.new();_builder.begin(data,_snapshot_geometry(geometry),_snapshot_placements(placements),_snapshot_poses(poses))
	_snapshot_us=Time.get_ticks_usec()-started;_launch_thread_id=OS.get_thread_caller_id()
	_thread=Thread.new()
	# Pool jobs can be stolen by Godot's waiting render worker. A dedicated
	# low-priority thread keeps this optional CPU work off that critical path.
	var status: Error=_thread.start(_run,Thread.PRIORITY_LOW)
	if status!=OK:_thread=null;_result=status
	return status

func _is_cancelled() -> bool:
	_mutex.lock();var cancelled:=_cancelled;_mutex.unlock();return cancelled

func _run() -> void:
	var started:=Time.get_ticks_usec()
	_mutex.lock();_worker_thread_id=OS.get_thread_caller_id();_mutex.unlock()
	var status:=ERR_BUSY
	while status==ERR_BUSY and not _is_cancelled():status=_builder.step(1000,2048)
	if _is_cancelled():status=ERR_SKIP
	_mutex.lock();_worker_us=Time.get_ticks_usec()-started;_result=status;_mutex.unlock()

func is_running() -> bool:return _thread!=null and _thread.is_alive()

func poll() -> Error:
	if _thread!=null:
		if _thread.is_alive():return ERR_BUSY
		_thread.wait_to_finish();_thread=null;_joined=true
	return _result

func cancel() -> void:
	_mutex.lock();_cancelled=true;_mutex.unlock()
	if _thread!=null:
		var started:=Time.get_ticks_usec()
		_thread.wait_to_finish();_thread=null;_joined=true
		_cancel_wait_us=Time.get_ticks_usec()-started
	if _builder!=null:_builder.cancel();_builder=null

func take_builder() -> RefCounted:
	assert(_thread==null)
	var result:=_builder;_builder=null;return result

func snapshot() -> Dictionary:
	_mutex.lock()
	var state:={"worker_thread_id":_worker_thread_id,"launch_thread_id":_launch_thread_id,
		"snapshot_us":_snapshot_us,"worker_us":_worker_us,"cancel_requested":_cancelled,
		"status":_result,"joined":_joined,"cancel_wait_us":_cancel_wait_us}
	_mutex.unlock()
	state.running=_thread!=null and _thread.is_alive()
	return state
