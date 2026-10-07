extends Node
## Exact native/scalar grass generation, immutable worker inputs and lifetime.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ", label)

func equal(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for field in ["transforms", "colours", "custom"]:
		check(actual[field] == expected[field], label + " exact " + field)
		if failures < 8 and actual[field] != expected[field]:
			print("SIZES ", field, " ", actual[field].size(), " ", expected[field].size())
			for i in mini(actual[field].size(), expected[field].size()):
				if actual[field][i] != expected[field][i]:
					print("FIRST ", i, " ", actual[field][i], " != ", expected[field][i]); break

func fixture() -> TerrainDetails:
	var t := EITerrain.new()
	t.map_name = "grass differential 481529"
	t.sectors_x = 2; t.sectors_y = 2; t.grid_w = 65
	t.texture_size = 512; t.tile_size = 64
	t.heights.resize(65 * 65); t.land_xy.resize(65 * 65)
	t.water.resize(64 * 64); t.water.fill(-INF)
	t.surface.resize(64 * 64); t.surface.fill(-INF)
	t.ground.resize(64 * 64); t.land_tile.resize(32 * 32)
	var rng := RandomNumberGenerator.new(); rng.seed = 721854
	for y in 65:
		for x in 65:
			var i := y * 65 + x
			t.heights[i] = 4.0 + sin(x * 0.1) + cos(y * 0.07) + (8.0 if x > 40 else 0.0)
			t.land_xy[i] = Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)) if x > 0 and y > 0 and x < 64 and y < 64 else Vector2.ZERO
	for y in 64:
		for x in 64:
			var i := y * 64 + x
			t.ground[i] = [0, 5, 11, 1][int(x / 16)]
			if x < 8 and y < 32: t.water[i] = 10.0
			if x > 24 and x < 32 and y > 24 and y < 48: t.surface[i] = 20.0
	for i in t.land_tile.size(): t.land_tile[i] = i % 64 | ((i % 3) << 6) | ((i % 4) << 14)
	var details := TerrainDetails.new(); details.terrain = t; details._grass = true
	for atlas in 3:
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				image.set_pixel(x, y, Color(0.08 + float(x % 32) / 300.0, 0.30 + float(y % 64) / 130.0, 0.08) if (x + y + atlas * 3) % 23 > 2 else Color(0.4, 0.2, 0.3))
		details._images[atlas] = image
	details._scenery_signature = [0, 0, 0, t.surface_rev]
	# Tilted scenery, low walls and overhead boxes exercise segment clipping.
	for y in 8:
		for x in 8:
			var point := Vector2(x * 8 + 3, y * 8 + 4)
			var basis := Basis(Vector3.UP, (x + y) * 0.31).scaled(Vector3(1, 1.2, 0.8))
			var xf := Transform3D(basis, Vector3(point.x, t.height_at(point.x, point.y), -point.y))
			details._scenery[Vector2i(x, y)] = [{"inverse":xf.affine_inverse(),"box":AABB(Vector3(-1, -0.1, -1),Vector3(2, 1.3, 2))}]
	return details

func _ready() -> void:
	check(ClassDB.class_exists("GrassFieldKernel") and ClassDB.class_exists("GrassChunkJob"), "native grass available")
	if failures: get_tree().quit(1); return
	var details := fixture()
	details.prepare_grass()
	check(details._grass_field != null, "field captured")
	var rng := RandomNumberGenerator.new(); rng.seed = 529136
	var sample_job := details._grass_job(Vector2i.ZERO)
	for i in 1600:
		var p := Vector2(rng.randf_range(-0.2, 64.2), rng.randf_range(-0.2, 64.2))
		check(details._grass_field.sample(p) == details.surface_sample(p), "jittered triangle sample " + str(i))
		check(sample_job.growth(p) == details.growth(p), "growth noise " + str(i))
	var expected := {}; var native_us := 0; var script_us := 0; var tufts := 0
	for y in 8:
		for x in 8:
			var key := Vector2i(x, y)
			var start := Time.get_ticks_usec()
			var a := details.instances(key)
			native_us += Time.get_ticks_usec() - start
			start = Time.get_ticks_usec()
			var b := details.instances_script(key)
			script_us += Time.get_ticks_usec() - start
			equal(a, b, str(key))
			expected[key] = a
			tufts += b.transforms.size()
			check(a.buffer.size() == b.transforms.size() * 20, "complete instance buffer")
			# Godot's scalar setters are an independent check of buffer layout.
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true; mm.use_custom_data = true; mm.mesh = QuadMesh.new(); mm.instance_count = b.transforms.size()
			for i in b.transforms.size():
				mm.set_instance_transform(i, b.transforms[i]); mm.set_instance_color(i, b.colours[i]); mm.set_instance_custom_data(i, b.custom[i])
			if DisplayServer.get_name() != "headless":
				# Compatibility quantizes color/custom channels to half floats. Compare
				# both upload routes after the renderer has applied the same conversion.
				var packed := MultiMesh.new(); packed.transform_format = MultiMesh.TRANSFORM_3D
				packed.use_colors = true; packed.use_custom_data = true; packed.mesh = mm.mesh
				packed.instance_count = b.transforms.size(); packed.buffer = a.buffer
				check(packed.buffer == mm.buffer, "engine MultiMesh buffer layout")
	check(tufts > 500, "substantial accepted and rejected coverage")
	var jobs := []
	for key: Vector2i in expected:
		var job := details._grass_job(key)
		jobs.append({"key":key,"kernel":job,"task":WorkerThreadPool.add_task(Callable(job,"run"))})
	# Source edits after publication cannot change a running job's field.
	details.terrain.heights.fill(999.0); details.terrain.water.fill(999.0)
	for image: Image in details._images.values(): image.fill(Color.RED)
	for job: Dictionary in jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
		equal(job.kernel.read_result(), expected[job.key], "immutable concurrent " + str(job.key))
	# A clear must join its outstanding workers and discard every old result.
	for i in 4:
		var job := details._grass_job(Vector2i(i, 0))
		details._grass_jobs.append({"key":Vector2i(i,0),"kernel":job,"task":WorkerThreadPool.add_task(Callable(job,"run")),"generation":details._grass_generation})
	details.water_changed()
	check(details._grass_jobs.is_empty() and details._grass_field == null and details._chunks.is_empty(), "water invalidates outstanding chunks")
	check(details._building_chunks.is_empty() and details._wanted_chunks.is_empty(), "clear discards requested cells")
	var invalid: RefCounted = ClassDB.instantiate("GrassFieldKernel")
	check(not invalid.configure({},{}), "malformed field rejected")
	check(invalid.sample(Vector2.ZERO).is_empty(), "invalid field never sampled")
	details.terrain.free(); details.free()
	print("GRASS_CHUNKS checks=",checks," failures=",failures," tufts=",tufts," native_us=",native_us," script_us=",script_us)
	get_tree().quit(1 if failures else 0)
