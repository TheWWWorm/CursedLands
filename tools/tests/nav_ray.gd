extends Node
## Exact differential coverage of the live dispatcher against its retained
## script oracle, including half-cell ties and edits to doors/floor spans.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ", label)

func compare(nav: NavGrid, a: Vector2, za: float, b: Vector2, zb: float) -> void:
	var expected := nav.ray_script(a, za, b, zb)
	var actual := nav.ray(a, za, b, zb)
	check(actual == expected, "ray %s/%s -> %s/%s: %s != %s" % [a, za, b, zb, actual, expected])

func _ready() -> void:
	var nav := NavGrid.new()
	compare(nav, Vector2.ZERO, 0, Vector2.ONE, 2)
	check(nav._ray_kernel != null, "native dispatcher is installed")
	if nav._ray_kernel == null: get_tree().quit(1); return
	var rng := RandomNumberGenerator.new(); rng.seed = 127934
	nav.size = Vector2i(128,128)
	nav._h.resize(128*128)
	for scene in 4:
		nav._alt = [1.0, 3.7, 511.0/32.0, 51.1][scene]
		for i in nav._h.size(): nav._h[i] = rng.randf_range(-2, 4) if scene % 2 else 0.0
		nav._spans.clear()
		for i in 1800:
			var at := rng.randi_range(0,nav._h.size()-1)
			nav._spans[at] = [[-3, 120, 2, 9], [20, 80, scene % 3, 10]]
		for i in 3000:
			var a := Vector2(rng.randf_range(-1,65),rng.randf_range(-1,65))
			var b := Vector2(rng.randf_range(-1,65),rng.randf_range(-1,65))
			compare(nav,a,rng.randf_range(-2,12),b,rng.randf_range(-2,12))
		# These exact boundaries alternate their nearest-even cell choice.
		for x in range(-2,132):
			for epsilon: float in [-0.000001,0.0,0.000001]:
				var a := Vector2(float(x)*.5+epsilon,12.0)
				compare(nav,a,5,Vector2(45.0,12.0),5)
				compare(nav,Vector2(45.0,12.0),5,a,5)
				compare(nav,a,5,a,5)
	nav._h.fill(0.0); nav._spans.clear(); nav._alt=10.0
	var a := Vector2(2.25,8.25); var b := Vector2(50.25,8.25)
	var key := 16*128+40
	compare(nav,a,4,b,4)
	nav._spans[key]=[[0,80,0,1]]
	check(nav.ray(a,4,b,4)==0.0001,"adding a closed door applies immediately")
	nav._spans[key]=[[0,80,2,1],[0,80,2,2]]
	compare(nav,a,4,b,4)
	check(nav.ray(a,4,b,4)==0.99*0.99,"overlapping crowns retain multiplication order")
	nav._spans.erase(key)
	check(nav.ray(a,4,b,4)==1.0,"opening/removing a door applies immediately")
	nav._h[key]=4.0
	check(nav.ray(a,4,b,4)==0.0,"raised floor applies immediately")
	nav._h[key]=0.0
	check(nav.ray(a,4,b,4)==1.0,"lowering the floor applies immediately")
	# A near-maximum map diagonal exercises long clear rays without a cache.
	nav.size=Vector2i(1024,1024); nav._h.resize(1024*1024); nav._h.fill(0)
	var queries := []
	for i in 1000:
		queries.append([Vector2(rng.randf_range(1,511),rng.randf_range(1,511)), Vector2(rng.randf_range(1,511),rng.randf_range(1,511))])
	var expected := []; var started := Time.get_ticks_usec()
	for q: Array in queries: expected.append(nav.ray_script(q[0],5,q[1],6))
	var script_us := Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for i in queries.size(): check(nav.ray(queries[i][0],5,queries[i][1],6)==expected[i],"long clear ray "+str(i))
	var native_us := Time.get_ticks_usec()-started
	var native := nav._ray_kernel; nav._ray_kernel=null
	compare(nav,Vector2.ONE,5,Vector2(500,500),6)
	check(nav.ray(Vector2.ONE,5,Vector2(500,500),6)==1.0,"script-only fallback remains available")
	nav._ray_kernel=native
	print("NAV_RAY ",JSON.stringify({"checks":checks,"failures":failures,"long_script_us":script_us,"long_native_us":native_us}))
	get_tree().quit(1 if failures else 0)
