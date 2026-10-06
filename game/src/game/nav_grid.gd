class_name NavGrid
extends RefCounted
## Walkability grid over a zone with A* paths, after the original's AI map (CAIMap
## built): 0.5 m cells (64 per 32 m sector), each with a ground
## height (half the nearest quad corner + a quarter of its two edge neighbours), the water depth
## and the ground type of its terrain tile.
##
## Passability and path cost of a cell, one 4-bit value per movement class
## (the class of a unit: GameUnit.move_class
##   cost = tiledesc.reg CostMul (of the liquid's tile type under a type 2 / 3
##   liquid, so lava costs 1 and is closed only by depth), + 30 when wading
##   deeper than half the class height; speed = 1024, 880 in shallow water, 800
##   wading; in height steps closed at depth >= class height - 1 (
##   class 1 in any water) or cost > 70;
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
## beyond the last allowed quantized step of the 40 deg table keeps only class
## 0, beyond the 60 deg table none; its 4 neighbours lose classes 5-6 and the 13-cell
## diamond round it class 7. The 3 border cells are blocked.
## Each class has its own A* grid, built when a unit of that class first asks.
## Standing units block the cells around them (see track_unit).
## Path search: the original's step cost (
## ) = ((slope factor x cell cost) >> 10) x step >> 10, step 0x400
## straight / 0x5a8 diagonal, cell cost = the step cost table by the cell value
## (or the flat 0x400 table while unit is set), slope factor = the class's
##  entry for the height step to the cell (uphill x (1 + sin^2)^2
## downhill / (1 + sin^2)); unit stamps close a cell for the mover whose value
## there is over round(16 (2 - its radius)) and not below its own cell's (
## ). A goal under 25 cells (octile) and within the 32 x 32 window
## is searched in that window, else along the block route.
## The turn pass (NavTurn) shifts nearby cells, prices the bend's
## effective length, adds 600 per 45 deg turn past the first and the end term
## for a diagonal last step, then repeats while the cost decreases.
## Heights for passability and costs are in the original's 1/ steps (=
## 511 / the map's max altitude; spans clamped to 0..1020 steps).
## Native 4 m representatives and signed symmetric edge costs choose the
## block route (NavBlocks); a moving 32x32 frontier retains overlap and
## parent directions. Goal relocation uses the native eight-ray/component
## search. The complete cell route is retained for the native timed spline.
## The earlier A* and LOS path is available only through exact_search=false
## for the existing comparison tools.

const CELL := 0.5
const TurnPass = preload("res://src/game/nav_turn.gd")
const BlockGraph = preload("res://src/game/nav_blocks.gd")
const FigureGeometry = preload("res://src/ei/figure_geometry.gd")
## Nominal metre-space cutoffs for diagnostic tools; passability uses the
## quantized heights and slope tables.
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
##  (map): the flat table, 0x400 for every open value; the
## search takes it instead while unit is set:
## attack approaches and moves ordered while the
## unit stands in water.
const FLAT_COST := 0x400
## step lengths of the 8 neighbours (1024 = one cell).
const STEP_STRAIGHT := 0x400
const STEP_DIAG := 0x5a8
## a turn of k 45-degree steps between two path
## steps (or from the unit's heading to the first) costs
## round(max(0, k - 1) * 10.0 * 60) (the 10.0 is of the pass's block
## set).
const TURN_COST := 600
## the 8 directions of the path passes (1..8), cell offsets.
const DIR_X := [0, 0, -1, -1, -1, 0, 1, 1, 1]
const DIR_Y := [0, -1, -1, 0, 1, 1, 1, 0, -1]
## the direct search's window (32 x 32 cells inside a 34 x 34
## node block) and limit for it: octile distance under 25 cells.
const WINDOW := 32
const DIRECT_CELLS := 25
## The half width (cells) of the band round the A* route the exact search
## of a longer path runs in (the original's windows: 16).
const BAND := 8
## a spot is refused when its path costs more than
## d * 2 * 5000 (d = the 3D distance in metres).
const COST_PER_M := 10000.0
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
## A completed native query can be repeated without changing its inputs.
## Keep a bounded set of results, validated against every painted stamp
## window actually consumed by the search and turn pass.
const PATH_MEMO_MAX := 64
const PATH_MEMO_INTS := 1048576


## One movement class's passability: its A* grid, the cells closed for the
## class before (`raw`) and after the class shape and slopes (`land`), and the regions.
class Layer:
	var cls := 3
	var astar := AStarGrid2D.new()
	var raw := PackedByteArray()
	var land := PackedByteArray()
	var comp := PackedInt32Array()   # connected region of each open cell, 0 = closed
	## A lower bound of the step cost table entries per 8 x 8 block (BLOCK):
	## the commonest entry or the smallest of the block's other entries
	## (_block_cmin; only ever lowered when cells change).
	var bmin := PackedInt32Array()
	## The step cost table entry of every cell: the A*
	## weight x 1024 (closed cells keep a stale entry; L.land closes them).
	var cost := PackedInt32Array()


## The class-3 grid (kept for tools and callers that do not name a class).
var astar: AStarGrid2D:
	get: return layer(WALK_CLASS).astar
var size := Vector2i.ZERO
var terrain: EITerrain
var _layers := {}                # class -> Layer
var _native_graphs := {}
var _graphs_rev := -1
var _h0 := PackedFloat32Array()  # terrain cell heights
var _cost0 := PackedInt32Array() # tiledesc cost of the terrain, -1 = impassable
var _depth0 := PackedFloat32Array()  # water depth over the terrain
var _h := PackedFloat32Array()   # cell heights (floors raise them)
var _hq0 := PackedInt32Array()   # terrain cell heights steps
var _hq := PackedInt32Array()    # cell heights steps (the AI map's ushort)
var _cost := PackedInt32Array()  # tiledesc cost before water, -1 = impassable
var _depth := PackedFloat32Array()  # water depth over the cell's floor
var _liq := PackedByteArray()      # ground type of the liquid over the terrain, 255 = none
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
var _face_buckets := {}          # 4m square -> [object key, native BASE face]
var floor_rev := 0               # placement caches / immutable worker snapshot
var _face_snapshot_rev := -1
var _face_snapshot := {}
var _next_key := -1
var _occ := PackedByteArray()    # standing units whose stamp closes the cell (count)
## Counts the changes of the map's cells (build, objects, levers; not the
## unit stamps): a path planned on an older one is not reused (GameUnit._kept).
var map_rev := 0
var _stamps := {}                # quantised radius x 10 -> Array[Vector2i]
var _buckets := {}               # key -> Array[GameUnit]
var registry_world: GameWorld
var registered_units := {}       # instance id -> currently tracked unit
var registry_rev := 0            # membership only, not ordinary movement
var path_memo := true
var _path_memo := {}
var _path_memo_order: Array = []
var _path_memo_ints := 0
var _path_memo_rev := -1
var _stamp_kernel: RefCounted
var _stamp_kernel_checked := false
var _memo_capture := false
var _memo_windows := {}
var _memo_capture_ints := 0
var _memo_complete := true
var _memo_end_written := false


func build(t: EITerrain, water_levels: PackedFloat32Array, objects: Array) -> void:
	terrain = t
	map_rev += 1
	_layers = {}
	_spans = {}
	_floors = {}
	_fp = {}
	_fp_nodes = {}
	_face_buckets = {}
	floor_rev += 1
	var qw := t.sectors_x * EITerrain.SECTOR
	var qh := t.sectors_y * EITerrain.SECTOR
	size = Vector2i(qw * 2, qh * 2)
	var n := size.x * size.y
	_occ.resize(n)
	_occ.fill(0)
	_h0.resize(n)
	_hq0.resize(n)
	_cost0.resize(n)
	_depth0.resize(n)
	_depth0.fill(0.0)
	_steep.resize(n)
	_steep.fill(0)
	_fixed_sets = {}
	_alt = 511.0 / t.max_altitude if t.max_altitude > 0.0 else 1.0
	_slope_memo.clear()
	_build_slope_tabs()
	# Per ground type: cost (tiledesc CostMul, ground
	# defaults it to 1). Speed (lava -1) takes no part in the AI map:
	# lava cells are priced like any other ground (CostMul 1) and closed only
	# by their depth.
	var cost_of := PackedInt32Array()
	cost_of.resize(32)
	for g in 32:
		cost_of[g] = int(EITerrain.ground_value(g, "CostMul", 1.0))
	_floor_cost = cost_of[FLOOR_GROUND]
	var w := t.grid_w
	var hs := t.heights
	var has_ground := not t.ground.is_empty()
	var has_water := not water_levels.is_empty()
	# Liquids of map material type 2 / 3 put their tile's ground type on the
	# cells they cover (depth byte bit 0x80).
	var liq_ok := PackedByteArray()
	liq_ok.resize(256)
	for m in t.materials.size():
		var ty := int(t.materials[m].get("type", -1))
		liq_ok[m] = 1 if ty == 2 or ty == 3 else 0
	var has_liq := has_water and t.liquid_ground.size() == water_levels.size() \
		and t.water_mat.size() == water_levels.size()
	_liq.resize(n)
	_liq.fill(255)
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
			_hq0[i] = roundi(gz * _alt)
			var q := qy * qw + qx
			_cost0[i] = cost_of[int(t.ground[q]) & 31] if has_ground else 2
			if has_water:
				# the depth in height steps, 6 bits (63 = deeper)
				# a cell is under water when it rounds to 1 or more.
				var dep := maxf(0.0, water_levels[q] - gz)
				if roundi(dep * _alt) >= 1:
					_depth0[i] = dep
					if has_liq and t.liquid_ground[q] != 255 and liq_ok[t.water_mat[q]] == 1:
						_liq[i] = t.liquid_ground[q] & 31
						_cost0[i] = cost_of[_liq[i]]
	_h = _h0.duplicate()
	_hq = _hq0.duplicate()
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
	var z := _hq[i]
	var d := maxi(maxi(absi(_hq[i - 1] - z), absi(_hq[i + 1] - z)),
		maxi(absi(_hq[i - size.x] - z), absi(_hq[i + size.x] - z)))
	#  uses the last nonnegative entries of the slope tables
	# compared with the cells' ushort heights, not metre-space thresholds.
	if d > SLOPE_MID or _slope_tab[0][d + SLOPE_MID] < 0:
		return 2
	return 1 if _slope_tab[1][d + SLOPE_MID] < 0 else 0


