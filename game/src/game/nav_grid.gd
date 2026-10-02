class_name NavGrid
extends RefCounted
## Walkability grid over a zone with A* paths, after the original's AI map (CAIMap
## built): 0.5 m cells (64 per 32 m sector), each with a ground
## height (half the nearest quad corner + a quarter of its two edge neighbours), the water depth
## and the ground type of its terrain tile.
##
## Passability and path cost of a cell, one 4-bit value per movement class
## (the class of a unit: GameUnit.move_class
##   cost = tiledesc.reg CostMul, + 30 when wading deeper than half the class
##   height; speed = 1024, 880 in shallow water, 800 wading; impassable when the
##   water is as deep as the class height or cost > 70
##   each object span (below) the class's body [ground, ground + class height]
##   overlaps by a share f adds round(290 f) to the cost and takes the speed
##   x 0.6^(7 f) (object kind 0; kind 1: 20, 0.6^(2 f); kind 2 nothing);
##   value = [cost bucket][(speed + 50) / 102], buckets cost < 2
##   2, 3..9, 10..34, 35..70; the step cost table (map)
##   gives the A* weight of entering the cell (/1024: road 1, grass 2, the
##   WATER tile 5, swamp 35).
## Object footprints (for every placed object but units): the
## parts named by the object's record (else all of its figure's), skipping
## "EMPTY*" parts; each part's box (the .fig min / max at the object's
## complexion, around the part's centre and offset) is turned with the object,
## set on the ground cell under the object and its 6 faces sampled at a third
## of a cell; per cell the object keeps one span: the lowest bottom / side
## sample to the highest top-face sample (kind = the lowest of the top-face
## parts: 0, "CROWN*" parts 2). "BASE*" parts are floors: the
## cell's height rises to the span's top, its water goes and its ground type
## becomes 7 (ROAD). Levers re-sample at their target state.
## Cells near a blocked one are blocked too, by the class's shape (
## over the lists at map): classes
## 0-4 the 4-neighbour cross, 5-6 the 13-cell diamond, 7 the 5 x 5 square + the
## four cells 3 away on the axes (29). Then slopes (with the
##  tables): a cell whose height differs from a 4-neighbour
## by more than tan 40 deg x 0.5 m keeps only class 0, by more than tan 60 deg x
## 0.5 m none; its 4 neighbours lose classes 5-6 and the 13-cell
## diamond round it class 7. The 3 border cells are blocked.
## Each class has its own A* grid, built when a unit of that class first asks.
## Standing units block the cells around them (see track_unit).
## Approx.: heights are kept in metres (the original's are 1/ steps, =
## 511 / the map's max altitude; spans are clamped to 0..1020 steps as there);
## the slope step factor of the original's cost (:
## uphill x (1 + sin^2 a)^2, downhill / (1 + sin^2 a)) and the turn penalty
##  are left out; paths are global A* (the original searches 4 m
## blocks, then 16 m windows) and line-of-sight
## smoothed; a goal cut off from the start moves to the nearest cell of the
## start's region.

const CELL := 0.5
## tan(40 deg) x CELL: the largest height step to a 4-neighbour
## tan(60 deg) x CELL closes the cell to every class.
const MAX_STEP := 0.41955
const MAX_STEP_ALL := 0.86603
const BORDER := 3
## water clearance (body height) of movement classes 0..7.
const CLASS_HEIGHT := [2.0, 0.4, 1.0, 1.6, 2.2, 1.7, 3.0, 6.0]
## The class of every unit before the per-unit classes (humans standing).
const WALK_CLASS := 3
## the dilation shapes (cell offsets) of classes 0-4, 5-6 and 7.
const SHAPE_CROSS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## the 13 cells round a steep cell that class 7 loses (also the
## 5-6 dilation shape).
const SHAPE_DIAMOND := [Vector2i(0, 2), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-2, 0),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(0, -1),
	Vector2i(1, -1), Vector2i(0, -2)]
## the 4 neighbours of a steep cell that classes 5-6 lose.
const SHAPE_NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## cell value by cost bucket (rows) and speed bucket (columns).
const VALUE := [
	0, 0, 1, 1, 1, 1, 4, 7, 11, 12, 14, 14, 15, 15, 15, 15,
	0, 0, 1, 1, 1, 1, 4, 7, 11, 12, 13, 13, 13, 13, 13, 13,
	0, 0, 1, 1, 1, 1, 4, 7, 8, 9, 10, 10, 10, 10, 10, 10,
	0, 0, 1, 1, 1, 1, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6,
	0, 0, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3]
##  (map): step cost by cell value, 1024 = one cell.
const STEP_COST := [-1, 0x6400, 0x77ec, 0x8bd8, 0x2ff8, 0x37f0, 0x3ffc, 0xdfc, 0xfff,
	0x11fd, 0x1400, 0x666, 0x732, 0x800, 0x400, 0x4cc]
##  by object kind: the cost added for the share f
## of the body an object span overlaps, and k in the speed factor 0.6^(k f)
## (: exp(k f), that float = ln 0.6, set
const OBJ_COST := [290, 20, 0]
const OBJ_SLOW := [7, 2, 0]
## a floor cell's ground type (tiledesc "ROAD").
const FLOOR_GROUND := 7
## span heights are clamped to 0..0x3fc height steps.
const SPAN_MAX := 1020
## the corners of a part's box (lo / hi picked per axis: 0 = lo)
## in the original's order; face k has its corner k + 1 as origin and the edges to
## corners k and k + 2, and the outward normal FACE_NORMAL[k].
const BOX_CORNERS := [Vector3i(1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 1, 1),
	Vector3i(1, 1, 1), Vector3i(1, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, 0)]
const FACE_NORMAL := [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
	Vector3(1, 0, 0), Vector3(0, -1, 0)]
## Unit stamps: a unit of radius r adds round(16 (r' + 2 - d))
## to the cells at distance d (cell offsets x 0.5 m, -8..7 around its cell),
## r' = round(10 r + 1) / 10; a cell is closed to a mover
## radius R when the value exceeds round(16 (2 - R)). The path
## grid uses the default radius 0.5 for R.
const R_REF := 0.5
const BUCKET := 4.0            # spatial hash for unit queries (m)


## One movement class's passability: its A* grid, the cells closed for the
## class before (`raw`) and after the class shape and slopes (`land`), and the regions.
class Layer:
	var cls := 3
	var astar := AStarGrid2D.new()
	var raw := PackedByteArray()
	var land := PackedByteArray()
	var comp := PackedInt32Array()   # connected region of each open cell, 0 = closed


## The class-3 grid (kept for tools and callers that do not name a class).
var astar: AStarGrid2D:
	get: return layer(WALK_CLASS).astar
