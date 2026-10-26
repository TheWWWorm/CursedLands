extends Node
## A private RR candidate already consumed its latest geometry deltas. Replaying
## every static placement at promotion also dirties the following motion frame.
## Exercise the real scene tracker and motion packing without allocating a GPU.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const Path = preload("res://src/game/fx/path_trace_device.gd")
const RR = preload("res://src/game/fx/path_trace_rr.gd")
const STATIC_COUNT := 128
const MOVING := STATIC_COUNT
const STOPPED := STATIC_COUNT+1
const HIDDEN := STATIC_COUNT+2
const REVEALED := STATIC_COUNT+3
const COUNT := STATIC_COUNT+4

class QuietController extends Controller:
	func _bind_outputs() -> void:_bound=true
	func _bind_handoff_outputs(_previous: Path) -> void:_bound=true

class CpuPath extends Path:
	var uploaded_bytes:=0
	var adopted:=false
	func output_ready() -> bool:return not _closed and _ready
	func _upload_record_range(_buffer: RID,_data: PackedByteArray,begin: int,end: int) -> bool:
		uploaded_bytes+=end-begin;return true
	func seed(scene: RefCounted) -> void:
		_ready=true;ray_reconstruction=true;_size=Vector2i(160,90)
		_motion_data.resize(scene.instances.size()*MOTION_STRIDE)
		for entry: Dictionary in scene.instances:
			var instance:=RDAccelerationStructureInstance.new()
			instance.transform=entry.transform;instance.mask=entry.mask
			_instances.append(instance)
			_write_motion(_instances.size()-1,Transform3D.IDENTITY,Basis.IDENTITY,true,false)
	func apply(changes: Dictionary) -> bool:
		uploaded_bytes=0
		if not _update_motion(changes):return false
		for entry: Dictionary in changes.instances:
			_instances[entry.index].transform=entry.transform
			_instances[entry.index].mask=entry.mask
		completed_renders+=1;return true
	func adopt_history(previous: RefCounted,matches: PackedInt32Array) -> void:
		# Reproduce only NRD's CPU transform transfer. The native pool swap and
		# rebind have separate rendered handoff/lifecycle regression coverage.
		adopted=true
		for i in matches.size():
			if matches[i]>=0:
				_instances[i].transform=previous._instances[matches[i]].transform
				_instances[i].mask=previous._instances[matches[i]].mask
	func motion(index: int) -> Vector3:
		var offset:=index*MOTION_STRIDE
		return Vector3(_motion_data.decode_float(offset+12),_motion_data.decode_float(offset+60),_motion_data.decode_float(offset+76))

var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func collect(nodes: Array[MeshInstance3D],native: bool) -> RefCounted:
	var scene:=Scene.new();scene.lighting_camera_mask=1
	if not native:scene._kernel=null
	scene.geometries.append({})
	for node in nodes:scene._add_instance(node,0,node.global_transform,0)
	scene.updates(true)
	return scene

func ids(changes: Dictionary) -> Array[int]:
	var found: Array[int]=[]
	for entry: Dictionary in changes.instances:found.append(entry.index)
	found.sort();return found

