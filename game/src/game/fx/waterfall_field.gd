extends RefCounted
## Optional waterfall classification from authored liquid vertices, not ground
## slope or the smoothed current field. EI XY grid; heights are Godot Y.
## Reference rules: owned renderer R1 procedural_falls.h and
## owned_terrain_front_end.h, commit 0092dc6e1d7c4aab3f74644a79e9bfca11ecf293.
const EDGE_DROP := 0.9
const MIN_DROP := 2.5
const MIN_STEEPNESS := 1.4
const MAX_WIDTH := 30.0
const MAX_FALLS := 32
const NEIGHBOURS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
var size := Vector2i.ZERO
var rest := PackedFloat32Array()
var owners := PackedInt32Array()
var bed := PackedFloat32Array()
var layer := PackedFloat32Array()
var exposed := PackedFloat32Array()
var falls: Array[Dictionary] = []
var conflicts := 0
var builds := 0
var build_us := 0
var candidates := 0
var levels := PackedFloat32Array()
var _indexed := false
var _eligible := PackedInt32Array()
var _cardinal := PackedInt32Array()


func _init(terrain: EITerrain = null) -> void:
	if terrain == null: return
	size = Vector2i(terrain.sectors_x*32+1,terrain.sectors_y*32+1)
	if size.x < 2 or size.y < 2 or size.x*size.y > 4194304: return
	rest.resize(size.x*size.y); rest.fill(INF)
	owners.resize(rest.size()); owners.fill(-1)
	bed = terrain.heights
	for node in terrain.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Water_") or node.mesh == null: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var material: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if vertices.size()%9 != 0 or material.size() != vertices.size(): continue
		for first in range(0,vertices.size(),9):
			# Recover the whole tile before its vertices: type-4 XY offsets
			# exceed half a metre, so rounding each point is not reliable.
			var tile := Vector2i(roundi(vertices[first].x/2.0),roundi(-vertices[first].z/2.0))
			if tile.x < 0 or tile.y < 0 or tile.x*2+2 >= size.x or tile.y*2+2 >= size.y: continue
			var cell := tile.y*2*(size.x-1)+tile.x*2
			if cell >= terrain.liquid_ground.size() or terrain.liquid_ground[cell] in [13,14,255]: continue
			for lane in 9:
				var index := (tile.y*2+lane/3)*size.x+tile.x*2+lane%3
				var m := int(material[first+lane].y+0.5)%64
				if m >= terrain.materials.size() or terrain._lava[m] > 0.0: continue
				var authored: Dictionary = terrain.materials[m]
				if not int(authored.get("type",0)) in [2,3,4] or float(authored.get("self_illum",0.0)) > 0.0: continue
				var height := vertices[first+lane].y
				if not is_finite(height): continue
				if owners[index] >= 0 and (owners[index] != m or absf(rest[index]-height) > 0.001):
					owners[index] = -2; conflicts += 1
				elif owners[index] != -2:
					owners[index] = m; rest[index] = height
	refresh(terrain._level)


## The authored snapshot is immutable. Keep its row-major candidate order
## and cardinal neighbours once; flood updates only change height/exposure.
func _index() -> void:
	for i in rest.size():
		if owners[i]>=0 and is_finite(rest[i]) and is_finite(bed[i]): _eligible.append(i)
	_cardinal.resize(_eligible.size()*4)
	for k in _eligible.size():
		var i := _eligible[k]; var x := i%size.x
		_cardinal[k*4] = i+1 if x+1<size.x else -1
		_cardinal[k*4+1] = i-1 if x>0 else -1
		_cardinal[k*4+2] = i+size.x if i+size.x<rest.size() else -1
		_cardinal[k*4+3] = i-size.x if i>=size.x else -1
	_indexed = true


func refresh(next_levels: PackedFloat32Array) -> bool:
	if levels == next_levels and builds > 0: return false
	levels = next_levels.duplicate()
	falls.clear(); candidates = 0
	var count := size.x*size.y
	if size.x < 2 or size.y < 2 or count > 4194304 or rest.size() != count or owners.size() != count or bed.size() != count: return false
	var started := Time.get_ticks_usec()
	if not _indexed: _index()
	layer.resize(count); layer.fill(INF)
	exposed.resize(count); exposed.fill(INF)
	var active := PackedInt32Array()
	for k in _eligible.size():
		var i := _eligible[k]
		var m := owners[i]
		if m >= levels.size(): continue
		var height := rest[i]+levels[m]
		if not is_finite(height): continue
		layer[i] = height
		if height < bed[i]-0.05: continue
		exposed[i] = height; active.append(k)
	var spikes := PackedByteArray(); spikes.resize(count)
	var potential := PackedInt32Array()
	for k in active:
		var i := _eligible[k]
		var above := 0; var below := 0; var neighbours := 0
		for d in 4:
			var other := _cardinal[k*4+d]
			if other<0 or not is_finite(exposed[other]): continue
			neighbours += 1
			var difference := exposed[other]-exposed[i]
			above += int(difference >= EDGE_DROP); below += int(difference <= -EDGE_DROP)
		spikes[i] = int(neighbours >= 2 and (above == neighbours or below == neighbours))
		# Only these vertices can satisfy the identical edge predicate below.
		# Flat water needs no second cardinal scan or cluster-start scan.
		if not spikes[i] and above+below>0: potential.append(k)
	var edges := PackedByteArray(); edges.resize(count)
	for k in potential:
		var i := _eligible[k]
		for d in 4:
			var other := _cardinal[k*4+d]
			if other>=0 and is_finite(exposed[other]) and not spikes[other] and absf(exposed[i]-exposed[other]) >= EDGE_DROP:
				edges[i] = 1; break
	var seen := PackedByteArray(); seen.resize(count)
	for k in potential:
		var start := _eligible[k]
		if not edges[start] or seen[start]: continue
		var cluster := PackedInt32Array()
		var stack := PackedInt32Array([start]); seen[start] = 1
		while not stack.is_empty():
			var at := stack[stack.size()-1]; stack.resize(stack.size()-1); cluster.append(at)
			var p := Vector2i(at%size.x,at/size.x)
			for dy in range(-1,2):
				for dx in range(-1,2):
					var q := p+Vector2i(dx,dy)
					if not inside(q): continue
					var i := q.y*size.x+q.x
					if edges[i] and not seen[i]: seen[i] = 1; stack.append(i)
		var fall := classify(cluster,edges)
		if fall.is_empty(): continue
		candidates += 1
		if falls.size() < MAX_FALLS: falls.append(fall)
	build_us = Time.get_ticks_usec()-started; builds += 1
	return true


