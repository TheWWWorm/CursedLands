extends Node
## Promotion must retain its old CPU snapshot for bounded teardown, while
## preserving the replacement and shared source/ground caches.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const Device = preload("res://src/game/fx/scene_raytrace_device.gd")
class QuietController extends Controller:
	func _bind_outputs() -> void: _bound=true
class QuietDevice extends Device:
	func output_ready() -> bool:return not _closed

var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func seed_scene(controller: QuietController) -> Dictionary:
	var scene:=Scene.new();scene._sources=controller._source_cache;scene._ground=controller._ground_cache
	var payloads: Array[WeakRef]=[]
	for i in 1500:
		var payload:=RefCounted.new();payloads.append(weakref(payload))
		scene.geometries.append({"payload":payload});scene.instances.append({"payload":payload});scene._nodes[i]=payload
	scene.vertices.resize(48*10000)
	controller._scene=scene;controller.device=QuietDevice.new()
	return {"scene":weakref(scene),"payloads":payloads,"device":controller.device}

func alive(payloads: Array) -> int:
	var count:=0
	for reference: WeakRef in payloads:
		if reference.get_ref()!=null:count+=1
	return count

func promote(controller: QuietController) -> void:
	controller._pending_scene=Scene.new();controller._pending_device=QuietDevice.new()
	controller._activate_candidate()

func _ready() -> void:run.call_deferred()

func run() -> void:
	var owner:=Game.new();var controller:=QuietController.new(owner)
	# Model a render thread that has not consumed begin_retirement yet. A
	# process-frame grace period alone does not acknowledge that callback.
	var waiting: Variant=controller.get("_retired_devices")
	var delayed_kept:=false
	if waiting is Array:
		var delayed:=QuietDevice.new()
		waiting.append({"device":delayed,"after":0,"started_frame":Engine.get_process_frames(),"started_usec":Time.get_ticks_usec()})
		controller.call("_service_retirement")
		delayed_kept=waiting.size()==1
		controller.call("_flush_retirement")
	check(delayed_kept,"retirement queue retains an owner until its render-thread begin callback has run")
	var cached:=Resource.new();controller._source_cache._store(cached,0,PackedByteArray([2,3,4]),3)
	controller._ground_cache.profiles[Vector2i.ZERO]=Vector2(2,3)
	var old:=seed_scene(controller);promote(controller)
	var replacement:=controller.device;var scene:=controller._scene
	check(old.scene.get_ref()!=null and alive(old.payloads)==1500,"promotion defers destruction of the previous CPU snapshot")
	await get_tree().process_frame
	check(old.device._closed and not old.device.output_ready(),"retired device stops accepting rendering immediately")
	if controller.has_method("_service_retirement"):controller.call("_service_retirement")
	check(old.scene.get_ref()!=null and alive(old.payloads)>0,"one retirement step cannot destroy all old scene records")
	check(controller.device==replacement and controller._scene==scene and replacement.output_ready(),"bounded teardown preserves the complete replacement")
	var steps:=0
	for i in 100:
		if old.scene.get_ref()==null:break
		if controller.has_method("_service_retirement"):controller.call("_service_retirement")
		steps+=1;await get_tree().process_frame
	check(old.scene.get_ref()==null and alive(old.payloads)==0 and steps>1,"all old CPU records release after several bounded steps")
	check(controller._source_cache._find(cached,0)==PackedByteArray([2,3,4])
		and controller._ground_cache.profiles.get(Vector2i.ZERO)==Vector2(2,3),"retirement leaves shared immutable source and ground caches intact")
	old=seed_scene(controller);promote(controller)
	if controller.has_method("_flush_retirement"):controller.call("_flush_retirement")
	await get_tree().process_frame
	check(old.scene.get_ref()==null and alive(old.payloads)==0 and old.device._closed,"shutdown drains a partially retired snapshot immediately")
	if controller.has_method("_flush_retirement"):controller.call("_flush_retirement")
	check(controller.device.output_ready(),"repeated retirement flush does not dispose the active replacement")
	controller.device.dispose();controller._source_cache.clear();controller.free();owner.free()
	print("RT_RETIREMENT_BUDGET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
