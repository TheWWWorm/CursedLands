extends Node
## The world's navigation grid is built on a thread of its own while the
## map's objects are placed (NavGrid.build_start from EIMapScene.load_map's
## on_placing; build_finish binds the placed nodes): the grid equals a
## serial build from the placed objects cell for cell (heights, costs,
## depths, slopes, dry values, special cells, spans, floors, face buckets,
## footprints, their nodes, the walk layer, the class closures), the floor
## objects' meshes carry the decal layer, the world's lever and object
## records are the same, and a serial build after it is identical again.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func same_layer(a: NavGrid.Layer, b: NavGrid.Layer, size: Vector2i) -> bool:
	if a.cls != b.cls or a.raw != b.raw or a.land != b.land or a.cost != b.cost or a.bmin != b.bmin or a.comp != b.comp:
		return false
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if a.astar.is_point_solid(c) != b.astar.is_point_solid(c) \
					or not is_equal_approx(a.astar.get_point_weight_scale(c), b.astar.get_point_weight_scale(c)):
				return false
	return true

## The grid's cell arrays and registers, for equality.
func state(n: NavGrid, with_closures := true) -> Dictionary:
	var out := {}
	for p in ["size", "_alt", "_h0", "_hq0", "_cost0", "_depth0", "_liq", "_h", "_hq", "_cost", "_depth", "_steep", "_steep_cells",
			"_dry_raw", "_dry_weight", "_special", "_special_cells", "_mode_w", "_dry_diff", "_floor_cost", "_spans", "_floors"]:
		out[p] = n.get(p)
	if with_closures:
		out._fixed_sets = n._fixed_sets
	var faces := {}
	for bucket: Vector2i in n._face_buckets:
		var keys := []
		for e: Array in n._face_buckets[bucket]:
			keys.append(e[0])
		faces[bucket] = keys
	out.faces = faces
	var fp := {}
	for key: int in n._fp:
		var f: Dictionary = n._fp[key]
		fp[key] = [f.spans, f.floors, f.radius, f.faces.size()]
	out.fp = fp
	return out

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0}, true)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mpr: String = zone.mpr
	var w := GameWorld.new()
	w.zone = {"type": "game"}
	w.presentation = false
	add_child(w)
	var t0 := Time.get_ticks_usec()
	check(w.load_map(mpr, zone.get("mob", mpr), false), "the authority world loads %s" % mpr)
	var load_us := Time.get_ticks_usec() - t0
	var nav: NavGrid = w.nav
	check(w.map.stats.get("nav_ahead", false) == true and nav.built_ahead, "the navigation grid was built on a thread while the objects were placed (%s)" % str(w.map.stats.get("nav_ahead")))
	var objects: Array = w.map.object_nodes
	check(objects.size() > 500 and nav._fp.size() == objects.size(), "every placed object has a footprint (%d of %d)" % [nav._fp.size(), objects.size()])
	# The serial reference from the placed objects.
	var serial := NavGrid.new()
	t0 = Time.get_ticks_usec()
	serial.build(w.terrain, w.terrain.water_base, objects)
	var serial_us := Time.get_ticks_usec() - t0
	var a := state(nav)
	var b := state(serial)
	var differ := []
	for k in a:
		if a[k] != b[k]:
			differ.append(k)
	check(differ.is_empty(), "the grid equals a serial build from the placed objects (%s)" % str(differ))
	check(nav._fp.keys() == serial._fp.keys(), "the footprints carry the same keys in the same order")
	var nodes_same := true
	for key: int in serial._fp_nodes:
		if nav._fp_nodes.get(key) != serial._fp_nodes[key]:
			nodes_same = false
	check(nodes_same and nav._fp_nodes.size() == serial._fp_nodes.size(), "every footprint is bound to the same placed node")
	check(nav._layers.keys() == [NavGrid.WALK_CLASS] and same_layer(nav.layer(NavGrid.WALK_CLASS), serial.layer(NavGrid.WALK_CLASS), nav.size), "the walk layer equals the serial build's")
	var decals := 0
	var floor_objects := 0
	for key: int in nav._fp:
		if nav._fp[key].faces.is_empty():
			continue
		floor_objects += 1
		var o: Node3D = nav._fp_nodes[key]
		var all := true
		for mesh: MeshInstance3D in o.find_children("*", "MeshInstance3D", true, false):
			if not (mesh.layers & EITerrain.DECAL_LAYER):
				all = false
		if all:
			decals += 1
	check(floor_objects > 0 and decals == floor_objects, "the floor objects' meshes carry the decal layer (%d of %d)" % [decals, floor_objects])
	check(not w.objects.is_empty() and w.objects.size() >= objects.size(), "the world registers the placed objects (%d)" % w.objects.size())
	print("nav_build_ahead: %s %s, %d objects, world load %.1f ms, serial nav build %.1f ms" % [mpr, str(nav.size), objects.size(), load_us / 1000.0, serial_us / 1000.0])
	# A serial rebuild of the same grid is identical again, and clears the flag.
	nav.build(w.terrain, w.terrain.water_base, objects)
	check(not nav.built_ahead and state(nav) == b, "a serial rebuild of the grid is identical and clears built_ahead")
	# A world with units: the units' occupancy comes after the grid.
	var u := GameWorld.new()
	u.zone = {"type": "game"}
	u.presentation = false
	add_child(u)
	check(u.load_map(mpr, zone.get("mob", mpr), true) and u.map.stats.get("nav_ahead", false) == true and u.unit_rows().size() > 20,
		"a world with units builds its grid ahead and spawns them (%d)" % u.unit_rows().size())
	var serial_units := NavGrid.new()
	serial_units.build(u.terrain, u.terrain.water_base, u.map.object_nodes)
	# (The world built its standing classes' layers too: their closures are
	# left out of the comparison.)
	check(state(u.nav, false) == state(serial_units, false) and u.nav._fp.keys() == serial_units._fp.keys(), "the grid of a world with units equals a serial build from its placed objects")
	print("NAV_BUILD_AHEAD %d checks %d failures" % [checks, failures.size()])
	for f in failures:
		print("  ", f)
	get_tree().quit(1 if failures.size() else 0)
