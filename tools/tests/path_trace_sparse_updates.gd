extends Node
## Actual GPU records and acceleration structures, including scattered stable
## IDs, stopped motion, deformation, visibility, and a failed partial upload.
const PathDevice = preload("res://src/game/fx/path_trace_device.gd")
const COUNT := 8192
class AuditDevice extends PathDevice:
	var uploads: Array = []
	var builds := 0
	var fail_at := -1
	var full_span := false
	func _update_lighting_offsets(changes: Dictionary) -> bool:
		if not full_span:return super._update_lighting_offsets(changes)
		# Preserve the old min/max bookkeeping too, so the benchmark includes
		# the cost of collecting changed offset IDs in the new implementation.
		var first := _lighting_offset_values.size();var last := -1
		for placement: Dictionary in changes.get("instances",[]):
			var index: int=placement.index
			var offset: Vector3=placement.get("lighting_offset",Vector3.ZERO)
			if offset==_lighting_offset_values[index]:continue
			_write_lighting_offset(index,offset)
			first=mini(first,index);last=maxi(last,index)
		return true if last<first else _upload_record_range(_lighting_offsets,_lighting_offset_data,first*16,(last+1)*16)
	func _upload_records(buffer: RID,data: PackedByteArray,indices: Array,stride: int) -> bool:
		# Same-build performance reference to the previous single-span upload.
		if full_span and not indices.is_empty():
			indices.sort()
			return _upload_record_range(buffer,data,indices.front()*stride,(indices.back()+1)*stride)
		return super._upload_records(buffer,data,indices,stride)
	func _upload_record_range(buffer: RID,data: PackedByteArray,begin: int,end: int) -> bool:
		uploads.append({"motion":buffer==_motion,"begin":begin,"end":end})
		if uploads.size()-1==fail_at:return false
		return super._upload_record_range(buffer,data,begin,end)
	func _build_tlas() -> bool:
		builds+=1
		return super._build_tlas()
	func reset_counts() -> void:
		uploads.clear();builds=0
	func bytes(motion: bool) -> int:
		var total := 0
		for upload: Dictionary in uploads:
			if upload.motion==motion:total+=upload.end-upload.begin
		return total
	func calls(motion: bool) -> int:
		var count := 0
		for upload: Dictionary in uploads:
			if upload.motion==motion:count+=1
		return count

