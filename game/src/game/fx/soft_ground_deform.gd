class_name SoftGroundDeform
extends Node
## Shallow, optional snow/sand geometry displacement. Only stepped-on tiles
## are tessellated; original triangle planes, UVs and lighting are interpolated.
## Per-sector textures and geometry are bounded and discarded on leaving the
## world, loading or disabling the option. Saves and collision remain original.

const TYPES := [3, 9, 12] # authored sand, loose snow, packed snow
const SECTOR := 32
const RESOLUTION := 512
const SUBDIV := 16
const DEPTH := 0.04
const MAX_SECTORS := 8
const MAX_TILES := 128
const MAX_STEPS := 64 # per sector
const LIFE := 240.0
const FADE := 60.0

var terrain: EITerrain
var sectors := {} # Vector2i -> source mesh/arrays, dense tiles, track image
var _queue: Array[Dictionary] = []
var _age := 0.0
var _refresh := 0.0


func _exit_tree() -> void:
	clear()


func clear() -> void:
	_queue.clear()
	for key: Vector2i in sectors.keys():
		_restore(key)


func _restore(key: Vector2i) -> void:
	var rec: Dictionary = sectors[key]
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	if node:
		node.mesh = rec.source
	sectors.erase(key)
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != key)


func refresh_materials() -> void:
	for key: Vector2i in sectors:
		var rec: Dictionary = sectors[key]
		rec.material = terrain._land_mat.duplicate() as ShaderMaterial
		rec.material.set_shader_parameter("soft_tracks", true)
		rec.material.set_shader_parameter("soft_track_origin", Vector2(key * SECTOR))
		rec.material.set_shader_parameter("soft_track_texture", rec.texture)
		var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
		# A newly queued sector still displays its original mesh. Never attach
		# the track material to that source: restoring it must remove tracks.
		if node and node.mesh != rec.source:
			node.mesh.surface_set_material(0, rec.material)


func refresh_rain_cover() -> void:
	for rec: Dictionary in sectors.values():
		rec.material.set_shader_parameter("rain_cover", terrain._rain_cover)


func step_allowed(p: Vector2) -> bool:
	var size := terrain.size_ei()
	if p.x < 0.0 or p.y < 0.0 or p.x >= size.x or p.y >= size.y:
		return false
	var h := terrain.height_at(p.x, p.y)
	return terrain.ground_type(p.x, p.y) in TYPES \
		and terrain.ground_at(p.x, p.y) <= h + 0.04 and terrain.water_at(p.x, p.y) <= h - 0.025


func add_step(p: Vector2, extent: Vector2, angle: float) -> void:
	if not is_instance_valid(terrain) or not step_allowed(p):
		return
	var ext := extent.abs().clamp(Vector2(0.06, 0.10), Vector2(0.32, 0.46))
	var radius := ext.length() * 1.35
	var first := Vector2i(((p - Vector2.ONE * radius) / SECTOR).floor())
	var last := Vector2i(((p + Vector2.ONE * radius) / SECTOR).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			if x < 0 or y < 0 or x >= terrain.sectors_x or y >= terrain.sectors_y:
				continue
			var rec := _sector(key)
			if rec.is_empty():
				continue
			var ids := _tile_ids(p, ext, key)
			var needed := 0
			for id: int in ids:
				needed += int(not rec.tiles.has(id))
			# Reserve the complete footfall. A capacity reset halfway through its
			# tiles would otherwise discard part of this newest footprint too.
			_make_room(key, needed)
			for id: int in ids:
				if not rec.tiles.has(id):
					rec.tiles[id] = null
					_queue.append({"key": key, "id": id})
			rec.last = _age
			rec.steps.append({"p": p, "extent": ext, "angle": angle, "time": _age})
			if rec.steps.size() > MAX_STEPS:
				rec.steps.pop_front()
			rec.dirty = true


static func _tile_ids(p: Vector2, extent: Vector2, key: Vector2i) -> PackedInt32Array:
	var radius := extent.length() * 1.35
	var origin := Vector2(key * SECTOR)
	var lo := Vector2i(((p - Vector2.ONE * radius - origin) * 0.5).floor()).clamp(Vector2i.ZERO, Vector2i(15, 15))
	var hi := Vector2i(((p + Vector2.ONE * radius - origin) * 0.5).floor()).clamp(Vector2i.ZERO, Vector2i(15, 15))
	var ids := PackedInt32Array()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			ids.append(y * 16 + x)
	return ids


func _make_room(keep: Vector2i, needed: int = 1) -> void:
	while tile_count() + needed > MAX_TILES and sectors.size() > 1:
		var oldest := keep
		var time := INF
		for key: Vector2i in sectors:
			if key != keep and sectors[key].last < time:
				oldest = key
				time = sectors[key].last
		_restore(oldest)
	if tile_count() + needed > MAX_TILES:
		# A very long walk within a single sector also has a strict ceiling.
		# Discard its old tracks as a group; the next footfall starts afresh.
		var rec: Dictionary = sectors[keep]
		rec.tiles.clear()
		rec.steps.clear()
		_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != keep)
		var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
		if node:
			node.mesh = rec.source


