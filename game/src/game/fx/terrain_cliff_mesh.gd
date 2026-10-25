extends RefCounted
## Refine tall, verified natural walls along a continuous height contour.
## The original anchors, heights, collision grid and tile attributes remain
## authoritative. Only the presentation mesh bends between those anchors.
const SUBDIV := 4
const MIN_SPAN := 3.0
const MAX_OFFSET := 0.6
const CHANNELS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV,
	Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]
var grid_size := Vector2i.ZERO
var tile_size := Vector2i.ZERO
var _height := PackedFloat32Array()
var _gradient := PackedVector2Array()
var _allowed := PackedByteArray()
var _prepared := {}
var patches := {}
var refined_triangles := 0


func _init(terrain: EITerrain, field: TerrainCliff) -> void:
	grid_size = field.grid_size
	tile_size = field.tile_size
	_allowed = field.eligible
	# A separable 1-2-1 filter removes the metre-grid staircase from contours.
	# Interpolate a shared gradient field too: a bilinear height's *derivative*
	# jumps at cell edges and would tear independently generated wall patches.
	var horizontal := PackedFloat32Array(); horizontal.resize(terrain.heights.size())
	_height.resize(horizontal.size()); _gradient.resize(horizontal.size())
	for y in grid_size.y:
		for x in grid_size.x:
			var i := y * grid_size.x + x
			horizontal[i] = (terrain.heights[y * grid_size.x + maxi(x - 1, 0)]
				+ terrain.heights[i] * 2.0 + terrain.heights[y * grid_size.x + mini(x + 1, grid_size.x - 1)]) * 0.25
	for y in grid_size.y:
		for x in grid_size.x:
			var i := y * grid_size.x + x
			_height[i] = (horizontal[maxi(y - 1, 0) * grid_size.x + x]
				+ horizontal[i] * 2.0 + horizontal[mini(y + 1, grid_size.y - 1) * grid_size.x + x]) * 0.25
	for y in grid_size.y:
		for x in grid_size.x:
			_gradient[y * grid_size.x + x] = Vector2(
				_height[y * grid_size.x + mini(x + 1, grid_size.x - 1)] - _height[y * grid_size.x + maxi(x - 1, 0)],
				_height[mini(y + 1, grid_size.y - 1) * grid_size.x + x] - _height[maxi(y - 1, 0) * grid_size.x + x]) * 0.5


func _vertex_mask(vertex: int, tile: int) -> float:
	# Signed MPR offsets can cross a rounding boundary. Recover the authored
	# grid address from the immutable nine-vertex tile, not its world position.
	var local := vertex % 9
	var grid := Vector2i(tile % tile_size.x, tile / tile_size.x) * 2 + Vector2i(local % 3, local / 3)
	# Every tile touching this anchor must support the effect. An unsupported
	# neighbour then shares an entirely stationary edge, including its midpoint.
	for y in range(maxi((grid.y - 1) / 2, 0), mini(grid.y / 2, tile_size.y - 1) + 1):
		for x in range(maxi((grid.x - 1) / 2, 0), mini(grid.x / 2, tile_size.x - 1) + 1):
			if _allowed[y * tile_size.x + x] == 0: return 0.0
	return 1.0


func _amount(heights: Vector3, weights: Vector3, mask: float) -> float:
	# Pairwise variance is stable at large map altitudes and symmetric on an
	# edge. Edges spanning <=3 m and all authored vertices remain exactly fixed.
	var variance := weights.x * weights.y * pow(heights.x - heights.y, 2) \
		+ weights.x * weights.z * pow(heights.x - heights.z, 2) \
		+ weights.y * weights.z * pow(heights.y - heights.z, 2)
	return smoothstep(MIN_SPAN * 0.5, MIN_SPAN, sqrt(maxf(variance, 0.0))) * mask


func _sample(point: Vector3) -> Vector3:
	var grid := Vector2(point.x, -point.z).clamp(Vector2.ZERO, Vector2(grid_size - Vector2i.ONE))
	var cell := Vector2i(grid.floor()).min(grid_size - Vector2i(2, 2))
	var p := grid - Vector2(cell)
	var i := cell.y * grid_size.x + cell.x
	var height := lerpf(lerpf(_height[i], _height[i + 1], p.x),
		lerpf(_height[i + grid_size.x], _height[i + grid_size.x + 1], p.x), p.y)
	var gradient := _gradient[i].lerp(_gradient[i + 1], p.x).lerp(
		_gradient[i + grid_size.x].lerp(_gradient[i + grid_size.x + 1], p.x), p.y)
	return Vector3(height, gradient.x, gradient.y)


