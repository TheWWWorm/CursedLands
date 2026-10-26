extends RefCounted
## Refine tall, verified natural walls along a continuous height contour.
## Original heights, collision and tile attributes remain authoritative.
## Snow may inset a sharp convex presentation ridge; rock anchors stay exact.
const SUBDIV := 4
const MIN_SPAN := 3.0
const MAX_OFFSET := 0.6
const SNOW_OFFSET := 0.3
const SnowBevel = preload("res://src/game/fx/terrain_snow_bevel.gd")
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
var _snow_tiles := PackedByteArray()
var _snow_normals := {}
var _snow_limits := {}
var _snow_insets := {}
var _snow_fine := {}
var _snow_fine_normals := {}
var _snow_refined := {}
var _snow_mask := {}
var _snow_edges := {}
var _patch_domains := {}
var _dense_snow := {}
const DENSE_SUBDIV := 16
const DENSE_TRI_VERTICES := 153
const AUTHORED_SECTOR_VERTICES := 16 * 16 * 9
const MAX_DENSE_SNOW := 128


func _init(terrain: EITerrain, field: TerrainCliff) -> void:
	grid_size = field.grid_size
	tile_size = field.tile_size
	_allowed = field.geometry_eligible
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
	_build_snow(terrain, field)


func _point(terrain: EITerrain, index: int) -> Vector3:
	return Vector3(index % grid_size.x + terrain.land_xy[index].x, terrain.heights[index],
		-int(index / grid_size.x) - terrain.land_xy[index].y)


func _edge(a: int, b: int) -> int:
	return mini(a, b) * grid_size.x * grid_size.y + maxi(a, b)


func _grid_index(vertex: int, tile: int) -> int:
	var local := vertex % 9
	return (int(tile / tile_size.x) * 2 + int(local / 3)) * grid_size.x + (tile % tile_size.x) * 2 + local % 3


func _snow_anchor(index: int) -> float:
	if _snow_mask.has(index): return _snow_mask[index]
	var grid := Vector2i(index % grid_size.x, index / grid_size.x)
	for y in range(maxi((grid.y - 1) / 2, 0), mini(grid.y / 2, tile_size.y - 1) + 1):
		for x in range(maxi((grid.x - 1) / 2, 0), mini(grid.x / 2, tile_size.x - 1) + 1):
			if _snow_tiles[y * tile_size.x + x] == 0:
				_snow_mask[index] = 0.0
				return 0.0
	_snow_mask[index] = 1.0
	return 1.0


func _presentation_point(terrain: EITerrain, index: int) -> Vector3:
	return _point(terrain,index) + _snow_insets.get(index,Vector3.ZERO)


func _geometry_normal(terrain: EITerrain, index: int, presentation := false) -> Vector3:
	var grid := Vector2i(index % grid_size.x, index / grid_size.x)
	var result := Vector3.ZERO
	var width := INF
	# Angle weighting prevents the tall wall's area from overwhelming its
	# horizontal cap. Adjacent tiles obtain exactly the same endpoint normal.
	for y in range(maxi(grid.y - 1, 0), mini(grid.y, grid_size.y - 2) + 1):
		for x in range(maxi(grid.x - 1, 0), mini(grid.x, grid_size.x - 2) + 1):
			var a := y * grid_size.x + x
			for tri: Vector3i in [Vector3i(a,a+1,a+grid_size.x), Vector3i(a+1,a+grid_size.x+1,a+grid_size.x)]:
				var ids := [tri.x, tri.y, tri.z]
				var corner := ids.find(index)
				if corner < 0: continue
				var origin := _presentation_point(terrain,index) if presentation else _point(terrain,index)
				var u := (_presentation_point(terrain,ids[(corner+1)%3]) if presentation else _point(terrain,ids[(corner+1)%3]))-origin
				var v := (_presentation_point(terrain,ids[(corner+2)%3]) if presentation else _point(terrain,ids[(corner+2)%3]))-origin
				var cross := u.cross(v)
				if not cross.is_finite() or cross.y <= 1e-7: continue
				var longest := maxf(Vector2(u.x,u.z).length(),maxf(Vector2(v.x,v.z).length(),Vector2(u.x-v.x,u.z-v.z).length()))
				width = minf(width,cross.y/maxf(longest,0.00001))
				result += cross.normalized() * atan2(cross.length(),u.dot(v))
	# Signed MPR offsets can leave very narrow but valid source triangles.
	# Height must not inflate their displacement allowance. Every edge uses
	# the same conservative width at its endpoints, including adjacent caps.
	if not presentation: _snow_limits[index] = minf(SNOW_OFFSET,width*0.2) if is_finite(width) else 0.0
	return result.normalized() if result.length_squared() > 1e-8 else terrain.land_n[index]