## The class-independent state of a cell: whether the layers work it out
## (water, object spans) or its dry value.
func _dry_cell(i: int) -> void:
	_dry_raw[i] = 0
	_dry_weight[i] = 1.0
	if _depth[i] > 0.0 or _spans.has(i):
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
	# Class 0 ignores the ground's cost and the water (cost 1, speed 1024).
	var cost := 1 if cls == 0 else _cost[i]
	if cost < 0:
		return 0
	var speed := 1024
	var depth := _depth[i]
	var wade: float = CLASS_HEIGHT[cls]
	if depth > 0.0 and cls != 0:
		# In height steps: the depth dq (6 bits) against the class height hq
		# (x, 0 for class 1): closed at dq = 63 or
		# dq >= hq - 1; below hq 1024, deeper than hq / 2 wades (800, cost
		# + 30), else 880.
		var dq := mini(63, roundi(depth * _alt))
		var hq := 0 if cls == 1 else roundi(wade * _alt)
		if dq == 63 or hq - 1 <= dq:
			return 0
		if hq < 1024:
			if hq / 2 < dq:
				speed = 800
				cost += 30
			else:
				speed = 880
	var spans: Array = _spans.get(i, [])
	if not spans.is_empty():
		# The body: quantized floor (class 0 adds capped depth), up by class height.
		var bb := _hq[i] + (mini(63, roundi(depth * _alt)) if cls == 0 else 0)
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
	var mode_weight := 1.0 if cls == 0 else _mode_w
	A.fill_weight_scale_region(A.region, mode_weight)
	L.cost.resize(n)
	L.cost.fill(roundi(mode_weight * 1024.0))
	var bw := (size.x + BLOCK - 1) / BLOCK
	L.bmin.resize(bw * ((size.y + BLOCK - 1) / BLOCK))
	L.bmin.fill(roundi(mode_weight * 1024.0))
	for i in _dry_diff:
		var weight_here := 1.0 if cls == 0 else _dry_weight[i]
		A.set_point_weight_scale(Vector2i(i % size.x, i / size.x), weight_here)
		L.cost[i] = roundi(weight_here * 1024.0)
		var bi := (i / size.x / BLOCK) * bw + (i % size.x) / BLOCK
		L.bmin[bi] = mini(L.bmin[bi], L.cost[i])
	for k in _special_cells.size():
		if weight[k] > 0.0:
			var i := _special_cells[k]
			A.set_point_weight_scale(Vector2i(i % size.x, i / size.x), weight[k])
			L.cost[i] = roundi(weight[k] * 1024.0)
			var bi := (i / size.x / BLOCK) * bw + (i % size.x) / BLOCK
			L.bmin[bi] = mini(L.bmin[bi], L.cost[i])

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
	var out := {"spans": {}, "floors": {}, "radius": 0.0, "faces": []}
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
	var base := Vector3(pos.x, pos.y, pos.z + (_hq0[oc.y * size.x + oc.x] / _alt if _in(oc) else 0.0))
	var lists := [{}, {}]   # spans, floors: cell -> [bottom, top, kind]
	var bounds: Array = []
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
		var geometry: Dictionary = FigureGeometry.from_figure(f, c)
		if geometry.is_empty():
			continue
		bounds.append({"position": offs[part], "geometry": geometry})
		if flags & 0x800:
			continue
		var ctr: Vector3 = geometry.centre
		var mn: Vector3 = geometry.min
		var mx: Vector3 = geometry.max
		if mn.x > mx.x or mn.y > mx.y or mn.z > mx.z:
			continue
		var o0: Vector3 = offs[part] + ctr
		_raster_box(o0 + mn, o0 + mx, rot, base, (flags >> 3) & 7, lists[1 if flags & 0x400 else 0])
		if flags & 0x400:
			out.faces.append_array(_box_faces(o0 + mn,o0 + mx,rot,base,rot * o0 + base,float(geometry.radius)))
	if not bounds.is_empty():
		out.radius = FigureGeometry.combine(bounds).radius
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


##  560650: the six authored box rectangles. Only normals
## whose z is at least0.8 join the scene's ground-plane list.
static func _box_faces(lo: Vector3,hi: Vector3,rot: Basis,base: Vector3,centre: Vector3,radius: float) -> Array:
	var points: Array[Vector3] = []
	for k: Vector3i in BOX_CORNERS:
		points.append(rot * Vector3(hi.x if k.x else lo.x,hi.y if k.y else lo.y,hi.z if k.z else lo.z) + base)
	var faces := []
	for k in 6:
		var normal: Vector3 = rot * FACE_NORMAL[k]
		if normal.z < 0.800000011920929:
			continue
		var origin := points[k+1]
		var a := points[k] - origin
		var b := points[k+2] - origin
		var al := float(a.length())
		var bl := float(b.length())
		if al == 0.0 or bl == 0.0:
			continue
		faces.append({"centre":centre,"radius":radius,"origin":origin,"a":a/al,"b":b/bl,
			"normal":normal,"length_a":al,"length_b":bl})
	return faces


static func _face_rect(face: Dictionary) -> Rect2i:
	var c: Vector3 = face.centre
	var radius: float = face.radius
	return Rect2i(Vector2i(floori((c.x-radius)/BUCKET),floori((c.y-radius)/BUCKET)),
		Vector2i(floori((c.x+radius)/BUCKET),floori((c.y+radius)/BUCKET))-
		Vector2i(floori((c.x-radius)/BUCKET),floori((c.y-radius)/BUCKET))+Vector2i.ONE)


##  (ground baseline) / 561150 (zero baseline, winning normal).
## Project onto the eligible authored rectangle, including its native.5m
## edge padding and separate centre/radius gate. Newer planes win equal heights.
func plane_at(p: Vector2,ground := 0.0) -> Dictionary:
	return plane_in(_face_buckets, p, ground)


func ground_height(p: Vector2, ground: float) -> float:
	return ground_in(_face_buckets, p, ground)


## Most unit/particle samples have no floor nearby. Avoid allocating a
## plane result for every particle on ordinary terrain.
static func ground_in(buckets: Dictionary, p: Vector2, ground: float) -> float:
	if buckets.is_empty() or not buckets.has(Vector2i(floori(p.x/BUCKET),floori(p.y/BUCKET))):
		return ground
	return float(plane_in(buckets,p,ground).height)


## Immutable until the next floor mutation; worker effects must not read
## the live buckets while SetCP / lever morphs replace their entries.
func floor_snapshot() -> Dictionary:
	if _face_snapshot_rev != floor_rev:
		_face_snapshot = _face_buckets.duplicate(true)
		_face_snapshot_rev = floor_rev
	return _face_snapshot


static func plane_in(buckets: Dictionary, p: Vector2, ground := 0.0) -> Dictionary:
	var height := ground
	var normal := Vector3(0,0,1)
	var candidates: Array = buckets.get(Vector2i(floori(p.x/BUCKET),floori(p.y/BUCKET)),[])
	for i in range(candidates.size()-1,-1,-1):
		var face: Dictionary = candidates[i][1]
		var centre: Vector3 = face.centre
		if (p-Vector2(centre.x,centre.y)).length_squared() > float(face.radius)*float(face.radius):
			continue
		var origin: Vector3 = face.origin
		var n: Vector3 = face.normal
		var d := Vector3(p.x-origin.x,p.y-origin.y,0)
		d.z = -(float(n.x)*d.x+float(n.y)*d.y)/n.z
		var a: Vector3 = face.a
		var b: Vector3 = face.b
		var ax: float = PackedFloat32Array([float(a.x)*d.x+float(a.y)*d.y+float(a.z)*d.z])[0]
		var bx: float = PackedFloat32Array([float(b.x)*d.x+float(b.y)*d.y+float(b.z)*d.z])[0]
		if ax < -.5 or bx < -.5 or ax > float(face.length_a)+.5 or bx > float(face.length_b)+.5:
			continue
		var h: float = PackedFloat32Array([float(a.z)*ax+float(b.z)*bx+origin.z])[0]
		if h > height:
			height = h
			normal = n
	return {"height":height,"normal":normal}


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
				# Original stores the quantized sample as float32 before nearest-even FISTP.
				var h := clampi(round_even(PackedFloat32Array([(pa.z + db.z * ib) * _alt])[0]), 0, SPAN_MAX)
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
	if not fp.get("faces", []).is_empty():
		for mesh: MeshInstance3D in o.find_children("*", "MeshInstance3D", true, false):
			mesh.layers |= EITerrain.DECAL_LAYER
	_put(key, fp)
	return key


func _put(key: int, fp: Dictionary) -> void:
	if not fp.get("faces", []).is_empty():
		floor_rev += 1
	for face: Dictionary in fp.get("faces",[]):
		var r := _face_rect(face)
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):
				var bucket := Vector2i(x,y)
				if not _face_buckets.has(bucket): _face_buckets[bucket] = []
				_face_buckets[bucket].append([key,face])
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
	if not fp.get("faces", []).is_empty():
		floor_rev += 1
	for face: Dictionary in fp.get("faces",[]):
		var r := _face_rect(face)
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):
				var bucket := Vector2i(x,y)
				var entries: Array = _face_buckets.get(bucket,[])
				for i in range(entries.size()-1,-1,-1):
					if int(entries[i][0]) == key: entries.remove_at(i)
				if entries.is_empty(): _face_buckets.erase(bucket)
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
		_hq[i] = _hq0[i]
		_depth[i] = _depth0[i]
		_cost[i] = _cost0[i]
		return
	var top := 0
	for e: Array in fl:
		top = maxi(top, e[0])
	_h[i] = maxf(_h0[i], top / _alt)
	_hq[i] = roundi(_h[i] * _alt)
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


## Object, from the same target-state part boxes as its footprint.
func object_radius(nid: int) -> float:
	return float(_fp[nid].radius) if _fp.has(nid) else NAN


## Native use approach: lift only the target object's stamp
## search to its origin with flat costs, then put the stamp back. Keep the
## motion's cell factors while it is lifted too. Ordinary movement still
## treats the object as an obstacle, including on a failed approach search.
func find_object_path(u: GameUnit, to: Vector2, nid: int, limit := 1e6,
		moving_at := Vector2.INF) -> Dictionary:
	var fp: Dictionary = _fp.get(nid, {})
	var region := _fp_rect(fp) if not fp.is_empty() else Rect2i()
	if not fp.is_empty():
		_take(nid, fp)
		_update_region(region)
	var found := find_path(u.pos, to, [u], [], 0.0, u.move_class(), true,
		NAN, limit, 0.0, u.controller < 0, moving_at)
	var result := {"path": found, "blocks": last_block_count,
		"motion": motion_record(u.pos, found, u.move_class(), u.has_meta("flying"))}
	if not fp.is_empty():
		_put(nid, fp)
		_update_region(region)
	return result