var size := Vector2i.ZERO
var terrain: EITerrain
var _layers := {}                # class -> Layer
var _h0 := PackedFloat32Array()  # terrain cell heights
var _cost0 := PackedInt32Array() # tiledesc cost of the terrain, -1 = impassable
var _depth0 := PackedFloat32Array()  # water depth over the terrain
var _h := PackedFloat32Array()   # cell heights (floors raise them)
var _cost := PackedInt32Array()  # tiledesc cost before water, -1 = impassable
var _depth := PackedFloat32Array()  # water depth over the cell's floor
var _floor_cost := 1             # tiledesc cost of FLOOR_GROUND
var _alt := 1.0                  # height steps per metre
var _steep := PackedByteArray()  # 1 = step over 40 deg to a 4-neighbour, 2 = over 60 deg
var _steep_cells := PackedInt32Array()
var _fixed_sets := {}                  # slope / border closures by class group (_fixed)
var _dry_raw := PackedByteArray()      # 1 = closed when dry (cost)
var _dry_weight := PackedFloat32Array()  # step cost / 1024 when dry
var _special := PackedByteArray()      # 1 = wet or under an object span: per class
var _special_cells := PackedInt32Array()
var _mode_w := 1.0                     # the commonest dry weight
var _dry_diff := PackedInt32Array()    # open dry cells of another weight
var _lists_dirty := false              # _steep_cells / _special_cells / _dry_diff stale
var _spans := {}                 # cell -> Array of [bottom, top, kind, key] (height steps)
var _floors := {}                # cell -> Array of [top, key]
var _fp := {}                    # object key -> {"spans": {cell: [b, t, k]}, "floors": {cell: top}}
var _fp_nodes := {}              # object key -> Node3D
var _next_key := -1
var _occ := PackedByteArray()    # standing units whose stamp closes the cell (count)
var _stamps := {}                # quantised radius x 10 -> Array[Vector2i]
var _buckets := {}               # key -> Array[GameUnit]


func build(t: EITerrain, water_levels: PackedFloat32Array, objects: Array) -> void:
	terrain = t
	_layers = {}
	_spans = {}
	_floors = {}
	_fp = {}
	_fp_nodes = {}
	var qw := t.sectors_x * EITerrain.SECTOR
	var qh := t.sectors_y * EITerrain.SECTOR
	size = Vector2i(qw * 2, qh * 2)
	var n := size.x * size.y
	_occ.resize(n)
	_occ.fill(0)
	_h0.resize(n)
	_cost0.resize(n)
	_depth0.resize(n)
	_depth0.fill(0.0)
	_steep.resize(n)
	_steep.fill(0)
	_fixed_sets = {}
	_alt = 511.0 / t.max_altitude if t.max_altitude > 0.0 else 1.0
	_slope_memo.clear()
	# Per ground type: cost (CostMul), -1 = impassable.
	var cost_of := PackedInt32Array()
	cost_of.resize(32)
	for g in 32:
		var c := int(EITerrain.ground_value(g, "CostMul", 2.0))
		# Approx.: lava (Speed -1) is impassable; the original's lava rule was not traced.
		cost_of[g] = -1 if g == EITerrain.LAVA or EITerrain.ground_value(g, "Speed", 1024.0) < 0.0 else c
	_floor_cost = cost_of[FLOOR_GROUND]
	var w := t.grid_w
	var hs := t.heights
	var has_ground := not t.ground.is_empty()
	var has_water := not water_levels.is_empty()
	for cy in size.y:
		var qy := cy >> 1
		var ny := 0 if (cy & 1) == 0 else w   # row of the nearest quad corner
		for cx in size.x:
			var qx := cx >> 1
			var nx := cx & 1
			# half the nearest quad corner + a quarter of each of the
			# two corners sharing an edge with it.
			var vi := qy * w + qx
			var gz := hs[vi + ny + nx] * 0.5 + (hs[vi + ny + (1 - nx)] + hs[vi + (w - ny) + nx]) * 0.25
			var i := cy * size.x + cx
			_h0[i] = gz
			var q := qy * qw + qx
			_cost0[i] = cost_of[int(t.ground[q]) & 31] if has_ground else 2
			if has_water:
				_depth0[i] = maxf(0.0, water_levels[q] - gz)
	_h = _h0.duplicate()
	_cost = _cost0.duplicate()
	_depth = _depth0.duplicate()
	# Object footprints, then the floors they lay.
	for o: Node3D in objects:
		_add_footprint(o, _footprint(o))
	for i: int in _floors:
		_apply_floor(i)
	# Slopes.
	for cy in range(1, size.y - 1):
		for cx in range(1, size.x - 1):
			_steep[cy * size.x + cx] = _steep_at(cy * size.x + cx)
	# Dry cell values (the same for every class); wet cells and cells under
	# object spans are left to the layers.
	_dry_raw.resize(n)
	_dry_raw.fill(0)
	_dry_weight.resize(n)
	_dry_weight.fill(1.0)
	_special.resize(n)
	_special.fill(0)
	for i in n:
		_dry_cell(i)
	_rebuild_lists()
	layer(WALK_CLASS)


##  test of one cell: 2 = a step over 60 deg to a 4-neighbour
## 1 = over 40 deg, else 0.
func _steep_at(i: int) -> int:
	var x := i % size.x
	var y := i / size.x
	if x < 1 or y < 1 or x >= size.x - 1 or y >= size.y - 1:
		return 0
	var z := _h[i]
	var d := maxf(maxf(absf(_h[i - 1] - z), absf(_h[i + 1] - z)),
		maxf(absf(_h[i - size.x] - z), absf(_h[i + size.x] - z)))
	return 2 if d > MAX_STEP_ALL else (1 if d > MAX_STEP else 0)


## The class-independent state of a cell: whether the layers work it out
## (water, object spans) or its dry value.
func _dry_cell(i: int) -> void:
	_dry_raw[i] = 0
	_dry_weight[i] = 1.0
	if (_depth[i] > 0.0 and _cost[i] >= 0) or _spans.has(i):
		_special[i] = 1
		return
	_special[i] = 0
	var v := _value(_cost[i], 1024)
	if v == 0:
		_dry_raw[i] = 1
	elif v != 14:
		_dry_weight[i] = STEP_COST[v] / 1024.0


## The cell lists the layer builds walk: steep cells, special cells, the
## commonest dry weight and the open dry cells of another weight.
func _rebuild_lists() -> void:
	var n := size.x * size.y
	_steep_cells = PackedInt32Array()
	for v in [1, 2]:
		var i0 := _steep.find(v)
		while i0 >= 0:
			_steep_cells.append(i0)
			i0 = _steep.find(v, i0 + 1)
	_special_cells = PackedInt32Array()
	var s0 := _special.find(1)
	while s0 >= 0:
		_special_cells.append(s0)
		s0 = _special.find(1, s0 + 1)
	var hist := {}
	for i in n:
		if _dry_raw[i] == 0 and _special[i] == 0:
			var wv := _dry_weight[i]
			hist[wv] = int(hist.get(wv, 0)) + 1
	_mode_w = 1.0
	var best := -1
	for wv: float in hist:
		if hist[wv] > best:
			best = hist[wv]
			_mode_w = wv
	_dry_diff = PackedInt32Array()
	for i in n:
		if _dry_raw[i] == 0 and _special[i] == 0 and _dry_weight[i] != _mode_w:
			_dry_diff.append(i)
	_lists_dirty = false


## Cell value: [cost bucket][speed bucket]; 0 = closed.
static func _value(cost: int, speed: int) -> int:
	if cost < 0 or cost > 70 or speed < 0:
		return 0
	var row := (1 if cost > 1 else 0) if cost < 3 else (2 if cost < 10 else (3 if cost < 35 else 4))
	return VALUE[row * 16 + mini(15, (speed + 50) / 102)]


## The step weight of a wet cell or a cell under object spans for class
## `cls`, 0 = closed.
func _cell_weight(i: int, cls: int) -> float:
	var v := _cell_value(i, cls)
	return 0.0 if v == 0 else STEP_COST[v] / 1024.0


