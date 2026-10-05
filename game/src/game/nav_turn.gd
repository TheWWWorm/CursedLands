class_name NavTurn
extends RefCounted
## The local path improvement pass, the original. Its 81 pairs
## move templates retain an edge, connect two adjacent edges
## then relax the new template's edges in their original order.
## Costs include the bend's effective length, not just the
## straight / diagonal length, and 600 per 45 degrees past the first.
## Reconstruct and repeat while the cost decreases, as the original does.

const LIMIT := 0x7fffffff
const DX := [0, 0, -1, -1, -1, 0, 1, 1, 1]
const DY := [0, -1, -1, 0, 1, 1, 1, 0, -1]
static var _templates: Array[Array] = []

class State:
	var g := PackedInt32Array()
	var chain := PackedInt32Array()
	func _init() -> void:
		g.resize(9)
		g.fill(LIMIT)
		chain.resize(9)
		chain.fill(-1)

var _nav: NavGrid
var _layer: NavGrid.Layer
var _flat := false
var _rect := Rect2i()
var _stamps := PackedInt32Array()
var _base := {}   # Vector3i(source x, source y, direction) -> cell cost
var _nodes := PackedInt32Array()
var _parents := PackedInt32Array()


static func heading(facing: float) -> int:
	return [7, 6, 5, 4, 3, 2, 1, 8][posmod(roundi(facing / (PI / 4.0)), 8)]


static func refine(nav: NavGrid, layer: NavGrid.Layer, cells: PackedInt32Array,
		facing: float, end: Vector2, flat: bool) -> Dictionary:
	if cells.size() < 3:
		return {"cells": cells, "cost": 0}
	_build_templates()
	var runner := NavTurn.new()
	runner._nav = nav
	runner._layer = layer
	runner._flat = flat
	var best := LIMIT
	var path := cells
	while true:
		var next := runner._once(path, heading(facing), end)
		if int(next.cost) >= best:
			return {"cells": path, "cost": best}
		# Identical input cells would produce this same deterministic result
		# on the original's next iteration; avoid doing that stable pass twice.
		if next.cells == path:
			return next
		best = next.cost
		path = next.cells
	return {} # unreachable


##  5c3840 / 5c3a00: edges [.x, .y, to.x, to.y].
## Cardinal templates have seven edges, diagonals nine, start / end eight.
static func _moves(dir: int, finish: bool) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	if dir == 0:
		for k in range(1, 9):
			out.append(Vector4i(-DX[k], -DY[k], 0, 0) if finish else Vector4i(0, 0, DX[k], DY[k]))
		return out
	var d := Vector2i(DX[dir], DY[dir])
	var p: Vector2i = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 1), Vector2i(1, 0)][dir]
	if (dir & 1) != 0:
		for e: Array in [[Vector2i.ZERO, d], [-p, d - p], [p, d + p], [-p, d],
				[Vector2i.ZERO, d + p], [p, d], [Vector2i.ZERO, d - p]]:
			out.append(Vector4i(e[0].x, e[0].y, e[1].x, e[1].y))
	else:
		var q := d - p
		for e: Array in [[Vector2i.ZERO, d], [p, d + p], [p - d, p], [q, d + q],
				[q - d, q], [Vector2i.ZERO, p], [Vector2i.ZERO, q], [p, d], [q, d]]:
			out.append(Vector4i(e[0].x, e[0].y, e[1].x, e[1].y))
	return out


##  (including its switch): [source state, target
## state, from.x, from.y, dx, dy, turn steps past the first, length, reverse dir].
static func _transition(a: Vector4i, b: Vector4i, i: int, j: int) -> PackedInt32Array:
	var before := NavGrid._dir_of(a.z - a.x, a.w - a.y)
	var after := NavGrid._dir_of(b.z - b.x, b.w - b.y)
	var k := absi(before - after)
	k = mini(k, 8 - k)
	var len := 0
	match k:
		0: len = 0x5a8 if (before & 1) == 0 else 0x400
		1: len = 0x479
		2: len = 0x648 if (before & 1) == 0 else 0x46e
		3: len = 0x200
	return PackedInt32Array([i, j, b.x, b.y, b.z - b.x, b.w - b.y,
		maxi(0, k - 1), len, posmod(after + 3, 8) + 1])


static func _build_templates() -> void:
	if not _templates.is_empty():
		return
	for prev in 9:
		for next in 9:
			var a := _moves(prev, false)
			var b := _moves(next, true)
			for i in a.size():
				a[i] -= Vector4i(DX[prev], DY[prev], DX[prev], DY[prev])
			var copy := PackedInt32Array()
			var cross := PackedInt32Array()
			var within := PackedInt32Array()
			for i in a.size():
				for j in b.size():
					if a[i] == b[j]:
						copy.append_array(PackedInt32Array([i, j]))
			for i in a.size():
				for j in b.size():
					if a[i].z == b[j].x and a[i].w == b[j].y:
						cross.append_array(_transition(a[i], b[j], i, j))
			for i in b.size():
				for j in b.size():
					if b[i].z == b[j].x and b[i].w == b[j].y:
						within.append_array(_transition(b[i], b[j], i, j))
			_templates.append([copy, cross, within])