signal done
var checks := 0
var failures := []
var rows := []
var out := "user://sparse-updates"
var d: AuditDevice
var mesh_bytes := PackedByteArray()

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func _ready() -> void:run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified sparse scene-update device")
	if PathDevice.supported():
		RenderingServer.call_on_render_thread(exercise);await done
	FileAccess.open(out.path_join("path-sparse-updates.json"),FileAccess.WRITE).store_string(JSON.stringify(
		{"checks":checks,"failures":failures,"rows":rows,"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	TexUpscale.shutdown()
	print("PT_SPARSE_UPDATES ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

func setup_device() -> bool:
	d=AuditDevice.new()
	var vertices := PackedFloat32Array()
	for p: Vector3 in [Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(0,0,1)]:
		vertices.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,0,1,0,0.5,1,1,1,1,0,0,0,0]))
	mesh_bytes=vertices.to_byte_array()
	var geometry := [{"offset":0,"count":3,"standard":true,"opaque":true},
		{"offset":0,"count":3,"standard":true,"opaque":true}]
	var placements := []
	for i in COUNT:
		placements.append({"geometry":0 if i in [0,COUNT-1] else 1,
			"transform":Transform3D(Basis.IDENTITY,Vector3(i*3,0,0)),"mask":7 if i in [0,COUNT-1] else 0})
	var white := Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	d.build(mesh_bytes,images,geometry,placements)
	return d._ready

func change(index: int,delta := Vector3.ZERO,mask := -1,offset := Vector3.ZERO) -> Dictionary:
	var pose: Transform3D=d._instances[index].transform;pose.origin+=delta
	return {"index":index,"transform":pose,"mask":d._instances[index].mask if mask<0 else mask,"lighting_offset":offset}

func update(label: String,changes: Dictionary) -> bool:
	d.reset_counts()
	var ok := d.update_scene(changes)
	rows.append({"label":label,"ok":ok,"motion_bytes":d.bytes(true),"offset_bytes":d.bytes(false),
		"motion_calls":d.calls(true),"offset_calls":d.calls(false),"tlas_builds":d.builds})
	return ok

func gpu_matches(label: String) -> void:
	check(d._rd.buffer_get_data(d._motion)==d._motion_data,label+": GPU motion records equal CPU bytes")
	check(d._rd.buffer_get_data(d._lighting_offsets)==d._lighting_offset_data,label+": GPU lighting offsets equal CPU bytes")

func exercise() -> void:
	check(setup_device(),"build two active triangles and 8192 stable placements")
	if not d._ready:d.dispose();done.emit.call_deferred();return
	var untouched := d._motion_data.slice(96,(COUNT-1)*96)
	var ends := [change(COUNT-1,Vector3(0,0.2,0),-1,Vector3(0,0.1,0)),change(0,Vector3(0,0.2,0),-1,Vector3(0,0.1,0))]
	check(update("separated",{"instances":ends}),"separated moving objects update successfully")
	check(d.bytes(true)==192 and d.calls(true)==2,"two distant motion records upload only 192 bytes")
	check(d.bytes(false)==32 and d.calls(false)==2,"two distant lighting offsets upload only 32 bytes")
	check(d.builds==1,"real movement rebuilds the TLAS once")
	check(d._motion_data.slice(96,(COUNT-1)*96)==untouched,"unchanged placements preserve their motion records")
	gpu_matches("separated")
	check(update("stop",{}),"stopped motion retires successfully")
	check(d.bytes(true)==192 and d.bytes(false)==0 and d.builds==0,"stopping clears just the two pending records without a TLAS rebuild")
	check(d._motion_data.decode_float(76)==0.0 and d._motion_data.decode_float((COUNT-1)*96+76)==0.0,"both stopped endpoints lose their stale motion flags")
	gpu_matches("stopped")
	check(update("idle",{}) and d.uploads.is_empty() and d.builds==0,"idle scene performs no record uploads or TLAS builds")
	ends=[change(0,Vector3.ZERO,-1,Vector3(0,0.3,0)),change(COUNT-1,Vector3.ZERO,-1,Vector3(0,0.3,0))]
	check(update("lighting_only",{"instances":ends}),"lighting-only update succeeds")
	check(d.builds==0 and d.bytes(false)==32,"lighting-only update avoids rebuilding unchanged geometry")
	gpu_matches("lighting only")
	check(update("duplicate",{"instances":ends}) and d.builds==0 and d.bytes(false)==0,"repeated unchanged records do not rebuild or reupload offsets")
	check(update("hidden_move",{"instances":[change(4096,Vector3(0,2,0))]}) and d.builds==0,"moving a fully hidden placement only updates its cached transform")
	check(update("reveal",{"instances":[change(4096,Vector3.ZERO,7)]}) and d.builds==1,"revealing hidden geometry builds its BLAS and TLAS")
	check(d._active_instances.has(4096) and d._active_instances[4096].transform.origin.y==2.0,"reveal uses the most recent hidden transform")
	check(update("hide",{"instances":[change(4096,Vector3.ZERO,0)]}) and d.builds==1 and not d._active_instances.has(4096),"hiding visible geometry rebuilds and removes its active instance")
	update("settle",{})
	var dense := []
	for i in range(128,256):dense.append(change(i,Vector3(0,0.1,0),-1,Vector3(0,0.15,0)))
	check(update("dense",{"instances":dense}) and d.calls(true)==1 and d.bytes(true)==128*96,"adjacent moving parts retain one compact upload")
	check(d.calls(false)==1 and d.bytes(false)==128*16,"bulk lighting offsets retain their compact upload fast path")
	gpu_matches("dense")
	update("dense_stop",{})
	var scattered := []
	for i in 16:scattered.append(change(i*500,Vector3(0,0.1,0)))
	check(update("fragmented",{"instances":scattered}) and d.calls(true)<=8,"fragmented motion has at most eight upload calls")
	check(d.bytes(true)<COUNT*96*0.65,"bounded batching still skips substantial unchanged data")
	gpu_matches("fragmented")
	update("fragmented_stop",{})
	check(update("deformation",{"poses":[{"geometry":0,"data":mesh_bytes}]}) and d.builds==1,"posed active geometry still rebuilds acceleration structures")
	check(d.bytes(true)==192 and d._motion_data.decode_float(60)==0.0 and d._motion_data.decode_float((COUNT-1)*96+60)==0.0,"deformation sparsely rejects both affected placement histories")
	gpu_matches("deformation")
	d._history_reject=PackedInt32Array([0,COUNT-1])
	check(update("handoff",{"instances":[change(0,Vector3(0,0.1,0))]}) and d.bytes(true)==192,"handoff rejection and simultaneous motion share sparse updates")
	check(d._motion_data.decode_float(60)==0.0 and d._motion_data.decode_float((COUNT-1)*96+60)==0.0,"handoff rejection takes priority over rigid motion")
	update("handoff_stop",{})
	check(d._motion_data.decode_float(60)==1.0 and d._motion_data.decode_float((COUNT-1)*96+60)==1.0,"rejected motion becomes valid identity on the next stationary frame")
	gpu_matches("handoff retired")
	d.fail_at=1
	check(not update("failed_second_range",{"instances":[change(0,Vector3(0,0.1,0)),change(COUNT-1,Vector3(0,0.1,0))]}),"failure of a later sparse upload propagates")
	check(not d._published_valid and not d._history_valid and d.builds==0,"partial upload cannot publish a frame or advance acceleration structures")
	d.dispose();check(d._owned.is_empty(),"sparse-update device retires all resources")
	done.emit.call_deferred()