func _ridge_inset(terrain: EITerrain, index: int) -> Vector3:
	if _snow_anchor(index) == 0.0: return Vector3.ZERO
	var grid := Vector2i(index%grid_size.x,index/grid_size.x)
	var origin := _point(terrain,index)
	var normals: Array[Vector3] = []
	var sum := Vector3.ZERO; var weight := 0.0
	var minimum := origin.y; var maximum := origin.y; var flat := false
	for y in range(maxi(grid.y-1,0),mini(grid.y,grid_size.y-2)+1):
		for x in range(maxi(grid.x-1,0),mini(grid.x,grid_size.x-2)+1):
			var a := y*grid_size.x+x
			for tri: Vector3i in [Vector3i(a,a+1,a+grid_size.x),Vector3i(a+1,a+grid_size.x+1,a+grid_size.x)]:
				var ids := [tri.x,tri.y,tri.z]; var at := ids.find(index)
				if at<0:continue
				var u := _point(terrain,ids[(at+1)%3])-origin
				var v := _point(terrain,ids[(at+2)%3])-origin
				var cross := u.cross(v); var area := cross.length()
				if area<1e-8:continue
				normals.append(cross/area)
				minimum=minf(minimum,origin.y+minf(u.y,v.y));maximum=maxf(maximum,origin.y+maxf(u.y,v.y))
				flat=flat or (absf(u.y)<0.25 and absf(v.y)<0.25)
				# Positive cotangent weights make a local convex combination.
				# Unlike a grid average, they detect a ridge in the 3D surface.
				var wu := maxf((u-v).dot(-v)/area,0.0)
				var wv := maxf((v-u).dot(-u)/area,0.0)
				sum+=u*wu+v*wv;weight+=wu+wv
	if maximum-minimum<=MIN_SPAN or weight<=1e-8 or (flat and maximum>origin.y+1.0):return Vector3.ZERO
	var agreement := 1.0
	for a: Vector3 in normals:
		for b: Vector3 in normals:agreement=minf(agreement,a.dot(b))
	if agreement>0.85:return Vector3.ZERO
	var normal: Vector3 = _snow_normals[index]
	var curvature := sum/weight
	var inset := Vector3(curvature.x,0.0,curvature.z)
	# Preserve concave corners and walkable feet. Only the outside of a
	# convex natural snow ridge recedes, without changing its authored height.
	if curvature.dot(normal)>=-0.00001 or inset.dot(normal)>=-0.00001:return Vector3.ZERO
	return inset.limit_length(minf(0.25,_snow_limits[index]*1.5))


