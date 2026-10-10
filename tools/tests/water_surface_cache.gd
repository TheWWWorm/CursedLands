extends "water_interaction.gd"
## Exact-result checks against the pre-cache query, plus isolated ABBA timings.
const Reference = preload("water_surface_cache_reference.gd")
const Optimized = preload("res://src/game/fx/water_surface.gd")

func candidate(terrain: EITerrain) -> RefCounted:
	return Optimized.new(terrain)

func payload(surface: RefCounted) -> int:
	var bytes := 0
	for record: Dictionary in surface._sectors.values():
		for key: String in ["triangle_ready","triangle_points","triangle_edges","triangle_heights","triangle_det"]:
			if record.has(key):
				bytes += record[key].size() if key == "triangle_ready" else record[key].to_byte_array().size()
	return bytes

func compare(surfaces: Array, points: PackedVector2Array, label: String) -> Array:
	var durations := []; var reference := PackedByteArray(); var hits := 0
	for i in surfaces.size():
		var results := []; var surface: RefCounted = surfaces[i]
		var start := Time.get_ticks_usec()
		for point: Vector2 in points: results.append(surface.sample(point))
		durations.append(Time.get_ticks_usec()-start)
		if i == 0:
			reference = var_to_bytes(results)
			for result: Dictionary in results: hits += int(not result.is_empty())
		else:
			check(var_to_bytes(results) == reference,label+" exact heights/slopes/owners arm "+str(i))
		check(surface._sectors.size() <= Surface.CACHE_SECTORS,label+" sector cache stays bounded")
	rows.append({"case":label,"query_us_abba":durations,"queries":points.size(),"hits":hits,
		"extra_packed_bytes":payload(surfaces[1]),"cache_sectors":surfaces[1]._sectors.size()})
	return durations

func begin(surfaces: Array, deformed: bool, cache_mean := true) -> void:
	for i in surfaces.size():
		if i in [1,2]: surfaces[i].begin_frame(deformed,cache_mean)
		else: surfaces[i].begin_frame(deformed)

func mesh_fixture() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(1.03,1.137,-1.17),Vector3(3.18,2.27,-1.08),Vector3(1.12,3.319,-3.24),
		Vector3(1,0.9,-1),Vector3(3,0.9,-1),Vector3(1,0.9,-3),
		Vector3(1,4,-1),Vector3(3,4,-1),Vector3(1,4,-3),
		Vector3(1,4,-1),Vector3(3,4,-1),Vector3(1,4,-3),
		Vector3(8,15,-8),Vector3(8.00001,17,-8),Vector3(8,16,-8.00001),
		Vector3(9,5,-9),Vector3(9.0002,7,-9),Vector3(9,6,-9.0002),
		Vector3(12,1.137,-12),Vector3(14,2.27,-12),Vector3(12,3.319,-14),
		Vector3(20,2,-20),Vector3(23,3,-20),Vector3(20,4,-23),
		Vector3(31,2,-1),Vector3(32,3,-1),Vector3(31,4,-3)])
	var uv := PackedVector2Array(); var indices := PackedInt32Array()
	for i in vertices.size():
		uv.append(Vector2(0,[0,1,2,3,0,0,0,65,4][i/3])); indices.append(i)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV2] = uv; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func synthetic() -> void:
	var terrain := EITerrain.new(); terrain.sectors_x = 20; terrain.sectors_y = 1
	terrain.materials = [{"type":2,"wave":0.9},{"type":3,"wave":0.7},{"type":4,"wave":0.5},
		{"type":2,"wave":0.0},{"type":4,"wave":1.0}]
	terrain._lava.resize(64); terrain.visible = false; add_child(terrain); terrain.set_process(false)
	var mesh := mesh_fixture()
	for sx in 20:
		var node := MeshInstance3D.new(); node.name = "Water_%d_0" % sx
		node.mesh = mesh; node.position.x = sx*32; terrain.add_child(node)
	var points := PackedVector2Array([Vector2(1.5,-1.5),Vector2(4,-4),Vector2(-0.2,-0.2),
		Vector2(8,-8),Vector2(9.00005,-9.00005),Vector2(12,-12),Vector2(14,-12),
		Vector2(11.999998,-12.1),Vector2(11.999996,-12.1),Vector2(13,-13.000002),
		Vector2(20.5,-20.5),Vector2(31.5,-1.5),Vector2(32,-1),Vector2(INF,0),Vector2(NAN,0)])
	var rng := RandomNumberGenerator.new(); rng.seed = 73812
	for i in 256: points.append(Vector2(rng.randf_range(0,32),-rng.randf_range(0,32)))
	var surfaces := [Reference.new(terrain),candidate(terrain),candidate(terrain),Reference.new(terrain)]
	begin(surfaces,false); compare(surfaces,points,"synthetic/mean-cold")
	check(surfaces[1].sample(points[0]).material == 2,"first owner wins equal-height overlap")
	check(surfaces[1].sample(points[0]).height == 4.0,"highest containing triangle wins")
	compare(surfaces,points,"synthetic/mean-repeat")
	terrain._lava[2] = 1.0; compare(surfaces,points,"synthetic/live-lava")
	check(surfaces[1].sample(points[0]).lava,"cached triangle keeps live lava flags")
	terrain._lava[2] = 0.0; terrain.water_offsets[2] = 0.75
	compare(surfaces,points,"synthetic/same-frame-offset")
	begin(surfaces,false); compare(surfaces,points,"synthetic/next-frame-offset")
	check(surfaces[1].sample(points[0]).height == 4.75,"new frame refreshes cached geometry")
	begin(surfaces,true); compare(surfaces,points,"synthetic/posed")
	terrain._waves.advance(7.37); begin(surfaces,true); compare(surfaces,points,"synthetic/posed-moved")
	begin(surfaces,false); compare(surfaces,points,"synthetic/back-to-mean")
	begin(surfaces,false,false); compare(surfaces,points,"synthetic/cache-disabled")
	terrain.water_offsets[0] = 0.1137
	begin(surfaces,false); compare(surfaces,points,"synthetic/cache-reenabled")
	var node := terrain.get_node("Water_0_0") as MeshInstance3D
	node.scale = Vector3(0.8,1.1,0.9); node.position = Vector3(0.25,0.375,-0.125)
	begin(surfaces,false); compare(surfaces,points,"synthetic/node-transform")
	terrain.position = Vector3(-17,3,12); terrain.scale = Vector3(1.1,1.2,0.9)
	var shifted := PackedVector2Array()
	for point: Vector2 in points:
		if not point.is_finite(): shifted.append(point); continue
		var world := terrain.to_global(Vector3(point.x,0,point.y)); shifted.append(Vector2(world.x,world.z))
	begin(surfaces,false); compare(surfaces,shifted,"synthetic/terrain-transform")
	var arrays := mesh.surface_get_arrays(0); arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	var replacement := ArrayMesh.new(); replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	node.mesh = replacement; compare(surfaces,shifted,"synthetic/mesh-replaced-without-frame")
	node.mesh = null; compare(surfaces,shifted,"synthetic/mesh-removed")
	node.free(); compare(surfaces,shifted,"synthetic/node-freed")
	node = MeshInstance3D.new(); node.name = "Water_0_0"; node.mesh = mesh; terrain.add_child(node)
	compare(surfaces,shifted,"synthetic/node-recreated")
	terrain.transform = Transform3D.IDENTITY; begin(surfaces,false)
	var distant := PackedVector2Array()
	for sx in 20: distant.append(Vector2(sx*32+1.5,-1.5))
	compare(surfaces,distant,"synthetic/eviction")
	check(surfaces[1]._sectors.size() == Surface.CACHE_SECTORS,"LRU reaches its exact sector limit")
	check(not surfaces[1]._sectors.has(Vector2i.ZERO),"oldest sector evicted")
	compare(surfaces,points,"synthetic/revisit-evicted")
	for surface: RefCounted in surfaces:
		surface.clear(); check(surface._sectors.is_empty(),"clear releases all triangle storage")
	begin(surfaces,true); compare(surfaces,points,"synthetic/posed-only-after-clear")
	check(payload(surfaces[1]) == 0,"posed-only query never allocates triangle payload")
	terrain.free()
	for surface: RefCounted in surfaces: check(surface.sample(Vector2.ZERO).is_empty(),"freed terrain remains safe")

