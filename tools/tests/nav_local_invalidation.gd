extends "nav_topology.gd"
## Work bounds, independent of machine timing, on fully prepared native maps.
func _ready()->void:
	for dimensions:Vector2i in [Vector2i(128,128),Vector2i(512,512)]:
		var nav:=NavGrid.new();nav.size=dimensions
		var l:=NavGrid.Layer.new();l.cls=3
		var n:=dimensions.x*dimensions.y;l.land.resize(n);l.cost.resize(n);l.cost.fill(1024)
		nav._hq.resize(n);nav._layers[3]=l
		var slope:=PackedInt32Array();slope.resize(2049);slope.fill(-1);slope[1023]=1024;nav._slope_tab=[slope,slope]
		var graph=Blocks.new(nav,l)
		var points:Array[Vector2i]=[dimensions/2]
		graph._terrain_kernel.prepare_routes(points)
		for at in [Vector2i.ZERO,Vector2i(8,8),dimensions/2,dimensions-Vector2i(2,2)]:
			var rect:=Rect2i(at,Vector2i(2,2))
			for p in [at,at+Vector2i.ONE]:l.land[p.y*dimensions.x+p.x]=1-l.land[p.y*dimensions.x+p.x]
			check(graph.update_region(rect),"local update succeeds")
			var stats:Dictionary=graph._terrain_kernel.topology_stats()
			check(int(stats.get("update_blocks_visited",-1)) in range(1,65),"local edit visits at most 64 block anchors regardless of map size")
			check(int(stats.get("update_labels_probed",-1)) in range(1,129),"local edit probes at most 128 label windows")
			var fresh=Blocks.new(nav,l)
			for delta in [Vector2i.ZERO,Vector2i(-1,-1),Vector2i(1,1),Vector2i(2,0)]:
				var b:Vector2i=(at/8+delta).clamp(Vector2i.ZERO,dimensions/8-Vector2i.ONE)
				check(graph.representative(b)==fresh.representative(b),"representative remains exact")
				check(graph._connections(b)==fresh._connections(b),"connections remain exact")
				check(graph._raw(b)==fresh._raw(b),"weighted routes remain exact")
	print("NAV_LOCAL_INVALIDATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
