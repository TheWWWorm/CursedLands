extends Node
## Crowded-scene motion packing: one final record per changed placement,
## with the actual GPU buffer checked after movement stops and is rejected.
class MotionDevice extends "res://src/game/fx/path_trace_device.gd":
	var writes := 0
	func _write_motion(index: int,position: Transform3D,normal: Basis,valid: bool,moving: bool) -> void:
		writes+=1
		super._write_motion(index,position,normal,valid,moving)

signal done
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready() -> void:run.call_deferred()
func run() -> void:
	RenderingServer.call_on_render_thread(exercise)
	await done
	print("PT_MOTION_COST ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
func exercise() -> void:
	var d := MotionDevice.new()
	d._rd=RenderingServer.get_rendering_device()
	d._motion_data.resize(1000*d.MOTION_STRIDE)
	d._geometry_placements.append([])
	var moving := []
	for i in 1000:
		var instance := RDAccelerationStructureInstance.new()
		instance.transform=Transform3D.IDENTITY;instance.mask=7;d._instances.append(instance)
		d._geometry_placements[0].append(i)
		d._write_motion(i,Transform3D.IDENTITY,Basis.IDENTITY,true,false)
		moving.append({"index":i,"transform":Transform3D(Basis.IDENTITY,Vector3(0.1,0,0)),"mask":7})
	d._motion=d._rd.storage_buffer_create(d._motion_data.size(),d._motion_data)
	d.writes=0
	check(d._update_motion({"instances":moving}) and d.writes==1000,"starting 1000 moving parts packs each record once")
	d.writes=0
	check(d._update_motion({"instances":moving}) and d.writes==1000,"continuing 1000 moving parts does not clear then overwrite their records")
	check(is_equal_approx(d._motion_data.decode_float(12),-0.1) and d._motion_data.decode_float(60)==1.0 and d._motion_data.decode_float(76)==1.0,"moving record maps the current surface back to its previous position")
	d.writes=0
	check(d._update_motion({}) and d.writes==1000,"stopping retires every previous motion exactly once")
	check(d._motion_data.decode_float(12)==0.0 and d._motion_data.decode_float(60)==1.0 and d._motion_data.decode_float(76)==0.0,"stopped record is valid identity with no stale motion")
	d.writes=0
	check(d._update_motion({}) and d.writes==0,"stationary scene does not repack motion")
	d.writes=0
	check(d._update_motion({"poses":[{"geometry":0}],"instances":moving}) and d.writes==1000,"deforming moving parts also produce only their final records")
	check(d._motion_data.decode_float(60)==0.0,"deformation rejects rigid history")
	d.writes=0;d._history_reject=PackedInt32Array([0,999])
	check(d._update_motion({"instances":moving}) and d.writes==1000,"handoff rejection supersedes movement without duplicate packing")
	check(d._motion_data.decode_float(60)==0.0 and d._motion_data.decode_float(999*d.MOTION_STRIDE+60)==0.0,"both ends of the placement range reject incompatible history")
	check(d._rd.buffer_get_data(d._motion)==d._motion_data,"uploaded GPU records match CPU records byte for byte")
	d._update_motion({})
	check(d._motion_data.decode_float(60)==1.0 and d._motion_data.decode_float(999*d.MOTION_STRIDE+60)==1.0,"rejected history becomes valid identity on the following stationary frame")
	d._rd.free_rid(d._motion);d._motion=RID();d._instances.clear()
	done.emit.call_deferred()
