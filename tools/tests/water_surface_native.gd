extends "water_surface_cache.gd"
## Mean-query native/fallback parity, ownership and unusual geometry. Reuses
## authored maps, cache invalidation and posed-query controls from the base.

func expected_native() -> bool:
	return ClassDB.class_exists(&"WaterSurfaceKernel") and not "--ei-script-water-surface" in OS.get_cmdline_user_args()

func payload(surface: RefCounted) -> int:
	var bytes := super.payload(surface)
	for record: Dictionary in surface._sectors.values():
		if record.get("mean_kernel") != null: bytes += record.mean_kernel.cache_bytes()
	return bytes

func compare(surfaces: Array, points: PackedVector2Array, label: String) -> Array:
	var times := super.compare(surfaces,points,label)
	if surfaces[1]._cache_mean and rows.back().hits > 0:
		check(surfaces[1]._native_mean == expected_native(),"selected mean path "+label)
		var owners := 0
		for record: Dictionary in surfaces[1]._sectors.values():
			owners += int(record.get("mean_kernel") != null)
			if expected_native(): check(not record.has("triangle_ready"),"native path avoids script triangle payload "+label)
		check((owners > 0) == expected_native(),"actual sector owner path "+label)
	return times

func native_contracts() -> void:
	if not ClassDB.class_exists(&"WaterSurfaceKernel"): return
	var terrain := EITerrain.new(); terrain.materials = [{"wave":0.0}]
	terrain._lava.resize(64)
	for owner in 64: terrain.water_offsets[owner] = (owner-32)*0.113719
	var reference := candidate(terrain); reference._native_mean = false
	var kernel: RefCounted = ClassDB.instantiate(&"WaterSurfaceKernel")
	var rng := RandomNumberGenerator.new(); rng.seed = 567813
	var vertices := PackedVector3Array(); var uv2 := PackedVector2Array(); var indices := PackedInt32Array()
	for triangle in 72:
		var anchor := Vector3(rng.randf_range(-16,16),rng.randf_range(-8,8),rng.randf_range(-16,16))
		var edge := 0.0001 if triangle%9 == 0 else rng.randf_range(0.2,8)
		for j in 3:
			vertices.append(anchor+Vector3(edge if j==1 else 0,rng.randf_range(-2,2),-edge if j==2 else 0))
			uv2.append(Vector2(0,[-65.6,-0.75,-0.5,0.49,63.5,64.5,127.0,4095.0][(triangle+j)%8]))
			indices.append(indices.size())
	# Include reversed winding, exact degeneracy and shared vertices.
	indices.append_array(PackedInt32Array([0,2,1,3,3,4,0,4,8]))
	check(kernel.initialize(vertices,indices,uv2),"native accepts finite authored ownership and indexed triangles")
	var bucket := PackedInt32Array()
	for at in range(0,indices.size(),3): bucket.append(at)
	var record := {"vertices":vertices,"indices":indices,"uv2":uv2,"frame":-1,
		"posed":PackedVector3Array(),"ready":PackedByteArray(),"buckets":{Vector2i.ZERO:bucket}}
	record.posed.resize(vertices.size()); record.ready.resize(vertices.size())
	var transforms := [Transform3D.IDENTITY,
		Transform3D(Basis.from_euler(Vector3(0.2,0.31,-0.17)).scaled(Vector3(0.8,1.17,0.9)),Vector3(7.375,-2.25,12.125)),
		Transform3D(Basis.from_euler(Vector3(-0.2,1.37,0.1)).scaled(Vector3(-1.2,0.7,1.4)),Vector3(-21.25,4.75,-3.375))]
	var total_queries := 0; var total_hits := 0
	for xf: Transform3D in transforms:
		var points := PackedVector2Array()
		for at in range(0,vertices.size(),3):
			var a := xf*vertices[at]; var b := xf*vertices[at+1]; var c := xf*vertices[at+2]
			for p: Vector3 in [a,b,c,(a+b+c)/3.0,(a+b)*0.5]: points.append(Vector2(p.x,p.z))
		for i in 32: points.append(Vector2(rng.randf_range(-40,40),rng.randf_range(-40,40)))
		for state in 3:
			if state != 1: reference.begin_frame(false,true)
			# Same-frame levels/transform must retain already prepared vertices;
			# liquid flags are live, and the following frame refreshes geometry.
			terrain.water_offsets[0] = float(state)*0.375
			terrain._lava[63] = float(state%2)
			var transform := xf.translated(Vector3(0.125,0.37,-0.125)) if state==1 else xf
			var expected := []; var actual := []
			for point: Vector2 in points:
				expected.append(reference._sample_mean(record,transform,point,Vector2i.ZERO,{}))
				actual.append(kernel.sample_mean(point,transform,bucket,terrain.water_offsets,terrain._lava,reference._frame,{}))
				if not expected.back().is_empty(): total_hits += 1
			check(var_to_bytes(actual)==var_to_bytes(expected),"exact randomized edge/transform/epoch results "+str(transforms.find(xf))+"/"+str(state))
			total_queries += points.size()
	check(total_hits > 1000,"randomized cases include substantial positive coverage")
	var best := {"height":1e9,"marker":"caller-owned"}; var held := best.duplicate()
	check(kernel.sample_mean(Vector2.ZERO,Transform3D.IDENTITY,bucket,{},terrain._lava,999,best)==held and best==held,"losing triangles preserve the caller result")
	for bad: PackedInt32Array in [PackedInt32Array([-3]),PackedInt32Array([1]),PackedInt32Array([indices.size()])]:
		check(kernel.sample_mean(Vector2.ZERO,Transform3D.IDENTITY,bad,{},terrain._lava,1000,best)==held,"invalid bucket returns the original result")
	for point: Vector2 in [Vector2(NAN,0),Vector2(0,INF)]:
		check(kernel.sample_mean(point,Transform3D.IDENTITY,bucket,{},terrain._lava,1000,best)==held,"nonfinite point is safe")
	var bad_uv := uv2.duplicate()
	for value: float in [NAN,INF,1e20,-1e20]:
		bad_uv[0] = Vector2(0,value)
		check(not kernel.initialize(vertices,indices,bad_uv),"nonrepresentable owner rejected")
	check(not kernel.initialize(vertices,PackedInt32Array([0,1]),uv2),"incomplete triangle rejected")
	check(not kernel.initialize(vertices,PackedInt32Array([0,1,vertices.size()]),uv2),"invalid vertex index rejected")
	check(not kernel.initialize(vertices,indices,PackedVector2Array()),"missing owners rejected")
	reference.begin_frame(false,true)
	var centre := (vertices[3]+vertices[4]+vertices[5])/3.0
	var probe := Vector2(centre.x,centre.z)
	check(not reference._sample_mean(record,Transform3D.IDENTITY,probe,Vector2i.ZERO,{}).is_empty(),"preserved snapshot probe has water")
	check(var_to_bytes(kernel.sample_mean(probe,Transform3D.IDENTITY,bucket,terrain.water_offsets,terrain._lava,reference._frame,{})) ==
		var_to_bytes(reference._sample_mean(record,Transform3D.IDENTITY,probe,Vector2i.ZERO,{})),"rejected initialization preserves previous snapshot")
	var weak := weakref(kernel); kernel = null
	check(weak.get_ref()==null,"native owner releases independently")
	rows.append({"case":"native-contracts","queries":total_queries,"hits":total_hits})
	terrain.free()

