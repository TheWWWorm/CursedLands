extends Node
## Live recentering must include source discovery in the same bounded work
## as packing. Counters verify scheduling without a machine-speed threshold.
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
class CountScene extends Scene:
	var inspected := 0
	var packed := {}
	func _mesh_version(mesh: MeshInstance3D,materials: Dictionary) -> Array:
		inspected += 1
		return super._mesh_version(mesh,materials)
	func _pack_mesh(mesh: MeshInstance3D,_source: Mesh) -> void:
		var id := mesh.get_instance_id()
		packed[id] = int(packed.get(id,0)) + 1
class QuietWorld extends GameWorld:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _physics_process(_dt: float) -> void: pass
class QuietTerrain extends EITerrain:
	func _process(_dt: float) -> void: pass

var checks := 0
var failures := 0
var world: QuietWorld
var terrain: QuietTerrain
var roots: Array[Node3D] = []
var material := StandardMaterial3D.new()
var shared := BoxMesh.new()
var incremental_supported := false

func check(ok: bool,label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func add_root(id: int) -> MeshInstance3D:
	var root := Node3D.new();world.add_child(root);world.objects[id]=root;roots.append(root)
	var mesh := MeshInstance3D.new();mesh.mesh=shared;mesh.material_override=material;root.add_child(mesh)
	return mesh

func begin(incremental: bool) -> CountScene:
	var scene := CountScene.new()
	if incremental and incremental_supported: scene.call("begin",terrain,Vector3.ZERO,-1000.0,true)
	else: scene.begin(terrain,Vector3.ZERO,-1000.0)
	return scene

func complete(scene: CountScene) -> void:
	for i in 1000:
		if scene.step(1): return
	check(false,"bounded source gather eventually finishes")

func _ready() -> void: run.call_deferred()

func run() -> void:
	world=QuietWorld.new();add_child(world)
	terrain=QuietTerrain.new();world.add_child(terrain)
	for i in 120: add_root(i)
	var reference := begin(false)
	for method in reference.get_method_list():
		if method.name=="begin": incremental_supported=method.args.size()>3
	check(reference._nodes.size()==120,"initial loading retains synchronous source discovery")
	complete(reference)
	var scene := begin(true)
	check(scene.inspected==0 and scene._nodes.is_empty(),"live begin queues roots without discovering every mesh")
	var done := scene.step(1)
	check(not done and scene.inspected>0 and scene.inspected<120,"tiny live budget yields during source discovery")
	complete(scene)
	check(scene.inspected==120 and scene._nodes==reference._nodes,"bounded discovery retains exactly the original source versions")
	check(scene.packed==reference.packed and scene.packed.values().count(1)==120,"every discovered mesh is packed exactly once")
	check(not scene.topology_changed(),"completed bounded snapshot passes fresh atomic validation")
	var observed:=begin(true)
	var diagnostic_supported:=false
	for property in observed.get_property_list():
		if property.name=="profile_cpu":diagnostic_supported=true
	if diagnostic_supported:observed.set("profile_cpu",true)
	var observed_roots:=0;var observed_meshes:=0;var detail:={}
	for i in 1000:
		var finished:=observed.step(1)
		if diagnostic_supported:
			detail=observed.get("profile_gather")
			observed_roots+=int(detail.get("counts",{}).get("root",0))
			observed_meshes+=int(detail.get("counts",{}).get("mesh",0))
		if finished:break
	check(observed._nodes==reference._nodes and observed.packed==reference.packed,"profiling preserves gathered source versions and exact packing membership")
	check(observed_roots==120 and observed_meshes==120 and detail.get("complete",false),"profiling accounts for every bounded discovery and packing entry")
	var observed_changed:=observed.topology_changed()
	var topology: Dictionary=observed.get("profile_topology") if diagnostic_supported else {}
	check(not observed_changed and topology.get("fresh",false) and topology.get("mesh_count",0)==120 and topology.get("reason","")=="complete","profiling observes the complete fresh topology validation")
	material.roughness=0.31
	observed_changed=observed.topology_changed()
	topology=observed.get("profile_topology") if diagnostic_supported else {}
	check(observed_changed and topology.get("changed",false) and topology.get("reason","")=="mesh","profiled validation still rejects a current material change")
	material.roughness=0.5
	var canceled := begin(true);canceled.step(1);canceled.discard_geometry()
	check(canceled.pending.is_empty() and (not incremental_supported or canceled._gather_roots.is_empty()),"canceling releases queued roots and packing inputs")
	scene=begin(true);scene.step(1)
	world.objects.erase(119);roots[119].free()
	complete(scene)
	check(scene._nodes.size()==119 and scene.packed.size()==119,"roots freed before discovery are safely skipped")
	check(not scene.topology_changed(),"freed roots cannot cause a false replacement loop")
	scene=begin(true);scene.step(1);material.roughness=0.21;complete(scene)
	check(scene.topology_changed(),"fresh validation rejects a material changed during discovery")
	scene=begin(true);scene.step(1);add_root(120);complete(scene)
	check(scene.topology_changed(),"fresh validation detects roots added after discovery began")
	world.free()
	print("RT_GATHER_BUDGET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
