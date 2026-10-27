extends RefCounted
## Only immutable derived data survives a world. Serialized snapshots give
## each new field its own dictionaries and geometry caches; materials, nodes,
## deformation and live weather never enter this bounded cache.
const MAX_BYTES := 64 * 1024 * 1024
const MAX_ENTRIES := 2
## Increment when field/geometry generation or the serialized schema changes.
## All source map, artwork and deformation inputs are also part of the key.
const REVISION := 1
const DISK_MAX_BYTES := 128 * 1024 * 1024
const DISK_MAX_ENTRIES := 8
const MAGIC := "CLCLIFF1"
const HEADER_BYTES := 48 # magic, access timestamp, SHA-256 of payload
static var disk_root := "user://cache/terrain_cliffs"
static var entries := {}
static var bytes := 0

static func key(terrain: EITerrain, verified: Dictionary) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes([REVISION, terrain.sectors_x, terrain.sectors_y, terrain.grid_w,
		terrain.texture_size, terrain.tile_size, terrain.tile_types, terrain.land_tile,
		terrain.heights, terrain.land_xy, terrain.land_n, verified]))
	if verified.is_empty():
		# Classify the actual original atlas, including a replaced data set.
		# The map name or HD texture preference cannot establish identity.
		for atlas in clampi(int(terrain.get_meta("textures_count", 0)), 0, 256):
			var image := GameData.load_original_image("%s%03d" % [terrain.resource_prefix, atlas])
			digest.update(var_to_bytes([atlas, image.get_size() if image else Vector2i.ZERO,
				image.get_format() if image else -1, image.get_data() if image else PackedByteArray()]))
	# Patches also interpolate source UVs, normals and underwater colours.
	# Hash those exact inputs, not just the height field used for admission.
	for sector in terrain.get_children():
		if sector is EITerrainSector:
			digest.update(var_to_bytes(sector.deformation_arrays()))
	return digest.finish().hex_encode()

static func take(identity: String) -> Dictionary:
	if not entries.has(identity):
		var persisted := _read_disk(identity)
		if persisted.is_empty(): return {}
		var data: PackedByteArray = persisted.data
		var snapshot: Dictionary = persisted.state
		var field: Dictionary = snapshot.field
		var textures: Array = [null, null, null]
		if field.admitted > 0:
			textures = [ImageTexture.create_from_image(Image.create_from_data(field.tile_size.x,
				field.tile_size.y, false, Image.FORMAT_R8, field.eligible)),
				ImageTexture.create_from_image(Image.create_from_data(field.grid_size.x,
				field.grid_size.y, false, Image.FORMAT_R8, field.guards)),
				ImageTexture.create_from_image(Image.create_from_data(field.tile_size.x,
				field.tile_size.y, false, Image.FORMAT_RGBAF, field.blend_rows.to_byte_array()))]
		store_entry(identity, {"data": data, "textures": textures, "bytes": _size(data, field)})
		# Validation already decoded this private snapshot. Return it directly
		# rather than allocating another map-sized copy from the retained bytes.
		# It also serves this load if GPU pixels exceed the memory-cache budget.
		return {"state": snapshot, "textures": textures}
	var entry: Dictionary = entries[identity]
	entries.erase(identity)
	entries[identity] = entry
	return {"state": bytes_to_var(entry.data), "textures": entry.textures}

static func state(object: RefCounted, excluded: Array) -> Dictionary:
	var result := {}
	for property in object.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not property.name in excluded:
			var value: Variant = object.get(property.name)
			# A new object-owning member must be considered explicitly. Never
			# serialize object IDs or accidentally retain a world through it.
			assert(not value is Object)
			result[property.name] = value
	return result

static func remember(identity: String, field: RefCounted) -> void:
	if identity.is_empty() or entries.has(identity): return
	var data := var_to_bytes({"field": state(field, ["tiles", "flatness", "blends", "geometry",
		"_shaders", "_cache_key", "reused", "build_us"]),
		"geometry": state(field.geometry, ["_dense_snow"]) if field.geometry else {}})
	var textures := [field.tiles, field.flatness, field.blends]
	# The source pixels are already on the field. Accounting must not force
	# three synchronous GPU readbacks just after terrain construction.
	var size := _size(data, {"admitted": field.admitted, "eligible": field.eligible,
		"guards": field.guards, "blend_rows": field.blend_rows})
	store_entry(identity, {"data": data, "textures": textures, "bytes": size})
	_write_disk(identity, data)

static func _size(data: PackedByteArray, field: Dictionary) -> int:
	return data.size() + (field.eligible.size() + field.guards.size() + field.blend_rows.size() * 16 \
		if field.admitted > 0 else 0)

static func _path(identity: String) -> String:
	return disk_root.path_join("v%d-%s.bin" % [REVISION, identity])

static func _digest(data: PackedByteArray, identity: String) -> PackedByteArray:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(identity.to_ascii_buffer()); digest.update(data)
	return digest.finish()

