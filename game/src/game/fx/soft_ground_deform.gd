class_name SoftGroundDeform
extends Node
## Optional snow/sand compaction: planted feet and connected travel troughs.
## Only touched tiles
## are tessellated; original triangle planes, UVs and lighting are interpolated.
## Per-sector textures and geometry are bounded and discarded on leaving the
## world, loading or disabling the option. Saves and collision remain original.

const TYPES := [3, 9, 12] # authored sand, loose snow, packed snow
const SECTOR := SoftGroundField.SECTOR
const RESOLUTION := SoftGroundField.RESOLUTION
const SUBDIV := 16
const DEPTH := 0.30 # maximum loose-snow depth; see the terrain material profiles
const MAX_SECTORS := 8
const MAX_TILES := 128
const MAX_STEPS := 384 # recent-contact log; the persistent field survives eviction
const MAX_WALKERS := 1024 # separate foot identities, including multi-legged units
const LINK_TIME := 8.0 # slow gaits; idle/death explicitly end the contact stream
const LINK_DISTANCE := 2.5 # never connect teleports or widely separated contacts
const LIFE := 240.0
const FADE := 60.0
const TRAIL_SUPPORT := 2.6 # feathered, irregular shoulders around the swept floor

static var _edge_noise: FastNoiseLite

var terrain: EITerrain
var field: SoftGroundField
var sectors := {} # Vector2i -> source mesh/arrays, dense tiles, track image
var _queue: Array[Dictionary] = []
var _age := 0.0
var _refresh := 0.0
var _walkers := {} # rendered foot identity -> most recent grounded contact
var _native_mesh := ClassDB.class_exists("SoftGroundMeshJob") and not OS.get_cmdline_user_args().has("--ei-script-soft-ground")
var _mesh_jobs: Array[Dictionary] = []
var _generation := 0


func shared_field() -> SoftGroundField:
	if field == null:
		field = SoftGroundField.new(terrain.sectors_x * 16, terrain.sectors_y * 16)
	return field


func _exit_tree() -> void:
	clear()


func clear() -> void:
	# Workers own only packed snapshots. Join before releasing this world's
	# bookkeeping; a completed old job must never restore a cleared trail.
	for job: Dictionary in _mesh_jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_mesh_jobs.clear()
	_queue.clear()
	_walkers.clear()
	for key: Vector2i in sectors.keys():
		_restore(key)
	if field:
		field.flush(_age)


func _restore(key: Vector2i) -> void:
	var rec: Dictionary = sectors[key]
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	if node:
		node.mesh = rec.source
		node.extra_cull_margin = rec.margin
	var shadow := (rec.shadow as WeakRef).get_ref() as MeshInstance3D
	if shadow: shadow.free()
	sectors.erase(key)
	field.release(key)
	field.flush(_age)
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != key)


func refresh_materials() -> void:
	for key: Vector2i in sectors:
		var rec: Dictionary = sectors[key]
		rec.material = terrain._land_mat.duplicate() as ShaderMaterial
		rec.material.set_shader_parameter("soft_tracks", true)
		rec.material.set_shader_parameter("soft_track_origin", Vector2(key * SECTOR))
		rec.material.set_shader_parameter("soft_track_texture", rec.texture)
		rec.material.set_shader_parameter("soft_track_layer", rec.layer)
		rec.material.set_shader_parameter("soft_track_time", _age)
		var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
		# A newly queued sector still displays its original mesh. Never attach
		# the track material to that source: restoring it must remove tracks.
		if node and node.mesh != rec.source:
			node.mesh.surface_set_material(0, rec.material)
		var shadow := (rec.shadow as WeakRef).get_ref() as MeshInstance3D
		if shadow and shadow.mesh:
			shadow.mesh.surface_set_material(0, rec.material)


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
	var ext := extent.abs().clamp(Vector2(0.025, 0.045), Vector2(0.32, 0.46))
	_add_mark({"p": p, "extent": ext, "angle": angle, "time": _age})


func forget_contact(owner: int) -> void:
	_walkers.erase(owner)