func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y


func valid(p: Vector2i) -> bool:
	return inside(p) and is_finite(exposed[p.y*size.x+p.x])


func classify(cluster: PackedInt32Array, edges: PackedByteArray) -> Dictionary:
	if cluster.size() < 4: return {}
	var low := INF; var high := -INF; var identity := cluster[0]
	for i in cluster:
		var p := Vector2i(i%size.x,i/size.x)
		if p.x < 3 or p.y < 3 or p.x > size.x-4 or p.y > size.y-4: return {}
		low = minf(low,exposed[i]); high = maxf(high,exposed[i]); identity = mini(identity,i)
	if high-low < MIN_DROP: return {}
	var middle := (low+high)*0.5
	var ring := {}; var tops := []; var bottoms := []
	var top_centre := Vector2.ZERO; var bottom_centre := Vector2.ZERO
	for i in cluster:
		var p := Vector2i(i%size.x,i/size.x)
		for dy in range(-2,3):
			for dx in range(-2,3):
				var q := p+Vector2i(dx,dy)
				if not valid(q): continue
				var at := q.y*size.x+q.x
				if ring.has(at): continue
				ring[at] = true
				if edges[at]: continue
				if exposed[at] >= middle: tops.append(exposed[at]); top_centre += Vector2(q)
				else: bottoms.append(exposed[at]); bottom_centre += Vector2(q)
	if tops.is_empty() or bottoms.is_empty(): return {}
	tops.sort(); bottoms.sort()
	var top: float = tops[tops.size()/2]; var bottom: float = bottoms[bottoms.size()/2]
	if top-bottom < MIN_DROP: return {}
	var direction := bottom_centre/bottoms.size()-top_centre/tops.size()
	if direction.length() < 0.001: return {}
	direction = direction.normalized()
	var side := Vector2(-direction.y,direction.x)
	var lip := -INF; var side_low := INF; var side_high := -INF
	var top_owner := -1; var bottom_owner := -1; var foot := INF
	for at: int in ring:
		var p := Vector2(at%size.x,at/size.x)
		if exposed[at] >= top-0.4:
			lip = maxf(lip,p.dot(direction)); top_owner = owners[at]
		elif not edges[at] and exposed[at] <= bottom+0.4: bottom_owner = owners[at]
	for at in cluster:
		var across := Vector2(at%size.x,at/size.x).dot(side)
		side_low = minf(side_low,across); side_high = maxf(side_high,across)
	if top_owner < 0 or bottom_owner < 0: return {}
	for at: int in ring:
		var p := Vector2(at%size.x,at/size.x)
		var across := p.dot(side)
		if not edges[at] and exposed[at] <= bottom+0.4 and across >= side_low-0.5 and across <= side_high+0.5:
			foot = minf(foot,p.dot(direction))
	if not is_finite(foot) or foot <= lip: return {}
	var steepness := (top-bottom)/maxf(foot-lip,0.5)
	var width := side_high-side_low+1.0
	if width > MAX_WIDTH or width < 1.0 or steepness < MIN_STEEPNESS: return {}
	var centre := direction*lip+side*(side_low+side_high)*0.5
	return {"id":identity,"lip":centre,"direction":direction,"width":width,"top":top,"bottom":bottom,
		"run":foot-lip,"steepness":steepness,"top_owner":top_owner,"bottom_owner":bottom_owner,"vertices":cluster.size()}


## Height/exposure interpolation for shell placement; an absent corner does
## not manufacture a surface. Ground still occludes each final vertex.
func sample(point: Vector2) -> Vector2:
	var p := Vector2i(floori(point.x),floori(point.y))
	if not inside(p) or not inside(p+Vector2i.ONE): return Vector2(INF,0)
	var f := point-Vector2(p)
	var height := 0.0; var visible_share := 0.0
	for dy in 2:
		for dx in 2:
			var at := (p.y+dy)*size.x+p.x+dx
			if not is_finite(layer[at]): return Vector2(INF,0)
			var weight := (f.x if dx else 1.0-f.x)*(f.y if dy else 1.0-f.y)
			height += layer[at]*weight
			visible_share += float(is_finite(exposed[at]))*weight
	return Vector2(height,visible_share)


func ground_at(point: Vector2) -> float:
	var p := Vector2i(floori(point.x),floori(point.y))
	if not inside(p) or not inside(p+Vector2i.ONE): return INF
	var f := point-Vector2(p)
	var at := p.y*size.x+p.x
	return lerpf(lerpf(bed[at],bed[at+1],f.x),lerpf(bed[at+size.x],bed[at+size.x+1],f.x),f.y)