## A lever's new state (: the figure's morph axis set to the
## target, the part boxes worked out again and the object placed anew).
func set_object_t(nid: int, t: float) -> void:
	var o: Node3D = _fp_nodes.get(nid)
	if o == null or not is_instance_valid(o):
		return
	var old: Dictionary = _fp[nid]
	var p: Vector3 = o.get_meta("ei", {}).get("position", Vector3.ZERO)
	var radius := float(old.get("radius", 0.0)) + 0.5
	var near: Array = []
	for u: GameUnit in units_all_around(Vector2(p.x, p.y), radius):
		if u.pos.distance_squared_to(Vector2(p.x, p.y)) < radius * radius:
			near.append(u)
	var fp := _footprint(o, t)
	if fp.hash() == old.hash():
		return
	for u: GameUnit in near:
		if u._occ_cell.x >= 0:
			_stamp(u._occ_cell, u._occ_r, -1)
			u._occ_cell = Vector2i(-1, -1)
			u._trk_key = -1
	_take(nid, old)
	_fp[nid] = fp
	_put(nid, fp)
	var r := _fp_rect(old)
	var r2 := _fp_rect(fp)
	var region := r2 if r.size == Vector2i.ZERO else (r if r2.size == Vector2i.ZERO else r.merge(r2))
	_update_region(region)
	_relocate(near)


##  lifts all nearby unit stamps before the target-state map is
## made. Each unit is then tested / placed and restored in the query order;
## later placements see earlier ones, while still-unprocessed units stay lifted.
func _relocate(near: Array) -> void:
	var lifted := near.duplicate()
	for u: GameUnit in near:
		if not cell_or_neighbour_open(u.pos, u.move_class()):
			var placement := place_unit(u.pos, u.pos, u.move_class(), u.body_radius(), lifted)
			u.pos = placement.point
			u.orders.clear()
			u.order = {}
			u.path = PackedVector2Array()
			u.target = null
			u._motion = null
			u._kept = {}
			u._move_speed = 0.0
			u._set_action("idle")
		lifted.erase(u)
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
	map_rev += 1
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
	var bw := (size.x + BLOCK - 1) / BLOCK
	for L: Layer in _layers.values():
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var i := y * size.x + x
				var wv := _cell_weight(i, L.cls) if _special[i] else \
					(0.0 if _dry_raw[i] else (1.0 if L.cls == 0 else _dry_weight[i]))
				L.raw[i] = 1 if wv <= 0.0 else 0
				if wv > 0.0:
					L.astar.set_point_weight_scale(Vector2i(x, y), wv)
					L.cost[i] = roundi(wv * 1024.0)
					var bi := (y / BLOCK) * bw + x / BLOCK
					L.bmin[bi] = mini(L.bmin[bi], L.cost[i])
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
	return Vector2i(round_even(p.x/CELL-0.5),round_even(p.y/CELL-0.5))

## ROUND in the original x87 nearest mode. Cell-boundary ties alternate
## between adjacent cells, unlike floor or Godot's away-from-zero roundi.
static func round_even(v: float) -> int:
	var lo := floori(v)
	var part := v-float(lo)
	return lo+1 if part > 0.5 or part == 0.5 and (lo&1) != 0 else lo


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
	var z := _hq[c.y * size.x + c.x]
	var slope: PackedInt32Array = _slope_tab[0 if cls == 0 else 1]
	for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var q := c + o
		if _in(q):
			var i := q.y * size.x + q.x
			var dh := _hq[i] - z + SLOPE_MID
			if L.land[i] == 0 and dh >= 0 and dh <= SLOPE_MID * 2 and slope[dh] > 0:
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
	var dh := _hq[i] - _hq[c.y * size.x + c.x]
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


## The slope tables of the path search as arrays by dh + SLOPE_MID: [0] for
## class 0, [1] for the other classes; the smallest entry
## each (the steepest allowed descent) bounds the search's estimate.
const SLOPE_MID := 1023
var _slope_tab: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _slope_min := PackedInt32Array([1024, 1024])


func _build_slope_tabs() -> void:
	for k in 2:
		var t := PackedInt32Array()
		t.resize(SLOPE_MID * 2 + 1)
		var lo := 1024
		for i in t.size():
			var v := _slope_div_calc(i - SLOPE_MID, k)
			t[i] = v
			if v > 0:
				lo = mini(lo, v)
		_slope_tab[k] = t
		_slope_min[k] = lo
		# The search's estimate (remake): every allowed step of length s (1 or
		# 1.414 cells) and height step dh has slope factor f with
		# s f >= s (1 - mu) + lam dh, so a path's cost from height H to the
		# goal's Hg over octile distance o is at least c_min ((1 - mu) o +
		# lam (Hg - H)); lam is picked for the smallest mu.
		var best_mu := 1.0
		var best_lam := 0.0
		for li in 41:
			var lam := li * 0.005
			var mu := 0.0
			for i in t.size():
				if t[i] <= 0:
					continue
				var f := t[i] / 1024.0
				var dh := float(i - SLOPE_MID)
				for sl: float in [1.0, STEP_DIAG / 1024.0]:
					mu = maxf(mu, -(sl * (f - 1.0) - lam * dh) / sl)
			if mu < best_mu:
				best_mu = mu
				best_lam = lam
		_bound_mu[k] = best_mu
		_bound_lam[k] = best_lam


var _bound_mu := PackedFloat64Array([0.0, 0.0])
var _bound_lam := PackedFloat64Array([0.0, 0.0])
## Block size of Layer.bmin (cells).
const BLOCK := 8


## A lower bound of the step cost table entries of the layer's cells in `r`
## (the smallest Layer.bmin of the blocks it touches).
func _block_cmin(L: Layer, r: Rect2i) -> int:
	var bw := (size.x + BLOCK - 1) / BLOCK
	var best := 0x7fffffff
	for by in range(r.position.y / BLOCK, (r.end.y - 1) / BLOCK + 1):
		for bx in range(r.position.x / BLOCK, (r.end.x - 1) / BLOCK + 1):
			best = mini(best, L.bmin[by * bw + bx])
	return best


##  without its stamp test: the cost of the step from cell `i` to
## its neighbour `j` (flat indices) for a layer, -1 when the step is refused:
## ((slope[dh] * cost[value]) >> 10) * step >> 10, dh = the height step in
##  units (to - ), cost the step cost table (FLAT_COST with
## `flat`), step 0x400 or 0x5a8.
func _step_cost(L: Layer, i: int, j: int, flat: bool) -> int:
	if L.land[j] != 0:
		return -1
	var c := FLAT_COST if flat else _cell_cost(L, j)
	if c < 0:
		return -1
	var dh := _hq[j] - _hq[i]
	if dh < -SLOPE_MID or dh > SLOPE_MID:
		return -1
	var d: int = _slope_tab[0 if L.cls == 0 else 1][dh + SLOPE_MID]
	if d < 0:
		return -1
	var dx := absi(j % size.x - i % size.x)
	var dy := absi(j / size.x - i / size.x)
	return ((d * c >> 10) * (STEP_DIAG if dx != 0 and dy != 0 else STEP_STRAIGHT)) >> 10


## The step cost table entry of cell `j` for the layer
## -1 when closed: the layer's A* weight x 1024 (the weights are exactly
## STEP_COST[value] / 1024).
func _cell_cost(L: Layer, j: int) -> int:
	if L.land[j] != 0:
		return -1
	return L.cost[j]


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


## The two native unit-stamp maps for physical placement / stepping. The
## path search's temporary moving-window copy is deliberately separate.
func _placement_layers(r: Rect2i, lifted: Array = []) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	for k in 2:
		out[k].resize(r.size.x * r.size.y)
	var mid := center(r.position) + Vector2(r.size - Vector2i.ONE) * CELL * 0.5
	var reach := Vector2(r.size).length() * CELL * 0.5 + 6.0
	for u: GameUnit in units_around(mid, reach, false):
		if u.dead or u in lifted:
			continue
		var c := cell(u.pos)
		var key := stamp_key(u.body_radius())
		if key == 0:
			continue
		var index := int(u._moving)
		for y in range(maxi(r.position.y, c.y - 8), mini(r.end.y, c.y + 8)):
			for x in range(maxi(r.position.x, c.x - 8), mini(r.end.x, c.x + 8)):
				var i := (y - r.position.y) * r.size.x + x - r.position.x
				out[index][i] = maxi(out[index][i], stamp_value(key, x - c.x, y - c.y))
	return out


## ordered441 offsets within5m, native representative-area
## identity, standing unsigned / moving signed stamp eligibility. Failure
## preserves the requested point, as the engine's in/out point argument does.
func place_unit(start: Vector2, goal: Vector2, cls: int, radius: float, lifted: Array = []) -> Dictionary:
	var source := cell(start)
	if source.x <= 0 or source.y <= 0 or source.x >= size.x - 1 or source.y >= size.y - 1:
		return {"ok": false, "point": goal}
	var target := cell(goal)
	var movement_layer := layer(cls)
	var graph = native_graph(movement_layer)
	var wanted: int = graph.component_of(source)
	var rect := Rect2i(target - Vector2i(10, 10), Vector2i(21, 21))
	var stamps := _placement_layers(rect, lifted)
	var threshold := stamp_threshold(radius) & 255
	for k in range(0, BlockGraph.NEAR_OFFSETS.size(), 2):
		var q := target + Vector2i(BlockGraph.NEAR_OFFSETS[k], BlockGraph.NEAR_OFFSETS[k + 1])
		if not _in(q) or movement_layer.land[q.y * size.x + q.x] != 0:
			continue
		var i := (q.y - rect.position.y) * rect.size.x + q.x - rect.position.x
		if stamps[0][i] > threshold or signed_stamp(stamps[1][i]) > threshold:
			continue
		if wanted != 0 and graph.component_of(q) != wanted:
			continue
		return {"ok": true, "point": goal if k == 0 else center(q)}
	return {"ok": false, "point": goal}


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