func tile_count() -> int:
	var count := 0
	for rec: Dictionary in sectors.values():
		count += rec.tiles.size()
	return count


func _sector(key: Vector2i) -> Dictionary:
	if sectors.has(key):
		return sectors[key]
	if sectors.size() >= MAX_SECTORS:
		var oldest: Vector2i = sectors.keys()[0]
		for k: Vector2i in sectors:
			if sectors[k].last < sectors[oldest].last:
				oldest = k
		_restore(oldest)
	var node := terrain.get_node_or_null("Sector_%d_%d" % [key.x, key.y]) as MeshInstance3D
	if node == null or node.mesh == null:
		return {}
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RG8)
	image.fill(Color(0, 0, 0, 1))
	var rec := {"node": weakref(node), "source": node.mesh, "arrays": node.mesh.surface_get_arrays(0),
		"tiles": {}, "steps": [], "last": _age, "image": image,
		"texture": ImageTexture.create_from_image(image), "material": terrain._land_mat.duplicate(), "dirty": false}
	rec.material.set_shader_parameter("soft_tracks", true)
	rec.material.set_shader_parameter("soft_track_origin", Vector2(key * SECTOR))
	rec.material.set_shader_parameter("soft_track_texture", rec.texture)
	sectors[key] = rec
	return rec


func _rebuild(rec: Dictionary) -> void:
	var source: Array = rec.arrays
	var arrays := source.duplicate(true)
	# Godot may generate tangent rows for the source's UVs. The terrain
	# shader derives its frame from derivatives; obsolete rows cannot be
	# kept when adding vertices (and are unnecessary for either look).
	arrays[Mesh.ARRAY_TANGENT] = null
	var ids := PackedInt32Array()
	var original: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	for tile in 256:
		if not rec.tiles.has(tile) or rec.tiles[tile] == null:
			ids.append_array(original.slice(tile * 24, tile * 24 + 24))
			continue
		var dense: Array = rec.tiles[tile]
		var base := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for field in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			arrays[field].append_array(dense[field])
		for id: int in dense[Mesh.ARRAY_INDEX]:
			ids.append(base + id)
	arrays[Mesh.ARRAY_INDEX] = ids
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, rec.material)
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	if node:
		node.mesh = mesh