## The cell value (0..15, 0 = closed) of a wet cell or a cell under object
## spans for class `cls`.
func _cell_value(i: int, cls: int) -> int:
	var cost := _cost[i]
	if cost < 0:
		return 0
	var speed := 1024
	var depth := _depth[i]
	var wade: float = CLASS_HEIGHT[cls]
	if depth > 0.0:
		if depth >= wade:
			return 0
		elif depth > wade * 0.5:
			speed = 800
			cost += 30
		else:
			speed = 880
	var spans: Array = _spans.get(i, [])
	if not spans.is_empty():
		# The body: from the floor (class 0: the water surface) up by the class height.
		var bb := roundi((_h[i] + (depth if cls == 0 else 0.0)) * _alt)
		var bt := bb + roundi(wade * _alt)
		for s: Array in spans:
			var k: int = s[2]
			if k >= 2 or s[0] > bt or s[1] < bb:
				continue
			var f := float(mini(s[1], bt) - maxi(s[0], bb)) / float(bt - bb)
			cost += roundi(OBJ_COST[k] * f)
			speed = roundi(speed * pow(0.6, OBJ_SLOW[k] * f))
	return _value(cost, speed)


## The grid of movement class `cls` (0..7), built on first use.
func layer(cls: int) -> Layer:
	cls = clampi(cls, 0, 7)
	var L: Layer = _layers.get(cls)
	if L == null:
		L = _build_layer(cls)
		_layers[cls] = L
	return L


func _build_layer(cls: int) -> Layer:
	if _lists_dirty:
		_rebuild_lists()
	var L := Layer.new()
	L.cls = cls
	var n := size.x * size.y
	L.astar.region = Rect2i(Vector2i.ZERO, size)
	L.astar.cell_size = Vector2.ONE
	#  expands all 8 neighbours (diagonals 0x5a8 / 0x400).
	L.astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	L.astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	L.astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	L.astar.update()
	if n == 0:
		return L
	# Cell values: the dry cells are the same for every class (_dry_raw /
	# _dry_weight); only the special ones are worked out per class.
	var raw := _dry_raw.duplicate()
	var weight := PackedFloat32Array()
	weight.resize(_special_cells.size())
	for k in _special_cells.size():
		var wv := _cell_weight(_special_cells[k], cls)
		weight[k] = wv
		if wv <= 0.0:
			raw[_special_cells[k]] = 1
	# Dilation of those blocks by the class shape, over the closures shared
	# by the class's group (_fixed: dry cells dilated, slopes, border).
	var land := _fixed(cls).duplicate()
	var shape := _shape(cls)
	var w := size.x
	for i in _special_cells:
		if raw[i] == 0:
			continue
		var c0 := Vector2i(i % w, i / w)
		# A cell whose 4 neighbours are closed adds nothing: every offset of
		# the shapes is a neighbour's offset plus another of the shape.
		if c0.x > 0 and c0.y > 0 and c0.x < w - 1 and c0.y < size.y - 1 \
				and raw[i - 1] != 0 and raw[i + 1] != 0 and raw[i - w] != 0 and raw[i + w] != 0:
			land[i] = 1
			continue
		for d: Vector2i in shape:
			var q := c0 + d
			if _in(q):
				land[q.y * size.x + q.x] = 1
	L.raw = raw
	L.land = land
	# The A* grid: the commonest weight everywhere, then the other weights and
	# the closed cells (walking only those keeps a layer's build short).
	var A := L.astar
	A.fill_weight_scale_region(A.region, _mode_w)
	for i in _dry_diff:
		A.set_point_weight_scale(Vector2i(i % size.x, i / size.x), _dry_weight[i])
	for k in _special_cells.size():
		if weight[k] > 0.0:
			var i := _special_cells[k]
			A.set_point_weight_scale(Vector2i(i % size.x, i / size.x), weight[k])
	var i0 := land.find(1)
	while i0 >= 0:
		A.set_point_solid(Vector2i(i0 % size.x, i0 / size.x))
		i0 = land.find(1, i0 + 1)
	for b: Array in _buckets.values():
		for u: GameUnit in b:
			if u._occ_cell.x >= 0:
				for off: Vector2i in _stamp_offsets(u._occ_r):
					if _in(u._occ_cell + off):
						A.set_point_solid(u._occ_cell + off)
	_label(L)
	return L


## The class group sharing the dry / slope closures (_fixed).
static func _group(cls: int) -> int:
	return 0 if cls == 0 else (5 if cls == 5 or cls == 6 else (7 if cls == 7 else 1))


## The cells a class loses to dry ground, slopes and the border, shared by the
## classes that lose the same (the dilation shape and slope rules): closed
## dry cells with the class shape round them; slopes over 40 deg close a cell to every class but 0,
## over 60 deg to all; the 4 neighbours of such a cell are closed to classes
## 5-6, the 13-cell diamond round it to class 7; the 3 border cells are closed.
func _fixed(cls: int) -> PackedByteArray:
	var key := _group(cls)
	if _fixed_sets.has(key):
		return _fixed_sets[key]
	if _lists_dirty:
		_rebuild_lists()
	var n := size.x * size.y
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	# Closed dry cells (terrain cost) dilated by the class shape.
	var shape := _shape(cls)
	var i0 := _dry_raw.find(1)
	var w := size.x
	while i0 >= 0:
		var c0 := Vector2i(i0 % w, i0 / w)
		if c0.x > 0 and c0.y > 0 and c0.x < w - 1 and c0.y < size.y - 1 and _dry_raw[i0 - 1] != 0 \
				and _dry_raw[i0 + 1] != 0 and _dry_raw[i0 - w] != 0 and _dry_raw[i0 + w] != 0:
			out[i0] = 1
		else:
			for d: Vector2i in shape:
				var q := c0 + d
				if _in(q):
					out[q.y * w + q.x] = 1
		i0 = _dry_raw.find(1, i0 + 1)
	var near: Array = SHAPE_NEIGHBOURS if key == 5 else (SHAPE_DIAMOND if key == 7 else [])
	for i in _steep_cells:
		if _steep[i] == 2 or key != 0:
			out[i] = 1
		if not near.is_empty():
			var c0 := Vector2i(i % size.x, i / size.x)
			for d: Vector2i in near:
				var q := c0 + d
				if _in(q):
					out[q.y * size.x + q.x] = 1
	for cy in size.y:
		if cy < BORDER or cy >= size.y - BORDER:
			for cx in size.x:
				out[cy * size.x + cx] = 1
		else:
			for k in BORDER:
				out[cy * size.x + k] = 1
				out[cy * size.x + size.x - 1 - k] = 1
	_fixed_sets[key] = out
	return out


## One cell of _fixed (group `key`) or, with a layer's `raw`, of its `land`:
## the border, the slope rules and the closed cells within the class shape.
func _closed_at(c: Vector2i, key: int, raw: PackedByteArray) -> int:
	if c.x < BORDER or c.y < BORDER or c.x >= size.x - BORDER or c.y >= size.y - BORDER:
		return 1
	var i := c.y * size.x + c.x
	if _steep[i] == 2 or (_steep[i] != 0 and key != 0):
		return 1
	if key == 5 or key == 7:
		for d: Vector2i in (SHAPE_NEIGHBOURS if key == 5 else SHAPE_DIAMOND):
			var q := c + d
			if _in(q) and _steep[q.y * size.x + q.x] != 0:
				return 1
	# The shapes are symmetric: a closed cell at c + d closes c.
	for d: Vector2i in _shape(key if key != 1 else 3):
		var q := c + d
		if _in(q) and raw[q.y * size.x + q.x] != 0:
			return 1
	return 0


## The dilation shape of a class (map).
static func _shape(cls: int) -> Array:
	if cls == 5 or cls == 6:
		return SHAPE_DIAMOND
	if cls == 7:
		var out := []
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				out.append(Vector2i(dx, dy))
		out.append_array([Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)])
		return out
	return SHAPE_CROSS


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# ------------------------------------------------------------------ objects