## The original cell path in EI xy, with its actual final point. GameUnit
## builds the native spline from these cells; diagnostics may opt into LOS.
## The stamps of the `ignore` units are lifted for the search (the mover and,
## for an attack, its target: take them out with
## ). `avoid` units are stamped once more, as if standing, with
## their radius + `extra` (: a faster mover going round a slower
## one; `extra` = the mover's radius over R_REF, as the grid is stamped for R_REF).
## A start cell closed by unit stamps is left the original's way (: a
## stamped cell is entered only when its value is below that of the cell the
## search comes from): `_stamp_descent` leads out first, the search goes on from
## there; no way out is no path.
## The exact search (_cost_search) takes the mover (`ignore`'s first unit) for
## its stamp threshold and costs the steps with the step cost table, or with
## the flat one when `flat` (unit, see FLAT_COST).
func find_path(a: Vector2, b: Vector2, ignore: Array = [], avoid: Array = [], extra := 0.0,
		cls := WALK_CLASS, flat := false, facing := NAN, limit := 1e6,
		min_radius := 0.0, retry := false,moving_at := Vector2.INF) -> PackedVector2Array:
	var started := Time.get_ticks_usec() if profile_paths else 0
	var L := layer(cls)
	var mover: GameUnit = ignore[0] if not ignore.is_empty() and ignore[0] is GameUnit else null
	_ctx_thr = stamp_threshold(mover.body_radius() if mover else R_REF)
	_ctx_lifted = ignore
	_ctx_avoid = avoid
	_ctx_flat = flat
	_ctx_facing = mover.facing if mover else facing
	_ctx_limit = limit
	_ctx_min_radius = min_radius
	_ctx_retry = retry
	_ctx_moving_rect = Rect2i()
	if moving_at != Vector2.INF:
		#  copies the secondary grid into a temporary primary
		# stamp: 14x14 cells around the attempted position, truncated xy.
		var c := Vector2i(int(moving_at.x*2.0),int(moving_at.y*2.0))
		var lo := (c-Vector2i(7,7)).max(Vector2i.ZERO)
		var hi := (c+Vector2i(7,7)).min(size-Vector2i.ONE)
		_ctx_moving_rect = Rect2i(lo,(hi-lo).max(Vector2i.ZERO))
	last_block_count = 0
	last_flat = flat
	last_cls = L.cls
	last_cells = PackedInt32Array()
	last_turn_cost = -1
	last_facing = NAN
	_memo_end_written = false
	var memo_key: Array = []
	_memo_capture = false
	_memo_windows.clear()
	_memo_capture_ints = 0
	_memo_complete = true
	if exact_search and path_memo:
		if _path_memo_rev != map_rev:
			_path_memo.clear()
			_path_memo_order.clear()
			_path_memo_ints = 0
			_path_memo_rev = map_rev
		memo_key = [a,b,cls,flat,"none" if is_nan(_ctx_facing) else _ctx_facing,
			_ctx_thr,mover.body_radius() if mover else R_REF,extra,min_radius,retry,_ctx_moving_rect]
		var saved: Dictionary = _path_memo.get(memo_key,{})
		# A successful query never took the carrier's maximum-block rejection.
		# Raising that limit cannot change any of its branches or native ties.
		# Failure, smaller limits and limits outside the native integer range
		# still require their own original search.
		var compatible_limit: bool = not saved.is_empty() and (limit == saved.limit \
			or not (saved.path as PackedVector2Array).is_empty() and limit >= float(saved.limit) \
			and limit <= 0x1fffffff and float(saved.limit) >= -0x1fffffff)
		if compatible_limit and _memo_valid(saved):
			last_path = (saved.path as PackedVector2Array).duplicate()
			last_cells = (saved.cells as PackedInt32Array).duplicate()
			last_block_count = int(saved.blocks)
			last_turn_cost = int(saved.turn_cost)
			last_facing = float(saved.facing)
			if saved.end_written: last_end = saved.end
			_ctx_lifted = []
			_ctx_avoid = []
			_ctx_moving_rect = Rect2i()
			_path_profile(started,Time.get_ticks_usec(),a,b,cls,limit,mover,last_path,true)
			return last_path.duplicate()
		_memo_capture = true
	var lifted := []
	for u: GameUnit in ignore:
		if u and u._occ_cell.x >= 0:
			lifted.append(u)
	for u: GameUnit in lifted:
		_stamp(u._occ_cell, u._occ_r, -1)
	var stamped := []   # [cell, radius] stamped for this search only
	for u: GameUnit in avoid:
		if not u.dead and not u in ignore:
			stamped.append([cell(u.pos), u.body_radius() + extra])
	# A new plan round a blocker is searched with the mover's own
	# threshold round(16 (2 - r)); the grid holds the
	# stamps for R_REF, so the standing units near the start are stamped
	# again with `extra` like the blocker (**approx.**: only there).
	if not stamped.is_empty() and extra > 0.0:
		for u: GameUnit in units_around(a, 8.0, false):
			if u._occ_cell.x >= 0 and not u in lifted and not u in avoid:
				stamped.append([u._occ_cell, u._occ_r + extra])
	for e: Array in stamped:
		_stamp(e[0], e[1], 1)
	var sc := cell(a)
	var out := PackedVector2Array()
	if not exact_search and _in(sc) and L.land[sc.y * size.x + sc.x] == 0 and _occ[sc.y * size.x + sc.x] != 0:
		var lead := _stamp_descent(L, a, b, lifted, stamped)
		if not lead.is_empty():
			var rest := _find_path(L, lead[-1], b)
			if not rest.is_empty():
				out = lead
				out.append_array(rest)
				var lc := PackedInt32Array([sc.y * size.x + sc.x])
				for p in lead.slice(0, lead.size() - 1):
					var c := cell(p)
					lc.append(c.y * size.x + c.x)
				lc.append_array(last_cells)
				last_cells = lc
	else:
		out = _find_path(L, a, b)
	var searched := Time.get_ticks_usec() if profile_paths else 0
	# The original improves the complete cell route before making its spline.
	# A caller without a unit may supply `facing`; without either, the cell
	# search remains available on its own (tools and navigation diagnostics).
	if not out.is_empty() and not is_nan(_ctx_facing):
		var improved := TurnPass.refine(self, L, last_cells, _ctx_facing, last_end, flat)
		last_turn_cost = improved.cost
		last_facing = _ctx_facing
		if last_turn_cost < TurnPass.LIMIT:
			last_cells = improved.cells
			_search_pre = PackedInt32Array()
			var pts := PackedVector2Array()
			for i in last_cells:
				pts.append(center(Vector2i(i % size.x, i / size.x)))
			pts[-1] = last_end
			out = pts if exact_search else _smooth(L, a, pts, last_cells)
		else:
			out = PackedVector2Array()
	# The smoothing samples its lines every 25 cm: the first leg from the unit's
	# spot may graze the corner of a closed cell, which the movement tick then
	# refuses. Such a leg starts at the centre of the unit's cell.
	if not exact_search and not out.is_empty() and _in(sc) and not _leg_clear(L, a, out[0]):
		out.insert(0, center(sc))
	for e: Array in stamped:
		_stamp(e[0], e[1], -1)
	for u: GameUnit in lifted:
		_stamp(u._occ_cell, u._occ_r, 1)
	_ctx_lifted = []
	_ctx_avoid = []
	_ctx_moving_rect = Rect2i()
	last_path = out
	if out.is_empty():
		last_cells = PackedInt32Array()
	_memo_capture = false
	if not memo_key.is_empty() and _memo_complete: _memo_store(memo_key,out)
	_path_profile(started,searched,a,b,cls,limit,mover,out,false)
	return out


func _path_profile(started: int,searched: int,a: Vector2,b: Vector2,cls: int,
		limit: float,mover: GameUnit,out: PackedVector2Array,hit: bool) -> void:
	if not profile_paths: return
	var done := Time.get_ticks_usec()
	profile_last = {"search_us":searched-started,"turn_us":done-searched,"memo":hit}
	profile_totals.queries = int(profile_totals.get("queries",0))+1
	profile_totals.search_us = int(profile_totals.get("search_us",0))+searched-started
	profile_totals.turn_us = int(profile_totals.get("turn_us",0))+done-searched
	profile_totals.max_us = maxi(int(profile_totals.get("max_us",0)),done-started)
	profile_totals.failed = int(profile_totals.get("failed",0))+int(out.is_empty())
	profile_totals.memo_hits = int(profile_totals.get("memo_hits",0))+int(hit)
	if done-started > 20000:
		profile_slow.append({"us":done-started,"search_us":searched-started,"turn_us":done-searched,
			"from":a,"to":b,"cls":cls,"limit":limit,"uid":mover.uid if mover else 0,
			"cells":last_cells.size(),"blocks":last_block_count,"memo":hit})
		if profile_slow.size() > 32: profile_slow.pop_front()


func _memo_valid(saved: Dictionary) -> bool:
	for r: Rect2i in saved.windows:
		if _paint_stamp_window(r) != saved.windows[r]: return false
	return true


func _memo_store(key: Array,out: PackedVector2Array) -> void:
	var count := last_cells.size()+out.size()*2
	for values: PackedInt32Array in _memo_windows.values(): count += values.size()
	if _path_memo.has(key): _memo_erase(key)
	if count > PATH_MEMO_INTS:
		_memo_windows.clear()
		return
	while not _path_memo_order.is_empty() and (_path_memo_order.size() >= PATH_MEMO_MAX 			or _path_memo_ints+count > PATH_MEMO_INTS):
		_memo_erase(_path_memo_order[0])
	# Copies keep this entry independent of the public last_* arrays and the
	# caller's returned path. Packed arrays also copy each saved window.
	var windows := {}
	for r: Rect2i in _memo_windows: windows[r] = (_memo_windows[r] as PackedInt32Array).duplicate()
	var saved_key := key.duplicate(true)
	_path_memo[saved_key] = {"path":out.duplicate(),"cells":last_cells.duplicate(),
		"blocks":last_block_count,"turn_cost":last_turn_cost,"facing":last_facing,
		"end":last_end,"end_written":_memo_end_written,"windows":windows,"ints":count,"limit":_ctx_limit}
	_path_memo_order.append(saved_key)
	_path_memo_ints += count
	_memo_windows.clear()


func _memo_erase(key: Array) -> void:
	_path_memo_ints -= int(_path_memo[key].ints)
	_path_memo.erase(key)
	_path_memo_order.erase(key)


## No closed cell (the A* grid) on the straight line from `a` to `b` but their own.
func _leg_clear(L: Layer, a: Vector2, b: Vector2) -> bool:
	var ca := cell(a)
	var cb := cell(b)
	var steps := int(a.distance_to(b) * 64.0) + 1
	for i in range(1, steps):
		var c := cell(a.lerp(b, float(i) / steps))
		if c != ca and c != cb and (not _in(c) or L.astar.is_point_solid(c)):
			return false
	return true


## The gamepad stick's straight walk (remake, no original counterpart: a move
## order with "line", PadField._direct_move): whether unit `u` may walk the
## straight line from where it stands to `b` as it is, without a path
## search. Every cell the line crosses (sampled finer than a frame's step,
## as _leg_clear) is open on its movement class's A* grid — walls, cliffs,
## deep water and the stamps of standing units are closed there, its own
## stamp is lifted as find_path lifts it — and every step between them is
## one the search itself may take (_line_cost: no refused slope step).
## The search's smoothing keeps a staircase of cell centres off the 45°
## lines (SMOOTH_SLACK); a stick re-aimed five times a second walked each
## new staircase from its first step and wiggled from side to side.
func direct_line(u: GameUnit, b: Vector2) -> bool:
	var L := layer(u.move_class())
	var a := u.pos
	var ca := cell(a)
	var cb := cell(b)
	if not _in(ca) or not _in(cb):
		return false
	var lift := u._occ_cell.x >= 0
	if lift:
		_stamp(u._occ_cell, u._occ_r, -1)
	var ok := not L.astar.is_point_solid(ca) and not L.astar.is_point_solid(cb) and _leg_clear(L, a, b) \
		and _line_cost(L, a, b, false) >= 0
	if lift:
		_stamp(u._occ_cell, u._occ_r, 1)
	return ok


