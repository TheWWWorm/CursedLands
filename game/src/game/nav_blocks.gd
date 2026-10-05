extends RefCounted
## CAIMap's static4 m representative graph (5afae0), native
## sorted-frontier floods, and bidirectional block route.
## Static entries are evaluated lazily; invalidation follows the map revision.
const BLOCK := 8
const LIMIT := 0x7fffffff
const DIRECTIONS := [Vector2i.ZERO,Vector2i(0,-1),Vector2i(-1,-1),Vector2i(-1,0),Vector2i(-1,1),
	Vector2i(0,1),Vector2i(1,1),Vector2i(1,0),Vector2i(1,-1)]
const CELL_ORDER := [4,5,6,7,3,2,1,8]
##  5bfc40 ordered nearest-cell offsets. Equal-distance order
## follows the original CRT sort, so fallback choices agree at a blocked door.
const NEAR_OFFSETS := [
	0,0,1,0,1,1,0,1,-1,1,-1,0,1,-1,0,-1,-1,-1,-2,0,2,0,-2,1,2,1,1,2,0,2,-1,2,
	0,-2,-1,-2,2,-1,-2,-1,1,-2,2,-2,-2,2,2,2,-2,-2,3,0,-1,3,-3,-1,3,-1,-3,0,-3,1,3,1,
	-1,-3,0,3,1,3,1,-3,0,-3,2,-3,-3,-2,-3,2,3,-2,2,3,3,2,-2,-3,-2,3,-3,3,3,-3,-3,-3,
	3,3,-1,4,0,4,1,-4,4,0,1,4,-1,-4,-4,0,-4,1,-4,-1,0,-4,4,1,4,-1,2,4,-2,4,-4,2,
	-2,-4,4,2,-4,-2,2,-4,4,-2,3,4,-3,-4,4,-3,-4,-3,3,-4,-3,4,4,3,-4,3,5,1,-1,-5,-1,5,
	5,0,-5,-1,5,-1,-5,0,1,-5,0,5,0,-5,-5,1,1,5,-2,5,5,-2,2,-5,5,2,2,5,-5,2,-5,-2,
	-2,-5,-4,-4,-4,4,4,-4,4,4,-3,-5,5,-3,3,-5,-3,5,-5,3,3,5,5,3,-5,-3,1,6,-6,1,0,6,
	6,-1,-6,0,6,1,0,-6,-4,5,-4,-5,1,-6,4,-5,5,4,-5,4,6,0,-1,6,-1,-6,-6,-1,4,5,5,-4,
	-5,-4,6,-2,-6,2,-2,-6,-6,-2,2,-6,-2,6,6,2,2,6,3,6,-3,-6,3,-6,-6,3,-3,6,-6,-3,6,3,
	6,-3,-5,5,-5,-5,5,-5,5,5,-4,-6,4,6,4,-6,-4,6,6,-4,-6,-4,-6,4,6,4,0,-7,-1,-7,1,-7,
	0,7,-7,-1,1,7,7,-1,-7,1,-1,7,7,0,-7,0,7,1,-2,-7,7,-2,7,2,-7,2,2,-7,2,7,-7,-2,
	-2,7,3,-7,3,7,-3,7,7,-3,-7,-3,-3,-7,7,3,-7,3,-5,-6,-6,-5,6,-5,5,-6,-5,6,-6,5,6,5,
	5,6,7,4,-7,4,7,-4,-4,7,-7,-4,-4,-7,4,7,4,-7,-8,-1,-1,-8,8,-1,8,1,0,-8,1,8,-8,0,
	1,-8,8,0,-1,8,0,8,-8,1,-8,2,-2,-8,8,2,2,-8,2,8,-6,-6,6,6,-8,-2,8,-2,-6,6,-2,8,
	6,-6,7,5,5,7,5,-7,-7,5,-7,-5,-5,7,-5,-7,7,-5,-8,3,8,3,8,-3,-3,-8,3,8,-8,-3,-3,8,
	3,-8,-4,-8,-4,8,4,-8,-8,-4,8,-4,8,4,-8,4,4,8,7,-6,-6,7,6,7,7,6,-7,-6,6,-7,-7,6,
	-6,-7,-1,-9,0,-9,-9,1,9,1,-9,0,1,-9,-9,-1,-1,9,9,0,0,9,1,9,9,-1,2,-9,9,2,-2,-9,
	2,9,-8,5,-9,-2,-2,9,-5,-8,5,8,9,-2,-5,8,8,5,-9,2,5,-8,8,-5,-8,-5,-9,3,9,3,3,9,
	3,-9,-3,9,-3,-9,-9,-3,9,-3,-7,-7,-7,7,7,-7,7,7,-4,9,9,-4,4,-9,-9,4,-9,-4,-4,-9,9,4,
	4,9,8,-6,-8,6,6,-8,-6,8,-6,-8,6,8,8,6,-8,-6,-5,9,9,-5,5,-9,-9,5,9,5,-9,-5,5,9,
	-5,-9,1,-10,-10,1,-10,-1,0,-10,-10,0,10,1,-1,-10,10,-1,10,0,-1,10,0,10,1,10,-2,10,10,-2,-2,-10,
	-10,-2,10,2,2,-10,2,10,-10,2,3,-10,-3,10,3,10,-10,3,8,-7,10,3,-8,-7,8,7,7,8,10,-3,7,-8,
	-10,-3,-7,8,-3,-10,-7,-8,-8,7,6,-9,-9,6,9,6,-9,-6,6,9,9,-6,-6,9,-6,-9,-10,4,4,-10,10,4,
	4,10,-4,-10,-4,10,10,-4,-10,-4,10,-5,-5,-10,5,-10,10,5,5,10,-10,-5,-5,10,-10,5,-8,8,-8,-8,8,-8,
	8,8,9,7,-9,7,7,-9,9,-7,-7,-9,-7,9,-9,-7,7,9,-6,10,10,6,-10,-6,-6,-10,10,-6,6,10,-10,6,
	6,-10,-8,-9,-8,9,9,8,9,-8,8,9,-9,8,-9,-8,8,-9,7,-10,10,-7,-10,-7,10,7,7,10,-10,7,-7,-10,
	-7,10,9,9,9,-9,-9,-9,-9,9,-8,10,10,-8,10,8,8,10,-10,8,-10,-8,-8,-10,8,-10,-9,10,10,9,10,-9,
	-10,-9,-10,9,9,-10,-9,-10,9,10,10,-10,-10,-10,10,10,-10,10]
