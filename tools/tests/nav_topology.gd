extends Node
## Compare persistent native records with the unchanged script graph. Both
## use the existing weighted route/frontier kernels; a subset also runs the
## fully scripted graph. Random maps include directed slopes and blocked starts.
const Blocks := preload("res://src/game/nav_blocks.gd")
var checks := 0
var failures := 0
var rng := RandomNumberGenerator.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ",label)

func fixture(trial: int) -> NavGrid:
	var nav := NavGrid.new()
	nav.size = Vector2i(32,32 if trial % 3 else 48)
	var n := nav.size.x * nav.size.y
	var layer := NavGrid.Layer.new()
	layer.land.resize(n); layer.cost.resize(n)
	nav._hq.resize(n)
	var slopes := PackedInt32Array()
	slopes.resize(2049)
	for i in slopes.size():
		var dh := i - 1023
		slopes[i] = 1024 + maxi(dh,0) * 7 if absi(dh) <= 5 and (trial % 5 != 0 or dh <= 1) else -1
	nav._slope_tab = [slopes,slopes]
	for i in n:
		layer.land[i] = int(rng.randf() < (0.05 if trial % 2 else 0.35))
		layer.cost[i] = NavGrid.STEP_COST[rng.randi_range(1,NavGrid.STEP_COST.size()-1)]
		nav._hq[i] = rng.randi_range(-5,5) if trial % 4 else 0
	nav._layers[3] = layer
	return nav

func _ready() -> void:
	rng.seed = 8037281
	for trial in 24:
		var nav := fixture(trial)
		var a = Blocks.new(nav,nav.layer(3))
		var b = Blocks.new(nav,nav.layer(3)); b._native_topology = false
		check(a._native_topology,"new native topology available")
		for y in a.size.y:
			for x in a.size.x:
				var at := Vector2i(x,y)
				check(a.representative(at) == b.representative(at),"representative %s %s" % [trial,at])
				check(a._connections(at) == b._connections(at),"connections %s %s" % [trial,at])
				check(a._raw(at) == b._raw(at),"weighted edges %s %s" % [trial,at])
		# Matching query order also makes the private numeric component IDs
		# equal; this is stronger than the gameplay equivalence-class contract.
		for y in a.size.y:
			for x in a.size.x:
				var at := Vector2i(x,y)
				check(a.component(at) == b.component(at),"component %s %s" % [trial,at])
		for query in 30:
			var start := Vector2i(rng.randi_range(-2,nav.size.x+1),rng.randi_range(-2,nav.size.y+1))
			var goal := Vector2i(rng.randi_range(0,nav.size.x-1),rng.randi_range(0,nav.size.y-1))
			for reverse in [false,true]:
				check(a._topology_seeds(start,reverse) == b._topology_seeds(start,reverse),"seed order %s %s %s" % [trial,query,reverse])
			check(a.component_of(start) == b.component_of(start),"source majority")
			check(a.source_seeds_connected(start) == b.source_seeds_connected(start),"bounded connectivity proof")
			check(a.route(start,goal) == b.route(start,goal),"weighted block route")
			var from := Vector2(start)*0.5+Vector2(.1,.2)
			var to := Vector2(goal)*0.5+Vector2(.23,.13)
			for connected in [false,true]:
				check(a.relocate(from,to,connected) == b.relocate(from,to,connected),"relocated endpoint")
		if trial < 3:
			var scalar = Blocks.new(nav,nav.layer(3)); scalar._native_topology = false; scalar._terrain_kernel = null
			for y in a.size.y:
				for x in a.size.x:
					var at := Vector2i(x,y)
					check(a.representative(at) == scalar.representative(at),"full script representative")
					check(a._connections(at) == scalar._connections(at),"full script connections")
					check(a._raw(at) == scalar._raw(at),"full script weighted edges")
		# Map changes replace the whole static graph; occupancy never enters it.
		var old = nav.native_graph(nav.layer(3))
		nav.layer(3).land[10*nav.size.x+10] = 1-nav.layer(3).land[10*nav.size.x+10]
		nav.map_rev += 1
		var fresh = nav.native_graph(nav.layer(3))
		check(fresh != old,"map revision replaces native graph")
		var reference = Blocks.new(nav,nav.layer(3)); reference._native_topology = false
		check(fresh._topology_seeds(Vector2i(10,10),false) == reference._topology_seeds(Vector2i(10,10),false),"new obstacle topology is live")
	print("NAV_TOPOLOGY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