## An object's footprint with its complexion's first morph
## axis at `t` (levers; < 0 = the record's): {"spans": {cell: [bottom, top,
## kind]}, "floors": {cell: top}} in height steps.
func _footprint(o: Node3D, t := -1.0) -> Dictionary:
	var out := {"spans": {}, "floors": {}}
	var info: Dictionary = o.get_meta("ei", {})
	if String(info.get("kind", "")) == "UNIT":
		return out
	var model := EIFigure.get_model(String(info.get("template", "")))
	if model.is_empty():
		return out
	var c: Vector3 = info.get("complexion", Vector3.ZERO)
	if t >= 0.0:
		c.x = t
	# Each part's offset in the object (its bone offsets down the chain,
	#  part record).
	var offs := {}
	var all := []
	for link: Array in model.links:
		var b: PackedFloat32Array = model.bones.get(link[0], PackedFloat32Array())
		offs[link[0]] = (offs.get(link[1], Vector3.ZERO) as Vector3) \
			+ (EIFigure.bone_pos(b, c) if b.size() >= 24 else Vector3.ZERO)
		all.append(link[0])
	# The record's body parts (prototype), else all.
	var names: Array = Array(info.get("parts", PackedStringArray()))
	if names.is_empty():
		names = all
	var q: Quaternion = info.get("rotation", Quaternion.IDENTITY)
	var rot := Basis(_ei_rot(q, Vector3(1, 0, 0)), _ei_rot(q, Vector3(0, 1, 0)), _ei_rot(q, Vector3(0, 0, 1)))
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	# On the ground of the object's cell (the terrain's, also under a floor:
	var oc := cell(Vector2(pos.x, pos.y))
	var base := Vector3(pos.x, pos.y, pos.z + (_h0[oc.y * size.x + oc.x] if _in(oc) else 0.0))
	var lists := [{}, {}]   # spans, floors: cell -> [bottom, top, kind]
	for nm in names:
		var part := String(nm).to_lower()
		var f: Dictionary = model.parts.get(part, {})
		if not offs.has(part) or f.is_empty():
			continue   # "Bodypart %s for object %s not found"
		# part flags 5, "BASE*" | 0x400, "CROWN*" | 0x90
		# "EMPTY*" | 0x890; 0x800 = no footprint, kind = (flags >> 3) & 7.
		var flags := 5
		if part.begins_with("base"):
			flags |= 0x400
		if part.begins_with("crown"):
			flags |= 0x90
		if part.begins_with("empty"):
			flags |= 0x890
		if flags & 0x800:
			continue
		var hdr: PackedFloat32Array = f.get("hdr", PackedFloat32Array())
		if hdr.is_empty():
			hdr = (f.data as PackedByteArray).slice(40, 40 + int(f.n) * 40).to_float32_array()
			f.hdr = hdr
		if hdr.size() < 80:
			continue
		# The .fig header: 8 centres, mins, maxes (the box around the centre).
		var ctr := Vector3(EIFigure.blend(hdr, 0, 3, c), EIFigure.blend(hdr, 1, 3, c), EIFigure.blend(hdr, 2, 3, c))
		var mn := Vector3(EIFigure.blend(hdr, 24, 3, c), EIFigure.blend(hdr, 25, 3, c), EIFigure.blend(hdr, 26, 3, c))
		var mx := Vector3(EIFigure.blend(hdr, 48, 3, c), EIFigure.blend(hdr, 49, 3, c), EIFigure.blend(hdr, 50, 3, c))
		if mn.x > mx.x or mn.y > mx.y or mn.z > mx.z:
			continue
		var o0: Vector3 = offs[part] + ctr
		_raster_box(o0 + mn, o0 + mx, rot, base, (flags >> 3) & 7, lists[1 if flags & 0x400 else 0])
	#  keep the spans with bottom < top.
	for i: int in lists[0]:
		var s: Array = lists[0][i]
		if s[0] < s[1]:
			out.spans[i] = s
	for i: int in lists[1]:
		var s: Array = lists[1][i]
		if s[0] < s[1]:
			out.floors[i] = s[1]
	return out


## EI-space vector `v` turned by the Godot-space quaternion `q`.
static func _ei_rot(q: Quaternion, v: Vector3) -> Vector3:
	var g := q * Vector3(v.x, v.z, -v.y)
	return Vector3(g.x, -g.z, g.y)


##  sampling of one box: its corners turned by `rot` and moved
## to `base`, each face sampled (round(3 x its horizontal edge length) + 2
## samples per edge, at the sample centres); a sample in a cell sets the
## cell's span top (an upward face, also lowering the kind) or
## bottom (the others).
func _raster_box(lo: Vector3, hi: Vector3, rot: Basis, base: Vector3, kind: int, list: Dictionary) -> void:
	var P: Array[Vector3] = []
	for k: Vector3i in BOX_CORNERS:
		P.append(rot * Vector3(hi.x if k.x else lo.x, hi.y if k.y else lo.y, hi.z if k.z else lo.z) + base)
	for k in 6:
		var top: bool = (rot * (FACE_NORMAL[k] as Vector3)).z > 0.0
		var o := P[k + 1]
		var a := P[k] - o
		var b := P[k + 2] - o
		var na := roundi(Vector2(a.x, a.y).length() * 3.0) + 2
		var nb := roundi(Vector2(b.x, b.y).length() * 3.0) + 2
		var da := a / na
		var db := b / nb
		var last := -1
		var s: Array = []
		for ia in na:
			var pa := o + da * (ia + 0.5) + db * 0.5
			for ib in nb:
				var px := pa.x + db.x * ib
				var py := pa.y + db.y * ib
				var cx := floori(px / CELL)
				var cy := floori(py / CELL)
				if cx < 0 or cy < 0 or cx >= size.x or cy >= size.y:
					continue
				var h := clampi(roundi((pa.z + db.z * ib) * _alt), 0, SPAN_MAX)
				var i := cy * size.x + cx
				if i != last:
					last = i
					s = list.get(i, [])
					if s.is_empty():
						s.append_array([0x7fffffff, h, kind] if top else [h, 0, kind])
						list[i] = s
						continue
				if top:
					if h > s[1]:
						s[1] = h
					if kind < s[2]:
						s[2] = kind
				elif h < s[0]:
					s[0] = h


## Adds an object's footprint to the cells; returns the key it is kept under.
func _add_footprint(o: Node3D, fp: Dictionary) -> int:
	var key := int(o.get_meta("ei", {}).get("nid", 0))
	if key == 0 or _fp.has(key):
		key = _next_key
		_next_key -= 1
	_fp[key] = fp
	_fp_nodes[key] = o
	_put(key, fp)
	return key


func _put(key: int, fp: Dictionary) -> void:
	for i: int in fp.spans:
		var s: Array = fp.spans[i]
		if not _spans.has(i):
			_spans[i] = []
		_spans[i].append([s[0], s[1], s[2], key])
	for i: int in fp.floors:
		if not _floors.has(i):
			_floors[i] = []
		_floors[i].append([fp.floors[i], key])


func _take(key: int, fp: Dictionary) -> void:
	for i: int in fp.spans:
		var a: Array = _spans.get(i, [])
		for k in range(a.size() - 1, -1, -1):
			if a[k][3] == key:
				a.remove_at(k)
		if a.is_empty():
			_spans.erase(i)
	for i: int in fp.floors:
		var a: Array = _floors.get(i, [])
		for k in range(a.size() - 1, -1, -1):
			if a[k][1] == key:
				a.remove_at(k)
		if a.is_empty():
			_floors.erase(i)