var _nav: WeakRef
var nav:
	get: return _nav.get_ref()
	set(value): _nav = weakref(value)
var layer
var _width := 0
var _height := 0
var _land := PackedByteArray()
var _cost := PackedInt32Array()
var _heights := PackedInt32Array()
var _slopes := PackedInt32Array()
var _cost_lookup: Array = []
var _offsets := PackedInt32Array()
var _links := PackedInt32Array()
var _edges8 := PackedInt32Array()
var _flat_edges8 := PackedInt32Array()
var size := Vector2i.ZERO
var representatives := {}
var raw_edges := {}
var connections := {}
var last_blocks: Array[Vector2i] = []
var components := {}
var next_component := 0
var _reach_labels := {}
var _tile_labels := {}
var _seed_costs := {}
var _seed_topology := {}
var _cell_components := {}
var _single_source := {}
var _undirected := true
var profile := false
var profile_us := {}
var profile_counts := {}

class CellFrontier:
	extends RefCounted
	var rect: Rect2i
	var costs: Array[int] = []
	var parents: Array[int] = []
	var closed: Array[int] = []
	var queue: Array = []
	var stamp := PackedInt32Array()
	var reverse := false
	var flat := false
	var threshold := 0

func _init(grid, movement_layer) -> void:
	nav = grid
	layer = movement_layer
	size = nav.size / BLOCK
	_width = grid.size.x;_height = grid.size.y
	_land = movement_layer.land;_cost = movement_layer.cost
	_heights = grid._hq;_slopes = grid._slope_tab[0 if movement_layer.cls == 0 else 1]
	_cost_lookup = grid.STEP_COST
	for d: Vector2i in DIRECTIONS: _offsets.append(d.x+d.y*_width)
	_links.resize(_width*_height);_links.fill(-1)
	_edges8.resize(_links.size()*8)
	_flat_edges8.resize(_edges8.size())
	for i in _slopes.size():
		if (_slopes[i] >= 0) != (_slopes[_slopes.size()-1-i] >= 0):
			_undirected = false
			break

func _profile(part: String, started: int) -> void:
	if not profile: return
	profile_us[part] = int(profile_us.get(part,0))+Time.get_ticks_usec()-started
	profile_counts[part] = int(profile_counts.get(part,0))+1

func representative(b: Vector2i) -> Vector2i:
	var key := b.y * size.x + b.x
	if representatives.has(key): return representatives[key]
	var started := Time.get_ticks_usec() if profile else 0
	var chosen := b * BLOCK + Vector2i(3,3)
	var best := 0
	var crossing := false
	for radius in range(1,5):
		for y in range(4-radius,4+radius):
			for x in range(4-radius,4+radius):
				var p := b * BLOCK + Vector2i(x,y)
				var value := _value(p)
				if value == 0 or crossing and value <= best: continue
				var f := _reachable(Rect2i(b * BLOCK,Vector2i(9,9)),p)
				var left := false
				var right := false
				var top := false
				var bottom := false
				for i in range(9):
					left = left or _seen(f,b*BLOCK+Vector2i(0,i))
					right = right or _seen(f,b*BLOCK+Vector2i(8,i))
					top = top or _seen(f,b*BLOCK+Vector2i(i,0))
					bottom = bottom or _seen(f,b*BLOCK+Vector2i(i,8))
				var connects := left and right or top and bottom
				if connects or not crossing:
					chosen = p
					best = value
					crossing = connects
	representatives[key] = chosen
	_profile("representatives",started)
	return chosen

