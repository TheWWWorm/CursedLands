extends Node
var checks := 0
var failures := 0
var native_us := 0
var script_us := 0
var changed := 0
var finite := 0

class TestGrid extends NavGrid:
	var stamps := PackedInt32Array()
	func _stamp_window(rect: Rect2i) -> PackedInt32Array:
		var out := PackedInt32Array()
		out.resize(rect.size.x * rect.size.y)
		for y in rect.size.y:
			for x in rect.size.x:
				out[y*rect.size.x+x] = stamps[(rect.position.y+y)*size.x+rect.position.x+x]
		return out

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ",label)

func compare(nav: TestGrid, cells: PackedInt32Array, facing: float, end: Vector2, flat: bool) -> void:
	var layer := nav.layer(3)
	var context := NavTurn.native_context(nav,layer,flat)
	var before := Time.get_ticks_usec()
	var got: Dictionary = NavTurn.native_kernel().refine(context,cells,NavTurn.heading(facing),NavTurn.end_cost(end),nav._stamp_window)
	native_us += Time.get_ticks_usec()-before
	before = Time.get_ticks_usec()
	var want := NavTurn.refine_script(nav,layer,cells,facing,end,flat)
	script_us += Time.get_ticks_usec()-before
	check(not got.is_empty(),"native path actually ran")
	check(got == want,"cells/cost equal: %s heading %s flat %s native %s script %s" % [cells,facing,flat,got,want])
	check(NavTurn.refine(nav,layer,cells,facing,end,flat) == want,"public integration")
	changed += int(want.cells != cells)
	finite += int(want.cost < NavTurn.LIMIT)

func _ready() -> void:
	check(NavTurn.native_kernel() != null,"compiled turn kernel available")
	if failures:
		get_tree().quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 850091
	var nav := TestGrid.new()
	nav.size = Vector2i(32,32)
	nav._hq.resize(1024); nav.stamps.resize(1024)
	var layer := NavGrid.Layer.new()
	layer.cls = 3; layer.land.resize(1024); layer.cost.resize(1024)
	nav._layers[3] = layer
	var slopes := PackedInt32Array()
	slopes.resize(2049)
	slopes.fill(1024)
	nav._slope_tab = [slopes,slopes]
	layer.cost.fill(2048)
	# These costs and lengths were captured from the original x86 turn pass.
	for sample: Array in [
		[[Vector2i(3,6),Vector2i(4,6),Vector2i(5,6),Vector2i(6,6)],6144,4],
		[[Vector2i(3,6),Vector2i(4,6),Vector2i(4,7),Vector2i(5,7)],4338,3],
		[[Vector2i(3,6),Vector2i(4,6),Vector2i(5,7),Vector2i(6,7),Vector2i(7,8),Vector2i(8,8)],10966,6]]:
		var cells := PackedInt32Array()
		for p: Vector2i in sample[0]: cells.append(p.y*32+p.x)
		var got := NavTurn.refine(nav,layer,cells,0.0,NavGrid.center(sample[0][-1]),false)
		check(got.cost == sample[1] and got.cells.size() == sample[2],"original turn cost and length")
	layer.cost.fill(1024)
	# Every pair of direction templates, including reversals and equal-cost
	# ties; eight initial headings and different subcell endpoints.
	for prev in range(1,9):
		for next in range(1,9):
			var p := Vector2i(15,15)
			var q := p + Vector2i(NavTurn.DX[prev],NavTurn.DY[prev])
			var t := q + Vector2i(NavTurn.DX[next],NavTurn.DY[next])
			var cells := PackedInt32Array([p.y*32+p.x,q.y*32+q.x,t.y*32+t.x])
			for heading in 8:
				compare(nav,cells,heading*PI/4.0,Vector2(t)*0.5+Vector2(heading/16.0,.2),false)
	for trial in 420:
		for i in 1024:
			layer.land[i] = int(rng.randf() < (.02 if trial % 3 else .15))
			layer.cost[i] = NavGrid.STEP_COST[rng.randi_range(1,15)] if trial % 2 else 1024
			nav._hq[i] = rng.randi_range(-4,4) if trial % 4 == 0 else 0
			nav.stamps[i] = rng.randi_range(0,100) if trial % 3 == 0 else 0
		for i in slopes.size():
			var dh := i-1023
			slopes[i] = 1024+maxi(dh,0)*15 if absi(dh)<=5 and (trial % 4 != 0 or dh<=2) else -1
		nav._slope_tab = [slopes,slopes]
		nav._ctx_thr = rng.randi_range(10,55)
		var p := Vector2i(rng.randi_range(0,31),rng.randi_range(0,31))
		var cells := PackedInt32Array([p.y*32+p.x])
		for step in rng.randi_range(3,60):
			var k := rng.randi_range(1,8)
			p = (p + Vector2i(NavTurn.DX[k],NavTurn.DY[k])).clamp(Vector2i.ZERO,Vector2i(31,31))
			if p.y*32+p.x != cells[-1]: cells.append(p.y*32+p.x)
		var end := Vector2(p)*0.5+Vector2(rng.randf_range(-.4,.4),rng.randf_range(-.4,.4))
		compare(nav,cells,rng.randf_range(-20,20),end,trial % 2 == 0)
	check(changed > 300,"path-improving iterations exercised")
	check(finite > 500,"finite successful refinements exercised")
	# Real maps are much larger than a route's local rectangle. Shared map
	# arrays must remain read-only instead of copying megabytes on each path.
	var large := TestGrid.new()
	large.size = Vector2i(1536,1024)
	var count := large.size.x*large.size.y
	large._hq.resize(count); large.stamps.resize(count)
	var large_layer := NavGrid.Layer.new()
	large_layer.cls = 3; large_layer.land.resize(count); large_layer.cost.resize(count)
	large_layer.cost.fill(2048)
	large._layers[3] = large_layer
	slopes.fill(1024); large._slope_tab = [slopes,slopes]
	var native_before := native_us
	var script_before := script_us
	for trial in 64:
		var p := Vector2i(1100,750)
		var cells := PackedInt32Array([p.y*large.size.x+p.x])
		for i in 20:
			p += Vector2i(1,i%2)
			cells.append(p.y*large.size.x+p.x)
		compare(large,cells,trial*PI/4.0,NavGrid.center(p),false)
	var large_native := native_us-native_before
	var large_script := script_us-script_before
	for cells in [PackedInt32Array(),PackedInt32Array([1]),PackedInt32Array([1,2])]:
		check(NavTurn.refine(nav,layer,cells,0.0,Vector2.ZERO,false) == {"cells":cells,"cost":0},"short path unchanged")
	print("NAV_TURN_NATIVE ",JSON.stringify({"checks":checks,"failures":failures,"changed":changed,"finite":finite,"native_us":native_us,"script_us":script_us,"large_native_us":large_native,"large_script_us":large_script}))
	get_tree().quit(1 if failures else 0)