## A cell's height, water and ground under its floors (: the
## highest floor top over the terrain, no water, ground type 7), or the
## terrain's when it has none.
func _apply_floor(i: int) -> void:
	var fl: Array = _floors.get(i, [])
	if fl.is_empty():
		_h[i] = _h0[i]
		_depth[i] = _depth0[i]
		_cost[i] = _cost0[i]
		return
	var top := 0
	for e: Array in fl:
		top = maxi(top, e[0])
	_h[i] = maxf(_h0[i], top / _alt)
	_depth[i] = 0.0
	_cost[i] = _floor_cost


## Places an object added after the build (AddMob),.
func add_object(o: Node3D) -> void:
	if size.x == 0:
		return
	var fp := _footprint(o)
	_add_footprint(o, fp)
	_update_region(_fp_rect(fp))


## Takes a removed object's footprint off.
func remove_object(nid: int) -> void:
	if not _fp.has(nid):
		return
	var fp: Dictionary = _fp[nid]
	_take(nid, fp)
	_fp.erase(nid)
	_fp_nodes.erase(nid)
	_update_region(_fp_rect(fp))


## A lever's new state (: the figure's morph axis set to the
## target, the part boxes worked out again and the object placed anew).
func set_object_t(nid: int, t: float) -> void:
	var o: Node3D = _fp_nodes.get(nid)
	if o == null or not is_instance_valid(o):
		return
	var old: Dictionary = _fp[nid]
	var fp := _footprint(o, t)
	if fp.hash() == old.hash():
		return
	_take(nid, old)
	_fp[nid] = fp
	_put(nid, fp)
	var r := _fp_rect(old)
	var r2 := _fp_rect(fp)
	var region := r2 if r.size == Vector2i.ZERO else (r if r2.size == Vector2i.ZERO else r.merge(r2))
	_update_region(region)
	_relocate(region)


##  after re-placing the object: each unit around it whose cell
## and its eight neighbours are all closed to its class is
## put on the nearest open cell. Approx.: "around" = within
## the changed cells (the original: the object's radius + 0.5 m); the nearest
## open cell within 6 m stands in for the original's spiral search that also
## keeps the unit's connected area.
func _relocate(region: Rect2i) -> void:
	if region.size == Vector2i.ZERO:
		return
	var c0 := center(region.get_center())
	var rad := Vector2(region.size).length() * CELL * 0.5 + 1.0
	for u: GameUnit in units_around(c0, rad):
		if u.dead:
			continue
		var L := layer(u.move_class())
		var c := cell(u.pos)
		var open := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := c + Vector2i(dx, dy)
				if _in(q) and L.land[q.y * size.x + q.x] == 0:
					open = true
		if open:
			continue
		var best := u.pos
		var best_d := INF
		var rr := ceili(6.0 / CELL)
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var q := c + Vector2i(dx, dy)
				if _in(q) and L.land[q.y * size.x + q.x] == 0 and center(q).distance_squared_to(u.pos) < best_d:
					best_d = center(q).distance_squared_to(u.pos)
					best = center(q)
		if best_d < INF:
			u.pos = best
			u.path = PackedVector2Array()
			track_unit(u)


func _fp_rect(fp: Dictionary) -> Rect2i:
	var r := Rect2i()
	var first := true
	for d: Dictionary in [fp.spans, fp.floors]:
		for i: int in d:
			var c := Vector2i(i % size.x, i / size.x)
			if first:
				r = Rect2i(c, Vector2i.ONE)
				first = false
			else:
				r = r.expand(c).expand(c + Vector2i.ONE)
	return r


## Works out the cells of `r` again after their spans or floors changed, and
## the closures round them (over the box +- 3), in every built layer.
func _update_region(r: Rect2i) -> void:
	if r.size == Vector2i.ZERO:
		return
	var full := Rect2i(Vector2i.ZERO, size)
	r = r.intersection(full)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * size.x + x
			_apply_floor(i)
			_dry_cell(i)
	var r1 := r.grow(1).intersection(full)
	for y in range(r1.position.y, r1.end.y):
		for x in range(r1.position.x, r1.end.x):
			_steep[y * size.x + x] = _steep_at(y * size.x + x)
	_lists_dirty = true
	var g := r.grow(3).intersection(full)
	for key: int in _fixed_sets:
		var fs: PackedByteArray = _fixed_sets[key]
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				fs[y * size.x + x] = _closed_at(Vector2i(x, y), key, _dry_raw)
	for L: Layer in _layers.values():
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var i := y * size.x + x
				var wv := _cell_weight(i, L.cls) if _special[i] else (0.0 if _dry_raw[i] else _dry_weight[i])
				L.raw[i] = 1 if wv <= 0.0 else 0
				if wv > 0.0:
					L.astar.set_point_weight_scale(Vector2i(x, y), wv)
		var key := _group(L.cls)
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				var i := y * size.x + x
				L.land[i] = _closed_at(Vector2i(x, y), key, L.raw)
				L.astar.set_point_solid(Vector2i(x, y), L.land[i] != 0 or _occ[i] != 0)
		_label(L)


