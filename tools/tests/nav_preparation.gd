extends "nav_topology.gd"
## Preparing static caches in a different order/on independent workers must
## preserve the lazy graph's paths, reachable regions and relocated targets.

func _ready() -> void:
	rng.seed = 810477
	var cases: Array = []
	var tasks := PackedInt64Array()
	for trial in 24:
		var nav := fixture(trial)
		nav.layer(3).cls = 3
		var lazy = Blocks.new(nav, nav.layer(3))
		var warm = Blocks.new(nav, nav.layer(3))
		check(warm._native_topology, "native topology available")
		var points: Array[Vector2i] = []
		for i in 25:
			points.append(Vector2i(rng.randi_range(-2,nav.size.x+1),rng.randi_range(-2,nav.size.y+1)))
		points.make_read_only()
		cases.append([nav,lazy,warm,points])
		tasks.append(WorkerThreadPool.add_task(Callable(warm._terrain_kernel,"prepare_routes").bind(points), true))
	for task: int in tasks: WorkerThreadPool.wait_for_task_completion(task)
	for trial in cases.size():
		var nav: NavGrid = cases[trial][0]
		var lazy = cases[trial][1]
		var warm = cases[trial][2]
		var labels := {0:0}
		var reverse := {0:0}
		var stats: Dictionary = warm._terrain_kernel.topology_stats()
		check(stats.weighted_blocks >= stats.components, "all occupied components have prepared route weights")
		# IDs may differ with query order. Their equivalence classes must not.
		for y in warm.size.y:
			for x in warm.size.x:
				var at := Vector2i(x,y)
				check(warm.representative(at) == lazy.representative(at),"representative")
				check(warm._connections(at) == lazy._connections(at),"connections")
				check(warm._raw(at) == lazy._raw(at),"weighted edges")
				var a: int = warm.component(at)
				var b: int = lazy.component(at)
				check(not labels.has(a) or labels[a] == b,"component unchanged")
				check(not reverse.has(b) or reverse[b] == a,"components remain distinct")
				labels[a] = b; reverse[b] = a
		for point: Vector2i in cases[trial][3]:
			var goal := Vector2i(rng.randi_range(0,nav.size.x-1),rng.randi_range(0,nav.size.y-1))
			for direction in [false,true]:
				check(warm._topology_seeds(point,direction) == lazy._topology_seeds(point,direction),"ordered seeds")
			check(labels.get(warm.component_of(point),-1) == lazy.component_of(point),"majority and ties")
			check(warm.source_seeds_connected(point) == lazy.source_seeds_connected(point),"bounded connection proof")
			check(warm.route(point,goal) == lazy.route(point,goal),"block route")
			for connected in [false,true]:
				var from := Vector2(point)*0.5+Vector2(.1,.2)
				var to := Vector2(goal)*0.5+Vector2(.23,.13)
				check(warm.relocate(from,to,connected) == lazy.relocate(from,to,connected),"relocated endpoint")
		# Exercise the production dispatcher and subsequent map replacement.
		var actor := GameUnit.new()
		actor.pos = Vector2(5.25,5.25)
		actor._classes = [3,3,3]
		nav.prepare_static_navigation([actor])
		var prepared = nav.native_graph(nav.layer(3))
		# A completely trapped source legitimately has no reachable component,
		# but its empty seed result is still prepared before the join returns.
		check(prepared._terrain_kernel.topology_stats().seeds == 1,"dispatcher joined preparation")
		nav.layer(3).land[10*nav.size.x+10] = 1-nav.layer(3).land[10*nav.size.x+10]
		nav.map_rev += 1
		var fresh = nav.native_graph(nav.layer(3))
		check(fresh != prepared,"door/map change discards prepared graph")
		var reference = Blocks.new(nav,nav.layer(3))
		check(fresh._topology_seeds(Vector2i(10,10),false) == reference._topology_seeds(Vector2i(10,10),false),"new map remains live")
		actor.free()
	print("NAV_PREPARATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