func _build_snow(terrain: EITerrain, field: TerrainCliff) -> void:
	_snow_tiles.resize(_allowed.size())
	for i in _allowed.size():
		if _allowed[i] > 0 and field.eligible[i] == 0: _snow_tiles[i] = 1
	if _snow_tiles.count(1) == 0: return
	var pending := {}
	for tile in _snow_tiles.size():
		if _snow_tiles[tile] == 0: continue
		var base := int(tile / tile_size.x) * 2 * grid_size.x + (tile % tile_size.x) * 2
		for dy in 2:
			for dx in 2:
				var a := base + dy * grid_size.x + dx
				for tri: Vector3i in [Vector3i(a,a+1,a+grid_size.x), Vector3i(a+1,a+grid_size.x+1,a+grid_size.x)]:
					var ids := [tri.x,tri.y,tri.z]
					var h := Vector3(terrain.heights[tri.x],terrain.heights[tri.y],terrain.heights[tri.z])
					if maxf(h.x,maxf(h.y,h.z))-minf(h.x,minf(h.y,h.z)) <= MIN_SPAN: continue
					for index: int in ids:
						if not _snow_normals.has(index): _snow_normals[index] = _geometry_normal(terrain,index)
					for i in 3:
						var p: int = ids[i]; var q: int = ids[(i+1)%3]; var other: int = ids[(i+2)%3]
						var key := _edge(p,q)
						# Keep the base of a cliff and its walkable floor exact.
						# A level crest may curve, with the adjoining cap refined.
						var foot := is_equal_approx(terrain.heights[p],terrain.heights[q]) and terrain.heights[other] > terrain.heights[p] + MIN_SPAN
						if not pending.has(key): pending[key] = [mini(p,q),maxi(p,q),foot]
						elif foot: pending[key][2] = true
	var normal_indices: Array = _snow_normals.keys()
	for index: int in normal_indices:
		var inset := _ridge_inset(terrain,index)
		if inset.length_squared()>1e-10:_snow_insets[index]=inset
	if not _snow_insets.is_empty():
		var affected := {}
		for index: int in normal_indices:affected[index]=true
		for index: int in _snow_insets:
			var grid := Vector2i(index%grid_size.x,index/grid_size.x)
			for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,1),Vector2i(1,-1)]:
				var neighbour := grid+step
				if neighbour.x>=0 and neighbour.y>=0 and neighbour.x<grid_size.x and neighbour.y<grid_size.y:affected[neighbour.y*grid_size.x+neighbour.x]=true
		for index: int in affected:_snow_normals[index]=_geometry_normal(terrain,index,true)
	for record: Array in pending.values():
		var a: int = record[0]; var b: int = record[1]
		if record[2] or _snow_anchor(a) == 0.0 or _snow_anchor(b) == 0.0: continue
		var edge := _presentation_point(terrain,b)-_presentation_point(terrain,a)
		var na: Vector3 = _snow_normals[a]; var nb: Vector3 = _snow_normals[b]
		# PN-triangle edge controls (Vlachos et al., 2001), restricted to XZ.
		# Clamping control displacements bounds the entire Bézier patch by its
		# convex hull, without clipping individual samples or splitting edges.
		var first := -na * edge.dot(na) / 3.0
		var second := nb * edge.dot(nb) / 3.0
		first.y = 0.0; second.y = 0.0
		var limit := minf(_snow_limits[a],_snow_limits[b])
		first = first.limit_length(limit); second = second.limit_length(limit)
		var inset_a: Vector3 = _snow_insets.get(a,Vector3.ZERO)
		var inset_b: Vector3 = _snow_insets.get(b,Vector3.ZERO)
		var first_base := (inset_a*2.0+inset_b)/3.0
		var second_base := (inset_a+inset_b*2.0)/3.0
		first = (first_base+first).limit_length(SNOW_OFFSET)-first_base
		second = (second_base+second).limit_length(SNOW_OFFSET)-second_base
		if first.length_squared()+second.length_squared() < 1e-10: continue
		_snow_edges[_edge(a,b)] = PackedVector3Array([first,second])
	var bevel := SnowBevel.new(self,terrain,pending.values())
	_snow_fine=bevel.positions;_snow_fine_normals=bevel.normals;_snow_refined=bevel.triangles


func _snow_controls(ids: PackedInt32Array) -> PackedVector3Array:
	var result := PackedVector3Array(); result.resize(7)
	for i in 3:
		var a := ids[i]; var b := ids[(i+1)%3]
		var key := _edge(a,b)
		if not _snow_edges.has(key): continue
		var controls: PackedVector3Array = _snow_edges[key]
		result[i*2] = controls[0 if a < b else 1]
		result[i*2+1] = controls[1 if a < b else 0]
	for i in 6: result[6] += result[i] * 0.25
	var limit := SNOW_OFFSET
	for index in ids: limit = minf(limit,_snow_limits.get(index,SNOW_OFFSET))
	result[6] = result[6].limit_length(limit)
	var center := Vector3.ZERO
	for index in ids:center+=_snow_insets.get(index,Vector3.ZERO)/3.0
	result[6] = (center+result[6]).limit_length(SNOW_OFFSET)-center
	return result


func _snow_position(point: Vector3, weights: Vector3, controls: PackedVector3Array) -> Vector3:
	var u := weights.x; var v := weights.y; var w := weights.z
	return point + 3.0 * (u*u*v*controls[0] + u*v*v*controls[1]
		+ v*v*w*controls[2] + v*w*w*controls[3] + w*w*u*controls[4] + w*u*u*controls[5]) + 6.0*u*v*w*controls[6]


func _source_normal(source: Array, index: int, tile: int) -> Vector3:
	var normal: Vector3 = source[Mesh.ARRAY_NORMAL][index]
	if _snow_tiles.is_empty() or _snow_tiles[tile] == 0: return normal
	var grid := _grid_index(index,tile)
	var fine := (int(grid/grid_size.x)*grid_size.x*SUBDIV+grid%grid_size.x)*SUBDIV
	if _snow_fine_normals.has(fine):return _snow_fine_normals[fine]
	return _snow_normals[grid] if _snow_normals.has(grid) and _snow_anchor(grid) > 0.0 else normal


