extends Node
## Compare worker geometry with the original tessellation/assembly, including
## reused dense tiles, concurrent snapshots and map/option lifetime changes.
var checks := 0
var failures := 0
const FIELDS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]

class Capture extends SoftGroundDeform:
	var result: Array
	func _apply_mesh(_rec: Dictionary, arrays: Array, shadow: Array) -> void:
		result = [arrays, shadow]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ", label)

func fixture() -> Array:
	var source := []; source.resize(Mesh.ARRAY_MAX)
	for f in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]: source[f] = PackedVector3Array()
	for f in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]: source[f] = PackedVector2Array()
	source[Mesh.ARRAY_COLOR] = PackedColorArray()
	source[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var rng := RandomNumberGenerator.new(); rng.seed = 4815702
	for tile in 256:
		var base: int = source[0].size()
		for y in 3:
			for x in 3:
				source[0].append(Vector3((tile % 16) * 2 + x + rng.randf() * 0.1, rng.randf() * 20, -int(tile / 16) * 2 - y))
				source[1].append(Vector3(rng.randf(), 1, rng.randf()).normalized())
				source[4].append(Vector2(x, y) * 0.5)
				source[5].append(Vector2(rng.randi_range(0, 4096), tile))
				source[3].append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		for y in 2:
			for x in 2:
				var a := base + y * 3 + x
				source[12].append_array([a + 3, a + 1, a, a + 1, a + 3, a + 4])
	return source

func tile_reference(source: Array, tile: int) -> Array:
	var dense := []; dense.resize(Mesh.ARRAY_MAX)
	for f in FIELDS: dense[f] = source[f].slice(0, 0)
	var ids := PackedInt32Array()
	var original: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	for triangle in 8:
		var at := tile * 24 + triangle * 3
		SoftGroundDeform._subdivide(dense, ids, source, original[at], original[at + 1], original[at + 2])
	dense[Mesh.ARRAY_INDEX] = ids
	return dense

func equal_arrays(actual: Array, expected: Array, label: String) -> void:
	check(actual.size() == Mesh.ARRAY_MAX, label + " complete layout")
	for field in Mesh.ARRAY_MAX:
		check(actual[field] == expected[field], label + " exact attribute/index " + str(field))

func drain(soft: SoftGroundDeform) -> void:
	for i in 5:
		soft._process(0)
		soft._finish_mesh_jobs(true)
	check(soft._mesh_jobs.is_empty() and soft._queue.is_empty(), "all queued work joined")

func mark(soft: SoftGroundDeform, p := Vector2(8, 8)) -> void:
	soft._add_mark({"p":p, "extent":Vector2(0.12, 0.2), "angle":0.3, "time":soft._age})

func _ready() -> void:
	check(ClassDB.class_exists("SoftGroundMeshJob"), "native worker available")
	if failures:
		get_tree().quit(1); return
	var source := fixture()
	var original := source.duplicate(true)
	var reference := Capture.new()
	var native_us := 0
	var script_us := 0
	var cache := {}
	for count in [0, 1, 2, 8, 32, 64, 128]:
		var tiles := {}
		for i in count:
			var id: int = (i * 73 + 19) % 256
			tiles[id] = cache.get(id) if i % 2 == 0 else null
		var job: Object = ClassDB.instantiate("SoftGroundMeshJob")
		check(job.configure(source, tiles), "bounded sector accepted " + str(count))
		var start := Time.get_ticks_usec()
		job.run()
		native_us += Time.get_ticks_usec() - start
		var result: Array = job.read_result()
		start = Time.get_ticks_usec()
		for id: int in tiles:
			if tiles[id] == null: tiles[id] = tile_reference(source, id)
			cache[id] = tiles[id]
		reference._rebuild({"arrays":source, "tiles":tiles})
		script_us += Time.get_ticks_usec() - start
		equal_arrays(result[0], reference.result[0], "surface " + str(count))
		equal_arrays(result[1], reference.result[1], "shadow " + str(count))
		for id: int in result[2]: equal_arrays(result[2][id], tiles[id], "new tile " + str(id))
	check(source == original, "shared source never mutated")
	var jobs := []
	for i in 16:
		var tiles := {i:null, 255-i:cache.values()[0]}
		var job: Object = ClassDB.instantiate("SoftGroundMeshJob")
		check(job.configure(source, tiles), "concurrent job accepted")
		jobs.append([job, WorkerThreadPool.add_task(Callable(job, "run"), true), i])
		tiles.clear() # worker must own its snapshot, not this mutable dictionary.
	for row: Array in jobs:
		WorkerThreadPool.wait_for_task_completion(row[1])
		var result: Array = row[0].read_result()
		equal_arrays(result[2][row[2]], tile_reference(source, row[2]), "concurrent tile")
	check(source == original, "concurrent jobs preserve source")
	var bad: Object = ClassDB.instantiate("SoftGroundMeshJob")
	check(not bad.configure([], {}), "invalid source rejected")
	check(not bad.configure(source, {-1:null}), "negative tile rejected")
	check(not bad.configure(source, {256:null}), "outside tile rejected")
	var corrupt := source.duplicate(true)
	corrupt[Mesh.ARRAY_INDEX][0] = 999999
	check(not bad.configure(corrupt, {0:null}), "invalid source index rejected")
	check(not bad.configure(source, {0:source}), "invalid dense shape rejected")
	var excess := {}
	for i in 129: excess[i] = null
	check(not bad.configure(source, excess), "memory bound enforced")
	# Run the actual script dispatcher and resource replacement, not a mock job.
	var terrain := EITerrain.new(); terrain.sectors_x = 1; terrain.sectors_y = 1
	terrain._land_mat = ShaderMaterial.new()
	terrain._land_mat.shader = Shader.new(); terrain._land_mat.shader.code = "shader_type spatial;"
	add_child(terrain); terrain.set_process(false)
	var node := MeshInstance3D.new(); node.name = "Sector_0_0"
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source)
	node.mesh = mesh; node.extra_cull_margin = 0.1; terrain.add_child(node)
	var soft := SoftGroundDeform.new(); soft.terrain = terrain; terrain.add_child(soft); soft.set_process(false)
	mark(soft); soft._process(0)
	check(soft._mesh_jobs.size() == 1, "sector geometry dispatched to worker")
	mark(soft, Vector2(15, 15)) # another contact while the first snapshot runs.
	drain(soft)
	var rec: Dictionary = soft.sectors[Vector2i.ZERO]
	check(rec.tiles.values().all(func(v: Variant) -> bool: return v != null), "later contacts coalesced without loss")
	check(node.mesh != mesh and (rec.shadow as WeakRef).get_ref().mesh != null, "surface and shadow installed together")
	equal_arrays(rec.arrays, mesh.surface_get_arrays(0), "source resource retained")
	mark(soft, Vector2(23, 23)); soft._process(0)
	soft.clear()
	check(soft._mesh_jobs.is_empty() and soft.sectors.is_empty() and node.mesh == mesh, "clear joins and restores original")
	check(is_equal_approx(node.extra_cull_margin, 0.1), "clear restores cull margin")
	mark(soft); soft._process(0)
	var generation: int = soft.sectors[Vector2i.ZERO].generation
	soft._restore(Vector2i.ZERO)
	mark(soft, Vector2(23, 23))
	check(soft.sectors[Vector2i.ZERO].generation != generation, "same sector gets new generation")
	drain(soft)
	check(not soft.sectors[Vector2i.ZERO].tiles.has(51), "retired snapshot cannot revive earlier tiles")
	mark(soft, Vector2(8, 8)); soft._process(0)
	rec = soft.sectors[Vector2i.ZERO]
	for id: int in rec.touched: rec.touched[id] = -SoftGroundDeform.LIFE
	soft._process(1.1); drain(soft)
	check(rec.tiles.is_empty() and (rec.shadow as WeakRef).get_ref().mesh == null, "expiry discards in-flight geometry")
	mark(soft); soft._process(0)
	soft._make_room(Vector2i.ZERO, SoftGroundDeform.MAX_TILES)
	mark(soft, Vector2(23, 23)); drain(soft)
	check(not rec.tiles.has(51) and not rec.tiles.is_empty(), "capacity reset retains only new contacts")
	mark(soft, Vector2(8, 8)); soft._process(0)
	soft.free()
	check(node.mesh == mesh, "node removal joins workers and restores geometry")
	terrain.free(); reference.free()
	print("SOFT_GROUND_MESH checks=", checks, " failures=", failures, " native_us=", native_us, " script_us=", script_us)
	get_tree().quit(1 if failures else 0)