static func _read_disk(identity: String) -> Dictionary:
	if disk_root.is_empty(): return {}
	var path := _path(identity)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var valid := file.get_length() > HEADER_BYTES and file.get_length() <= MAX_BYTES + HEADER_BYTES
	var data := PackedByteArray()
	if valid:
		valid = file.get_buffer(8).get_string_from_ascii() == MAGIC
		file.get_64() # last access, used only for eviction
		var digest := file.get_buffer(32)
		data = file.get_buffer(file.get_length() - HEADER_BYTES)
		valid = valid and _digest(data, identity) == digest
	file.close()
	var snapshot: Variant = bytes_to_var(data) if valid else null
	if valid: valid = _valid_snapshot(snapshot)
	if not valid:
		# An interrupted, obsolete or corrupt cache never prevents loading.
		DirAccess.remove_absolute(path)
		return {}
	# Refresh the file's modification time without rewriting its geometry.
	file = FileAccess.open(path, FileAccess.READ_WRITE)
	if file:
		file.seek(8); file.store_64(int(Time.get_unix_time_from_system() * 1000000.0)); file.close()
	return {"data": data, "state": snapshot}

static func _valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not value.get("field") is Dictionary or not value.get("geometry") is Dictionary:
		return false
	var field: Dictionary = value.field
	if not field.get("admitted") is int or not field.get("tile_size") is Vector2i \
		or not field.get("grid_size") is Vector2i or not field.get("eligible") is PackedByteArray \
		or not field.get("guards") is PackedByteArray or not field.get("blend_rows") is PackedColorArray:
		return false
	if field.admitted > 0:
		var tiles: Vector2i = field.tile_size; var grid: Vector2i = field.grid_size
		if tiles.x <= 0 or tiles.y <= 0 or grid.x != tiles.x * 2 + 1 or grid.y != tiles.y * 2 + 1 \
			or field.eligible.size() != tiles.x * tiles.y or field.blend_rows.size() != tiles.x * tiles.y \
			or field.guards.size() != grid.x * grid.y:
			return false
	return true

static func _write_disk(identity: String, data: PackedByteArray) -> void:
	if disk_root.is_empty() or data.is_empty() or data.size() > MAX_BYTES: return
	if DirAccess.make_dir_recursive_absolute(disk_root) != OK: return
	var path := _path(identity)
	# Processes use independent staging files; readers see only complete data.
	var temporary := path + ".%d.part" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	file.store_buffer(MAGIC.to_ascii_buffer()); file.store_64(int(Time.get_unix_time_from_system() * 1000000.0))
	file.store_buffer(_digest(data, identity)); file.store_buffer(data)
	var error := file.get_error()
	file.close()
	if error == OK: DirAccess.rename_absolute(temporary, path)
	if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	_prune_disk()

static func _prune_disk() -> void:
	var directory := DirAccess.open(disk_root)
	if directory == null: return
	var files: Array[Dictionary] = []
	var total := 0
	var pattern := RegEx.create_from_string("^v[0-9]+-[0-9a-f]{64}\\.bin$")
	var partial := RegEx.create_from_string("^v[0-9]+-[0-9a-f]{64}\\.bin\\.([0-9]+)\\.part$")
	for name in directory.get_files():
		var pending := partial.search(name)
		if pending:
			var writer := int(pending.get_string(1))
			# OS.is_process_running only knows children on the supported engines.
			# Check a visible /proc for other instances; elsewhere retain foreign
			# staging whose ownership cannot be established safely.
			var can_check := (OS.has_feature("linuxbsd") or OS.has_feature("android")) \
				and DirAccess.dir_exists_absolute("/proc/%d" % OS.get_process_id())
			if writer == OS.get_process_id() or (can_check and not DirAccess.dir_exists_absolute("/proc/%d" % writer)):
				DirAccess.remove_absolute(disk_root.path_join(name))
			continue
		# Include old schema versions in the total budget. Never prune files
		# outside the cache's exact version/hash naming convention.
		if pattern.search(name) == null: continue
		var path := disk_root.path_join(name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: continue
		var size := file.get_length()
		file.seek(8)
		var accessed := file.get_64() if size >= HEADER_BYTES else 0
		file.close()
		files.append({"path": path, "size": size, "time": accessed})
		total += size
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	while files.size() > DISK_MAX_ENTRIES or total > DISK_MAX_BYTES:
		var oldest: Dictionary = files.pop_front()
		total -= int(oldest.size)
		DirAccess.remove_absolute(oldest.path)

static func store_entry(identity: String, entry: Dictionary) -> void:
	if entry.bytes > MAX_BYTES: return
	if entries.has(identity):
		bytes -= int(entries[identity].bytes)
		entries.erase(identity)
	while not entries.is_empty() and (entries.size() >= MAX_ENTRIES or bytes + entry.bytes > MAX_BYTES):
		var oldest: String = entries.keys()[0]
		bytes -= int(entries[oldest].bytes)
		entries.erase(oldest)
	entries[identity] = entry
	bytes += int(entry.bytes)

static func clear() -> void:
	entries.clear()
	bytes = 0