static func _subdivide(arrays: Array, ids: PackedInt32Array, source: Array, a: int, b: int, c: int) -> void:
	var base := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var rows := PackedInt32Array()
	for y in SUBDIV + 1:
		rows.append((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() - base)
		for x in SUBDIV - y + 1:
			var v := y / float(SUBDIV)
			var u := x / float(SUBDIV)
			var w := 1.0 - u - v
			for field in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				arrays[field].append(source[field][a] * w + source[field][b] * u + source[field][c] * v)
			var col: Color = source[Mesh.ARRAY_COLOR][a] * w + source[Mesh.ARRAY_COLOR][b] * u + source[Mesh.ARRAY_COLOR][c] * v
			arrays[Mesh.ARRAY_COLOR].append(col)
	for y in SUBDIV:
		for x in SUBDIV - y:
			var i := base + rows[y] + x
			var j := base + rows[y + 1] + x
			ids.append_array([i, i + 1, j])
			if x < SUBDIV - y - 1:
				ids.append_array([i + 1, j + 1, j])


func _process(dt: float) -> void:
	_age += dt
	_refresh += dt
	var timed := _refresh >= 1.0
	if timed:
		_refresh = 0.0
	var changed := {}
	# Retire expired work before tessellation. A newer footstep can keep a
	# sector alive without keeping every older tile's dense geometry alive.
	for key: Vector2i in sectors.keys():
		var rec: Dictionary = sectors[key]
		if (rec.node as WeakRef).get_ref() == null:
			_restore(key)
			continue
		if timed:
			rec.steps = rec.steps.filter(func(s: Dictionary) -> bool: return _age - s.time < LIFE)
		if rec.steps.is_empty():
			_restore(key)
			continue
		if rec.dirty or timed:
			var wanted := {}
			for s: Dictionary in rec.steps:
				for id: int in _tile_ids(s.p, s.extent, key):
					wanted[id] = true
			for id: int in rec.tiles.keys():
				if not wanted.has(id):
					rec.tiles.erase(id)
					changed[key] = true
			if changed.has(key):
				_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != key or rec.tiles.has(q.id))
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		if not sectors.has(q.key):
			continue
		var rec: Dictionary = sectors[q.key]
		if not rec.tiles.has(q.id) or rec.tiles[q.id] != null:
			continue
		var dense := []
		dense.resize(Mesh.ARRAY_MAX)
		for field in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
			dense[field] = PackedVector3Array()
		for field in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			dense[field] = PackedVector2Array()
		dense[Mesh.ARRAY_COLOR] = PackedColorArray()
		var ids := PackedInt32Array()
		var original: PackedInt32Array = rec.arrays[Mesh.ARRAY_INDEX]
		for triangle in 8:
			var at := int(q.id) * 24 + triangle * 3
			_subdivide(dense, ids, rec.arrays, original[at], original[at + 1], original[at + 2])
		dense[Mesh.ARRAY_INDEX] = ids
		rec.tiles[q.id] = dense
		changed[q.key] = true
		if Time.get_ticks_usec() - start >= TerrainDetails.BUILD_US:
			break
	for key: Vector2i in changed:
		_rebuild(sectors[key])
	for key: Vector2i in sectors:
		var rec: Dictionary = sectors[key]
		if rec.dirty or timed:
			_redraw(key, rec)
			rec.dirty = false


func _redraw(key: Vector2i, rec: Dictionary) -> void:
	var image: Image = rec.image
	image.fill(Color(0, 0, 0, 1))
	for s: Dictionary in rec.steps:
		var fade := clampf((LIFE - (_age - s.time)) / FADE, 0.0, 1.0)
		paint(image, s.p - Vector2(key * SECTOR), s.extent, s.angle, fade)
	(rec.texture as ImageTexture).update(image)


static func paint(image: Image, p: Vector2, extent: Vector2, angle: float, strength: float) -> void:
	var scale := float(RESOLUTION) / SECTOR
	var radius := extent.length() * 1.35
	var lo := Vector2i(((p - Vector2.ONE * radius) * scale).floor()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var hi := Vector2i(((p + Vector2.ONE * radius) * scale).ceil()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var turn := Transform2D(-angle, Vector2.ZERO)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var local := turn * (Vector2(x + 0.5, y + 0.5) / scale - p)
			var r := (local / extent).length()
			if r > 1.28:
				continue
			var depression := (1.0 - smoothstep(0.45, 1.0, r)) * strength * 0.82
			var rim := (smoothstep(0.85, 1.05, r) - smoothstep(1.05, 1.28, r)) * strength * 0.18
			var prev := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(maxf(prev.r, depression), maxf(prev.g, rim), 0, 1))