func add_travel(owner: int, p: Vector2, extent: Vector2) -> void:
	if owner == 0 or not is_instance_valid(terrain):
		return
	if not step_allowed(p):
		_walkers.erase(owner)
		return
	var previous: Dictionary = _walkers.get(owner, {})
	var footprint := extent.max(previous.get("extent", extent) as Vector2)
	if not _walkers.has(owner) and _walkers.size() >= MAX_WALKERS:
		_walkers.erase(_walkers.keys()[0])
	_walkers[owner] = {"p": p, "time": _age, "extent": footprint}
	if previous.is_empty() or _age - float(previous.time) > LINK_TIME:
		return
	var from: Vector2 = previous.p
	var distance := from.distance_to(p)
	if distance < 0.08:
		# Accumulate slow movement; resetting the start at every tiny contact
		# would prevent a slow walker from ever producing a connected strip.
		_walkers[owner].p = from
		return
	if distance > LINK_DISTANCE:
		return
	# Never drag a trench across a bridge, water, rock or a skipped contact.
	var samples := ceili(distance / 0.15)
	for i in samples + 1:
		if not step_allowed(from.lerp(p, float(i) / samples)):
			return
	# A foot displaces a band of loose material wider than its sole. Adjacent
	# foot paths merge into a compressed corridor with the prints inside it.
	var width := clampf(footprint.x * 1.8 + footprint.y * 0.5 + 0.14, 0.18, 0.65)
	var pressure := clampf(sqrt(footprint.x * footprint.y / 0.009), 0.35, 1.0)
	if terrain.ground_type(p.x, p.y) == 3:
		width *= 0.75
	_add_mark({"p": from, "to": p, "extent": Vector2.ONE * width, "pressure": pressure, "angle": 0.0, "time": _age})


static func _bounds(mark: Dictionary) -> Rect2:
	var radius: float = mark.extent.length() * 1.8 if not mark.has("to") else mark.extent.x * TRAIL_SUPPORT
	var to: Vector2 = mark.get("to", mark.p)
	return Rect2((mark.p as Vector2).min(to) - Vector2.ONE * radius,
		(to - (mark.p as Vector2)).abs() + Vector2.ONE * radius * 2.0)


static func _mark_tiles(mark: Dictionary, key: Vector2i) -> PackedInt32Array:
	var bounds := _bounds(mark)
	var origin := Vector2(key * SECTOR)
	var lo := Vector2i(((bounds.position - origin) * 0.5).floor()).clamp(Vector2i.ZERO, Vector2i(15, 15))
	var hi := Vector2i(((bounds.end - origin) * 0.5).floor()).clamp(Vector2i.ZERO, Vector2i(15, 15))
	var ids := PackedInt32Array()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			ids.append(y * 16 + x)
	return ids


