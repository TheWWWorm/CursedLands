extends "nav_topology.gd"
## Compare pruning with the unchanged full ray scan, including disconnected
## rooms, directed slopes, blocked endpoints, rounding and radius boundaries.
var fast_us := 0
var full_us := 0
var comparisons := 0

func prepared_endpoint_does_not_flood_neighbours() -> void:
	var nav := NavGrid.new();nav.size=Vector2i(256,256)
	var layer := NavGrid.Layer.new();layer.cls=3
	layer.land.resize(65536);layer.land.fill(1);layer.cost.resize(65536);layer.cost.fill(1024)
	nav._hq.resize(65536)
	var slopes:=PackedInt32Array();slopes.resize(2049);slopes.fill(1024)
	nav._slope_tab=[slopes,slopes];nav._layers[3]=layer
	# The goal's block neighbourhood also contains a large room across a wall.
	# A route inside the prepared small room must not label that other room.
	for rect in [Rect2i(4,8,28,56),Rect2i(33,8,207,232)]:
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):layer.land[y*256+x]=0
	var graph = Blocks.new(nav,layer)
	var start:=Vector2i(20,20);var goal:=Vector2i(29,20)
	graph.component_of(start)
	var expected: Array=graph.connected_route(start,goal)
	var before: int=graph._terrain_kernel.topology_stats().components if graph._native_topology else graph.components.size()
	graph.components_prepared=true
	check(not expected.is_empty() and graph.connected_route(start,goal)==expected,"prepared room keeps its valid route beside an unrelated component")
	var after: int=graph._terrain_kernel.topology_stats().components if graph._native_topology else graph.components.size()
	check(after==before,"one route endpoint does not flood an unrelated neighbouring room")

func compare(graph, from: Vector2, to: Vector2, minimum: float) -> void:
	var wanted: int = graph.component_of(NavGrid.cell(from))
	var expected_member := false
	for entry: Array in graph._topology_seeds(NavGrid.cell(to),true):
		if graph.component(entry[0]) == wanted: expected_member = true
	check(graph._in_component(NavGrid.cell(to),wanted)==expected_member,"component neighbourhood matches exact endpoint seeds")
	graph.components_prepared = false
	var original_route: Array = graph.connected_route(NavGrid.cell(from),NavGrid.cell(to))
	graph.components_prepared = true
	check(graph.connected_route(NavGrid.cell(from),NavGrid.cell(to))==original_route,"prepared-component route rejection preserves weighted routes")
	var started := Time.get_ticks_usec()
	var got: Dictionary = graph.relocate(from,to,true,minimum)
	fast_us += Time.get_ticks_usec()-started
	var saved: Dictionary = graph._relocation_bounds.duplicate()
	graph._relocation_bounds[wanted] = Rect2i()
	started = Time.get_ticks_usec()
	var expected: Dictionary = graph.relocate(from,to,true,minimum)
	full_us += Time.get_ticks_usec()-started
	graph._relocation_bounds = saved
	comparisons += 1
	check(got==expected,"ordered endpoint unchanged: %s -> %s radius %s" % [from,to,minimum])

func _ready() -> void:
	rng.seed=158705
	prepared_endpoint_does_not_flood_neighbours()
	for trial in 16:
		var nav := fixture(trial)
		var graph = Blocks.new(nav,nav.layer(3))
		for query in 12:
			var from := Vector2(rng.randf_range(-1,nav.size.x/2.0),rng.randf_range(-1,nav.size.y/2.0))
			var to := Vector2(rng.randf_range(-1,nav.size.x/2.0+1),rng.randf_range(-1,nav.size.y/2.0+1))
			for minimum in [0.0,0.25,2.75]:compare(graph,from,to,minimum)
	var nav := NavGrid.new();nav.size=Vector2i(256,256)
	var layer := NavGrid.Layer.new();layer.cls=3
	layer.land.resize(65536);layer.land.fill(1);layer.cost.resize(65536);layer.cost.fill(1024)
	nav._hq.resize(65536)
	var slopes:=PackedInt32Array();slopes.resize(2049);slopes.fill(1024)
	nav._slope_tab=[slopes,slopes];nav._layers[3]=layer
	for rect in [Rect2i(4,16,12,12),Rect2i(160,160,72,72)]:
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):layer.land[y*256+x]=0
	var graph = Blocks.new(nav,layer)
	for x in [80.25,100.25,116.25,128.25]:
		for y in [80.25,100.25,116.25,128.25]:
			for minimum in [0.0,0.25,2.75]:compare(graph,Vector2(4,10.5),Vector2(x,y),minimum)
	var wanted: int=graph.component_of(Vector2i(8,21))
	var bounds: Rect2i=graph._small_component_bounds(Vector2i(8,21),wanted)
	check(bounds.has_point(Vector2i(8,21)) and not bounds.has_point(Vector2i(200,200)),"complete small component gets a conservative bound")
	wanted=graph.component_of(Vector2i(180,180))
	check(not graph._small_component_bounds(Vector2i(180,180),wanted).has_area(),"large component keeps the full search")
	for y in range(8,36):
		for x in range(0,24):compare(graph,Vector2(4,10.5),Vector2(x,y)*0.5+Vector2(.249,.251),0.0)
	print("NAV_RELOCATION_BOUNDS ",checks," checks ",failures," failures; fast_us=",fast_us," full_us=",full_us)
	FileAccess.open("user://nav-relocation-bounds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"comparisons":comparisons,"fast_us":fast_us,"full_us":full_us},"  "))
	get_tree().quit(1 if failures else 0)