## A complete native motion record: cell coordinates and
## ushort factor on each outgoing node. The final value is512. Dense paths
## already supply adjacent cells; legacy/manual polylines expand their legs.
func motion_record(from: Vector2, path: PackedVector2Array, cls: int, _flying := false) -> Dictionary:
	var cells: Array[Vector2i] = []
	var values := PackedInt32Array()
	if path.is_empty():
		return {"cells": cells, "values": values}
	var current := cell(from)
	cells.append(current)
	for p in path:
		var goal := cell(p)
		var delta := goal - current
		var length := maxi(absi(delta.x), absi(delta.y))
		for i in range(1, length + 1):
			var c := current + Vector2i(roundi(float(delta.x) * i / length), roundi(float(delta.y) * i / length))
			if c != cells[-1]:
				cells.append(c)
		current = goal
	for i in cells.size() - 1:
		values.append(roundi(step_factor(center(cells[i]), center(cells[i + 1]), cls) * 512.0) & 65535)
	values.append(512)
	return {"cells": cells, "values": values}


## Every cell the straight step from `a` to `b` (ending in cell `q`) crosses
## before `q` is under `thr` or no higher than `v0` (the step test).
func _descent_line_ok(a: Vector2, b: Vector2, q: Vector2i, v0: int, thr: int, val: Callable) -> bool:
	var steps := int(a.distance_to(b) * 64.0) + 1   # ~1.5 cm, finer than a frame's step
	for i in range(1, steps):
		var c := cell(a.lerp(b, float(i) / steps))
		if c == q or c == cell(a):
			continue
		var v: int = val.call(c)
		if v > thr and v > v0:
			return false
	return true


## The way out of the unit stamps over the start cell `sc` (the
## step cost of the path search): a cell whose standing-layer value
## (the stamps max-combined) is over round(16 (2 - R)) is entered
## only from a cell of a higher value, so the search can only go down the
## stamps; the movement tick allows the same steps (: no higher
## than the unit's own cell). Cell centres from the first step to the open cell
## reached at the least cost plus straight distance to `b` (**approx.**: the
## original's single search picks the exit with the whole path), empty when the
## stamps leave no way down.
func _stamp_descent(L: Layer, a: Vector2, b: Vector2, lifted: Array, stamped: Array) -> PackedVector2Array:
	var sc := cell(a)
	var thr := roundi((2.0 - R_REF) * 16.0)
	var st := []   # [cell, k] of every stamp on the grid near the start
	for u: GameUnit in units_around(center(sc), 9.0, false):
		if u._occ_cell.x >= 0 and not u in lifted:
			st.append([u._occ_cell, roundi(u._occ_r * 10.0 + 1.0)])
	for e: Array in stamped:
		st.append([e[0], roundi(float(e[1]) * 10.0 + 1.0)])
	var val := func(c: Vector2i) -> int:
		var v := 0
		for e: Array in st:
			var o: Vector2i = c - e[0]
			v = maxi(v, stamp_value(e[1], o.x, o.y))
		return v
	var cost := {sc: 0.0}
	var prev := {}
	var vals := {sc: val.call(sc)}
	var open := [sc]
	var best := Vector2i(-1, -1)
	var best_f := INF
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var c: Vector2i = open[bi]
		open.remove_at(bi)
		var vc: int = vals[c]
		if c != sc and vc <= thr:
			var f: float = cost[c] * CELL + center(c).distance_to(b)
			if f < best_f:
				best_f = f
				best = c
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := c + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or not _in(q) or absi(q.x - sc.x) > 16 or absi(q.y - sc.y) > 16:
					continue
				if L.land[q.y * size.x + q.x] != 0:
					continue
				if not vals.has(q):
					vals[q] = val.call(q)
				var vq: int = vals[q]
				if vq > thr and vq >= vc:
					continue
				# The first step goes from the unit's spot, not the cell centre: no
				# cell it crosses on the way may rise above the start.
				if c == sc and not _descent_line_ok(a, center(q), q, vc, thr, val):
					continue
				var nc: float = cost[c] + (1.41421356 if dx != 0 and dy != 0 else 1.0)
				if nc < float(cost.get(q, INF)):
					if not cost.has(q):
						open.append(q)
					cost[q] = nc
					prev[q] = c
	var out := PackedVector2Array()
	if best.x < 0:
		return out
	var c := best
	while c != sc:
		out.append(center(c))
		c = prev[c]
	out.reverse()
	return out


func _find_path(L: Layer, a: Vector2, b: Vector2) -> PackedVector2Array:
	if exact_search: return _find_native(L,a,b)
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
	var cells := PackedInt32Array()
	_search_pre = PackedInt32Array()
	var rt := A.get_id_path(start, goal, true)
	if rt.is_empty():
		return PackedVector2Array()
	var ps := PackedVector2Array()
	for c in rt:
		ps.append(center(c))
		cells.append(c.y * size.x + c.x)
	if is_walkable(b, L.cls) and cell(b) == rt[-1]:
		ps[-1] = b
	last_cells = cells
	last_end = ps[-1]
	return _smooth_los(L, a, ps)


func native_graph(L: Layer):
	if _graphs_rev != map_rev:
		_native_graphs.clear()
		_graphs_rev = map_rev
	if not _native_graphs.has(L.cls): _native_graphs[L.cls] = BlockGraph.new(self,L)
	_native_graphs[L.cls].profile = profile_paths
	return _native_graphs[L.cls]

## native relocation, direct bidirectional windows, then the
## static block route and its overlapping dynamic windows.
func _find_native(L: Layer,a: Vector2,b: Vector2) -> PackedVector2Array:
	var start := cell(a)
	if not _in(start): return PackedVector2Array()
	var graph = native_graph(L)
	var adjusted: Dictionary = graph.relocate(a,b,false,_ctx_min_radius)
	if adjusted.is_empty() or (a*2.0).distance_squared_to(adjusted.point) < 0.001: return PackedVector2Array()
	var goal: Vector2i = adjusted.cell
	var result := {}
	if start == goal:
		result = {"cells":PackedInt32Array([start.y*size.x+start.x]),"blocks":[]}
	elif BlockGraph._octile((goal-start).abs()) < DIRECT_CELLS:
		result = graph.direct(start,goal)
	if result.is_empty():
		# Every native carrier starts with5b0af0's source representatives. If
		# there are none, no relocated destination can make its route succeed;
		# avoid a whole goal-component scan after the direct window has failed.
		if graph._topology_seeds(start,false).is_empty(): return PackedVector2Array()
		var proved_route: Array[Vector2i] = graph.connected_route(start,goal)
		if proved_route.is_empty():
			adjusted = graph.relocate(a,b,true,_ctx_min_radius)
			if adjusted.is_empty(): return PackedVector2Array()
			goal = adjusted.cell
		if start == goal:
			result = {"cells":PackedInt32Array([start.y*size.x+start.x]),"blocks":[]}
		else:
			var excluded: Array[Vector2i] = []
			result = graph.carrier(start,goal,round_even(_ctx_limit*2.0-0.5),excluded,_ctx_retry,proved_route)
			if result.is_empty(): return PackedVector2Array()
			if result.partial: adjusted.point = result.end
	last_cells = result.cells
	last_block_count = (result.blocks as Array).size()
	last_end = adjusted.point*CELL
	_memo_end_written = true
	var points := PackedVector2Array()
	for i in last_cells: points.append(center(Vector2i(i%size.x,i/size.x)))
	points[-1] = last_end
	return points


## The A* route the band search follows: `A.get_id_path(start, goal, true)`,
## the route to the goal or, when it cannot be reached, to the reachable cell
## AStarGrid2D settles as nearest it (least estimate to the goal, octile in
## cells, then least route cost). Remake speed: a goal shut in by the units
## standing round it (a target in a crowd) made that search settle every cell
## of the start's region — most of the map, a few hundred ms per attacker. A
## goal whose open cells close round it within POCKET_MAX cells without the
## start is unreachable; the nearest cell is then looked for ring by ring
## outside that pocket, each candidate tested the same way (its own closed
## pocket, another region), and the route searched to it. The cell and the
## route cost found are the native search's; between cells of equal estimate
## and equal cost the choice may differ.
const POCKET_MAX := 256
const POCKET_RINGS := 48
const POCKET_TRIES := 24