func _patch_vertex(patch: Array, domain: Vector2i, bary: Vector3, channel: int) -> Vector3:
	var n := domain.y
	var p := Vector2(bary.y,bary.z) * n
	var cell := Vector2i(p.floor()); var f := p - Vector2(cell)
	var row := cell.y * (n + 1) - cell.y * (cell.y - 1) / 2
	var a: int = domain.x + row + cell.x
	if cell.x + cell.y == n: return patch[channel][a]
	var b := a + 1
	var c: int = domain.x + row + n + 1 - cell.y + cell.x
	if f.x + f.y <= 1.0:
		return patch[channel][a] * (1.0-f.x-f.y) + patch[channel][b] * f.x + patch[channel][c] * f.y
	return patch[channel][b] * (1.0-f.y) + patch[channel][c+1] * (f.x+f.y-1.0) + patch[channel][c] * (1.0-f.x)


func _dense_snow_patch(tile: int) -> Array:
	if _dense_snow.has(tile): return _dense_snow[tile]
	# Footprint vertices sample the *installed four-way polyline*, not a finer
	# Bézier curve. This keeps their edges identical to untouched neighbours.
	var result := [PackedVector3Array(),PackedVector3Array()]
	var patch: Array = patches[tile]
	for domain: Vector2i in _patch_domains[tile]:
		for y in DENSE_SUBDIV + 1:
			for x in DENSE_SUBDIV - y + 1:
				var w := Vector3(1.0-float(x+y)/DENSE_SUBDIV,float(x)/DENSE_SUBDIV,float(y)/DENSE_SUBDIV)
				result[0].append(_patch_vertex(patch,domain,w,Mesh.ARRAY_VERTEX))
				result[1].append(_patch_vertex(patch,domain,w,Mesh.ARRAY_NORMAL))
	if _dense_snow.size() >= MAX_DENSE_SNOW: _dense_snow.erase(_dense_snow.keys()[0])
	_dense_snow[tile] = result
	return result


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
		if _snow_tiles[tile] > 0:
			for j in range(start,start+24):
				var index := _grid_index(indices[j],tile)
				if _snow_normals.has(index) and _snow_anchor(index) > 0.0: active = true
		for j in range(start, start + 24, 3):
			var a := vertices[indices[j]].y; var b := vertices[indices[j + 1]].y; var c := vertices[indices[j + 2]].y
			if maxf(a, maxf(b, c)) - minf(a, minf(b, c)) > MIN_SPAN: active = true
			if _snow_tiles[tile] > 0:
				for k in 3:
					if _snow_edges.has(_edge(_grid_index(indices[j+k],tile),_grid_index(indices[j+(k+1)%3],tile))): active = true
		if not active: continue
		var patch := []; patch.resize(Mesh.ARRAY_MAX)
		for channel in CHANNELS: patch[channel] = source[channel].slice(0, 0)
		patch[Mesh.ARRAY_INDEX] = PackedInt32Array()
		var domains: Array[Vector2i] = []
		for j in range(start, start + 24, 3):
			var first: int = patch[Mesh.ARRAY_VERTEX].size()
			_triangle(source, indices.slice(j, j + 3), patch)
			domains.append(Vector2i(first,SUBDIV if patch[Mesh.ARRAY_VERTEX].size()-first>3 else 1))
		patches[tile] = patch
		if _snow_tiles[tile] > 0: _patch_domains[tile] = domains