func map_case(name: String) -> void:
	var terrain := EITerrain.load_map(name); terrain.visible = false; add_child(terrain); terrain.set_process(false)
	var p := centre(terrain); check(p.is_finite(),name+" has exposed water")
	var points := PackedVector2Array()
	for y in 32:
		for x in 32: points.append(Vector2(p.x,p.z)+Vector2(x-15.25,y-15.75))
	for deformed: bool in [false,true]:
		var surfaces := [Reference.new(terrain),candidate(terrain),candidate(terrain),Reference.new(terrain)]
		var mode := "posed" if deformed else "mean"
		begin(surfaces,deformed); compare(surfaces,points,name+"/"+mode+"/cold")
		compare(surfaces,points,name+"/"+mode+"/repeat")
		terrain._waves.advance(0.137); begin(surfaces,deformed)
		compare(surfaces,points,name+"/"+mode+"/next-frame")
		if deformed: check(payload(surfaces[1]) == 0,name+" posed path allocates no triangle payload")
		for surface: RefCounted in surfaces: surface.clear()
	# The option may disable waves even when the consumer asks for posed water.
	terrain._water_mat.set_shader_parameter("waves",0.0)
	var surfaces := [Reference.new(terrain),candidate(terrain),candidate(terrain),Reference.new(terrain)]
	begin(surfaces,true,false); compare(surfaces,points,name+"/waves-off/default")
	check(payload(surfaces[1]) == 0,name+" default query allocates no triangles with waves disabled")
	begin(surfaces,true); compare(surfaces,points,name+"/waves-off/cold")
	terrain._water_mat.set_shader_parameter("waves",1.0); begin(surfaces,true)
	compare(surfaces,points,name+"/waves-reenabled")
	terrain.free(); await get_tree().process_frame
	print("SURFACE_CACHE_MAP ",name)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_water":1,"auto_graphics":0,"confine_mouse":0,"vsync":0},true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120; process_mode = Node.PROCESS_MODE_ALWAYS
	synthetic()
	for name: String in ["zone1","zone11","zone8"]: await map_case(name)
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://surface-cache.json",FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":rows,"platform":OS.get_name(),
		"scope":"CPU query batch timing, excluding constructors and comparisons; no FPS claim."},"\t"))
	print("SURFACE_CACHE_DONE checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