func exercise(native: bool,rr: bool) -> void:
	var label:="%s %s: "%["native tracker" if native else "script tracker","RR" if rr else "NRD"]
	var root:=Node3D.new();add_child(root)
	var nodes: Array[MeshInstance3D]=[];var mesh:=BoxMesh.new()
	for i in COUNT:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.position=Vector3(i,0,0)
		root.add_child(node);nodes.append(node)
	nodes[REVEALED].hide()
	var previous_scene:=collect(nodes,native);var candidate_scene:=collect(nodes,native)
	check(not native or candidate_scene._kernel!=null,label+"requested production tracker is available")
	var previous:=CpuPath.new();previous.seed(previous_scene)
	var candidate:=CpuPath.new();candidate.seed(candidate_scene)
	nodes[MOVING].position.x+=0.5;nodes[STOPPED].position.x+=0.5
	var private_changes: Dictionary=candidate_scene.updates()
	check(ids(private_changes)==[MOVING,STOPPED] and candidate.apply(private_changes),label+"private candidate consumes both moving placements")
	check(candidate.motion(MOVING).is_equal_approx(Vector3(-0.5,1,1))
		and candidate.motion(STOPPED).is_equal_approx(Vector3(-0.5,1,1)),label+"private frame records valid rigid motion")
	# One placement keeps moving, one stops, and visibility changes after the
	# candidate's complete private frame but before its first visible frame.
	nodes[MOVING].position.x+=0.5;nodes[HIDDEN].hide();nodes[REVEALED].show()
	var owner:=Game.new();var controller:=QuietController.new(owner)
	controller.device=previous;controller._scene=previous_scene
	controller._pending_device=candidate;controller._pending_scene=candidate_scene
	controller._rr_active=rr
	var effect:=RR.new()
	if rr:
		controller._rr_effect=effect;effect._last_target=previous.get_instance_id();effect._size=candidate._size
	controller._activate_candidate()
	await get_tree().process_frame
	var changes: Dictionary=controller._scene.updates(controller._handoff_updates)
	controller._handoff_updates=false
	if rr:
		check(effect._last_target==candidate.get_instance_id(),label+"native camera history accepts the complete replacement")
		check(ids(changes)==[MOVING,HIDDEN,REVEALED],label+"promotion sends only actual transform and visibility deltas")
	else:
		check(candidate.adopted and changes.instances.size()==COUNT,label+"NRD retains forced updates after restoring previous transforms")
	check(candidate.apply(changes),label+"promotion motion records pack successfully")
	var expected_moving:=-0.5 if rr else -1.0
	var expected_stopped:=Vector3(0,1,0) if rr else Vector3(-0.5,1,1)
	check(candidate.motion(MOVING).is_equal_approx(Vector3(expected_moving,1,1))
		and candidate.motion(STOPPED).is_equal_approx(expected_stopped),label+"moving and stopped history matches the correct previous scene")
	check(candidate._instances[HIDDEN].mask==0 and (candidate._instances[REVEALED].mask&1)!=0
		and candidate.motion(HIDDEN).y==0 and candidate.motion(REVEALED).y==0,label+"hide and reveal deltas reject incompatible history")
	var transforms_current:=true
	for i in COUNT:transforms_current=transforms_current and candidate._instances[i].transform==nodes[i].global_transform
	check(transforms_current and candidate.motion(0)==Vector3(0,1,0),label+"all current transforms and static identity motion survive promotion")
	if rr:check(candidate.uploaded_bytes<=4*Path.MOTION_STRIDE,label+"promotion uploads at most four motion records regardless of static population")
	var stopped: Dictionary=controller._scene.updates()
	check(stopped.instances.is_empty() and candidate.apply(stopped),label+"a stopped following frame needs no placement replay")
	check(candidate.motion(MOVING)==Vector3(0,1,0) and candidate.motion(STOPPED)==Vector3(0,1,0),label+"following frame clears prior movement")
	if rr:check(candidate.uploaded_bytes<=4*Path.MOTION_STRIDE,label+"following motion cleanup stays bounded to the real dirty subset")
	check(candidate.apply(controller._scene.updates()) and candidate.uploaded_bytes==0,label+"fully stationary scene submits no motion transfer")
	controller._flush_retirement();candidate.dispose();effect.dispose();controller.free();owner.free();root.free()

func _ready() -> void:run.call_deferred()
func run() -> void:
	var options:=GameData.options.duplicate(true);GameData.options["pt_accumulation"]=0
	for native in [false,true]:
		await exercise(native,true)
		await exercise(native,false)
	GameData.options=options
	print("PT_HANDOFF_DELTAS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