func _node(cell: int, parent: int) -> int:
	_nodes.append(cell)
	_parents.append(parent)
	return _nodes.size() - 1


##  cell / slope and stamp tests. A cache holds the cost
## before multiplying by the effective bend length; every template uses it.
func _base_cost(p: Vector2i, dir: int) -> int:
	var key := Vector3i(p.x,p.y,dir)
	if _base.has(key):
		return _base[key]
	if not _nav._in(p):
		_base[key] = -1
		return -1
	var i := p.y * _nav.size.x + p.x
	var q := p + Vector2i(DX[dir], DY[dir])
	var value := -1
	if _nav._in(q):
		var j := q.y * _nav.size.x + q.x
		var dh := _nav._hq[j] - _nav._hq[i] + NavGrid.SLOPE_MID
		if _layer.land[j] == 0 and dh >= 0 and dh <= NavGrid.SLOPE_MID * 2:
			var d: int = _nav._slope_tab[0 if _layer.cls == 0 else 1][dh]
			if d >= 0:
				var clear := true
				if not _stamps.is_empty():
					var s := p - _rect.position
					var t := q - _rect.position
					var v := _stamps[t.y * _rect.size.x + t.x]
					clear = v <= _nav._ctx_thr or v < _stamps[s.y * _rect.size.x + s.x]
				if clear:
					value = (d * (NavGrid.FLAT_COST if _flat else _layer.cost[j])) >> 10
	_base[key] = value
	return value


func _relax(records: PackedInt32Array, from: State, to: State, at: Vector2i) -> void:
	for m in range(0, records.size(), 9):
		var i := records[m]
		var j := records[m + 1]
		if from.g[i] == LIMIT:
			continue
		var p := at + Vector2i(records[m + 2], records[m + 3])
		var dir := ((records[m + 8] + 3)&7) + 1
		var base: int = _base.get(Vector3i(p.x,p.y,dir),-2)
		if base == -2: base = _base_cost(p, dir)
		if base < 0:
			continue
		var cost := from.g[i] + ((base * records[m + 7]) >> 10) + records[m + 6] * NavGrid.TURN_COST
		if cost < to.g[j]:
			to.g[j] = cost
			var q := p + Vector2i(records[m + 4], records[m + 5])
			to.chain[j] = _node(q.y * _nav.size.x + q.x, from.chain[i])


func _advance(from: State, prev: int, next: int, at: Vector2i) -> State:
	var to := State.new()
	var template: Array = _templates[prev * 9 + next]
	var copy: PackedInt32Array = template[0]
	for m in range(0, copy.size(), 2):
		to.g[copy[m + 1]] = from.g[copy[m]]
		to.chain[copy[m + 1]] = from.chain[copy[m]]
	_relax(template[1], from, to, at)
	_relax(template[2], to, to, at)
	return to


func _once(cells: PackedInt32Array, facing: int, end: Vector2) -> Dictionary:
	var w := _nav.size.x
	var start := Vector2i(cells[0] % w, cells[0] / w)
	var rect := Rect2i(start, Vector2i.ONE)
	for i in cells:
		rect = rect.expand(Vector2i(i % w, i / w))
	rect = rect.grow(2).intersection(Rect2i(Vector2i.ZERO, _nav.size))
	if rect != _rect:
		_rect = rect
		_stamps = _nav._stamp_window(_rect)
	# The map and stamp context do not change during refine; costs cached by
	# global cell / direction remain valid when another iteration shifts it.
	_nodes.clear()
	_parents.clear()
	var state := State.new()
	for k in range(1, 9):
		var base := _base_cost(start, k)
		if base < 0:
			continue
		var turn := absi(k - facing)
		turn = mini(turn, 8 - turn)
		state.g[k - 1] = ((base * (NavGrid.STEP_DIAG if (k & 1) == 0 else NavGrid.STEP_STRAIGHT)) >> 10) \
			+ maxi(0, turn - 1) * NavGrid.TURN_COST
		var q := start + Vector2i(DX[k], DY[k])
		state.chain[k - 1] = _node(q.y * w + q.x, -1)
	var prev := 0
	var at := start
	for m in range(1, cells.size()):
		var q := Vector2i(cells[m] % w, cells[m] / w)
		var next := NavGrid._dir_of(q.x - at.x, q.y - at.y)
		state = _advance(state, prev, next, at)
		prev = next
		at = q
	state = _advance(state, prev, 0, at)
	var best := LIMIT
	var chain := -1
	var x := end.x / NavGrid.CELL
	var end_cost := roundi((1.0 - 2.0 * absf(x - roundf(x))) * 2048.0)
	for k in range(1, 9):
		if state.g[k - 1] == LIMIT:
			continue
		var cost := state.g[k - 1] + (end_cost if (k & 1) == 0 else 0)
		if cost < best:
			best = cost
			chain = state.chain[k - 1]
	var out := PackedInt32Array()
	while chain >= 0:
		out.append(_nodes[chain])
		chain = _parents[chain]
	out.append(cells[0])
	out.reverse()
	return {"cells": out, "cost": best}
