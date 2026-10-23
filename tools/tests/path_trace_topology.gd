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

func detached_geometry() -> void:
	var source := GameUnit.new();source.name="LimbSource";source.world=world
	world.add_child(source);source.position=Vector3(20,0,0)
	world.units={1:unit,2:source}
	var model := EIUnitModel.new();source.add_child(model);source.model=model
	var arm := part(model,"Arm",Vector3(0,1,0))
	var original := snapshot()
	# Exercise the production severing path, including copied meshes/materials,
	# world parenting and registration, rather than manually opting into a group.
	var limb := SeveredLimb.throw(source,"Arm")
	check(limb!=null,"production severing creates a detached opaque figure part")
	if limb==null:
		world.units={1:unit};source.free();return
	limb.set_process(false);arm.hide()
	check(not world.objects.values().has(limb) and not world.units.values().has(limb),"detached part remains outside gameplay object and unit registries")
	check(limb.is_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP),"detached part registers its geometry on entering the world")
	check(original.topology_changed(),"new detached geometry invalidates the previous snapshot")
	var copy := limb.get_child(0) as MeshInstance3D
	check(copy!=null and copy.mesh==arm.mesh and copy.material_override==arm.material_override,"detached geometry retains the original mesh and material")
	var scene := snapshot()
	check(not legacy_nodes(scene).has(copy.get_instance_id()),"negative control: original object/unit-only collection omits the detached part")
	check(scene._nodes.has(copy.get_instance_id()),"detached mesh enters the next lighting snapshot")
	while not scene.step(): pass
	scene.updates(true)
	var index := -1
	for i in scene.instances.size():
		if scene.instances[i].node.get_ref()==copy: index=i
	check(index>=0 and scene.instances[index].mask==7,"detached part receives lighting, casts shadows and contributes to indirect paths")
	limb.position+=Vector3(0.3,0.2,0.1);limb.rotate_y(0.4)
	var changes: Dictionary=scene.updates()
	check(changes.instances.any(func(row: Dictionary):return row.index==index and row.transform==copy.global_transform),"tumbling detached part uploads its live transform")
	check(not scene.topology_changed(),"detached rigid motion preserves scene membership")
	limb.hide();changes=scene.updates()
	check(changes.instances.any(func(row: Dictionary):return row.index==index and row.mask==0),"hidden detached part stops tracing without rebuilding")
	limb.show();changes=scene.updates()
	check(changes.instances.any(func(row: Dictionary):return row.index==index and row.mask==7),"revealed detached part restores all lighting roles")
	world.objects["audit_detached"]=limb
	var duplicate := snapshot();while not duplicate.step(): pass
	check(duplicate.instances.filter(func(row: Dictionary):return row.node.get_ref()==copy).size()==1,"an opted-in registered root contributes each mesh only once")
	world.objects.erase("audit_detached")
	var other_world := GameWorld.new();other_world.process_mode=Node.PROCESS_MODE_DISABLED;add_child(other_world)
	var foreign := SeveredLimb.new();other_world.add_child(foreign);part(foreign,"OtherWorldPart",Vector3.ZERO)
	check(not scene.topology_changed(),"another loaded world's registered geometry is excluded")
	other_world.free()
	var water := Scene.new();water.begin(terrain,Vector3.ZERO,-1.0e20)
	check(water._nodes.has(copy.get_instance_id()),"water reflection collection also retains detached figure parts")
	world.remove_child(limb)
	check(scene.topology_changed() and get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP).is_empty(),"off-tree detached parts release active group membership")
	world.add_child(limb)
	check(not scene.topology_changed() and get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP).size()==1,"reattaching a detached part restores one registry entry")
	limb.position.x=127.5
	check(not scene.topology_changed(),"detached figure receives the same bounded exit hysteresis as its source")
	limb.position.x=128.5
	check(scene.topology_changed(),"detached figure outside the exit margin leaves the snapshot")
	limb.position.x=20.0
	var before_free := snapshot();limb.free()
	check(before_free.topology_changed(),"expiry removes detached geometry from the next snapshot")
	check(get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP).is_empty(),"freeing all detached parts releases every registry entry")
	world.units={1:unit};source.free()

func terrain_versions() -> void:
	var material := ShaderMaterial.new();var shader := Shader.new()
	shader.code="shader_type spatial; uniform sampler2D detail_nm; uniform sampler2D macro_tex; uniform bool blend_edges=true;"
	material.shader=shader;terrain._land_mat=material
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var first:=ImageTexture.create_from_image(image);var second:=ImageTexture.create_from_image(image)
	material.set_shader_parameter("detail_nm",first);material.set_shader_parameter("macro_tex",first)
	var scene:=Scene.new();scene.path_materials=true;scene.begin(terrain,Vector3.ZERO,-1.0e20)
	check(not scene.topology_changed(),"unchanged ready terrain textures preserve the snapshot")
	material.set_shader_parameter("detail_nm",second)
	check(scene.topology_changed(),"replacing a ready terrain normal texture invalidates the snapshot")
	material.set_shader_parameter("detail_nm",first);material.set_shader_parameter("macro_tex",second)
	check(scene.topology_changed(),"replacing a ready terrain macro texture invalidates the snapshot")
	material.set_shader_parameter("macro_tex",first);material.set_shader_parameter("blend_edges",false)
	check(scene.topology_changed(),"terrain edge-sampling changes invalidate the snapshot")
	material.set_shader_parameter("blend_edges",true)
	check(not scene.topology_changed(),"restoring the original terrain inputs restores its version")
	terrain._land_mat=null

func discarded_watcher() -> void:
	var scene := snapshot();while not scene.step(): pass
	check(not scene.vertices.is_empty() and not scene.images.is_empty(),"recovery watch begins with a fully populated scene")
	var nodes: Dictionary=scene._nodes.duplicate(true)
	scene.discard_geometry()
	check(scene.vertices.is_empty() and scene.images.is_empty() and scene.geometries.is_empty() and scene.instances.is_empty(),"discarding a failed scene releases packed geometry, textures and placements")
	check(scene.pending.is_empty() and scene._mesh_cache.is_empty() and scene._mesh_roots.is_empty() and scene._groups.is_empty() and scene._morph_geometries.is_empty() and scene._kernel==null,"discarding releases pending work, mesh caches and native instance watches")
	check(scene._nodes==nodes and not scene.topology_changed(),"discarded scene keeps the original topology snapshot")
	var material:=body.material_override as StandardMaterial3D
	var roughness:=material.roughness;material.roughness=0.2
	check(scene.topology_changed(),"discarded scene still detects a material fix")
	material.roughness=roughness
	var limb:=SeveredLimb.new();world.add_child(limb);part(limb,"WatcherPart",Vector3.ZERO)
	check(scene.topology_changed(),"discarded scene still detects new dynamic geometry")
	check(scene._mesh_roots.is_empty(),"topology-only polling does not repopulate packing bookkeeping")
	limb.free()
	check(not scene.topology_changed(),"discarded scene settles after temporary geometry is removed")

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
	boundaries();mutations();static_bounds();detached_geometry();terrain_versions();discarded_watcher();budgets()
	world.free()
	FileAccess.open(out.path_join("path-topology-results.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"legacy_boundary_changed":legacy_boundary_changed,
		"native_kernel":Scene.new()._kernel!=null},"\t"))
	print("PATH_TRACE_TOPOLOGY ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
