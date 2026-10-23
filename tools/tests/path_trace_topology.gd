extends Node
## CPU scene-membership regression. Run through Main --tool, including headless.
## The same boundary assertion fails against the pre-fix exported scene script.
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
var out := "user://path-trace-topology"
var checks := 0
var failures: Array[String] = []
var world: GameWorld
var terrain: EITerrain
var unit: GameUnit
var body: MeshInstance3D
var hidden_part: MeshInstance3D
var legacy_boundary_changed := false

func _ready() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func part(parent: Node3D,label: String,offset: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=label
	var mesh := BoxMesh.new();mesh.size=Vector3(2,1,1)
	node.mesh=mesh;node.material_override=StandardMaterial3D.new()
	parent.add_child(node);node.position=offset
	return node

func snapshot() -> RefCounted:
	var scene := Scene.new();scene.lighting_camera_mask=1
	scene.begin(terrain,Vector3.ZERO,-1.0e20)
	return scene

func legacy_nodes(scene: RefCounted) -> Array:
	# Explicit negative control: the previous per-part world-space admission.
	var ids := []
	for root: Node3D in world.objects.values()+world.units.values():
		if not is_instance_valid(root) or root.global_position.length_squared()>pow(Scene.RADIUS+24.0,2): continue
		for node: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if node.mesh!=null and scene._near(node.global_transform*node.get_aabb(),false): ids.append(node.get_instance_id())
	return ids

func boundaries() -> void:
	unit.position=Vector3(97.230194,0,0)
	body.position.x=-0.4 # nearest face 95.830194 m
	var scene := snapshot()
	check(scene._nodes.has(body.get_instance_id()),"boundary body is included before its idle swing")
	check(scene._nodes.has(hidden_part.get_instance_id()),"whole figure includes hidden parts beyond the per-mesh boundary")
	var before := legacy_nodes(scene)
	body.position.x=0.0 # nearest face 96.230194 m
	legacy_boundary_changed=legacy_nodes(scene)!=before
	check(legacy_boundary_changed,"negative control: old per-part admission changes during the idle swing")
	check(not scene.topology_changed(),"idle swing across 96 metres preserves the complete scene snapshot")
	for i in 12:
		body.position.x=-0.4 if i%2==0 else 0.0
		check(not scene.topology_changed(),"repeated boundary pose %d does not rebuild"%i)
	while not scene.step(): pass
	check(not scene.failed and scene.instances.size()==2,"both figure parts pack without exceeding the unchanged budgets")
	scene.updates(true)
	body.position.x=0.25
	var changes: Dictionary = scene.updates()
	check(not changes.instances.is_empty(),"boundary animation still produces live instance transforms")
	hidden_part.show()
	changes=scene.updates()
	check(not changes.instances.is_empty() and not scene.topology_changed(),"revealing a retained hidden part uses instance updates")
	hidden_part.hide();scene.updates()
	for distance: float in [119.5,120.5,127.5,128.0]:
		unit.position.x=distance
		check(not scene.topology_changed(),"retained whole unit remains admitted at %.1f metres"%distance)
	unit.position.x=128.5
	check(scene.topology_changed(),"unit exits only after the eight-metre hysteresis margin")
	var outside := snapshot()
	check(not outside._nodes.has(body.get_instance_id()),"replacement snapshot omits a unit outside the exit radius")
	for distance: float in [127.5,120.5]:
		unit.position.x=distance
		check(not outside.topology_changed(),"excluded unit does not re-enter at %.1f metres"%distance)
	unit.position.x=120.0
	check(outside.topology_changed(),"new unit entry is detected at the original 120-metre root radius")
	var entered := snapshot()
	check(entered._nodes.has(body.get_instance_id()) and entered._nodes.has(hidden_part.get_instance_id()),"entry admits the complete figure")
	unit.position.x=120.5
	check(not entered.topology_changed(),"newly admitted figure receives exit hysteresis")
	unit.position.x=97.230194

func mutations() -> void:
	var scene := snapshot()
	var original := body.mesh
	body.mesh=original.duplicate()
	check(scene.topology_changed(),"equipment mesh replacement still invalidates the snapshot")
	body.mesh=original
	check(not scene.topology_changed(),"restored mesh restores the original topology")
	var material := body.material_override as StandardMaterial3D
	var roughness := material.roughness;material.roughness=0.25
	check(scene.topology_changed(),"same-resource material value edits still invalidate the snapshot")
	material.roughness=roughness
	body.material_override=material.duplicate()
	check(scene.topology_changed(),"material resource replacement still invalidates the snapshot")
	body.material_override=material
	var equipment := part(unit,"NewEquipment",Vector3(8,0,0))
	check(scene.topology_changed(),"new equipment outside the old per-part boundary is detected")
	equipment.free()
	check(not scene.topology_changed(),"removing newly added equipment restores baseline membership")
	var with_part := snapshot()
	unit.remove_child(hidden_part)
	check(with_part.topology_changed(),"removal of an existing hidden part is detected")
	unit.add_child(hidden_part)
	check(not with_part.topology_changed(),"re-attaching the same hidden part restores membership")
	var newcomer := GameUnit.new();newcomer.name="SpawnedUnit"
	world.add_child(newcomer);newcomer.position=Vector3(80,0,0)
	part(newcomer,"Body",Vector3.ZERO);world.units={1:unit,2:newcomer}
	check(scene.topology_changed(),"a newly spawned nearby unit invalidates the snapshot")
	var with_spawn := snapshot()
	world.units={1:unit};newcomer.free()
	check(with_spawn.topology_changed(),"despawn of a snapshot unit is detected")
	check(not scene.topology_changed(),"unmodified original figure stays stable after the spawn/despawn")

func static_bounds() -> void:
	var root := Node3D.new();world.add_child(root);world.objects[1]=root
	var mesh := part(root,"Scenery",Vector3(96.8,0,0))
	var scene := snapshot()
	check(scene._nodes.has(mesh.get_instance_id()),"static mesh intersecting 96-metre sphere remains admitted")
	mesh.position.x=97.2
	check(scene.topology_changed(),"static objects retain per-mesh 96-metre admission")
	var outside := snapshot()
	check(not outside._nodes.has(mesh.get_instance_id()),"static mesh outside 96 metres remains omitted")
	world.objects.clear();root.free()

func budgets() -> void:
	check(Scene.MAX_TRIANGLES==320000 and Scene.MAX_TEXTURES==192 and Scene.MAX_INSTANCES==4096,"geometry, texture and instance budget caps are unchanged")
	var scene := Scene.new();scene._kernel=null;scene.triangles=Scene.MAX_TRIANGLES
	scene._append(body.mesh.surface_get_arrays(0),Transform3D.IDENTITY,body.material_override,false)
	check(scene.failed,"triangle overflow still rejects the snapshot")
	scene=Scene.new();scene.images.resize(Scene.MAX_TEXTURES)
	check(scene._layer(null)==-1 and scene.failed,"texture overflow still rejects the snapshot")
	scene=Scene.new();scene.instances.resize(Scene.MAX_INSTANCES)
	scene._add_instance(body,0,body.global_transform)
	check(scene.failed,"instance overflow still rejects the snapshot")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0},true)
	world=GameWorld.new();world.process_mode=Node.PROCESS_MODE_DISABLED;add_child(world)
	terrain=EITerrain.new();world.add_child(terrain);world.terrain=terrain
	unit=GameUnit.new();unit.name="BoundaryUnit";world.add_child(unit);world.units={1:unit}
	body=part(unit,"Body",Vector3(-0.4,0,0))
	hidden_part=part(unit,"HiddenPart",Vector3(5,0,0));hidden_part.hide()
	boundaries();mutations();static_bounds();budgets()
	world.free()
	FileAccess.open(out.path_join("path-topology-results.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"legacy_boundary_changed":legacy_boundary_changed},"\t"))
	print("PATH_TRACE_TOPOLOGY ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