func _ready() -> void:
	native_contracts()
	native_lifetime()
	await super._ready()

func native_lifetime() -> void:
	if not expected_native(): return
	var terrain := EITerrain.new(); terrain.sectors_x = 20; terrain.sectors_y = 1
	terrain.materials = [{"wave":0.0}]; add_child(terrain); terrain.set_process(false)
	var mesh := mesh_fixture()
	for sx in 20:
		var node := MeshInstance3D.new(); node.name = "Water_%d_0" % sx
		node.mesh = mesh; node.position.x = sx*32; terrain.add_child(node)
	var surface := candidate(terrain); surface.begin_frame(false,true)
	var owners := []
	for sx in 20:
		check(not surface.sample(Vector2(sx*32+1.5,-1.5)).is_empty(),"native lifetime visits water sector")
		owners.append(weakref(surface._sectors[Vector2i(sx,0)].mean_kernel))
	check(surface._sectors.size()==16,"native owners use existing LRU limit")
	for sx in 4: check(owners[sx].get_ref()==null,"eviction releases native sector")
	surface.clear()
	for owner: WeakRef in owners: check(owner.get_ref()==null,"clear releases remaining native sectors")
	surface.sample(Vector2(1.5,-1.5))
	var previous := weakref(surface._sectors[Vector2i.ZERO].mean_kernel)
	var node := terrain.get_node("Water_0_0") as MeshInstance3D
	node.mesh = mesh_fixture(); surface.sample(Vector2(1.5,-1.5))
	check(previous.get_ref()==null,"mesh replacement releases native snapshot")
	previous = weakref(surface._sectors[Vector2i.ZERO].mean_kernel)
	surface = null
	check(previous.get_ref()==null,"surface retirement releases native snapshot")
	terrain.free()
