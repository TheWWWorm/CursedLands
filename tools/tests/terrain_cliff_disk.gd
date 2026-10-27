extends "res://tools/tests/terrain_snow_contours.gd"
## Drop every process-local entry between construction and reuse. Exact
## arrays/pixels and corrupt-file fallback exercise the persisted payload.
var cache: Script

func _ready() -> void:
	cache = load("res://src/game/fx/terrain_cliff_cache.gd")
	if not cache.has_method("_read_disk"):
		# The previous loading build already has the in-process cache. Exercise
		# its actual miss after that cache is dropped, without requiring the
		# new persistence helpers merely to produce a negative control.
		var uncached := fixture(0)
		for y in 33:
			for x in 33: uncached.heights[y*33+x] = 16.0 if x+y >= 32 else 0.0
		var built: RefCounted = Field.create(uncached, rules())
		built.retain(); cache.clear()
		var reloaded: RefCounted = Field.create(uncached, rules())
		check(reloaded.reused and reloaded.build_us == 0, "first load after restart reuses prepared terrain geometry")
		uncached.free()
		finish_disk(); return
	cache.disk_root = "user://cliff-disk-test"
	cache.clear()
	var rock := fixture(0)
	for y in 33:
		for x in 33: rock.heights[y*33+x] = 16.0 if x+y >= 32 else 0.0
	var saved := round_trip(rock, rules(), "rock")
	var snow := snow_fixture()
	check(snow != null, "original snow artwork is available")
	if snow: round_trip(snow, {}, "snow"); snow.free()
	var flat := fixture(0)
	var neutral: RefCounted = Field.create(flat, rules()); neutral.retain(); cache.clear()
	var restored: RefCounted = Field.create(flat, rules())
	check(restored.reused and restored.geometry == null and restored.tiles == null,
		"flat terrain survives a restart without allocating GPU resources")
	flat.free()
	var identity: String = saved.key
	var path: String = cache._path(identity)
	var valid: PackedByteArray = saved.file
	var renamed := "another-map".sha256_text()
	FileAccess.open(cache._path(renamed), FileAccess.WRITE).store_buffer(valid)
	check(cache._read_disk(renamed).is_empty(), "a valid record copied under another map key is rejected")
	for damage in ["header", "checksum", "truncated", "schema", "oversize"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		var data := valid.duplicate()
		match damage:
			"header": data[0] = 0
			"checksum": data[data.size()-1] = data[data.size()-1] ^ 1
			"truncated": data.resize(12)
			"schema":
				var payload := var_to_bytes({"field": {}, "geometry": {}})
				data.resize(16); data.append_array(cache._digest(payload, identity)); data.append_array(payload)
		file.store_buffer(data)
		if damage == "oversize": file.seek(cache.MAX_BYTES + cache.HEADER_BYTES); file.store_8(0)
		file.close(); cache.clear()
		var rebuilt: RefCounted = Field.create(rock, rules())
		check(not rebuilt.reused and not FileAccess.file_exists(path), damage + " cache is rejected without preventing terrain construction")
		rebuilt.geometry.prepare(saved.source)
		check(rebuilt.geometry.arrays(saved.source) == saved.expected, damage + " fallback preserves exact geometry")
		rebuilt.retain(); cache.clear()
		check(Field.create(rock, rules()).reused, damage + " fallback replaces the invalid cache")
	cache.clear()
	rock.heights[544] += 0.5
	check(not Field.create(rock, rules()).reused, "changed map content cannot use a persisted field")
	rock.free()
	# This directory belongs only to the test. Preserve an unrelated sentinel
	# while exercising real file eviction rather than a mocked cache index.
	for name in DirAccess.get_files_at(cache.disk_root): DirAccess.remove_absolute(cache.disk_root.path_join(name))
	FileAccess.open(cache.disk_root.path_join("keep.txt"), FileAccess.WRITE).store_string("unrelated")
	var partial: String = cache._path("interrupted".sha256_text()) + ".%d.part" % OS.get_process_id()
	FileAccess.open(partial, FileAccess.WRITE).store_buffer(valid.slice(0, 100))
	cache._prune_disk()
	check(not FileAccess.file_exists(partial), "interrupted writes do not accumulate outside the disk budget")
	var foreign: String = cache._path("foreign-writer".sha256_text()) + ".1.part"
	FileAccess.open(foreign, FileAccess.WRITE).store_buffer(valid.slice(0, 100))
	cache._prune_disk()
	check(FileAccess.file_exists(foreign), "a foreign live writer is not mistaken for a dead child process")
	var payload: PackedByteArray = valid.slice(cache.HEADER_BYTES)
	var first := "first".sha256_text()
	cache._write_disk(first, payload)
	for i in cache.DISK_MAX_ENTRIES - 1: cache._write_disk(str(i).sha256_text(), payload)
	check(not cache._read_disk(first).is_empty(), "using a persisted record refreshes its eviction order")
	cache._write_disk("extra".sha256_text(), payload)
	check(FileAccess.file_exists(cache._path(first)) and not FileAccess.file_exists(cache._path("0".sha256_text())),
		"disk entry bound evicts the least recently used record")
	# Sparse files exercise the byte limit without allocating large buffers.
	for i in 4:
		var file := FileAccess.open(cache._path(("large%d" % i).sha256_text()), FileAccess.WRITE)
		file.store_buffer(cache.MAGIC.to_ascii_buffer()); file.store_64(i)
		file.seek(cache.DISK_MAX_BYTES / 3); file.store_8(0); file.close()
	cache._prune_disk()
	var total := 0; var count := 0
	for name in DirAccess.get_files_at(cache.disk_root):
		if not name.ends_with(".bin"): continue
		var file := FileAccess.open(cache.disk_root.path_join(name), FileAccess.READ)
		total += file.get_length(); count += 1
	check(total <= cache.DISK_MAX_BYTES and count <= cache.DISK_MAX_ENTRIES, "disk cache respects both file and byte budgets")
	check(FileAccess.get_file_as_string(cache.disk_root.path_join("keep.txt")) == "unrelated", "cache pruning preserves unrelated files")
	for name in DirAccess.get_files_at(cache.disk_root): DirAccess.remove_absolute(cache.disk_root.path_join(name))
	DirAccess.remove_absolute(cache.disk_root)
	cache.clear(); finish_disk()

func round_trip(terrain: EITerrain, masks: Dictionary, label: String) -> Dictionary:
	var source := source_mesh(terrain)
	var sector := EITerrainSector.new()
	sector.configure(source, StandardMaterial3D.new(), 6, false); terrain.add_child(sector)
	var field: RefCounted = Field.create(terrain, masks)
	check(not field.reused and field.geometry != null, label + ": first build generates geometry")
	sector.set_cliff_geometry(field.geometry)
	var expected: Array = field.geometry.arrays(source)
	field.retain()
	var identity: String = cache.key(terrain, masks)
	var valid := FileAccess.get_file_as_bytes(cache._path(identity))
	check(valid.size() > cache.HEADER_BYTES, label + ": complete derived data is persisted")
	cache.clear()
	var copy: RefCounted = Field.create(terrain, masks)
	check(copy.reused and copy.build_us == 0 and copy.geometry != field.geometry, label + ": disk reuse restores a private owner without rebuilding")
	check(copy.geometry.arrays(source) == expected, label + ": every raster/PT geometry channel survives serialization exactly")
	if field.admitted > 0:
		for texture in ["tiles", "flatness", "blends"]:
			check(copy.get(texture) != field.get(texture) and copy.get(texture).get_image().get_data() == field.get(texture).get_image().get_data(),
				label + ": fresh GPU " + texture + " matches source pixels")
	field.geometry.patches.clear(); field.geometry._prepared.clear()
	check(copy.geometry.arrays(source) == expected and copy._shaders.is_empty() and copy.geometry._dense_snow.is_empty(),
		label + ": restored data owns no previous shaders or mutable snow deformation")
	return {"key": identity, "file": valid, "source": source, "expected": expected}

func finish_disk() -> void:
	TexUpscale.shutdown()
	print("TERRAIN_CLIFF_DISK ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))
