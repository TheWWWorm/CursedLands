extends Node
const Blocks=preload("res://src/game/nav_blocks.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<15:printerr("FAIL ",label)
func _ready()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=5983125
	for directed in [false,true]:
		var nav:=NavGrid.new();nav.size=Vector2i(128,96);var n:=nav.size.x*nav.size.y
		var layer:=NavGrid.Layer.new();layer.cls=3;layer.land.resize(n);layer.cost.resize(n);nav._hq.resize(n)
		var slopes:=PackedInt32Array();slopes.resize(2049)
		for i in slopes.size():
			var dh:=i-1023;slopes[i]=1024+maxi(dh,0)*7 if absi(dh)<=5 and (not directed or dh<=1) else -1
		nav._slope_tab=[slopes,slopes];nav._layers[3]=layer
		for i in n:
			layer.land[i]=int(rng.randf()<0.12);layer.cost[i]=NavGrid.STEP_COST[rng.randi_range(1,NavGrid.STEP_COST.size()-1)]
			nav._hq[i]=rng.randi_range(-3,3)
		var cached=Blocks.new(nav,layer)
		for edit in 7:
			var fresh=Blocks.new(nav,layer)
			for y in cached.size.y:
				for x in cached.size.x:
					var at:=Vector2i(x,y)
					check(cached.representative(at)==fresh.representative(at),"representative after edit")
					check(cached._connections(at)==fresh._connections(at),"connections after edit")
					check(cached._raw(at)==fresh._raw(at),"weighted edges after edit")
					check(cached.component(at)==fresh.component(at),"component after edit")
			for query in 12:
				var a:=Vector2i(rng.randi_range(0,nav.size.x-1),rng.randi_range(0,nav.size.y-1))
				var b:=Vector2i(rng.randi_range(0,nav.size.x-1),rng.randi_range(0,nav.size.y-1))
				check(cached.route(a,b)==fresh.route(a,b),"complete block route after edit")
				check(cached._topology_seeds(a,false)==fresh._topology_seeds(a,false),"endpoint seeds after edit")
			var p:=Vector2i(rng.randi_range(0,nav.size.x-5),rng.randi_range(0,nav.size.y-5));var rect:=Rect2i(p,Vector2i(5,5))
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x):
					var i:=y*nav.size.x+x;layer.land[i]=1-layer.land[i]
					layer.cost[i]=NavGrid.STEP_COST[rng.randi_range(1,NavGrid.STEP_COST.size()-1)];nav._hq[i]=rng.randi_range(-3,3)
			check(cached.update_region(rect),"incremental native update available")
	print("NAV_DYNAMIC_TOPOLOGY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