func _triangle(source: Array, triangle: PackedInt32Array, result: Array) -> void:
	var a: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[0]]
	var b: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[1]]
	var c: Vector3 = source[Mesh.ARRAY_VERTEX][triangle[2]]
	var heights := Vector3(a.y, b.y, c.y)
	var tile := roundi(source[Mesh.ARRAY_TEX_UV2][triangle[0]].y)
	var mask := Vector3(_vertex_mask(triangle[0], tile), _vertex_mask(triangle[1], tile), _vertex_mask(triangle[2], tile))
	var tall := maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) > MIN_SPAN and mask != Vector3.ZERO
	var snowy := _snow_tiles[tile] > 0
	var ids := PackedInt32Array([_grid_index(triangle[0],tile),_grid_index(triangle[1],tile),_grid_index(triangle[2],tile)])
	var controls := _snow_controls(ids) if snowy else PackedVector3Array()
	var curved := snowy and controls != PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	var snow_mask := Vector3(_snow_anchor(ids[0]),_snow_anchor(ids[1]),_snow_anchor(ids[2])) if snowy else Vector3.ZERO
	var normals := PackedVector3Array([_source_normal(source,triangle[0],tile),_source_normal(source,triangle[1],tile),_source_normal(source,triangle[2],tile)])
	if snowy:
		a+=_snow_insets.get(ids[0],Vector3.ZERO);b+=_snow_insets.get(ids[1],Vector3.ZERO);c+=_snow_insets.get(ids[2],Vector3.ZERO)
	# A planar snow triangle needs no extra samples. Only curved edges and
	# transitions to the existing rock contour require the four-way patch.
	var cell:=Vector2i(mini(ids[0]%grid_size.x,mini(ids[1]%grid_size.x,ids[2]%grid_size.x)),mini(ids[0]/grid_size.x,mini(ids[1]/grid_size.x,ids[2]/grid_size.x)))
	var cell_base:=cell.y*grid_size.x+cell.x
	var refine := curved or (tall and (not snowy or snow_mask != Vector3.ONE)) or _snow_refined.has(cell_base*2+int(not cell_base in ids))
	var n := SUBDIV if refine else 1
	if refine: refined_triangles += 1
	var rows := PackedInt32Array()
	for y in n + 1:
		rows.append(result[Mesh.ARRAY_VERTEX].size())
		for x in n - y + 1:
			var w := Vector3(1.0 - float(x + y) / n, float(x) / n, float(y) / n)
			var point := a * w.x + b * w.y + c * w.z
			var grid:=Vector2.ZERO
			for i in 3:grid+=Vector2(ids[i]%grid_size.x,ids[i]/grid_size.x)*w[i]
			var fine:=roundi(grid.y*SUBDIV)*grid_size.x*SUBDIV+roundi(grid.x*SUBDIV)
			for channel in CHANNELS:
				var value: Variant = source[channel][triangle[0]] * w.x + source[channel][triangle[1]] * w.y + source[channel][triangle[2]] * w.z
				if channel == Mesh.ARRAY_VERTEX and tall: value = position(value, heights, w, mask.dot(w))
				if channel == Mesh.ARRAY_VERTEX and snowy:
					value = value.lerp(_snow_position(point,w,controls),snow_mask.dot(w))
					if _snow_fine.has(fine):value=_snow_fine[fine]
				if channel == Mesh.ARRAY_NORMAL:
					value = normals[0]*w.x + normals[1]*w.y + normals[2]*w.z
					if tall:value=_normal(value,point,heights,w,mask.dot(w))
					if snowy and _snow_fine_normals.has(fine):value=_snow_fine_normals[fine]
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
		if _snow_tiles[tile] > 0 and indices[i] >= AUTHORED_SECTOR_VERTICES:
			if not used.has(tile):
				used[tile] = true
				if result.is_empty(): result = source.duplicate(true)
				var dense := _dense_snow_patch(tile)
				var first := indices[i]
				# Both native and script snow workers append eight contiguous
				# 16-way triangles after the immutable authored sector vertices.
				assert(first + DENSE_TRI_VERTICES * 8 <= result[Mesh.ARRAY_VERTEX].size())
				for j in dense[0].size():
					result[Mesh.ARRAY_VERTEX][first+j] = dense[0][j]
					result[Mesh.ARRAY_NORMAL][first+j] = dense[1][j]
			ids.append_array(indices.slice(i,i+3))
			continue
		if used.has(tile): continue
		used[tile] = true
		if result.is_empty(): result = source.duplicate(true)
		var patch: Array = patches[tile]
		var base: int = result[Mesh.ARRAY_VERTEX].size()
		for channel in CHANNELS: result[channel].append_array(patch[channel])
		for index in patch[Mesh.ARRAY_INDEX]: ids.append(base + index)
	# Unrefined cap/floor triangles share corrected endpoint normals with the
	# neighbouring wall. No extra geometry is needed along straight edges.
	if not _snow_normals.is_empty():
		for i in mini(source[Mesh.ARRAY_NORMAL].size(),AUTHORED_SECTOR_VERTICES):
			var tile := roundi(uv2[i].y)
			var normal := _source_normal(source,i,tile)
			if normal == source[Mesh.ARRAY_NORMAL][i]: continue
			if result.is_empty(): result = source.duplicate(true)
			result[Mesh.ARRAY_NORMAL][i] = normal
	if result.is_empty(): return source
	result[Mesh.ARRAY_INDEX] = ids
	result[Mesh.ARRAY_TANGENT] = null
	return result