func position(point: Vector3, heights: Vector3, weights: Vector3, mask: float) -> Vector3:
	var amount := _amount(heights, weights, mask)
	if amount <= 0.0: return point
	var sample := _sample(point)
	if not sample.is_finite(): return point
	var gradient := Vector2(sample.y, sample.z)
	var offset := (gradient * ((point.y - sample.x) / maxf(gradient.length_squared(), 0.01))).limit_length(MAX_OFFSET)
	return point + Vector3(offset.x, 0.0, -offset.y) * amount


func _normal(normal: Vector3, point: Vector3, heights: Vector3, weights: Vector3, mask: float) -> Vector3:
	var amount := _amount(heights, weights, mask)
	if amount <= 0.0: return normal
	var sample := _sample(point)
	if not sample.is_finite(): return normal
	# Upward authored lighting normals are unsuitable for the curved wall.
	# Follow its broad contour while retaining the authored lighting response
	# and exactly the same normals along stationary floor/unsupported edges.
	return normal.lerp(Vector3(-sample.y,1.0,sample.z).normalized(),0.6*amount).normalized()


## Called on the immutable 9-vertex / 24-index tiles, once per sector. The
## retained patches are also reused by culled pieces, PT and snow rebuilds.
func prepare(source: Array) -> void:
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = source[Mesh.ARRAY_TEX_UV2]
	for start in range(0, indices.size(), 24):
		var tile := roundi(uv2[indices[start]].y)
		if _prepared.has(tile): continue
		_prepared[tile] = true
		if tile < 0 or tile >= _allowed.size() or _allowed[tile] == 0: continue
		var active := false
		for j in range(start, start + 24, 3):
			var a := vertices[indices[j]].y; var b := vertices[indices[j + 1]].y; var c := vertices[indices[j + 2]].y
			if maxf(a, maxf(b, c)) - minf(a, minf(b, c)) > MIN_SPAN: active = true
		if not active: continue
		var patch := []; patch.resize(Mesh.ARRAY_MAX)
		for channel in CHANNELS: patch[channel] = source[channel].slice(0, 0)
		patch[Mesh.ARRAY_INDEX] = PackedInt32Array()
		for j in range(start, start + 24, 3):
			_triangle(source, indices.slice(j, j + 3), patch)
		patches[tile] = patch


func _triangle(source: Array, triangle: PackedInt32Array, result: Array) -> void:
	var a: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[0]]
	var b: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[1]]
	var c: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[2]]
	var heights := Vector3(a.y, b.y, c.y)
	var tile := roundi(source[Mesh.ARRAY_TEX_UV2][triangle[0]].y)
	var mask := Vector3(_vertex_mask(triangle[0], tile), _vertex_mask(triangle[1], tile), _vertex_mask(triangle[2], tile))
	var tall := maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) > MIN_SPAN and mask != Vector3.ZERO
	var n := SUBDIV if tall else 1
	if tall: refined_triangles += 1
	var rows := PackedInt32Array()
	for y in n + 1:
		rows.append(result[Mesh.ARRAY_VERTEX].size())
		for x in n - y + 1:
			var w := Vector3(1.0 - float(x + y) / n, float(x) / n, float(y) / n)
			var point := a * w.x + b * w.y + c * w.z
			for channel in CHANNELS:
				var value: Variant = source[channel][triangle[0]] * w.x + source[channel][triangle[1]] * w.y + source[channel][triangle[2]] * w.z
				if channel == Mesh.ARRAY_VERTEX and tall: value = position(value, heights, w, mask.dot(w))
				if channel == Mesh.ARRAY_NORMAL and tall: value = _normal(value, point, heights, w, mask.dot(w))
				result[channel].append(value)
	for y in n:
		for x in n - y:
			result[Mesh.ARRAY_INDEX].append_array(PackedInt32Array([rows[y] + x, rows[y] + x + 1, rows[y + 1] + x]))
			if x + y < n - 1:
				result[Mesh.ARRAY_INDEX].append_array(PackedInt32Array([rows[y] + x + 1, rows[y + 1] + x + 1, rows[y + 1] + x]))


func arrays(source: Array) -> Array:
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var uv2: PackedVector2Array = source[Mesh.ARRAY_TEX_UV2]
	var used := {}
	var ids := PackedInt32Array()
	var result: Array = []
	for i in range(0, indices.size(), 3):
		var tile := roundi(uv2[indices[i]].y)
		if not patches.has(tile):
			ids.append_array(indices.slice(i, i + 3))
			continue
		if used.has(tile): continue
		used[tile] = true
		if result.is_empty(): result = source.duplicate(true)
		var patch: Array = patches[tile]
		var base: int = result[Mesh.ARRAY_VERTEX].size()
		for channel in CHANNELS: result[channel].append_array(patch[channel])
		for index in patch[Mesh.ARRAY_INDEX]: ids.append(base + index)
	if result.is_empty(): return source
	result[Mesh.ARRAY_INDEX] = ids
	result[Mesh.ARRAY_TANGENT] = null
	return result
