class_name EIMapScene
extends Node3D
## One loaded island: terrain + water + placed objects, all read from the original files.

var terrain: EITerrain
var mob: EIMob
var stats := {}
## When loaded for gameplay, unit records are returned here instead of being placed.
var unit_records: Array[Dictionary] = []
var object_nodes: Array[Node3D] = []
var _spawn_units := true


static func load_map(map_name: String, mob_name := "", spawn_units := true) -> EIMapScene:
	var t0 := Time.get_ticks_msec()
	var s := EIMapScene.new()
	s.name = map_name
	s._spawn_units = spawn_units
	if mob_name.is_empty():
		mob_name = map_name
	s.terrain = EITerrain.load_map(map_name)
	if s.terrain == null:
		return null
	s.add_child(s.terrain)
	var t1 := Time.get_ticks_msec()
	var mob_path := "maps/%s.mob" % mob_name
	if GameFiles.exists(GameData.root.path_join(mob_path)):
		s.mob = EIMob.load_bytes(GameData.read_file(mob_path))
		s._place_objects()
	s.stats.terrain_ms = t1 - t0
	s.stats.objects_ms = Time.get_ticks_msec() - t1
	return s


## Instantiates one .mob object record under `parent` (null if its model is missing).
func place_object(o: Dictionary, parent: Node3D) -> Node3D:
	var template: String = o.template
	var node: Node3D
	if o.kind == "UNIT":
		node = EIUnitModel.create(o)
	else:
		node = EIFigure.instantiate(template, o.texture, o.complexion, o.parts, o.kind == "LEVER", true,
				String(o.get("name", "")))
	if node == null:
		return null
	var p: Vector3 = o.position
	# Object z is relative to the ground under it.
	node.position = EISpace.pos(p.x, p.y, terrain.height_at(p.x, p.y) + p.z)
	node.quaternion = o.rotation
	node.name = String(o.get("name", template)).validate_node_name()
	node.set_meta("ei", o)
	parent.add_child(node)
	return node


func _place_objects() -> void:
	var root := Node3D.new()
	root.name = "Objects"
	add_child(root)
	var placed := 0
	var missing := {}
	for o: Dictionary in mob.objects:
		LoadingScreen.tick()
		NetStatus.keep_alive()
		var template: String = o.template
		if template.is_empty():
			continue
		if o.kind == "UNIT" and not _spawn_units:
			unit_records.append(o)
			continue
		var node := place_object(o, root)
		if node == null:
			missing[template] = true
			continue
		object_nodes.append(node)
		placed += 1
	stats.objects = mob.objects.size()
	stats.placed = placed
	stats.missing_models = missing.keys()