func _value(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= _width or p.y >= _height: return 0
	var i := p.y*_width+p.x
	return 0 if _land[i] != 0 else _cost_lookup.find(_cost[i])

func _raw(b: Vector2i) -> PackedInt32Array:
	var key := b.y*size.x+b.x
	if raw_edges.has(key): return raw_edges[key]
	var started := Time.get_ticks_usec() if profile else 0
	var result := PackedInt32Array()
	var goals: Array[Vector2i] = []
	for k in range(1,9):
		var q: Vector2i = b+DIRECTIONS[k]
		if _inside(q): goals.append(representative(q))
	var f := _static_distances(Rect2i(b*BLOCK-Vector2i(8,8),Vector2i(25,25)),representative(b),false,goals)
	for k in range(1,9):
		var q: Vector2i = b + DIRECTIONS[k]
		var cost := cost_at(f,representative(q)) if _inside(q) else LIMIT
		result.append(mini(cost >> 7,32767) if cost < LIMIT else -1)
	raw_edges[key] = result
	_profile("raw_edges",started)
	return result

func edge(b: Vector2i,k: int) -> int:
	var q: Vector2i = b+DIRECTIONS[k]
	if not _inside(b) or not _inside(q): return -1
	return mini(_raw(b)[k-1],_raw(q)[((k+3)&7)])

func _inside(b: Vector2i) -> bool:
	return b.x >= 0 and b.y >= 0 and b.x < size.x and b.y < size.y

## Native per-cell costs are immutable for this graph's map revision. Cache
## its eight directed costs once; overlapping25/32-cell windows read the
## same values. Two packed tables cost64bytes per grid cell/movement class.
func _link_mask(i: int) -> int:
	if _links[i] >= 0: return _links[i]
	var x := i%_width;var y := i/_width
	var mask := 0
	for k in range(1,9):
		var d: Vector2i = DIRECTIONS[k]
		var qx := x+d.x;var qy := y+d.y
		var slot := i*8+k-1
		_edges8[slot] = -1;_flat_edges8[slot] = -1
		if qx < 0 or qy < 0 or qx >= _width or qy >= _height: continue
		var to := i+_offsets[k]
		var dh := _heights[to]-_heights[i]+1023
		if _land[to] != 0 or dh < 0 or dh >= _slopes.size(): continue
		var slope := _slopes[dh];var cost := _cost[to]
		if slope < 0 or cost < 0: continue
		var step := 0x5a8 if (k&1) == 0 else 0x400
		_edges8[slot] = ((slope*cost)>>10)*step>>10
		_flat_edges8[slot] = slope*step>>10
		mask |= 1<<(k-1)
	_links[i] = mask
	return mask

func _cached_step(i: int,k: int,reverse: bool,flat := false) -> int:
	var from := i+_offsets[k] if reverse else i
	if _links[from] < 0: _link_mask(from)
	var slot := from*8+(((k+3)&7) if reverse else k-1)
	return _flat_edges8[slot] if flat else _edges8[slot]


## Connectivity never uses a positive step's magnitude. This queue visits
## exactly the native finite cells without sorting their weighted costs.
func _reachable(rect: Rect2i,start: Vector2i,reverse := false) -> Dictionary:
	# Native up/down costs differ, but their finite-step topology is symmetric.
	# One static component labelling serves all candidate floods in this box;
	# it cannot change a route's weighted cost or frontier tie order.
	if _undirected and rect.has_point(start) and start.x >= 0 and start.y >= 0 \
			and start.x < _width and start.y < _height and _land[start.y*_width+start.x] == 0:
		if not _reach_labels.has(rect): _reach_labels[rect] = _label_rect(rect)
		var labels: PackedInt32Array = _reach_labels[rect]
		return {"rect":rect,"labels":labels,"component":labels[(start.y-rect.position.y)*rect.size.x+start.x-rect.position.x]}
	var rw := rect.size.x;var rh := rect.size.y
	var seen := PackedByteArray();seen.resize(rw*rh)
	var pending := PackedInt32Array()
	if rect.has_point(start):
		var i := (start.y-rect.position.y)*rw+start.x-rect.position.x
		seen[i] = 1;pending.append(i)
	var at := 0
	while at < pending.size():
		var i := pending[at];at += 1
		var x := i%rw;var y := i/rw
		var gx := rect.position.x+x;var gy := rect.position.y+y
		if gx < 0 or gy < 0 or gx >= _width or gy >= _height: continue
		var gi := gy*_width+gx
		for k: int in CELL_ORDER:
			var d: Vector2i = DIRECTIONS[k]
			var qx := x+d.x;var qy := y+d.y
			if qx < 0 or qy < 0 or qx >= rw or qy >= rh: continue
			if gx+d.x < 0 or gy+d.y < 0 or gx+d.x >= _width or gy+d.y >= _height: continue
			var qi := qy*rw+qx
			if seen[qi] != 0: continue
			if _cached_step(gi,k,reverse) < 0: continue
			seen[qi] = 1;pending.append(qi)
	return {"rect":rect,"seen":seen}

func _connected_rect(rect: Rect2i) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > _width or rect.end.y > _height: return false
	for y in range(rect.position.y,rect.end.y):
		var row := _land.slice(y*_width+rect.position.x,y*_width+rect.end.x)
		if row.count(0) != rect.size.x: return false
	for y in range(rect.position.y,rect.end.y):
		var i := y*_width+rect.position.x
		for x in rect.size.x:
			if x+1 < rect.size.x:
				var dh := _heights[i+x+1]-_heights[i+x]+1023
				if dh < 0 or dh >= _slopes.size() or _slopes[dh] < 0: return false
			if y+1 < rect.end.y:
				var dh := _heights[i+x+_width]-_heights[i+x]+1023
				if dh < 0 or dh >= _slopes.size() or _slopes[dh] < 0: return false
	return true


func _label_rect(rect: Rect2i) -> PackedInt32Array:
	var started := Time.get_ticks_usec() if profile else 0
	var labels := PackedInt32Array()
	if _connected_rect(rect):
		labels.resize(rect.size.x*rect.size.y);labels.fill(1)
		_profile("open_rect",started)
	else:
		labels = _compose_labels(rect) if _undirected and rect.position.x%8 == 0 and rect.position.y%8 == 0 \
			and rect.size.x in [9,25] and rect.size.y == rect.size.x else _scan_labels(rect)
	_profile("topology",started)
	return labels


## Static9/25-cell windows overlap on8-cell boundaries. Components inside
## complete8x8 tiles can be reused; the one-cell boundary strips are labelled
## separately, so no path outside the requested rectangle joins its labels.
## Only native finite edges on tile seams are then needed. Numeric labels are
## private; their equivalence classes match the complete cell scan.
func _compose_labels(rect: Rect2i) -> PackedInt32Array:
	var rw := rect.size.x
	var labels := PackedInt32Array();labels.resize(rw*rect.size.y)
	var parents: Array[int] = [0]
	for oy in range(0,rect.size.y,8):
		for ox in range(0,rw,8):
			var piece := Rect2i(rect.position+Vector2i(ox,oy),Vector2i(mini(8,rw-ox),mini(8,rect.size.y-oy)))
			if not _tile_labels.has(piece): _tile_labels[piece] = _scan_labels(piece)
			var local: PackedInt32Array = _tile_labels[piece]
			var mapping := PackedInt32Array();mapping.resize(65)
			for y in piece.size.y:
				for x in piece.size.x:
					var value := local[y*piece.size.x+x]
					if value == 0: continue
					if mapping[value] == 0:
						mapping[value] = parents.size();parents.append(parents.size())
					labels[(oy+y)*rw+ox+x] = mapping[value]
	# Every cross-tile cardinal/diagonal edge has an endpoint on one of
	# these seams. `_link_mask` uses the same signed native slope gates.
	for x in range(8,rw,8):
		for y in rect.size.y:
			var i := y*rw+x
			if labels[i] == 0: continue
			var gi := (rect.position.y+y)*_width+rect.position.x+x
			var links := _link_mask(gi)
			if (links&4) != 0: _join_labels(parents,labels[i],labels[i-1])
			if y > 0 and (links&2) != 0: _join_labels(parents,labels[i],labels[i-rw-1])
			if y+1 < rect.size.y and (links&8) != 0: _join_labels(parents,labels[i],labels[i+rw-1])
	for y in range(8,rect.size.y,8):
		for x in rw:
			var i := y*rw+x
			if labels[i] == 0: continue
			var gi := (rect.position.y+y)*_width+rect.position.x+x
			var links := _link_mask(gi)
			if (links&1) != 0: _join_labels(parents,labels[i],labels[i-rw])
			if x > 0 and (links&2) != 0: _join_labels(parents,labels[i],labels[i-rw-1])
			if x+1 < rw and (links&128) != 0: _join_labels(parents,labels[i],labels[i-rw+1])
	# Every union points the larger root at the smaller one. Resolve roots
	# once in ascending order; all parent roots are already resolved before
	# their children. This keeps the exact labels without repeating each
	# root walk for every cell in overlapping windows.
	for i in range(1,parents.size()): parents[i] = parents[parents[i]]
	for i in labels.size(): labels[i] = parents[labels[i]]
	return labels


static func _join_labels(parents: Array[int],a: int,b: int) -> void:
	if a == 0 or b == 0 or a == b: return
	while parents[a] != a: a = parents[a]
	while parents[b] != b: b = parents[b]
	if a != b: parents[maxi(a,b)] = mini(a,b)


func _scan_labels(rect: Rect2i) -> PackedInt32Array:
	var rw := rect.size.x;var rh := rect.size.y
	var labels := PackedInt32Array();labels.resize(rw*rh)
	# A completely open rectangle with finite cardinal links has one
	# component. This proves the same reachability without eight neighbours
	# per cell; diagonals cannot disconnect already connected cardinal rows.
	if _connected_rect(rect):
		labels.fill(1)
		return labels
	var parents: Array[int] = [0]
	for y in rh:
		var gy := rect.position.y+y
		if gy < 0 or gy >= _height: continue
		for x in rw:
			var gx := rect.position.x+x
			if gx < 0 or gx >= _width: continue
			var gi := gy*_width+gx
			if _land[gi] != 0: continue
			var i := y*rw+x
			var links := _links[gi]
			if links < 0: links = _link_mask(gi)
			var label := labels[i-1] if x > 0 and (links&4) != 0 else 0
			if label == 0:
				label = parents.size();parents.append(label)
			labels[i] = label
			if y == 0: continue
			for dx in range(-1,2):
				if x+dx < 0 or x+dx >= rw: continue
				var bit := 2 if dx == -1 else (128 if dx == 1 else 1)
				if (links&bit) == 0: continue
				var above := labels[i-rw+dx]
				if above == 0 or above == label: continue
				var ra := label;var rb := above
				while parents[ra] != ra: ra = parents[ra]
				while parents[rb] != rb: rb = parents[rb]
				if ra != rb: parents[maxi(ra,rb)] = mini(ra,rb)
	# Union roots only decrease, so one ascending pass fully resolves them.
	for i in range(1,parents.size()): parents[i] = parents[parents[i]]
	for i in labels.size(): labels[i] = parents[labels[i]]
	return labels

static func _seen(f: Dictionary,p: Vector2i) -> bool:
	if not (f.rect as Rect2i).has_point(p): return false
	return f.labels[_index(f,p)] == f.component if f.has("labels") else f.seen[_index(f,p)] != 0

func _connections(b: Vector2i) -> PackedByteArray:
	var key := b.y*size.x+b.x
	if connections.has(key): return connections[key]
	var started := Time.get_ticks_usec() if profile else 0
	var result := PackedByteArray()
	var f := _reachable(Rect2i(b*BLOCK-Vector2i(8,8),Vector2i(25,25)),representative(b))
	for k in range(1,9):
		var q: Vector2i = b+DIRECTIONS[k]
		result.append(int(_inside(q) and _seen(f,representative(q))))
	connections[key] = result
	_profile("connections",started)
	return result

func _edge_open(b: Vector2i,k: int) -> bool:
	var q: Vector2i = b+DIRECTIONS[k]
	return _inside(b) and _inside(q) and _connections(b)[k-1] != 0 and _connections(q)[((k+3)&7)] != 0

## Static representative/seed callers consume distances only, never parent
## choices. A scalar integer heap and local PackedArrays avoid a dynamic
## frontier's dictionary/array work; stop after every reachable endpoint is
## settled. The signed edge quantization and block-route tie order stay native.
func _static_distances(rect: Rect2i,start: Vector2i,reverse: bool,goals: Array[Vector2i]) -> Dictionary:
	var started := Time.get_ticks_usec() if profile else 0
	var rw := rect.size.x;var rh := rect.size.y
	var costs := PackedInt32Array();costs.resize(rw*rh);costs.fill(LIMIT)
	var closed := PackedByteArray();closed.resize(costs.size())
	var reachable := _reachable(rect,start,reverse)
	var wanted := {}
	for p: Vector2i in goals:
		if _seen(reachable,p): wanted[(p.y-rect.position.y)*rw+p.x-rect.position.x] = true
	if not rect.has_point(start) or wanted.is_empty(): return {"rect":rect,"costs":costs}
	var si := (start.y-rect.position.y)*rw+start.x-rect.position.x
	costs[si] = 0
	var heap := PackedInt64Array([si])
	while not heap.is_empty():
		var item := heap[0]
		var last := heap[-1];heap.resize(heap.size()-1)
		if not heap.is_empty():
			var at := 0
			while at*2+1 < heap.size():
				var child := at*2+1
				if child+1 < heap.size() and heap[child+1] < heap[child]: child += 1
				if last <= heap[child]: break
				heap[at] = heap[child];at = child
			heap[at] = last
		var current := int(item&0xffff)
		var current_cost := int(item>>16)
		if closed[current] != 0 or costs[current] != current_cost: continue
		closed[current] = 1
		wanted.erase(current)
		if wanted.is_empty(): break
		var x := current%rw;var y := current/rw
		var gx := rect.position.x+x;var gy := rect.position.y+y
		if gx < 0 or gy < 0 or gx >= _width or gy >= _height: continue
		var gi := gy*_width+gx
		if not reverse and _links[gi] < 0: _link_mask(gi)
		for k: int in CELL_ORDER:
			var d: Vector2i = DIRECTIONS[k]
			var qx := x+d.x;var qy := y+d.y
			if qx < 0 or qy < 0 or qx >= rw or qy >= rh or gx+d.x < 0 or gy+d.y < 0 or gx+d.x >= _width or gy+d.y >= _height: continue
			var qi := qy*rw+qx
			if closed[qi] != 0: continue
			var step := _cached_step(gi,k,true) if reverse else _edges8[gi*8+k-1]
			if step < 0: continue
			var next := current_cost+step
			if next >= costs[qi]: continue
			costs[qi] = next
			var key := (next<<16)|qi
			var at := heap.size();heap.resize(at+1)
			while at > 0:
				var parent := (at-1)/2
				if heap[parent] <= key: break
				heap[at] = heap[parent];at = parent
			heap[at] = key
	_profile("static_distances",started)
	return {"rect":rect,"costs":costs}


##  connected block labels. Numeric labels are private; only
## equality is used by relocation, so the reachable component is built lazily.
func component(b: Vector2i) -> int:
	if not _inside(b): return 0
	var key := b.y*size.x+b.x
	if components.has(key): return int(components[key])
	next_component += 1
	var pending: Array[Vector2i] = [b]
	components[key] = next_component
	var at := 0
	while at < pending.size():
		var p := pending[at];at += 1
		for k in range(1,9):
			var q: Vector2i = p+DIRECTIONS[k]
			if not _inside(q): continue
			var i := q.y*size.x+q.x
			if not components.has(i) and _edge_open(p,k):
				components[i] = next_component
				pending.append(q)
	return next_component

##  chooses the most frequent component among the reachable
## representatives in a 3x3 block neighbourhood; first occurrence wins ties.
func component_of(p: Vector2i) -> int:
	if _cell_components.has(p): return _cell_components[p]
	var counts := {}
	for entry: Array in _topology_seeds(p,false):
		var c := component(entry[0])
		counts[c] = int(counts.get(c,0))+1
	var chosen := 0
	var best := 0
	for c: int in counts:
		if int(counts[c]) > best: chosen = c;best = int(counts[c])
	_cell_components[p] = chosen
	return chosen

func _in_component(p: Vector2i,wanted: int) -> bool:
	for entry: Array in _topology_seeds(p,true):
		if component(entry[0]) == wanted: return true
	return false

func _topology_seeds(p: Vector2i,reverse: bool) -> Array:
	var key := Vector3i(p.x,p.y,int(reverse))
	if _seed_topology.has(key): return _seed_topology[key]
	var block := Vector2i(clampi(p.x/BLOCK,0,size.x-1),clampi(p.y/BLOCK,0,size.y-1))
	var f := _reachable(Rect2i(block*BLOCK-Vector2i(8,8),Vector2i(25,25)),p,reverse)
	var out := []
	for y in range(block.y-1,block.y+2):
		for x in range(block.x-1,block.x+2):
			var b := Vector2i(x,y)
			if _inside(b) and _seen(f,representative(b)): out.append([b,0])
	_seed_topology[key] = out
	return out

## A positive local proof avoids building the whole global component just
## to accept an already reachable goal. Every source seed must be connected
## through the same native mutual25-window edges, so native majority/ties
## cannot choose a different component. A successful exact weighted route
## then proves a goal seed belongs to it. Ambiguity/failure uses relocation's
## complete native component labelling instead; the graph dies at map_rev.
func source_seeds_connected(p: Vector2i) -> bool:
	if _single_source.has(p): return bool(_single_source[p])
	var allowed := {}
	var seeds := _topology_seeds(p,false)
	for entry: Array in seeds: allowed[entry[0]] = true
	if allowed.is_empty():
		_single_source[p] = false
		return false
	var pending: Array[Vector2i] = [seeds[0][0]]
	var visited := {pending[0]:true}
	var at := 0
	while at < pending.size():
		var b := pending[at];at += 1
		for k in range(1,9):
			var q: Vector2i = b+DIRECTIONS[k]
			if allowed.has(q) and not visited.has(q) and _edge_open(b,k):
				visited[q] = true;pending.append(q)
	var proved := visited.size() == allowed.size()
	if not proved:
		# The nine source representatives may join just outside their3x3
		# neighbourhood. Accept only an actual path of native reciprocal
		# edges joining ALL of them, in a bounded9x9 block square. A missing
		# proof still runs5b0050's complete component/majority selection.
		var block := Vector2i(clampi(p.x/BLOCK,0,size.x-1),clampi(p.y/BLOCK,0,size.y-1))
		var bounds := Rect2i(block-Vector2i(4,4),Vector2i(9,9))
		pending.assign([seeds[0][0]])
		visited = {pending[0]:true}
		var remaining := allowed.duplicate()
		remaining.erase(pending[0])
		at = 0
		while at < pending.size() and not remaining.is_empty():
			var b := pending[at];at += 1
			for k in range(1,9):
				var q: Vector2i = b+DIRECTIONS[k]
				if bounds.has_point(q) and not visited.has(q) and _edge_open(b,k):
					visited[q] = true;pending.append(q);remaining.erase(q)
		proved = remaining.is_empty()
	_single_source[p] = proved
	return proved

func connected_route(start: Vector2i,goal: Vector2i) -> Array[Vector2i]:
	if not source_seeds_connected(start): return []
	return route(start,goal)

func _open(p: Vector2i,stamp: Dictionary) -> bool:
	if not nav._in(p) or layer.land[p.y*nav.size.x+p.x] != 0: return false
	if stamp.is_empty(): return true
	var r: Rect2i = stamp.rect
	var v: PackedInt32Array = stamp.values
	return not r.has_point(p) or v[(p.y-r.position.y)*r.size.x+p.x-r.position.x] <= nav._ctx_thr

static func _f(v: float) -> float:
	return PackedFloat32Array([v])[0]

##  goal-biased eight-ray search. It begins at the caller's
## radius and ends at the Chebyshev distance from the original unit cell.
## Returned points remain in native cell space for the path record.
func relocate(start: Vector2,goal: Vector2,connected := false,min_radius := 0.0) -> Dictionary:
	var origin: Vector2i = nav.cell(start)
	var target: Vector2i = nav.cell(goal)
	var delta := target-origin
	var radius := maxi(absi(delta.x),absi(delta.y))
	var rect := Rect2i(target-Vector2i(radius+1,radius+1),Vector2i(radius*2+3,radius*2+3))
	var values: PackedInt32Array = nav._stamp_window(rect)
	var stamp := {} if values.is_empty() else {"rect":rect,"values":values}
	if not connected and _open(target,stamp): return {"cell":target,"point":goal*2.0}
	var wanted := component_of(origin) if connected else 0
	var first := maxi(0,nav.round_even(min_radius*2.0)-1)
	var dx := _f(float(delta.x)/maxf(radius,1.0))
	var dy := _f(float(delta.y)/maxf(radius,1.0))
	var x := _f(dx*0.707-dy*0.707)
	var y := _f((dy+dx)*0.707)
	var scale := _f(1.0/maxf(maxf(absf(x),absf(y)),0.000001))
	if scale < 1.0:
		x = _f(x*scale);y = _f(y*scale);dx = _f(dx*scale);dy = _f(dy*scale)
	var rays := [Vector2(dx,dy),Vector2(x,y),Vector2(y,-x),Vector2(dy,-dx),
		Vector2(-dy,dx),Vector2(-y,x),Vector2(-x,-y),Vector2(-dx,-dy)]
	var checked := {}
	for r in range(first,radius+1):
		for k in (1 if r == 0 else 8):
			var ray: Vector2 = rays[k]
			var p := target-Vector2i(nav.round_even(r*ray.x),nav.round_even(r*ray.y))
			if not _open(p,stamp): continue
			if connected:
				if not checked.has(p): checked[p] = _in_component(p,wanted)
				if not bool(checked[p]): continue
			var point := goal*2.0
			if r != 0:
				point = Vector2(p)+Vector2(0.5,0.5)
				point.x += -0.49 if target.x < point.x else (0.49 if point.x < target.x else 0.0)
				point.y += -0.49 if target.y < point.y else (0.49 if point.y < target.y else 0.0)
			return {"cell":p,"point":point}
	return {}

## Four (cell) or eight (block) sorted lists, keyed by x&mask. Equal-cost
## insertions go before older entries; the first list wins equal front costs.
static func _queue(n: int) -> Array:
	var out := []
	for _i in n: out.append([])
	return out

static func _insert(queue: Array,index: int,x: int,costs) -> void:
	var list: Array = queue[x&(queue.size()-1)]
	var old := list.find(index)
	if old >= 0: list.remove_at(old)
	var lo := 0;var hi := list.size()
	while lo < hi:
		var mid := (lo+hi)/2
		if int(costs[int(list[mid])]) < int(costs[index]): lo = mid+1
		else: hi = mid
	list.insert(lo,index)

static func _front(queue: Array,costs) -> int:
	var out := -1
	var best := LIMIT
	for list: Array in queue:
		if not list.is_empty() and costs[int(list[0])] < best:
			out = int(list[0])
			best = costs[out]
	return out

static func _remove(queue: Array,index: int,x: int) -> void:
	(queue[x&(queue.size()-1)] as Array).erase(index)

## Mutable frontier arrays stay shared: editing a PackedArray extracted from
## the dictionary would copy the whole window on every pop. Queue order and
## native integer costs are unchanged.
## Native cell frontier, including unsettled tentative costs. `goal` stops
## before processing its node, as does; absent goal floods fully.
func flood(rect: Rect2i,start: Vector2i,reverse: bool,stamps: bool,flat: bool,
		goal := Vector2i(-1,-1),previous: CellFrontier = null,reopen := false) -> CellFrontier:
	var started := Time.get_ticks_usec() if profile else 0
	var n := rect.size.x*rect.size.y
	var costs: Array[int] = []
	costs.resize(n);costs.fill(LIMIT)
	var parents: Array[int] = [];parents.resize(n);parents.fill(0)
	var closed: Array[int] = [];closed.resize(n);closed.fill(0)
	var queue := _queue(4)
	var stamp: PackedInt32Array = nav._stamp_window(rect) if stamps else PackedInt32Array()
	var cutoff := LIMIT
	if previous != null and reopen:
		var old: Rect2i = previous.rect
		for y in range(old.position.y,old.end.y):
			for x in range(old.position.x,old.end.x):
				if rect.has_point(Vector2i(x,y)) and (x == old.position.x or x == old.end.x-1 or y == old.position.y or y == old.end.y-1):
					cutoff = mini(cutoff,cost_at(previous,Vector2i(x,y)))
	# Invalid margins and the old/new overlap are rectangles. Iterating their
	# bounds avoids two point tests and dictionary lookups for every cell in
	# every rolling window; copied fields and insertion order remain native.
	var valid := rect.intersection(Rect2i(Vector2i.ZERO,Vector2i(_width,_height)))
	if valid != rect:
		for y in rect.size.y:
			for x in rect.size.x:
				if not valid.has_point(rect.position+Vector2i(x,y)): closed[y*rect.size.x+x] = 1
	if previous != null:
		var overlap := rect.intersection(previous.rect)
		var old_costs := previous.costs
		var old_parents := previous.parents
		var old_closed := previous.closed
		for y in range(overlap.position.y,overlap.end.y):
			var i := (y-rect.position.y)*rect.size.x+overlap.position.x-rect.position.x
			var oi := (y-previous.rect.position.y)*previous.rect.size.x+overlap.position.x-previous.rect.position.x
			for x in range(overlap.position.x,overlap.end.x):
				costs[i] = old_costs[oi]
				parents[i] = old_parents[oi]
				closed[i] = old_closed[oi] if not reopen else int(costs[i] < cutoff)
				if costs[i] < LIMIT and closed[i] == 0:
					_insert(queue,i,x-rect.position.x+1,costs)
				i += 1;oi += 1
	if previous == null and rect.has_point(start):
		var i := (start.y-rect.position.y)*rect.size.x+start.x-rect.position.x
		costs[i] = 0;closed[i] = 0
		_insert(queue,i,start.x-rect.position.x+1,costs)
	var f := CellFrontier.new()
	f.rect = rect;f.costs = costs;f.parents = parents;f.closed = closed;f.queue = queue
	f.stamp = stamp;f.reverse = reverse;f.flat = flat;f.threshold = nav._ctx_thr
	while true:
		var current := _front(f.queue,f.costs)
		if current < 0: break
		var p := rect.position+Vector2i(current%rect.size.x,current/rect.size.x)
		if p == goal: break
		_advance(f,current)
	_profile("dynamic_flood" if stamps else "static_flood",started)
	return f

func _advance(f: CellFrontier,current := -1) -> void:
	var rect: Rect2i = f.rect
	var costs: Array = f.costs
	var parents: Array = f.parents
	var closed: Array = f.closed
	var stamp: PackedInt32Array = f.stamp
	var queue: Array = f.queue
	if current < 0: current = _front(queue,costs)
	if current < 0: return
	var rw := rect.size.x;var rh := rect.size.y
	var x := current%rw;var y := current/rw
	var gx := rect.position.x+x;var gy := rect.position.y+y
	_remove(queue,current,x+1)
	closed[current] = 1
	var gi := gy*_width+gx
	var threshold: int = f.threshold
	var reverse: bool = f.reverse
	var flat: bool = f.flat
	if not reverse and _links[gi] < 0: _link_mask(gi)
	for k: int in CELL_ORDER:
		var d: Vector2i = DIRECTIONS[k]
		var qx := x+d.x;var qy := y+d.y
		if qx < 0 or qy < 0 or qx >= rw or qy >= rh: continue
		if gx+d.x < 0 or gy+d.y < 0 or gx+d.x >= _width or gy+d.y >= _height: continue
		var qi := qy*rw+qx
		if int(closed[qi]) != 0: continue
		if not stamp.is_empty() and stamp[qi] > threshold and stamp[qi] >= stamp[current]: continue
		var step := _cached_step(gi,k,true,flat) if reverse else (_flat_edges8[gi*8+k-1] if flat else _edges8[gi*8+k-1])
		if step < 0: continue
		var next: int = int(costs[current])+step
		if next < int(costs[qi]):
			costs[qi] = next
			parents[qi] = ((k+3)&7)+1
			_insert(queue,qi,qx+1,costs)

func _chain(f: CellFrontier,p: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r: Rect2i = f.rect
	while r.has_point(p):
		out.append(p.y*nav.size.x+p.x)
		var direction := int(f.parents[_index(f,p)])
		if direction == 0: break
		p += DIRECTIONS[direction]
	return out

##  alternates two native windows and meets the first finite
## opposite cost at an open frontier. Tentative nodes count as reached.
func direct(start: Vector2i,goal: Vector2i) -> Dictionary:
	var rect := _frame(start,goal)
	if not rect.has_area(): return {}
	var sides := [flood(rect,start,false,true,nav._ctx_flat,start),
		flood(rect,goal,true,true,nav._ctx_flat,goal)]
	var meet := Vector2i.ZERO
	while true:
		_advance(sides[0]);_advance(sides[1])
		var done := false
		for side in 2:
			var i := _front(sides[side].queue,sides[side].costs)
			if i < 0: return {}
			meet = rect.position+Vector2i(i%rect.size.x,i/rect.size.x)
			if settled_cost_at(sides[1-side],meet) < LIMIT:
				done = true
				break
		if done: break
	var cells := _chain(sides[0],meet)
	cells.reverse()
	cells.append_array(_chain(sides[1],meet).slice(1))
	return {"cells":cells,"end":Vector2(goal)+Vector2(0.5,0.5),"partial":false,"blocks":[],"windows":[rect],
		"cost":cost_at(sides[0],meet)+cost_at(sides[1],meet)}


static func _index(f,p: Vector2i) -> int:
	var r: Rect2i = f.rect
	return (p.y-r.position.y)*r.size.x+p.x-r.position.x

static func cost_at(f,p: Vector2i) -> int:
	return f.costs[_index(f,p)] if (f.rect as Rect2i).has_point(p) else LIMIT

##  exposes only closed nodes. The boundary-copy pass and
## path merge still read the tentative values directly.
static func settled_cost_at(f: CellFrontier,p: Vector2i) -> int:
	if not (f.rect as Rect2i).has_point(p): return LIMIT
	var i := _index(f,p)
	return int(f.costs[i]) if f.closed[i] != 0 else LIMIT

func _seeds(p: Vector2i,reverse: bool) -> Array:
	# Static terrain costs and representative cells are immutable until this
	# graph's map revision is discarded. Callers only read these nine seeds.
	var key := Vector3i(p.x,p.y,int(reverse))
	if _seed_costs.has(key): return _seed_costs[key]
	var block := Vector2i(clampi(p.x/BLOCK,0,size.x-1),clampi(p.y/BLOCK,0,size.y-1))
	var goals: Array[Vector2i] = []
	for y in range(block.y-1,block.y+2):
		for x in range(block.x-1,block.x+2):
			var b := Vector2i(x,y)
			if _inside(b): goals.append(representative(b))
	var f := _static_distances(Rect2i(block*BLOCK-Vector2i(8,8),Vector2i(25,25)),p,reverse,goals)
	var out := []
	for y in range(block.y-1,block.y+2):
		for x in range(block.x-1,block.x+2):
			var b := Vector2i(x,y)
			if not _inside(b): continue
			var cost := cost_at(f,representative(b))
			if cost < LIMIT: out.append([b,cost>>7])
	_seed_costs[key] = out
	return out

func route(start: Vector2i,goal: Vector2i,avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var count := size.x*size.y
	var sides := []
	for reverse in [false,true]:
		var costs: Array[int] = [];costs.resize(count);costs.fill(LIMIT)
		var parents: Array[int] = [];parents.resize(count);parents.fill(0)
		var closed: Array[int] = [];closed.resize(count);closed.fill(0)
		var queue := _queue(8)
		for b: Vector2i in avoid:
			if _inside(b): costs[b.y*size.x+b.x] = -1
		for entry: Array in _seeds(goal if reverse else start,reverse):
			var b: Vector2i = entry[0]
			var i := b.y*size.x+b.x
			if int(entry[1]) <= costs[i]:
				costs[i] = int(entry[1])
				_insert(queue,i,b.x,costs)
		sides.append({"costs":costs,"parents":parents,"closed":closed,"queue":queue})
	var meet := -1
	while true:
		for s: Dictionary in sides:
			var current := _front(s.queue,s.costs)
			if current < 0: return []
			var b := Vector2i(current%size.x,current/size.x)
			_remove(s.queue,current,b.x)
			s.closed[current] = 1
			for k in range(1,9):
				var cost := edge(b,k)
				if cost < 0: continue
				var q: Vector2i = b+DIRECTIONS[k]
				var qi := q.y*size.x+q.x
				var next: int = s.costs[current]+cost
				if next < s.costs[qi]:
					s.costs[qi] = next
					s.parents[qi] = ((k+3)&7)+1
					_insert(s.queue,qi,q.x,s.costs)
		for index in 2:
			var s: Dictionary = sides[index]
			var current := _front(s.queue,s.costs)
			if current < 0: return []
			if sides[1-index].closed[current] != 0 and sides[1-index].costs[current] < LIMIT:
				meet = current
				break
		if meet >= 0: break
	var result: Array[Vector2i] = []
	for index in 2:
		var list: Array[Vector2i] = []
		var i := meet
		while true:
			var b := Vector2i(i%size.x,i/size.x)
			list.append(b)
			var k: int = sides[index].parents[i]
			if k == 0: break
			b += DIRECTIONS[k];i = b.y*size.x+b.x
		if index == 0:
			list.reverse();result = list
		else:
			result.append_array(list.slice(1))
	last_blocks = result
	return result

## the un-clipped interior of the 34x34 node allocation.
func _frame(start: Vector2i,goal: Vector2i) -> Rect2i:
	var d := (goal-start).abs()
	if d.x >= 32 or d.y >= 32 or not nav._in(start) or not nav._in(goal): return Rect2i()
	return Rect2i(Vector2i(mini((start.x+goal.x)/2-16,mini(start.x,goal.x)-1)+1,
		mini((start.y+goal.y)/2-16,mini(start.y,goal.y)-1)+1),Vector2i(32,32))

func _merge(f: CellFrontier,parents: Dictionary) -> void:
	var r: Rect2i = f.rect
	for y in r.size.y:
		for x in r.size.x:
			var p := r.position+Vector2i(x,y)
			if not nav._in(p): continue
			var i := y*r.size.x+x
			var key: int = p.y*nav.size.x+p.x
			if f.costs[i] < LIMIT and int(parents.get(key,0)) == 0:
				parents[key] = int(f.parents[i])

static func _octile(d: Vector2i) -> int:
	return maxi(d.x,d.y)-mini(d.x,d.y)+((mini(d.x,d.y)*0x5a8)>>10)

## follow static block representatives with one moving
## 32-cell frontier, preserving its overlap and first-written parent map.
func carrier(start: Vector2i,goal: Vector2i,maxcells := LIMIT,
		avoid: Array[Vector2i] = [],retry := false,proved_route: Array[Vector2i] = []) -> Dictionary:
	var blocks := proved_route if not proved_route.is_empty() else route(start,goal,avoid)
	if blocks.is_empty() or blocks.size()*8 > maxcells: return {}
	var points: Array[Vector2i] = []
	for b: Vector2i in blocks: points.append(representative(b))
	points.append(goal)
	var f: CellFrontier = null
	var parents := {}
	var current := start
	var reached := true
	var partial := false
	var windows: Array[Rect2i] = []
	for at in points.size():
		var point := points[at]
		if point == current: continue
		var rect := _frame(current,point)
		var valid := rect.has_area()
		if valid and f != null:
			var d: Vector2i = rect.position-(f.rect as Rect2i).position
			valid = absi(d.x) < 31 and absi(d.y) < 31
		if valid:
			f = flood(rect,current,false,true,nav._ctx_flat,point,f,not reached)
			reached = cost_at(f,point) < LIMIT
			if reached:
				current = point
			else:
				valid = false
				for offset in range(0,NEAR_OFFSETS.size(),2):
					var p := point+Vector2i(NEAR_OFFSETS[offset],NEAR_OFFSETS[offset+1])
					if settled_cost_at(f,p) < LIMIT:
						current = p
						valid = true
						break
			if valid and at == points.size()-1 and settled_cost_at(f,goal) == LIMIT:
				_merge(f,parents)
				windows.append(f.rect)
				var next := _frame(current,goal)
				var d: Vector2i = next.position-(f.rect as Rect2i).position
				valid = next.has_area() and absi(d.x) < 31 and absi(d.y) < 31
				if valid:
					f = flood(next,current,false,true,nav._ctx_flat,Vector2i(-1,-1),f,true)
					valid = settled_cost_at(f,goal) < LIMIT
		if not valid:
			if _octile((current-start).abs()) <= 15:
				if retry:
					var bad := blocks[clampi(at-1,0,blocks.size()-1)]
					if not bad in avoid:
						var excluded := avoid.duplicate()
						excluded.append(bad)
						return carrier(start,goal,maxcells,excluded,true)
				return {}
			partial = true
			if f != null: _merge(f,parents);windows.append(f.rect)
			break
		_merge(f,parents)
		windows.append(f.rect)
	parents[start.y*nav.size.x+start.x] = 0
	var finish := current if partial else goal
	var cells := PackedInt32Array()
	var p := finish
	var seen := {}
	while nav._in(p):
		var key: int = p.y*nav.size.x+p.x
		if seen.has(key): return {}
		seen[key] = true
		cells.append(key)
		var direction := int(parents.get(key,0))
		if direction == 0: break
		p += DIRECTIONS[direction]
	if p != start: return {}
	cells.reverse()
	return {"cells":cells,"end":Vector2(finish)+Vector2(0.5,0.5),"partial":partial,
		"blocks":blocks,"windows":windows}