func _add_mark(mark: Dictionary) -> void:
	var bounds := _bounds(mark)
	var first := Vector2i((bounds.position / SECTOR).floor())
	var last := Vector2i((bounds.end / SECTOR).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			if x < 0 or y < 0 or x >= terrain.sectors_x or y >= terrain.sectors_y:
				continue
			var rec := _sector(key)
			if rec.is_empty():
				continue
			var ids := _mark_tiles(mark, key)
			var needed := 0
			for id: int in ids:
				needed += int(not rec.tiles.has(id))
			# Reserve the complete footfall. A capacity reset halfway through its
			# tiles would otherwise discard part of this newest footprint too.
			_make_room(key, needed)
			for id: int in ids:
				rec.touched[id] = _age
				if not rec.tiles.has(id):
					rec.tiles[id] = null
					_queue.append({"key": key, "id": id})
			rec.last = _age
			rec.steps.append(mark)
			rec.pending.append(mark)
			if rec.steps.size() > MAX_STEPS:
				rec.steps.pop_front()
			# The bounded recent-contact log is not the deformation history.
			# Older imprints remain in the field until their own timestamps fade.
			if rec.pending.size() >= 128:
				_paint_pending(key, rec)
			rec.dirty = true


static func _tile_ids(p: Vector2, extent: Vector2, key: Vector2i) -> PackedInt32Array:
	var radius := extent.length() * 1.8
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
		rec.revision += 1
		rec.build_pending = false
		rec.tiles.clear()
		rec.touched.clear()
		rec.steps.clear()
		rec.pending.clear()
		rec.image.fill(Color(0, 0, 0, 0))
		_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != keep)
		var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
		if node:
			node.mesh = rec.source
		field.uninstall(keep)
		field.flush(_age)
		var shadow := (rec.shadow as WeakRef).get_ref() as MeshInstance3D
		if shadow: shadow.mesh = null


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
	var sector := terrain.get_node_or_null("Sector_%d_%d" % [key.x, key.y])
	var node: MeshInstance3D = sector.deformation_surface() if sector is EITerrainSector else sector as MeshInstance3D
	if node == null or node.mesh == null:
		return {}
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBAF)
	image.fill(Color(0, 0, 0, 0))
	var layer := shared_field().allocate(key, image)
	# The original land layer is deliberately excluded from the sun's map.
	# Only the touched patches opt into geometry-based local self-shadowing.
	var shadow := MeshInstance3D.new()
	shadow.name = "SoftGroundShadow"
	shadow.layers = 1
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.extra_cull_margin = DEPTH
	node.add_child(shadow)
	_generation += 1
	var rec := {"node": weakref(node), "source": node.mesh, "arrays": node.mesh.surface_get_arrays(0),
		"tiles": {}, "touched": {}, "steps": [], "pending": [], "last": _age, "image": image,
		"shadow": weakref(shadow), "margin": node.extra_cull_margin,
		"generation": _generation, "revision": 0, "building": false, "build_pending": false,
		"texture": field.texture, "layer": layer, "key": key,
		"material": terrain._land_mat.duplicate(), "dirty": false}
	node.extra_cull_margin = maxf(node.extra_cull_margin, DEPTH)
	rec.material.set_shader_parameter("soft_tracks", true)
	rec.material.set_shader_parameter("soft_track_origin", Vector2(key * SECTOR))
	rec.material.set_shader_parameter("soft_track_texture", rec.texture)
	rec.material.set_shader_parameter("soft_track_layer", layer)
	rec.material.set_shader_parameter("soft_track_time", _age)
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
	var shadow_ids := PackedInt32Array()
	var source_count := (source[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
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
			shadow_ids.append(base + id - source_count)
	arrays[Mesh.ARRAY_INDEX] = ids
	var shadow_arrays := []
	shadow_arrays.resize(Mesh.ARRAY_MAX)
	if not shadow_ids.is_empty():
		for field in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			shadow_arrays[field] = arrays[field].slice(source_count)
		shadow_arrays[Mesh.ARRAY_INDEX] = shadow_ids
	_apply_mesh(rec, arrays, shadow_arrays)


func _apply_mesh(rec: Dictionary, arrays: Array, shadow_arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, rec.material)
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	if node:
		node.mesh = mesh
	field.install(rec.key, rec.tiles)
	field.flush(_age)
	var shadow := (rec.shadow as WeakRef).get_ref() as MeshInstance3D
	if shadow:
		if shadow_arrays[Mesh.ARRAY_INDEX] == null:
			shadow.mesh = null
		else:
			var shadow_mesh := ArrayMesh.new()
			shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shadow_arrays)
			shadow_mesh.surface_set_material(0, rec.material)
			shadow.mesh = shadow_mesh


func _finish_mesh_jobs(wait := false) -> void:
	for i in range(_mesh_jobs.size() - 1, -1, -1):
		var job: Dictionary = _mesh_jobs[i]
		if not wait and not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_mesh_jobs.remove_at(i)
		var rec: Dictionary = sectors.get(job.key, {})
		if rec.is_empty() or rec.generation != job.generation:
			continue
		rec.building = false
		if rec.revision != job.revision:
			# Tile expiry/capacity eviction invalidates the snapshot. New contacts
			# can be coalesced into the next build without reviving old geometry.
			rec.build_pending = true
			continue
		var result: Array = job.kernel.read_result()
		for id: int in result[2]:
			rec.tiles[id] = result[2][id]
		_apply_mesh(rec, result[0], result[1])


func _build_meshes(changed: Dictionary) -> void:
	for q: Dictionary in _queue:
		if sectors.has(q.key): changed[q.key] = true
	_queue.clear()
	for key: Vector2i in changed:
		sectors[key].build_pending = true
	_finish_mesh_jobs()
	for key: Vector2i in sectors:
		var rec: Dictionary = sectors[key]
		if rec.building or not rec.build_pending or _mesh_jobs.size() >= MAX_SECTORS:
			continue
		var kernel: Object = ClassDB.instantiate("SoftGroundMeshJob")
		if not kernel.configure(rec.arrays, rec.tiles):
			# Preserve the ordinary script path for an unsupported mesh layout.
			_native_mesh = false
			_finish_mesh_jobs(true)
			for k: Vector2i in sectors:
				for id: int in sectors[k].tiles:
					if sectors[k].tiles[id] == null: _queue.append({"key": k, "id": id})
			_build_script(changed)
			return
		rec.building = true
		rec.build_pending = false
		var task := WorkerThreadPool.add_task(Callable(kernel, "run"), false, "soft-ground mesh")
		_mesh_jobs.append({"key": key, "generation": rec.generation, "revision": rec.revision,
			"kernel": kernel, "task": task})


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
		for owner: int in _walkers.keys():
			if _age - float(_walkers[owner].time) > LINK_TIME:
				_walkers.erase(owner)
	var changed := {}
	# Retire expired work before tessellation. A newer footstep can keep a
	# sector alive without keeping every older tile's dense geometry alive.
	for key: Vector2i in sectors.keys():
		var rec: Dictionary = sectors[key]
		rec.material.set_shader_parameter("soft_track_time", _age)
		if (rec.node as WeakRef).get_ref() == null:
			_restore(key)
			continue
		if timed:
			rec.steps = rec.steps.filter(func(s: Dictionary) -> bool: return _age - s.time < LIFE)
		if _age - float(rec.last) >= LIFE:
			_restore(key)
			continue
		if timed:
			for id: int in rec.tiles.keys():
				if _age - float(rec.touched[id]) >= LIFE:
					rec.tiles.erase(id)
					rec.touched.erase(id)
					rec.revision += 1
					changed[key] = true
			if changed.has(key):
				_queue = _queue.filter(func(q: Dictionary) -> bool: return q.key != key or rec.tiles.has(q.id))
	if _native_mesh:
		_build_meshes(changed)
	else:
		_build_script(changed)
	for key: Vector2i in sectors:
		var rec: Dictionary = sectors[key]
		if rec.dirty:
			_redraw(key, rec)
			rec.dirty = false
	if field:
		field.flush(_age)


func _build_script(changed: Dictionary) -> void:
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


func _paint_pending(key: Vector2i, rec: Dictionary) -> void:
	var image: Image = rec.image
	for s: Dictionary in rec.pending:
		var stamp := float(s.time)
		if s.has("to"):
			paint_trail(image, s.p - Vector2(key * SECTOR), s.to - Vector2(key * SECTOR), s.extent.x, s.get("pressure", 1.0), stamp, Vector2(key * SECTOR))
		else:
			paint(image, s.p - Vector2(key * SECTOR), s.extent, s.angle, 1.0, stamp)
	rec.pending.clear()


func _redraw(key: Vector2i, rec: Dictionary) -> void:
	_paint_pending(key, rec)
	field.update(key)


static func strength_at(stamp: float, now: float) -> float:
	return clampf((LIFE - maxf(now - stamp, 0.0)) / FADE, 0.0, 1.0)


static func paint(image: Image, p: Vector2, extent: Vector2, angle: float, strength: float, stamp := 0.0) -> void:
	# End samples sit on sector boundaries, shared exactly by both textures.
	var scale := float(RESOLUTION - 1) / SECTOR
	var radius := extent.length() * 1.8
	var lo := Vector2i(((p - Vector2.ONE * radius) * scale).floor()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var hi := Vector2i(((p + Vector2.ONE * radius) * scale).ceil()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var turn := Transform2D(-angle, Vector2.ZERO)
	var pressure := clampf(sqrt(extent.x * extent.y / 0.009), 0.35, 1.0)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var local := turn * (Vector2(x, y) / scale - p)
			var r := (local / extent).length()
			if r > 1.8:
				continue
			var depression := (1.0 - smoothstep(0.35, 1.25, r)) * strength * 0.82 * pressure
			var rim := (smoothstep(0.9, 1.3, r) - smoothstep(1.3, 1.8, r)) * strength * 0.06 * pressure
			var prev := image.get_pixel(x, y)
			var fade := strength_at(prev.b, stamp)
			image.set_pixel(x, y, Color(maxf(prev.r * fade, depression), maxf(prev.g * fade, rim), stamp, 1))


static func paint_trail(image: Image, from: Vector2, to: Vector2, width: float, strength: float, stamp := 0.0, origin := Vector2.ZERO) -> void:
	var scale := float(RESOLUTION - 1) / SECTOR
	var radius := width * TRAIL_SUPPORT
	var lo := Vector2i(((from.min(to) - Vector2.ONE * radius) * scale).floor()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var hi := Vector2i(((from.max(to) + Vector2.ONE * radius) * scale).ceil()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var along := to - from
	var length_sq := maxf(along.length_squared(), 1e-6)
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.seed = 73129
		_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_edge_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_edge_noise.frequency = 2.4
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var p := Vector2(x, y) / scale
			var nearest := from + along * clampf((p - from).dot(along) / length_sq, 0.0, 1.0)
			var r := p.distance_to(nearest) / width
			if r > TRAIL_SUPPORT:
				continue
			# World-anchored variation joins across sectors and successive steps.
			# It roughens the shoulders without punching holes in the floor.
			var q := p + origin
			var rough := _edge_noise.get_noise_2d(q.x, q.y) * 0.18 \
				+ _edge_noise.get_noise_2d(q.x * 3.7 + 43.0, q.y * 3.7 - 17.0) * 0.07
			r /= 1.0 + rough
			if r > 2.05:
				continue
			var depression := (1.0 - smoothstep(0.2, 1.6, r)) * strength * 0.64
			var rim := (smoothstep(1.0, 1.45, r) - smoothstep(1.45, 2.05, r)) * strength * 0.05
			var prev := image.get_pixel(x, y)
			var fade := strength_at(prev.b, stamp)
			image.set_pixel(x, y, Color(maxf(prev.r * fade, depression), maxf(prev.g * fade, rim), stamp, 1))
