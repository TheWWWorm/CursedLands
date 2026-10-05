class_name NavSpline
extends RefCounted
##  builds the motion nodes from a cell path.
## evaluates cubic Hermite segments in cell space at a fractional logic tick.
## Each segment keeps its first node's speed; turns cap that speed before
## evaluation. The first turn takes place without moving the unit.

var controls: Array[Dictionary] = []
var nodes: Array[Dictionary] = []
var start := Vector2.ZERO
var heading := 0.0
var initial_turn := 0.0
var turn_rate := 0.0
var duration := 0.0


## `from` / `to` are metres; `cells` are the original half-metre cell indices.
## `values` are ushort node factors, 512 on flat ordinary ground. `base` is
## cells/tick, and `turn` radians/tick (unit base × RotateSpeedMult = 100).
func build(from: Vector2, to: Vector2, cells: Array[Vector2i], values: PackedInt32Array,
		base: float, turn: float, facing: float) -> void:
	controls.clear()
	nodes.clear()
	start = from / 0.5
	heading = facing
	turn_rate = turn
	initial_turn = 0.0
	duration = 0.0
	if cells.is_empty():
		return
	controls.append({"p": start, "n": 0})
	var previous := 0
	for i in cells.size():
		controls[-1].n = int(controls[-1].n) + 1
		if i + 1 == cells.size():
			break
		var d := cells[i + 1] - cells[i]
		var direction := _direction(d)
		var c := Vector2(cells[i])
		match direction:
			2: _control(c)
			4: _control(c + Vector2(0, 1))
			6: _control(c + Vector2(1, 1))
			8: _control(c + Vector2(1, 0))
		var bend := previous != 0 and _bend(previous, direction) >= 2
		if i + 2 < cells.size():
			bend = bend or _bend(direction, _direction(cells[i + 2] - cells[i + 1])) >= 2
		if bend:
			match direction:
				1: _control(c + Vector2(0.5, 0))
				3: _control(c + Vector2(0, 0.5))
				5: _control(c + Vector2(0.5, 1))
				7: _control(c + Vector2(1, 0.5))
		previous = direction
	_control(to / 0.5)
	var vi := 0
	for i in controls.size() - 1:
		var a: Vector2 = controls[i].p
		var b: Vector2 = controls[i + 1].p
		var tangent := (b - a) / maxf(a.distance_to(b), 0.00001)
		var n := int(controls[i].n)
		var first := -0.5 if i == 0 else 0.0
		var last := 0.5 if i == controls.size() - 2 else 0.0
		if n == 1 and first != 0.0 and last != 0.0:
			var v := float(values[vi] if vi < values.size() else 512) * base / 512.0
			_node(a, tangent, v, cells[mini(vi, cells.size() - 1)])
			_node(b, tangent, v, cells[mini(vi, cells.size() - 1)])
			vi += 1
			continue
		for j in n:
			var f := (float(j) + first + 0.5) / (float(n) + first - last)
			var v := float(values[vi] if vi < values.size() else 512) * base / 512.0
			_node(a.lerp(b, f), tangent, v, cells[mini(vi, cells.size() - 1)])
			vi += 1
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var delta := absf(wrapf((a.d as Vector2).angle() - (b.d as Vector2).angle(), -PI, PI))
		var length := (a.p as Vector2).distance_to(b.p)
		if delta > 0.0 and (turn <= 0.0 or length / maxf(float(a.v), 0.00000001) < delta / turn):
			a.v = length * turn / delta
	if nodes.is_empty():
		return
	var first_direction: Vector2 = nodes[0].d
	var diff := wrapf(first_direction.angle() - facing, -PI, PI)
	if cos(diff) > 0.9:
		nodes[0].d = Vector2.from_angle(facing)
	elif first_direction != Vector2.ZERO:
		initial_turn = diff
	duration = absf(initial_turn) / turn_rate if turn_rate > 0.0 else (INF if initial_turn != 0.0 else 0.0)
	for i in nodes.size() - 1:
		var length := (nodes[i].p as Vector2).distance_to(nodes[i + 1].p)
		duration += length / float(nodes[i].v) if float(nodes[i].v) > 0.0 else INF


func _control(p: Vector2) -> void:
	controls.append({"p": p, "n": 0})


func _node(p: Vector2, d: Vector2, v: float, cell: Vector2i) -> void:
	nodes.append({"p": p, "d": d, "v": v, "cell": cell})


static func _direction(d: Vector2i) -> int:
	const DIRS := [Vector2i.ZERO, Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1)]
	return DIRS.find(d)


static func _bend(a: int, b: int) -> int:
	var n := absi(a - b)
	return mini(n, 8 - n)


## The returned speed is cells/tick; tangent is the spline derivative, whose
## length need not be one. Animation advances at tangent.length() × speed.
func sample(tick: float) -> Dictionary:
	if nodes.is_empty():
		return {"p": start * 0.5, "d": Vector2.from_angle(heading), "v": 0.0,
			"cell": Vector2i.ZERO, "index": 0, "turning": false, "active": false}
	var turning_time := absf(initial_turn) / turn_rate if turn_rate > 0.0 else (INF if initial_turn != 0.0 else 0.0)
	if tick <= turning_time:
		var angle := heading + signf(initial_turn) * maxf(tick, 0.0) * turn_rate
		return {"p": start * 0.5, "d": Vector2.from_angle(angle), "v": 0.0,
			"cell": nodes[0].cell, "index": 0, "turning": true, "active": true}
	var t := tick - turning_time
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var length := (a.p as Vector2).distance_to(b.p)
		var v := float(a.v)
		var interval := length / v if v > 0.0 else INF
		if t <= interval:
			var s := minf(t * v, length)
			var p := Vector2(_cubic(float(a.p.x), float(a.d.x), float(b.p.x), float(b.d.x), length, s),
				_cubic(float(a.p.y), float(a.d.y), float(b.p.y), float(b.d.y), length, s))
			var d := Vector2(_derivative(float(a.p.x), float(a.d.x), float(b.p.x), float(b.d.x), length, s),
				_derivative(float(a.p.y), float(a.d.y), float(b.p.y), float(b.d.y), length, s))
			return {"p": p * 0.5, "d": d, "v": v, "cell": b.cell,
				"index": i + 1, "turning": false, "active": true}
		t -= interval
	var last: Dictionary = nodes[-1]
	return {"p": last.p * 0.5, "d": last.d, "v": 0.0, "cell": last.cell,
		"index": nodes.size() - 1, "turning": false, "active": false}


static func _coefficients(a: float, da: float, b: float, db: float, length: float) -> Vector2:
	if length <= 0.00000001:
		return Vector2.ZERO
	var f := ((b - a) - da * length) / length * 2.0
	var cubic := ((db - da) - f) / (length * length)
	var quadratic := (f - cubic * length * length * 2.0) / length * 0.5
	return Vector2(quadratic, cubic)


static func _cubic(a: float, da: float, b: float, db: float, length: float, s: float) -> float:
	var c := _coefficients(a, da, b, db, length)
	return ((s * c.y + c.x) * s + da) * s + a


static func _derivative(a: float, da: float, b: float, db: float, length: float, s: float) -> float:
	var c := _coefficients(a, da, b, db, length)
	return (2.0 * c.x + s * c.y * 3.0) * s + da
