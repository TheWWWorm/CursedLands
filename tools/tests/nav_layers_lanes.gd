extends Node
## The navigation layers of the units' standing classes are built on worker
## lanes while the authority world loads (NavGrid.build_layers, one native
## build per class) and assembled in the order the classes were asked for:
## each equals the layer the serial builder makes from the same grid cell
## for cell (closed cells, weights, costs, block minima, labels, the units
## painted), the class groups' closures are the same, a class built already
## is left alone and a single missing class is built serially as before.
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

## Cell-for-cell equality of two layers of one grid.
func same_layer(a: NavGrid.Layer, b: NavGrid.Layer, size: Vector2i) -> Dictionary:
	var out := {"arrays": a.cls == b.cls and a.raw == b.raw and a.land == b.land and a.cost == b.cost and a.bmin == b.bmin and a.comp == b.comp,
		"solid": 0, "weight": 0}
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if a.astar.is_point_solid(c) != b.astar.is_point_solid(c):
				out.solid += 1
			elif not is_equal_approx(a.astar.get_point_weight_scale(c), b.astar.get_point_weight_scale(c)):
				out.weight += 1
	return out

func world(with_units: bool) -> GameWorld:
	var w := GameWorld.new()
	w.zone = {"type": "game"}
	w.presentation = false
	add_child(w)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz1g")
	check(w.load_map(zone.mpr, zone.get("mob", zone.mpr), with_units), "the authority world loads %s (units: %s)" % [zone.mpr, with_units])
	return w

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0}, true)
	# 1. The loaded world: the standing classes' layers, built on lanes, in
	# the order the units stand, each equal to a serial build now.
	var w := world(true)
	var nav: NavGrid = w.nav
	var classes := []
	for u: GameUnit in w.unit_rows():
		if not classes.has(u._classes[2]):
			classes.append(u._classes[2])
	check(classes.size() >= 3, "the units stand in several classes (%s)" % str(classes))
	# The grid's build makes the walk layer (WALK_CLASS) first; the standing
	# classes follow in the order the units stand.
	var expected := [NavGrid.WALK_CLASS]
	for cls: int in classes:
		if cls != NavGrid.WALK_CLASS:
			expected.append(cls)
	check(nav._layers.keys() == expected, "the walk layer, then the layers in the order the units stand (%s, %s)" % [str(nav._layers.keys()), str(expected)])
	check(nav.layers_grouped == expected.size() - 1, "every standing class's layer but the walk layer was built on a lane (%d of %d)" % [nav.layers_grouped, expected.size() - 1])
	var groups := {}
	for cls: int in classes:
		groups[NavGrid._group(cls)] = true
	check(nav._fixed_sets.keys().size() == groups.size(), "one closure set per class group (%d of %d)" % [nav._fixed_sets.keys().size(), groups.size()])
	var fixed_before := nav._fixed_sets.duplicate()
	var t0 := Time.get_ticks_usec()
	for cls: int in classes:
		var serial: NavGrid.Layer = nav._build_layer(cls)
		var same := same_layer(nav._layers[cls], serial, nav.size)
		check(same.arrays and same.solid == 0 and same.weight == 0, "class %d's lane layer equals the serial build (%s)" % [cls, JSON.stringify(same)])
	var serial_us := Time.get_ticks_usec() - t0
	check(nav._fixed_sets == fixed_before, "the serial builds find the same class group closures")
	print("nav_layers_lanes: %s %s, %d classes, serial rebuild %.1f ms" % [w.map.name, str(nav.size), classes.size(), serial_us / 1000.0])

	# 2. A grid without layers: the order asked for, duplicates and classes
	# built already skipped, a single missing class built serially.
	var s := world(false)
	var n: NavGrid = s.nav
	check(n._layers.keys() == [NavGrid.WALK_CLASS], "a world without units builds the walk layer only at load (%s)" % str(n._layers.keys()))
	n.build_layers([3, 1, 1, 5])
	check(n._layers.keys() == [3, 1, 5] and n.layers_grouped == 2, "build_layers makes the asked classes once, in order, the walk layer kept (%s, %d on lanes)" % [str(n._layers.keys()), n.layers_grouped])
	var kept: NavGrid.Layer = n._layers[1]
	n.build_layers([1, 7])
	check(n._layers.keys() == [3, 1, 5, 7] and n._layers[1] == kept and n.layers_grouped == 0, "a class built already is kept and a single new class is built serially (%s, %d on lanes)" % [str(n._layers.keys()), n.layers_grouped])
	n.build_layers([7, 3])
	check(n._layers.keys() == [3, 1, 5, 7] and n.layers_grouped == 0, "nothing to build builds nothing")
	for cls: int in [3, 1, 5, 7]:
		var same := same_layer(n._layers[cls], n._build_layer(cls), n.size)
		check(same.arrays and same.solid == 0 and same.weight == 0, "class %d built on demand equals the serial build (%s)" % [cls, JSON.stringify(same)])
	# layer() after build_layers returns the built one.
	check(n.layer(5) == n._layers[5] and n.layer(2) != null and n._layers.keys() == [3, 1, 5, 7, 2], "layer() returns the built layers and still builds the rest")

	print("NAV_LAYERS_LANES %d checks %d failures" % [checks, failures.size()])
	for f in failures:
		print("  ", f)
	get_tree().quit(1 if failures.size() else 0)