## `n`'s transform relative to the scene of `root` (both outside the tree too).
static func _local_xf(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent() as Node3D
	while p and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return root.transform * xf


## Labels the 8-connected regions of cells open to terrain and objects, so a
## search for a cut-off goal need not flood the whole region first.
func _label(L: Layer) -> void:
	# 8-connected regions of the open cells, numbered by their first cell in
	# row order. Done on the row runs of open cells (found with find(), so
	# the cells are not walked one by one in GDScript) joined by union-find:
	# the old per-cell flood fill took over half a second on a big map.
	var n := size.x * size.y
	var w := size.x
	L.comp.resize(n)
	L.comp.fill(0)
	var blocked := L.land
	var rs := PackedInt32Array()   # run start x
	var re := PackedInt32Array()   # run end x (exclusive)
	var ry := PackedInt32Array()
	var first := PackedInt32Array()   # first run of each row (+ the total)
	first.resize(size.y + 1)
	for y in size.y:
		first[y] = rs.size()
		var row := blocked.slice(y * w, y * w + w)
		var x := 0
		while x < w:
			var st := row.find(0, x)
			if st < 0:
				break
			var en := row.find(1, st)
			if en < 0:
				en = w
			rs.append(st)
			re.append(en)
			ry.append(y)
			x = en
	first[size.y] = rs.size()
	var runs := rs.size()
	var parent := PackedInt32Array()
	parent.resize(runs)
	for r in runs:
		parent[r] = r
	for y in range(1, size.y):
		var a := first[y - 1]
		var a_end := first[y]
		for r in range(first[y], first[y + 1]):
			# Runs of the row above touching this one, diagonals included.
			while a < a_end and re[a] < rs[r]:
				a += 1
			var b := a
			while b < a_end and rs[b] <= re[r]:
				var ra := _find(parent, r)
				var rb := _find(parent, b)
				if ra != rb:
					parent[maxi(ra, rb)] = mini(ra, rb)
				b += 1
	var ids := PackedInt32Array()
	ids.resize(runs)
	var next := 0
	for r in runs:
		var root := _find(parent, r)
		if ids[root] == 0:
			next += 1
			ids[root] = next
		var id := ids[root]
		var base := ry[r] * w
		for x in range(rs[r], re[r]):
			L.comp[base + x] = id


static func _find(parent: PackedInt32Array, r: int) -> int:
	while parent[r] != r:
		r = parent[r]
	return r


## The open cell of region `comp` nearest `p`, searched in square rings out
## to `radius` metres; (-1, -1) if none.
func _nearest_in(L: Layer, p: Vector2, comp: int, radius: float) -> Vector2i:
	var c := cell(p)
	for r in range(0, ceili(radius / CELL) + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			var step := 1 if absi(dy) == r else 2 * r
			for dx in range(-r, r + 1, maxi(step, 1)):
				var q := c + Vector2i(dx, dy)
				if not _in(q) or L.comp[q.y * size.x + q.x] != comp or L.astar.is_point_solid(q):
					continue
				var d := center(q).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _refresh(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	for L: Layer in _layers.values():
		L.astar.set_point_solid(c, L.land[i] != 0 or _occ[i] != 0)


static func cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func is_walkable(p: Vector2, cls := WALK_CLASS) -> bool:
	var c := cell(p)
	return _in(c) and not layer(cls).astar.is_point_solid(c)


## the cell under `p` is open to movement class `cls` (the
## class's nibble of the AI map cell; unit stamps are not looked at).
func cell_open(p: Vector2, cls: int) -> bool:
	var c := cell(p)
	return _in(c) and layer(cls).land[c.y * size.x + c.x] == 0


## the cell under `p` or one of its 8 neighbours (in the order
## (0,0) (1,0) (-1,0) (0,1) (0,-1) (1,1) (1,-1) (-1,1) (-1,-1)) is open to class
## `cls` and the height step from `p`'s cell to it passes the slope table
## (map, steps up to 40 deg;, up to 60 deg, for class 0 — both
## built over atan(dh / 0.5 m)).
func cell_or_neighbour_open(p: Vector2, cls: int) -> bool:
	var c := cell(p)
	if not _in(c):
		return false
	var L := layer(cls)
	var z := _h[c.y * size.x + c.x]
	var lim := MAX_STEP_ALL if cls == 0 else MAX_STEP
	for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var q := c + o
		if _in(q):
			var i := q.y * size.x + q.x
			if L.land[i] == 0 and absf(_h[i] - z) <= lim:
				return true
	return false


##  (map): the speed of a cell value, 1024 = full speed
## (-1: taken as 1024).
const SPEED_BY_VALUE := [-1, 512, 614, 716, 614, 716, 819, 716, 819, 921, 1024, 819, 921,
	1024, 1024, 1228]


## The speed factor of the step from `p`'s cell into `q`'s for class `cls`
## (stored on each path node as a ushort):
## (S << 9) / D over 512, S the cell value's speed (SPEED_BY_VALUE), D the
## slope table entry of the height step (_slope_div); 1 when both are the same
## cell or D < 0.
func step_factor(p: Vector2, q: Vector2, cls: int) -> float:
	var c := cell(p)
	var n := cell(q)
	if c == n or not _in(c) or not _in(n):
		return 1.0
	var i := n.y * size.x + n.x
	# A dry cell: its ground's value at speed 1024 (packs one
	# per class into ground; class 0 ignores the cost: row 0).
	var v := _cell_value(i, cls) if _special[i] != 0 else \
		(_value(0, 1024) if cls == 0 and _cost[i] >= 0 and _cost[i] <= 70 else _value(_cost[i], 1024))
	var sp: int = SPEED_BY_VALUE[v]
	if sp < 0:
		sp = 1024
	var dh := roundi(_h[i] * _alt) - roundi(_h[c.y * size.x + c.x] * _alt)
	var d := _slope_div(dh, cls)
	if d <= 0:
		return 1.0
	return float((sp << 9) / d) / 512.0


## the slope tables by height step dh (map for classes
## other than 0, for class 0), over theta = atan((|dh|) / 0.5 m):
## up or level round(1024 (1 + sin^2)^2), down round(1024 / (1 + sin^2)); over
## 40 deg -1. Class 0: 1024, over 60 deg -1.
func _slope_div(dh: int, cls: int) -> int:
	# Remake speed: a pure function of dh, class 0 or not and the map's _alt,
	# asked for every moving unit every physics step: remembered.
	var key := dh * 2 + int(cls == 0)
	var got = _slope_memo.get(key)
	if got != null:
		return got
	var v := _slope_div_calc(dh, cls)
	_slope_memo[key] = v
	return v


var _slope_memo := {}   # _slope_div results (cleared with _alt in build)


func _slope_div_calc(dh: int, cls: int) -> int:
	var th := rad_to_deg(atan((absf(dh) / _alt) / CELL))
	if cls == 0:
		return -1 if th > 60.0 else 1024
	if th > 40.0:
		return -1
	var s2 := pow(sin(deg_to_rad(th)), 2)
	return roundi(1024.0 * pow(1.0 + s2, 2)) if dh >= 0 else roundi(1024.0 / (1.0 + s2))


## The nearest open cell centre within `radius` metres of `p` (`p` itself when open).
func nearest_walkable(p: Vector2, radius := 6.0, cls := WALK_CLASS) -> Vector2:
	var A := layer(cls).astar
	var c := cell(p)
	if _in(c) and not A.is_point_solid(c):
		return p
	var best := p
	var best_d := INF
	var r := ceili(radius / CELL)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if _in(q) and not A.is_point_solid(q):
				var d := center(q).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = center(q)
	return best


## `nearest_walkable` for unit `u`'s own move: its own stamp lifted first, as
## find_path lifts the mover's. Without that the
## cell a unit stands on counts as closed to itself, and an order to the spot
## it already holds was moved to a neighbour cell — a script looping SetCP to
## its own spot (basecam.mob VTriger#0#378, Human4) then paced between the two
## cells for ever.
func nearest_walkable_for(u: GameUnit, p: Vector2, radius := 6.0, cls := WALK_CLASS) -> Vector2:
	var lift := u != null and u._occ_cell.x >= 0
	if lift:
		_stamp(u._occ_cell, u._occ_r, -1)
	var out := nearest_walkable(p, radius, cls)
	if lift:
		_stamp(u._occ_cell, u._occ_r, 1)
	return out


## Path in EI xy from `a` to `b` for movement class `cls`, smoothed by
## line-of-sight. Empty if unreachable.
## The stamps of the `ignore` units are lifted for the search (the mover and,
## for an attack, its target: take them out with
## ), and so are those of units standing over the start cell (the
## original lets a unit step from a stamped cell to a cell of no higher value
## ). `avoid` units are stamped once more, as if standing, with
## their radius + `extra` (: a faster mover going round a slower
## one; `extra` = the mover's radius over R_REF, as the grid is stamped for R_REF).
func find_path(a: Vector2, b: Vector2, ignore: Array = [], avoid: Array = [], extra := 0.0,
		cls := WALK_CLASS) -> PackedVector2Array:
	var L := layer(cls)
	var lifted := []
	for u: GameUnit in ignore:
		if u and u._occ_cell.x >= 0:
			lifted.append(u)
	var sc := cell(a)
	if _in(sc) and _occ[sc.y * size.x + sc.x] != 0:
		for u: GameUnit in units_around(a, 5.0):
			if u._occ_cell.x >= 0 and not u in lifted and _stamp_covers(u, sc):
				lifted.append(u)
	for u: GameUnit in lifted:
		_stamp(u._occ_cell, u._occ_r, -1)
	var stamped := []
	for u: GameUnit in avoid:
		if not u.dead and not u in ignore:
			stamped.append(u)
			_stamp(cell(u.pos), u.body_radius() + extra, 1)
	var out := _find_path(L, a, b)
	for u: GameUnit in stamped:
		_stamp(cell(u.pos), u.body_radius() + extra, -1)
	for u: GameUnit in lifted:
		_stamp(u._occ_cell, u._occ_r, 1)
	return out


func _find_path(L: Layer, a: Vector2, b: Vector2) -> PackedVector2Array:
	var A := L.astar
	var start := cell(a)
	if not _in(start):
		return PackedVector2Array()
	if A.is_point_solid(start):
		start = cell(nearest_walkable(a, 1.5, L.cls))
		if not _in(start) or A.is_point_solid(start):
			return PackedVector2Array()
	var goal := cell(nearest_walkable(b, 6.0, L.cls))
	if not _in(goal) or A.is_point_solid(goal):
		return PackedVector2Array()
	var comp := L.comp[start.y * size.x + start.x]
	if comp != 0 and L.comp[goal.y * size.x + goal.x] != comp:
		# Approx. (moves an unreachable goal by a spiral search; its
		# reach was not traced): the nearest cell of the start's region.
		var g := _nearest_in(L, b, comp, 32.0)
		if g.x >= 0:
			goal = g
	# Partial path when the goal is cut off: the original's search also ends at the
	# reachable cell nearest the goal (callers then compare the end with the goal).
	var cells := A.get_id_path(start, goal, true)
	if cells.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for c in cells:
		pts.append(center(c))
	if is_walkable(b, L.cls) and cell(b) == cells[-1]:
		pts[-1] = b
	return _smooth(L, a, pts)


func _smooth(L: Layer, a: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var from := a
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not line_clear(from, pts[j], L.cls):
			j -= 1
		out.append(pts[j])
		from = pts[j]
		i = j + 1
	return out


## the ground type (tiledesc index, the low 5 bits of the AI
## map cell, map) under `p`: a floor cell's is 7
## -1 off the map.
func cell_ground(p: Vector2) -> int:
	var c := cell(p)
	if not _in(c):
		return -1
	if _floors.has(c.y * size.x + c.x):
		return FLOOR_GROUND
	return terrain.ground_type(p.x, p.y) if terrain else 0


##  (also script IsUnitInWater, 0x99): the cell under `p` is
## under water (AI map cell byte 6 bit 7).
func cell_wet(p: Vector2) -> bool:
	var c := cell(p)
	return _in(c) and _depth[c.y * size.x + c.x] > 0.0


## the largest height difference (m) between the cell under
## `p` and its four neighbours; 0 at the map's edge cells and off the map.
func cell_slope(p: Vector2) -> float:
	var c := cell(p)
	if c.x <= 0 or c.y <= 0 or c.x > size.x - 2 or c.y > size.y - 2:
		return 0.0
	var i := c.y * size.x + c.x
	var h0 := roundi(_h[i] * _alt)
	var best := 0
	for j in [i + size.x, i - size.x, i + 1, i - 1]:
		best = maxi(best, absi(roundi(_h[j] * _alt) - h0))
	return best / _alt


## the line-of-sight ray from (a, za) to (b, zb) (heights
## metres): d = |b − a| (3D) / 0.5 m, n = round(d) steps of 1 / d in 16.16
## fixed point; 1 when d = 0, 0 when the start or end cell is off the map.
## Each step's height in steps at or below the cell's height (floors
## included) ends it with 0; every object span of the cell whose
## [bottom, top] holds the height multiplies the result at the
## span's class (cell bits 5-6: 0 → 0, 1 → 0.98, 2 → 0.99, 3 → 1; the class
## is part flags (>> 6) & 0xf, merged like the kind, so CROWN parts (flags
## 0x95) give class 2 = kind 2 and every other part class 0 = kind 0), and
## below 0.0001 it returns 0.0001. So walls, fences, cages and tree trunks
## hide what is behind them; crowns barely do.
func ray(a: Vector2, za: float, b: Vector2, zb: float) -> float:
	if size.x == 0:
		return 1.0
	var d := Vector3(b.x - a.x, b.y - a.y, zb - za).length() / CELL
	if d == 0.0:
		return 1.0
	var n := roundi(d)
	var step := (b - a) / d
	if not _in(cell(a)) or not _in(cell(a + step * n)):
		return 0.0
	var h0 := roundi(za * _alt)
	var dh := float(roundi(zb * _alt) - h0) / d
	var f := 1.0
	for k in range(1, n + 1):
		var c := cell(a + step * k)
		if not _in(c):
			return 0.0
		var i := c.y * size.x + c.x
		var hs := floori(h0 + dh * k)
		if hs <= roundi(_h[i] * _alt):
			return 0.0
		var spans: Array = _spans.get(i, [])
		for s: Array in spans:
			if hs <= int(s[1]) and int(s[0]) <= hs:
				f *= 0.99 if int(s[2]) == 2 else 0.0
				if f < 0.0001:
					return 0.0001
	return f


## The AI map height (m) of the cell under `p` (floors included); 0 off the map.
func cell_height(p: Vector2) -> float:
	var c := cell(p)
	return _h[c.y * size.x + c.x] if _in(c) else 0.0


## the largest height difference (m) between successive cells
## on the line a → b, walked in round(|b − a| / 0.5) steps of 16.16 fixed
## point cell coordinates; 100 when an end is off the map, 1 for a = b.
func max_step(a: Vector2, b: Vector2) -> float:
	var d := b - a
	var n_f := d.length() / CELL
	if n_f == 0.0:
		return 1.0
	var n := roundi(n_f)
	var x := roundi(a.x * 65536.0 / CELL)
	var y := roundi(a.y * 65536.0 / CELL)
	var sx := roundi(d.x / n_f * 65536.0 / CELL)
	var sy := roundi(d.y / n_f * 65536.0 / CELL)
	var c0 := Vector2i(x >> 16, y >> 16)
	var c1 := Vector2i((x + sx * n) >> 16, (y + sy * n) >> 16)
	if not _in(c0) or not _in(c1):
		return 100.0
	var prev := roundi(_h[c0.y * size.x + c0.x] * _alt)
	var best := 0
	for k in n:
		x += sx
		y += sy
		var c := Vector2i(x >> 16, y >> 16)
		var h := roundi(_h[c.y * size.x + c.x] * _alt) if _in(c) else prev
		best = maxi(best, absi(h - prev))
		prev = h
	return best / _alt


func line_clear(a: Vector2, b: Vector2, cls := WALK_CLASS) -> bool:
	var A := layer(cls).astar
	var d := a.distance_to(b)
	var steps := int(d * 4.0) + 1
	for s in range(1, steps + 1):
		var c := cell(a.lerp(b, float(s) / steps))
		if not _in(c) or A.is_point_solid(c):
			return false
	return true


# ------------------------------------------------------------------ units

## Cell offsets a standing unit of radius `r` closes on the path grid.
func _stamp_offsets(r: float) -> Array:
	var k := roundi(r * 10.0 + 1.0)
	if _stamps.has(k):
		return _stamps[k]
	var out := []
	var thr := roundi((2.0 - R_REF) * 16.0)
	for dy in range(-8, 8):
		for dx in range(-8, 8):
			if stamp_value(k, dx, dy) > thr:
				out.append(Vector2i(dx, dy))
	_stamps[k] = out
	return out


## Value of the stamp of a unit (radius r' = k / 10) at a cell offset.
static func stamp_value(k: int, dx: int, dy: int) -> int:
	if dx < -8 or dy < -8 or dx > 7 or dy > 7:
		return 0
	return maxi(0, roundi((k * 0.1 + 2.0 - sqrt(dx * dx + dy * dy) * 0.5) * 16.0))


func _stamp(c: Vector2i, r: float, add: int) -> void:
	for off: Vector2i in _stamp_offsets(r):
		var q := c + off
		if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
			var i := q.y * size.x + q.x
			_occ[i] += add
			if _occ[i] == (1 if add > 0 else 0):
				_refresh(q)


func _stamp_covers(u: GameUnit, c: Vector2i) -> bool:
	return (c - u._occ_cell) in _stamp_offsets(u._occ_r)


## Keeps a unit's stamp (standing units only: the original puts moving units on a
## separate layer, map, that only the movers' steps test)
## and its spatial hash entry up to date. Called after each unit tick.
func track_unit(u: GameUnit) -> void:
	var standing := not u.dead and not u._moving and size.x > 0
	var c := cell(u.pos) if standing else Vector2i(-1, -1)
	var r := u.body_radius()
	if c != u._occ_cell or (standing and r != u._occ_r):
		if u._occ_cell.x >= 0:
			_stamp(u._occ_cell, u._occ_r, -1)
		u._occ_cell = c
		u._occ_r = r
		if standing:
			_stamp(c, r, 1)
	rebucket(u)


## Puts a unit in the spatial bucket of its position (none while dead or not
## in GameWorld.units); GameUnit.pos calls it on every change.
func rebucket(u: GameUnit) -> void:
	var ak := -1 if u._seq == 0 else _bucket_key(u.pos)
	# The coarse grids (CBUCKET) serve the wide queries (sight radii).
	var cak := -1 if u._seq == 0 else _cbucket_key(u.pos)
	if cak != u._cabucket:
		if u._cabucket != -1 and _call_buckets.has(u._cabucket):
			(_call_buckets[u._cabucket] as Array).erase(u)
		u._cabucket = cak
		if cak != -1:
			if not _call_buckets.has(cak):
				_call_buckets[cak] = []
			_call_buckets[cak].append(u)
	var ck := -1 if u.dead or u._seq == 0 else _cbucket_key(u.pos)
	if ck != u._cbucket:
		if u._cbucket != -1 and _cbuckets.has(u._cbucket):
			(_cbuckets[u._cbucket] as Array).erase(u)
		u._cbucket = ck
		if ck != -1:
			if not _cbuckets.has(ck):
				_cbuckets[ck] = []
			_cbuckets[ck].append(u)
	if ak != u._abucket:
		if u._abucket != -1 and _all_buckets.has(u._abucket):   # (a key of another map's grid: nothing to drop)
			(_all_buckets[u._abucket] as Array).erase(u)
		u._abucket = ak
		if ak != -1:
			if not _all_buckets.has(ak):
				_all_buckets[ak] = []
			_all_buckets[ak].append(u)
	var key := -1 if u.dead or u._seq == 0 else _bucket_key(u.pos)
	if key != u._bucket:
		if u._bucket != -1 and _buckets.has(u._bucket):
			(_buckets[u._bucket] as Array).erase(u)
		u._bucket = key
		if key != -1:
			if not _buckets.has(key):
				_buckets[key] = []
			_buckets[key].append(u)


func untrack_unit(u: GameUnit) -> void:
	if u._occ_cell.x >= 0:
		_stamp(u._occ_cell, u._occ_r, -1)
		u._occ_cell = Vector2i(-1, -1)
	if u._bucket != -1:
		(_buckets[u._bucket] as Array).erase(u)
		u._bucket = -1
	if u._abucket != -1:
		(_all_buckets[u._abucket] as Array).erase(u)
		u._abucket = -1
	if u._cbucket != -1 and _cbuckets.has(u._cbucket):
		(_cbuckets[u._cbucket] as Array).erase(u)
	u._cbucket = -1
	if u._cabucket != -1 and _call_buckets.has(u._cabucket):
		(_call_buckets[u._cabucket] as Array).erase(u)
	u._cabucket = -1


var _all_buckets := {}   # like _buckets, with the dead units too (units_all_around)
## Remake (CPU): the same two indexes on a 16 m grid for queries of 6 m and
## more (a 25 m sight radius reads 16 cells instead of ~170); the result is
## the same units, sorted the same way.
const CBUCKET := 16.0
const WIDE := 6.0
var _cbuckets := {}
var _call_buckets := {}


## Every unit in GameWorld.units within `r` of `p`, dead ones too, in
## GameWorld.units order: GameWorld.units_near from the buckets.
func units_all_around(p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	var bs := BUCKET if r < WIDE else CBUCKET
	var grid: Dictionary = _all_buckets if r < WIDE else _call_buckets
	for by in range(floori((p.y - r) / bs), floori((p.y + r) / bs) + 1):
		for bx in range(floori((p.x - r) / bs), floori((p.x + r) / bs) + 1):
			var b = grid.get(bx + by * 4096)
			if b != null:
				for u: GameUnit in b:
					if u.pos.distance_squared_to(p) <= r2:
						out.append(u)
	if out.size() > 1:
		out.sort_custom(func(a: GameUnit, b: GameUnit): return a._seq < b._seq)
	return out


static func _bucket_key(p: Vector2) -> int:
	return floori(p.x / BUCKET) + floori(p.y / BUCKET) * 4096


static func _cbucket_key(p: Vector2) -> int:
	return floori(p.x / CBUCKET) + floori(p.y / CBUCKET) * 4096


## Live units within `r` of `p` (tracked ones only, i.e. on the host).
func units_around(p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	var bs := BUCKET if r < WIDE else CBUCKET
	var grid: Dictionary = _buckets if r < WIDE else _cbuckets
	for by in range(floori((p.y - r) / bs), floori((p.y + r) / bs) + 1):
		for bx in range(floori((p.x - r) / bs), floori((p.x + r) / bs) + 1):
			var b = grid.get(bx + by * 4096)
			if b != null:
				for u: GameUnit in b:
					if u.pos.distance_squared_to(p) <= r2:
						out.append(u)
	# In GameWorld.units order, as a scan of every unit returns them.
	if out.size() > 1:
		out.sort_custom(func(a: GameUnit, b: GameUnit): return a._seq < b._seq)
	return out


## The unit that stops `u` stepping to `q` (
## ), or null. The step is free when the cell of `q` is the unit's
## own cell, or when on each layer (standing / moving units) the stamp value
## there is at most round(16 (2 - R)) or at most the value of the cell the unit
## stands on. Otherwise the blocker is a unit whose centre is closer to `q`
## than the two radii and whose stamp at the mover's cell reaches the
## threshold; none found lets the step through. `standing` reports the layer.
func step_blocker(u: GameUnit, q: Vector2, result: Dictionary) -> GameUnit:
	var cq := cell(q)
	var c0 := cell(u.pos)
	if cq == c0:
		return null
	var r_me := u.body_radius()
	var thr := roundi((2.0 - r_me) * 16.0)
	var near := units_around(q, 4.5)
	var vq := [0, 0]
	var v0 := [0, 0]
	for o: GameUnit in near:
		if o == u or o.dead:
			continue
		var k := roundi(o.body_radius() * 10.0 + 1.0)
		var oc := cell(o.pos)
		var layer := 1 if o._moving else 0
		vq[layer] = maxi(vq[layer], stamp_value(k, cq.x - oc.x, cq.y - oc.y))
		v0[layer] = maxi(v0[layer], stamp_value(k, c0.x - oc.x, c0.y - oc.y))
	var layer := -1
	if vq[0] > thr and vq[0] > v0[0]:
		layer = 0
	elif vq[1] > thr and vq[1] > v0[1]:
		layer = 1
	if layer < 0:
		return null
	for o: GameUnit in near:
		if o == u or o.dead or q.distance_to(o.pos) >= r_me + o.body_radius():
			continue
		var oc := cell(o.pos)
		if stamp_value(roundi(o.body_radius() * 10.0 + 1.0), c0.x - oc.x, c0.y - oc.y) >= thr:
			result.standing = layer == 0
			return o
	return null