func _route(L: Layer, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var A := L.astar
	var pocket := _pocket(A, goal, start)
	if pocket.is_empty():
		return A.get_id_path(start, goal, true)
	var comp := L.comp[start.y * size.x + start.x]
	var shut := pocket   # cells known unreachable from the start
	var pending := []    # [estimate, cell] of untested candidates
	var best_h := INF
	var best: Array[Vector2i] = []
	var best_g := INF
	var tried := 0
	for k in range(1, POCKET_RINGS + 1):
		if float(k) > best_h + 0.0001:
			break   # every cell of ring k on is estimated at k or more
		for dy in range(-k, k + 1):
			var step := 1 if absi(dy) == k else 2 * k
			for dx in range(-k, k + 1, step):
				var q := goal + Vector2i(dx, dy)
				if _in(q) and not A.is_point_solid(q):
					pending.append([_octile(absi(dx), absi(dy)), q])
		pending.sort_custom(func(x, y): return x[0] < y[0])
		# Candidates estimated under k + 1 are complete (the outer rings
		# are estimated at k + 1 or more).
		while not pending.is_empty() and float(pending[0][0]) < float(k + 1):
			var e: Array = pending.pop_front()
			var h: float = e[0]
			if h > best_h + 0.0001:
				pending.clear()
				break
			var q: Vector2i = e[1]
			var qi := q.y * size.x + q.x
			if shut.has(qi) or (comp != 0 and L.comp[qi] != comp):
				continue
			var other := _pocket(A, q, start)
			if not other.is_empty():
				shut.merge(other)
				continue
			tried += 1
			if tried > POCKET_TRIES:
				return A.get_id_path(start, goal, true)
			var r := A.get_id_path(start, q, false)
			if r.is_empty():
				# Shut in by more than POCKET_MAX cells: the native search
				# (which has just settled the start's region) does it.
				return A.get_id_path(start, goal, true)
			var g := 0.0
			for m in range(1, r.size()):
				var dd := (r[m] - r[m - 1]).abs()
				g += (1.41421356 if dd.x != 0 and dd.y != 0 else 1.0) * A.get_point_weight_scale(r[m])
			if best.is_empty() or g < best_g - 0.0001:
				best = r
				best_g = g
				best_h = h
	if best.is_empty():
		return A.get_id_path(start, goal, true)
	return best


## AStarGrid2D's octile estimate over cell offsets (dx, dy >= 0).
static func _octile(dx: int, dy: int) -> float:
	const F := 0.41421356
	return F * dx + dy if dx < dy else F * dy + dx


## The open cells (8-connected over the A* grid, as AStarGrid2D steps) round
## `c` as {flat index: true} when they close within POCKET_MAX cells and do
## not hold `other`; else empty.
func _pocket(A: AStarGrid2D, c: Vector2i, other: Vector2i) -> Dictionary:
	var seen := {c.y * size.x + c.x: true}
	var todo: Array[Vector2i] = [c]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or not _in(q):
					continue
				var qi := q.y * size.x + q.x
				if seen.has(qi) or A.is_point_solid(q):
					continue
				if q == other or seen.size() >= POCKET_MAX:
					return {}
				seen[qi] = true
				todo.append(q)
	return seen


## The exact cost search along the A*
## route `route`: the cells within BAND of a route cell, from its first cell
## to its last.
func _band_search(L: Layer, route: Array[Vector2i]) -> PackedInt32Array:
	const M := BAND
	var lo := route[0]
	var hi := route[0]
	for c in route:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var r := Rect2i(lo - Vector2i(M, M), hi - lo + Vector2i(2 * M + 1, 2 * M + 1)).intersection(Rect2i(Vector2i.ZERO, size))
	# Per row of the window the column spans within M of a route cell
	# (relative to the window, merged: [lo, hi, lo, hi, ...]).
	var x0 := r.position.x
	var y0 := r.position.y
	var h := r.size.y
	var spans: Array[PackedInt32Array] = []
	spans.resize(h)
	for y in h:
		spans[y] = PackedInt32Array()
	for c in route:
		var cl := c.x - M - x0
		var ch := c.x + M - x0
		for y in range(maxi(0, c.y - M - y0), mini(h - 1, c.y + M - y0) + 1):
			var sp := spans[y]
			var k := sp.size()
			if k > 0 and cl <= sp[k - 1] + 1 and ch >= sp[k - 2] - 1:
				sp[k - 2] = mini(sp[k - 2], cl)
				sp[k - 1] = maxi(sp[k - 1], ch)
			else:
				sp.append(cl)
				sp.append(ch)
			spans[y] = sp
	for y in h:
		var sp := spans[y]
		if sp.size() > 2:
			# A row the route comes back to: sort and merge its spans.
			var pr: Array[Vector2i] = []
			for k in range(0, sp.size(), 2):
				pr.append(Vector2i(sp[k], sp[k + 1]))
			pr.sort()
			var m := PackedInt32Array([pr[0].x, pr[0].y])
			for k in range(1, pr.size()):
				if pr[k].x <= m[m.size() - 1] + 1:
					m[m.size() - 1] = maxi(m[m.size() - 1], pr[k].y)
				else:
					m.append(pr[k].x)
					m.append(pr[k].y)
			spans[y] = m
	return _cost_search(L, route[0], route[-1], r, spans)


## Search context set by find_path: the mover's stamp threshold
## round(16 (2 - r)), the units lifted from the stamps
## (the mover, an attack's target), the units stamped once more as standing
## and the cost table (flat:).
var _ctx_thr := roundi((2.0 - R_REF) * 16.0)
var _ctx_lifted: Array = []
var _ctx_avoid: Array = []
var _ctx_flat := false
var _ctx_facing := NAN
var _ctx_limit := 1e6
var _ctx_min_radius := 0.0
var _ctx_retry := false
var _ctx_moving_rect := Rect2i()
var last_block_count := 0
var last_path := PackedVector2Array()
var profile_paths := false
var profile_last := {}
var profile_totals := {}
var profile_slow: Array[Dictionary] = []
## The last path's cells (flat indices, start to end) and goal point, for
## path_cost (runs on the search's cell path).
var last_cells := PackedInt32Array()
var last_end := Vector2.ZERO
var last_flat := false
var last_cls := WALK_CLASS
var last_turn_cost := -1
var last_facing := NAN
var _stamp_k := {}   # k * 1024 + thr -> [dx, dy, value, ...] of stamp_value(k, dx, dy) > thr


## Only the most recent completed query is available to immediate AI
## callers; GameUnit captures this count when it adopts a path.
func path_blocks(p: PackedVector2Array) -> int:
	return last_block_count if p == last_path else -1


## The standing-unit stamps (max-combined as on the AI map's
## byte 8) over window `r`, without the lifted units and with
## the avoided ones; empty when no stamp reaches the window.
func _stamp_window(r: Rect2i) -> PackedInt32Array:
	var out := _paint_stamp_window(r)
	if _memo_capture and not _memo_windows.has(r):
		_memo_capture_ints += out.size()
		if _memo_capture_ints > PATH_MEMO_INTS:
			_memo_windows.clear()
			_memo_capture = false
			_memo_complete = false
		else: _memo_windows[r] = out.duplicate()
	return out


func _paint_stamp_window(r: Rect2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	var mid := (Vector2(r.position) + Vector2(r.size) * 0.5) * CELL
	var rad := Vector2(r.size).length() * CELL * 0.5 + 4.5
	# (Remake speed: the stamps out of reach of the window are dropped before
	# anything else is looked at, and painted straight into the window.)
	var cs: Array[Vector2i] = []
	var rs := PackedFloat64Array()
	var clips: Array[Rect2i] = []
	for u: GameUnit in units_around(mid, rad, false):
		var c := u._occ_cell
		if not _ctx_moving_rect.has_area() or not u._moving:
			if c.x < 0: continue
		else:
			c = cell(u.pos)
		if c.x < 0 or c.x + 8 < r.position.x or c.y + 8 < r.position.y or c.x - 8 >= r.end.x or c.y - 8 >= r.end.y:
			continue
		if not u in _ctx_lifted and not u in _ctx_avoid:
			cs.append(c)
			rs.append(u.body_radius() if u._moving else u._occ_r)
			clips.append(r.intersection(_ctx_moving_rect) if u._moving else r)
	for u: GameUnit in _ctx_avoid:
		if is_instance_valid(u) and not u.dead and not u in _ctx_lifted:
			var c := cell(u.pos)
			if c.x + 8 < r.position.x or c.y + 8 < r.position.y or c.x - 8 >= r.end.x or c.y - 8 >= r.end.y:
				continue
			cs.append(c)
			rs.append(u.body_radius())
			clips.append(r)
	if cs.is_empty():
		return out
	if not _stamp_kernel_checked:
		_stamp_kernel_checked = true
		if not OS.get_cmdline_user_args().has("--ei-script-nav") and ClassDB.class_exists("TerrainSearchKernel"):
			_stamp_kernel = ClassDB.instantiate("TerrainSearchKernel")
	var native_patterns: Array[PackedInt32Array] = []
	if _stamp_kernel == null:
		out.resize(r.size.x * r.size.y)
		out.fill(0)
	var w := r.size.x
	var h := r.size.y
	for n in cs.size():
		var c := cs[n]
		var k := stamp_key(rs[n])
		if k == 0:
			if _stamp_kernel != null: native_patterns.append(PackedInt32Array())
			continue
		# Only the values over the mover's threshold can close a cell (the
		# test is v > thr and v >= the value of the cell stepped from), so
		# the rest stay 0: per (k, thr) the offsets and values over it.
		var key := k * 1024 + _ctx_thr
		var st: PackedInt32Array = _stamp_k.get(key, PackedInt32Array())
		if st.is_empty():
			for dy in range(-8, 8):
				for dx in range(-8, 8):
					var v := stamp_value(k, dx, dy)
					if v > _ctx_thr:
						st.append(dx)
						st.append(dy)
						st.append(v)
			if st.is_empty():
				st.append(0)
			_stamp_k[key] = st
		if _stamp_kernel != null:
			native_patterns.append(st)
			continue
		var cx := c.x - r.position.x
		var cy := c.y - r.position.y
		var inside := cx >= 8 and cy >= 8 and cx + 8 <= w and cy + 8 <= h
		for m in range(0, st.size() - 2, 3):
			var y := cy + st[m + 1]
			var x := cx + st[m]
			if not inside and (x < 0 or y < 0 or x >= w or y >= h):
				continue
			if not clips[n].has_point(r.position + Vector2i(x, y)):
				continue
			var o := y * w + x
			if st[m + 2] > out[o]:
				out[o] = st[m + 2]
	if _stamp_kernel != null: return _stamp_kernel.paint_stamps(r,cs,native_patterns,clips)
	return out


## The search proper (the step cost) from cell `s`
## to `g` over the cells of window `r` (and, when `spans` is given, per window
## row only its column spans): a cell is entered at
## ((slope[dh] * cost[value]) >> 10) * step >> 10 (see _step_cost); a cell whose
## stamp is over the threshold only from a cell of a higher stamp. The original's
## Dijkstra (4 sorted lists by x & 3) is an A* here with a
## consistent estimate that never overrates (see _build_slope_tabs: the
## smallest step cost entry of the window's blocks x the octile distance,
## less the most a slope can take off, plus what the height to the goal
## must add), so the cost found is the same; ties may pick another of the
## equal paths. Cells from
## `s` to `g`, empty when `g` is not reached.
func _cost_search(L: Layer, s: Vector2i, g: Vector2i, r: Rect2i,
		spans: Array[PackedInt32Array] = []) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not r.has_point(s) or not r.has_point(g):
		return out
	# Local grid: the window plus a one-cell frame that is never entered.
	var W := r.size.x + 2
	var H := r.size.y + 2
	var x0 := r.position.x - 1
	var y0 := r.position.y - 1
	var n := W * H
	var sw := size.x
	# done: 1 = settled or not to be entered (frame, outside the band, closed
	# for the class: the static closures of the layer, L.land).
	var done := PackedByteArray()
	var zeros := PackedByteArray()
	zeros.resize(W)
	var ones := PackedByteArray()
	ones.resize(W)
	ones.fill(1)
	done.append_array(ones)
	var land := L.land
	for y in range(1, H - 1):
		var gy := y0 + y
		var row := land.slice(gy * sw + x0 + 1, gy * sw + x0 + W - 1)
		if not spans.is_empty():
			# Outside the band: closed too.
			var sp := spans[y - 1]
			var m := PackedByteArray()
			var at := 0
			for k in range(0, sp.size(), 2):
				var lo := clampi(sp[k], 0, W - 2)
				var hi := clampi(sp[k + 1], -1, W - 3)
				if hi < lo:
					continue
				m.append_array(ones.slice(0, lo - at))
				m.append_array(row.slice(lo, hi + 1))
				at = hi + 1
			m.append_array(ones.slice(0, W - 2 - at))
			row = m
		done.append(1)
		done.append_array(row)
		done.append(1)
	done.append_array(ones)
	var gs := PackedInt32Array()
	gs.resize(n)
	gs.fill(0x7fffffff)
	var par := PackedByteArray()   # direction (1..8) the cell was entered by
	par.resize(n)
	var st := _stamp_window(Rect2i(x0, y0, W, H))
	var stamps := not st.is_empty()
	var thr := _ctx_thr
	var flat := _ctx_flat
	var lc := L.cost
	var hqa := _hq
	var slope: PackedInt32Array = _slope_tab[0 if L.cls == 0 else 1]
	# The estimate (remake, see _build_slope_tabs): 0.995 c_min ((1 - mu) o +
	# lam (Hg - H)), o the octile distance in cells; the 0.995 covers the
	# integer steps' truncation, so it stays a lower bound and consistent.
	var kc := L.cls == 0
	var cmin := FLAT_COST if flat else _block_cmin(L, r)
	var e1 := 0.995 * cmin * (1.0 - _bound_mu[0 if kc else 1])
	var e2 := 0.995 * cmin * _bound_lam[0 if kc else 1]
	var ed := e1 * STEP_DIAG / 1024.0
	var sl := (s.y - y0) * W + s.x - x0
	var gl := (g.y - y0) * W + g.x - x0
	var gx := g.x - x0
	var gy := g.y - y0
	done[sl] = 0
	done[gl] = 0 if land[g.y * sw + g.x] == 0 else 1
	var hg := hqa[g.y * sw + g.x]
	gs[sl] = 0
	# Neighbour offsets in the local grid and on the map, step lengths.
	var dq := PackedInt32Array()
	var dg := PackedInt32Array()
	var ln := PackedInt32Array()
	dq.resize(9)
	dg.resize(9)
	ln.resize(9)
	for k in range(1, 9):
		dq[k] = DIR_Y[k] * W + DIR_X[k]
		dg[k] = DIR_Y[k] * sw + DIR_X[k]
		ln[k] = STEP_DIAG if (k & 1) == 0 else STEP_STRAIGHT
	# The open list: the negated keys in ascending order (the native bsearch /
	# insert keep it sorted), so the smallest key is the last element.
	# key: (g + estimate) << 36 | (0xffff - g >> 11) << 20 | local index.
	var heap := PackedInt64Array()
	heap.append(-sl)
	var found := false
	while not heap.is_empty():
		var top := -heap[heap.size() - 1]
		heap.resize(heap.size() - 1)
		var c := int(top & 0xfffff)
		if done[c]:
			continue
		done[c] = 1
		if c == gl:
			found = true
			break
		var gc := gs[c]
		var cgi := (c / W + y0) * sw + c % W + x0
		var hc := hqa[cgi]
		var vc := st[c] if stamps else 0
		for k in range(1, 9):
			var q := c + dq[k]
			if done[q]:
				continue
			if stamps:
				var vq := st[q]
				if vq > thr and vq >= vc:
					continue
			var gi := cgi + dg[k]
			var h := hqa[gi]
			var dh := h - hc + SLOPE_MID
			if dh < 0 or dh > SLOPE_MID * 2:
				continue
			var d := slope[dh]
			if d < 0:
				continue
			var ng := gc + (((d * (FLAT_COST if flat else lc[gi]) >> 10) * ln[k]) >> 10)
			if ng < gs[q]:
				gs[q] = ng
				par[q] = k
				var ex := absi(gx - q % W)
				var ey := absi(gy - q / W)
				var est := maxi(0, int((maxi(ex, ey) - mini(ex, ey)) * e1 + mini(ex, ey) * ed + (hg - h) * e2))
				# Ties of the estimate go to the cell reached at the larger cost
				# (nearer the goal): fewer cells are settled, the cost is the same.
				var key := (mini(ng + est, 0x7ffffff) << 36) | ((0xffff - mini(0xffff, ng >> 11)) << 20) | q
				heap.insert(heap.bsearch(-key), -key)
	if not found:
		return out
	_search_g = gs[gl]
	_search_pre = PackedInt32Array()
	var c := gl
	while c != sl:
		out.append((c / W + y0) * sw + c % W + x0)
		_search_pre.append(gs[c])
		c -= dq[par[c]]
	out.append(s.y * sw + s.x)
	_search_pre.append(0)
	out.reverse()
	_search_pre.reverse()
	return out


var _search_g := 0   # the cost of the last search's path (its goal's g)
var _search_pre := PackedInt32Array()   # its cost up to each of its cells


##  least cost from its local turn pass (result).
## find_path ran it with the mover's heading while its own stamp was lifted.
func path_cost(facing: float) -> int:
	if last_turn_cost >= 0 and not is_nan(last_facing) \
			and absf(wrapf(facing - last_facing, -PI, PI)) < 0.000001:
		return last_turn_cost
	return cells_cost(last_cells, facing, last_end, last_cls, last_flat)


func cells_cost(cells: PackedInt32Array, facing: float, end: Vector2, cls: int, flat: bool) -> int:
	return TurnPass.refine(self, layer(cls), cells, facing, end, flat).cost


##  direction number (1..8) of a step by (dx, dy).
static func _dir_of(dx: int, dy: int) -> int:
	for k in range(1, 9):
		if DIR_X[k] == dx and DIR_Y[k] == dy:
			return k
	return 0


## Line-of-sight smoothing of the cell path (**approx.**: the original walks a
## spline through the cell centres): from each point the
## farthest later point whose straight line is clear (line_clear) and costs,
## stepped cell by cell with the search's cost (_line_cost), at most
## SMOOTH_SLACK more than the cells it replaces, so the line does not undo a
## way round a slope or swamp the search chose. The farthest point is found by
## doubling the reach, then halving between the last good and first bad one.
const SMOOTH_SLACK := 1.0 / 16.0
## Remake switch for comparisons (tools/nav_cost_test.gd): false = the A*
## route over the cell weights with plain line-of-sight smoothing (the
## remake's earlier search, no slope factor).
static var exact_search := true


func _smooth_los(L: Layer, a: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
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


func _smooth(L: Layer, a: Vector2, pts: PackedVector2Array, cells: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var flat := _ctx_flat
	var pre := _search_pre   # cost of the cell path up to each cell
	if pre.size() != n:
		pre = PackedInt32Array()
		pre.resize(n)
		for m in range(1, n):
			pre[m] = pre[m - 1] + maxi(0, _step_cost(L, cells[m - 1], cells[m], flat))
	var from := a
	var fi := 0   # the cell index `from` stands for
	var i := 0
	while i < n:
		var good := i
		var bad := n
		var step := 1
		while good < n - 1:
			var j := mini(good + step, n - 1)
			if _shortcut_ok(L, from, pts[j], pre[j] - pre[fi], flat):
				good = j
				step *= 2
			else:
				bad = j
				break
		while bad - good > 1:
			var mid := (good + bad) / 2
			if _shortcut_ok(L, from, pts[mid], pre[mid] - pre[fi], flat):
				good = mid
			else:
				bad = mid
		out.append(pts[good])
		from = pts[good]
		fi = good
		i = good + 1
	return out


func _shortcut_ok(L: Layer, a: Vector2, b: Vector2, along: int, flat: bool) -> bool:
	var lc := _line_cost(L, a, b, flat)
	return lc >= 0 and float(lc) <= float(along) * (1.0 + SMOOTH_SLACK)


## The cost of walking the straight line from `a` to `b` (sampled every 25 cm,
## like line_clear) cell by cell with _step_cost; -1 when a cell on it is
## closed on the A* grid or a step is refused.
func _line_cost(L: Layer, a: Vector2, b: Vector2, flat: bool) -> int:
	var A := L.astar
	var steps := int(a.distance_to(b) * 4.0) + 1
	var px := floori(a.x / CELL)
	var py := floori(a.y / CELL)
	var sx := size.x
	if px < 0 or py < 0 or px >= sx or py >= size.y:
		return -1
	var lc := L.cost
	var hqa := _hq
	var land := L.land
	var slope: PackedInt32Array = _slope_tab[0 if L.cls == 0 else 1]
	var total := 0
	for s in range(1, steps + 1):
		var p := a.lerp(b, float(s) / steps)
		var cx := floori(p.x / CELL)
		var cy := floori(p.y / CELL)
		if cx == px and cy == py:
			continue
		if cx < 0 or cy < 0 or cx >= sx or cy >= size.y or A.is_point_solid(Vector2i(cx, cy)):
			return -1
		var ax := absi(cx - px)
		var ay := absi(cy - py)
		if ax > 1 or ay > 1:
			return -1
		# _step_cost inlined.
		var i := py * sx + px
		var j := cy * sx + cx
		if land[j] != 0:
			return -1
		var dh := hqa[j] - hqa[i]
		if dh < -SLOPE_MID or dh > SLOPE_MID:
			return -1
		var f := slope[dh + SLOPE_MID]
		if f < 0:
			return -1
		total += ((f * (FLAT_COST if flat else lc[j]) >> 10) * (STEP_DIAG if ax != 0 and ay != 0 else STEP_STRAIGHT)) >> 10
		px = cx
		py = cy
	return total


## the ground type (tiledesc index, the low 5 bits of the AI
## map cell, map) under `p`: a floor cell's is 7
## -1 off the map.
func cell_ground(p: Vector2) -> int:
	var c := cell(p)
	if not _in(c):
		return -1
	var i := c.y * size.x + c.x
	if _floors.has(i):
		return FLOOR_GROUND
	if _liq[i] != 255:
		return _liq[i]
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
	var h0 := _hq[i]
	var best := 0
	for j in [i + size.x, i - size.x, i + 1, i - 1]:
		best = maxi(best, absi(_hq[j] - h0))
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


## Script GetZValue (LiA) reads the stored uint16 height
## divided by the terrain altitude scale, rather than the unrounded sample.
func quantized_cell_height(p: Vector2) -> float:
	var c := cell(p)
	return float(_hq[c.y * size.x + c.x]) / _alt if _in(c) else 0.0


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
	var k := stamp_key(r)
	if k == 0: return []
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
## The original builds this 16x16 byte table once for each quantized radius;
## movement only reads it. Keep the identical F32/FISTP arithmetic on a miss.
const STAMP_CACHE_MAX := 64
static var _stamp_bytes := {}
static var _stamp_byte_order: Array[int] = []

static func stamp_value(k: int, dx: int, dy: int) -> int:
	if k == 0 or dx < -8 or dy < -8 or dx > 7 or dy > 7:
		return 0
	var index := (dy + 8) * 16 + dx + 8
	if _stamp_bytes.has(k):
		return (_stamp_bytes[k] as PackedByteArray)[index]
	var table := PackedByteArray()
	table.resize(256)
	var radius: float = PackedFloat32Array([k * 0.1])[0]
	for y in range(-8, 8):
		for x in range(-8, 8):
			var value := round_even(PackedFloat32Array([(radius + 2.0 - sqrt(x * x + y * y) * 0.5) * 16.0])[0])
			table[(y + 8) * 16 + x + 8] = value & 255 if value > 0 else 0
	if _stamp_byte_order.size() >= STAMP_CACHE_MAX:
		_stamp_bytes.erase(_stamp_byte_order.pop_front())
	_stamp_byte_order.append(k)
	_stamp_bytes[k] = table
	return table[index]


##  5b7b70 store the float before nearest-even FISTP.
## Radii at most0.2 have no stamp object (including high flying units).
static func stamp_key(r: float) -> int:
	return 0 if r <= 0.20000000298023224 else round_even(PackedFloat32Array([r*10.0+1.0])[0])


static func stamp_threshold(r: float) -> int:
	return maxi(0,round_even(PackedFloat32Array([(2.0-r)*16.0])[0]))


static func signed_stamp(value: int) -> int:
	return value - 256 if value & 128 else value


## primary bytes are unsigned; moving-layer bytes are signed.
## The threshold is a byte even for unusually large or negative radii.
## Returns0 for a free step,1 standing,2 moving.
static func stamp_step_layer(primary_now: int, primary_next: int, moving_now: int, moving_next: int, radius: float) -> int:
	var threshold := stamp_threshold(radius) & 255
	if primary_next > threshold and primary_next > primary_now:
		return 1
	if signed_stamp(moving_next) > threshold and signed_stamp(moving_next) > signed_stamp(moving_now):
		return 2
	return 0


func _stamp(c: Vector2i, r: float, add: int) -> void:
	for off: Vector2i in _stamp_offsets(r):
		var q := c + off
		if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
			var i := q.y * size.x + q.x
			_occ[i] += add
			if _occ[i] == (1 if add > 0 else 0):
				_refresh(q)


## Keeps a unit's stamp (standing units only: the original puts moving units on a
## separate layer, map, that only the movers' steps test)
## and its spatial hash entry up to date. Called after each unit tick.
func track_unit(u: GameUnit) -> void:
	var standing := not u.dead and not u._moving and size.x > 0
	var r := u.body_radius()
	# Remake speed (every unit, every physics step): nothing to do when the
	# position, state, radius and registration are those of the last call.
	var key := (u._seq << 2) | (2 if u.dead else 0) | (1 if standing else 0)
	if u.pos == u._trk_pos and key == u._trk_key and r == u._trk_r:
		return
	u._trk_pos = u.pos
	u._trk_key = key
	u._trk_r = r
	var c := cell(u.pos) if standing else Vector2i(-1, -1)
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
	var id := u.get_instance_id()
	if u._seq != 0:
		if registered_units.get(id) != u:
			registered_units[id] = u
			registry_rev += 1
	elif registered_units.erase(id):
		registry_rev += 1
	var bk := _bucket_key(u.pos)
	var cbk := _cbucket_key(u.pos)
	var ak := -1 if u._seq == 0 else bk
	# The coarse grids (CBUCKET) serve the wide queries (sight radii).
	var cak := -1 if u._seq == 0 else cbk
	if ak == u._abucket and cak == u._cabucket and (-1 if u.dead else ak) == u._bucket \
			and (-1 if u.dead else cak) == u._cbucket:
		return   # (remake speed: the usual case, a step within the same buckets)
	if cak != u._cabucket:
		if u._cabucket != -1 and _call_buckets.has(u._cabucket):
			(_call_buckets[u._cabucket] as Array).erase(u)
		u._cabucket = cak
		if cak != -1:
			if not _call_buckets.has(cak):
				_call_buckets[cak] = []
			_call_buckets[cak].append(u)
	var ck := -1 if u.dead or u._seq == 0 else cbk
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
	var key := -1 if u.dead or u._seq == 0 else bk
	if key != u._bucket:
		if u._bucket != -1 and _buckets.has(u._bucket):
			(_buckets[u._bucket] as Array).erase(u)
		u._bucket = key
		if key != -1:
			if not _buckets.has(key):
				_buckets[key] = []
			_buckets[key].append(u)


func untrack_unit(u: GameUnit) -> void:
	if registered_units.erase(u.get_instance_id()):
		registry_rev += 1
	u._trk_key = -1
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
func units_all_around(p: Vector2, r: float, ordered := true) -> Array:
	var out := []
	var r2 := r * r
	var bs := BUCKET if r < WIDE else CBUCKET
	var grid: Dictionary = _all_buckets if r < WIDE else _call_buckets
	if not local_bucket_query(p, r):
		for u: GameUnit in registered_units.values():
			if is_instance_valid(u) and u.pos.distance_squared_to(p) <= r2:
				out.append(u)
	else:
		for by in range(floori((p.y - r) / bs), floori((p.y + r) / bs) + 1):
			for bx in range(floori((p.x - r) / bs), floori((p.x + r) / bs) + 1):
				var b = grid.get(bx + by * 4096)
				if b != null:
					for u: GameUnit in b:
						if is_instance_valid(u) and u.pos.distance_squared_to(p) <= r2:
							out.append(u)
	return _ordered_units(out) if ordered else out


## Huge/nonfinite searches should visit the registered units once rather
## than enumerate mostly empty buckets. Exact distance filtering is shared.
func local_bucket_query(p: Vector2, r: float) -> bool:
	if not is_finite(r) or r < 0.0 or not is_finite(p.x) or not is_finite(p.y) \
			or p.x - r < 0.0 or p.y - r < 0.0:
		return false
	var bs := BUCKET if r < WIDE else CBUCKET
	var width := floori((p.x + r) / bs) - floori((p.x - r) / bs) + 1
	var height := floori((p.y + r) / bs) - floori((p.y - r) / bs) + 1
	return width > 0 and height > 0 and width < 4096 and height < 4096 \
		and width * height <= maxi(16, registered_units.size() * 4)


func _ordered_units(list: Array) -> Array:
	return registry_world.order_near_units(list) if is_instance_valid(registry_world) else _in_seq_order(list)


## `list` in GameWorld.units order (GameUnit._seq, unique per unit). Remake
## speed: the keys are sorted natively (a crowd's query sorted with a script
## comparator cost more than the query itself); the order is the same.
static func _in_seq_order(list: Array) -> Array:
	var n := list.size()
	if n < 2:
		return list
	var keys := PackedInt64Array()
	keys.resize(n)
	for i in n:
		keys[i] = ((list[i] as GameUnit)._seq << 20) | i
	keys.sort()
	var out := []
	out.resize(n)
	for i in n:
		out[i] = list[keys[i] & 0xfffff]
	return out


static func _bucket_key(p: Vector2) -> int:
	return floori(p.x / BUCKET) + floori(p.y / BUCKET) * 4096


static func _cbucket_key(p: Vector2) -> int:
	return floori(p.x / CBUCKET) + floori(p.y / CBUCKET) * 4096


## Live units within `r` of `p` (tracked ones only, i.e. on the host).
## `ordered` false: in no particular order, for callers that only combine
## them (stamp maxima, an any-test).
func units_around(p: Vector2, r: float, ordered := true) -> Array:
	var out := []
	var r2 := r * r
	var bs := BUCKET if r < WIDE else CBUCKET
	# The all-unit index plus the current flag also sees direct dead/revive
	# state changes before their ordinary bucket housekeeping completes.
	var grid: Dictionary = _all_buckets if r < WIDE else _call_buckets
	if not local_bucket_query(p, r):
		for u: GameUnit in registered_units.values():
			if is_instance_valid(u) and not u.dead and u.pos.distance_squared_to(p) <= r2:
				out.append(u)
	else:
		for by in range(floori((p.y - r) / bs), floori((p.y + r) / bs) + 1):
			for bx in range(floori((p.x - r) / bs), floori((p.x + r) / bs) + 1):
				var b = grid.get(bx + by * 4096)
				if b != null:
					for u: GameUnit in b:
						if is_instance_valid(u) and not u.dead and u.pos.distance_squared_to(p) <= r2:
							out.append(u)
	# In GameWorld.units order, as a scan of every unit returns them.
	return _ordered_units(out) if ordered else out


## The unit that stops `u` stepping to `q` (
## ), or null. The step is free when the cell of `q` is the unit's
## own cell, or when on each layer (standing / moving units) the stamp value
## there is at most round(16 (2 - R)) or at most the value of the cell the unit
## stands on. Otherwise the blocker is a unit whose centre is closer to `q`
## than the two radii and whose stamp at the mover's cell reaches the
## threshold; none found lets the step through. `standing` reports the layer.
## The spline walker passes its next node's cell (
## ). Re-quantizing the interpolated point can increase a stamp
## before the node's descending step, trapping overlapping party members.
## Point-only callers, including straight stick movement, keep their cell.
func step_blocker(u: GameUnit, q: Vector2, result: Dictionary, next_cell := Vector2i(-1, -1)) -> GameUnit:
	var cq := next_cell if next_cell.x >= 0 else cell(q)
	var c0 := cell(u.pos)
	if cq == c0:
		return null
	var r_me := u.body_radius()
	var near := units_around(q, 10.0)
	var vq := [0, 0]
	var v0 := [0, 0]
	for o: GameUnit in near:
		if o == u or o.dead:
			continue
		var k := stamp_key(o.body_radius())
		var oc := cell(o.pos)
		var layer := 1 if o._moving else 0
		vq[layer] = maxi(vq[layer], stamp_value(k, cq.x - oc.x, cq.y - oc.y))
		v0[layer] = maxi(v0[layer], stamp_value(k, c0.x - oc.x, c0.y - oc.y))
	var layer := stamp_step_layer(v0[0], vq[0], v0[1], vq[1], r_me)
	if layer == 0:
		return null
	var thr := stamp_threshold(r_me) & 255
	for o: GameUnit in near:
		if o == u or o.dead or q.distance_to(o.pos) >= r_me + o.body_radius():
			continue
		var oc := cell(o.pos)
		var offset := c0 - oc
		var key := stamp_key(o.body_radius())
		if key == 0 or offset.x < -8 or offset.y < -8 or offset.x > 7 or offset.y > 7 \
				or signed_stamp(stamp_value(key, offset.x, offset.y)) >= thr:
			result.standing = layer == 1
			return o
	return null
