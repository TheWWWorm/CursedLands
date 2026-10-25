extends Node
const Scene=preload("res://src/game/fx/water_raytrace_scene.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready() -> void:run.call_deferred()
func run() -> void:
	# Dar Leanos enters a little over 4096 retained parts during walking.
	# Real scene packing must accept them without dropping distant characters.
	var root := Node3D.new();add_child(root)
	var source := BoxMesh.new();source.material=StandardMaterial3D.new()
	var scene := Scene.new();scene._plane=-1000
	var last: MeshInstance3D
	for i in 4600:
		var mesh := MeshInstance3D.new();mesh.mesh=source;root.add_child(mesh)
		scene.pending.append({"node":weakref(mesh),"land":false});last=mesh
	var steps := 0
	while not scene.step(500):steps+=1
	check(not scene.failed,"dense city snapshot accepts more than 4096 articulated parts")
	check(scene.instances.size()==4600,"complete snapshot retains every part without truncation")
	check(scene.geometries.size()==1,"dense placements share one immutable source geometry")
	check(steps>1,"dense gather still yields between bounded steps")
	var initial := scene.updates()
	check(initial.instances.size()==4600,"all retained parts receive initial visibility masks")
	last.position=Vector3(2,0,0)
	var updates := scene.updates()
	check(updates.instances.size()==1 and updates.instances[0].index==4599 and updates.instances[0].transform.origin==last.position,"highest city placement updates without changing its identity")
	var bounded := Scene.new();bounded.instances.resize(Scene.MAX_INSTANCES)
	bounded._add_instance(last,0,Transform3D.IDENTITY)
	check(bounded.failed and bounded.instances.size()==Scene.MAX_INSTANCES,"larger crowd limit remains bounded and rejects overflow")
	root.free()
	check(scene.updates().instances.size()==4600,"freed crowd safely masks all retained instances")
	print("RT_DENSE_SCENE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
