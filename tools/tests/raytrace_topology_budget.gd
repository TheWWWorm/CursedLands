extends Node
const Scene=preload("res://src/game/fx/water_raytrace_scene.gd")
class CountScene extends Scene:
	var inspected := 0
	func _mesh_version(mesh: MeshInstance3D,materials: Dictionary) -> Array:
		inspected+=1
		return super._mesh_version(mesh,materials)
class QuietWorld extends GameWorld:
	func _ready() -> void:pass
	func _process(_dt: float) -> void:pass
	func _physics_process(_dt: float) -> void:pass
class QuietTerrain extends EITerrain:
	func _process(_dt: float) -> void:pass

var checks := 0
var failures := 0
var budget_supported := false
var world: QuietWorld
var terrain: QuietTerrain
var roots: Array[Node3D] = []
var material := StandardMaterial3D.new()
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready() -> void:run.call_deferred()
func poll(scene: CountScene) -> bool:
	return scene.call("topology_changed",1) if budget_supported else scene.topology_changed()
func changed(scene: CountScene) -> bool:
	for i in 500:
		if poll(scene):return true
		if not budget_supported or not scene.get("topology_pending"):return false
	check(false,"bounded topology scan eventually finishes");return false
func snapshot() -> CountScene:
	var scene := CountScene.new();scene.begin(terrain,Vector3.ZERO,-1000)
	scene.inspected=0;return scene
func add_root(id: int) -> MeshInstance3D:
	var root := Node3D.new();world.add_child(root);world.objects[id]=root;roots.append(root)
	var mesh := MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.material_override=material;root.add_child(mesh)
	return mesh
func run() -> void:
	world=QuietWorld.new();add_child(world)
	terrain=QuietTerrain.new();world.add_child(terrain)
	for i in 120:add_root(i)
	var scene := snapshot()
	for method in scene.get_method_list():
		if method.name=="topology_changed":budget_supported=method.args.size()>0
	check(not poll(scene) and scene.inspected>0 and scene.inspected<120,"one tiny live budget cannot inspect the entire crowded scene")
	check(not changed(scene),"unchanged scene completes without a false topology change")
	check(scene.inspected==120,"continued polling visits each retained mesh only once")
	var added := add_root(120)
	check(changed(scene),"new root is discovered during bounded polling")
	scene=snapshot();material.roughness=0.21
	check(changed(scene),"shared material edits invalidate the snapshot")
	scene=snapshot();added.mesh=SphereMesh.new()
	check(changed(scene),"equipment mesh replacement is discovered")
	scene=snapshot();added.hide()
	check(not changed(scene),"visibility changes keep membership for live instance masks")
	scene=snapshot();poll(scene)
	world.objects.erase(119);roots[119].free()
	check(changed(scene),"a root freed during scanning is safe and detected")
	scene=snapshot();poll(scene)
	added.mesh=BoxMesh.new()
	check(scene.topology_changed(),"atomic validation starts a fresh synchronous check during an unfinished poll")
	scene=snapshot();roots[118].position=Vector3(200,0,0)
	check(changed(scene),"leaving the retained region removes membership")
	scene=snapshot();roots[118].position=Vector3.ZERO
	check(changed(scene),"entering the retained region adds membership")
	scene=snapshot();poll(scene);scene.discard_geometry()
	check(not budget_supported or not scene.get("topology_pending"),"discarding a failed gather releases the partial scan")
	check(not changed(scene),"failed-gather source watch remains usable without retained geometry")
	world.free()
	print("RT_TOPOLOGY_BUDGET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
