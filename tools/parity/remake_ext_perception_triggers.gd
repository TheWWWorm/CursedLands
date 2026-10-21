extends RefCounted
## Remake side of cases_ext_perception_triggers.py: production ScriptVM._eval
## (UnitSee / GroupSee / PlayerSee / GroupCross / GroupHas / IsUnitVisible)
## and, for perception_ticks, production UnitAI.player_perceive.

## Layer 1: perception is supplied as exact (watcher, target) pairs. Every
## fixture actor stands within the watchers' sight radius, so the geometric
## prefilter keeps all of them; can_notice_with answers from the pairs.
class SuppliedAI extends UnitAI:
	var pairs := {}
	func can_notice_with(u: GameUnit, o: GameUnit, _k: PackedFloat64Array) -> bool:
		return pairs.has(Vector2i(u.uid, o.uid))

class FlatWorld extends GameWorld:
	var rays := {}
	func ground_at(_x: float, _y: float) -> float:
		return 0.0
	func darkness() -> float:
		return 0.0
	func weather_sight_factor() -> float:
		return 1.0
	## Supplied terrain ray per target, as on the native side (0x5bc3e0).
	func sight_ray(_a: GameUnit, b: GameUnit) -> float:
		return float(rays.get(b.uid, 1.0))

## Layer 2: the spatial broadphase is supplied as every other actor, every
## tick, on both sides; production notice tests and retention run.
class TickAI extends UnitAI:
	var everyone: Array = []
	func _notice_candidates(u: GameUnit, _radius := NAN) -> Array:
		return everyone.filter(func(x): return x != u)

## Supplied sense terms (the native logic-record fields).
class TermUnit extends GameUnit:
	var terms := {}
	func sight_factor() -> float: return float(terms.get("sight_factor", 1.0))
	func vis_factor() -> float: return float(terms.get("visibility", 1.0))
	func detect(which: int) -> float:
		return float(terms.get("life_detect", 1.0)) if which == 2 else float(terms.get("detect", 1.0))
	func sense(which: int) -> float:
		return float(terms.get("life", 0.0)) if which == 2 else float(terms.get("sight", 15.0))
	func sense_bonus(_which: int) -> float: return 0.0

func kinds() -> Array:
	return ["perception_group", "perception_ticks"]

func _units(data: Dictionary, world: GameWorld, trace: Node, term_units: bool) -> Array:
	var units := []
	var party := {}
	for i in data.get("player_units", []): party[int(i)] = true
	for i in data.units.size():
		var row: Dictionary = data.units[i]
		var u: GameUnit = TermUnit.new() if term_units else GameUnit.new()
		if term_units: u.terms = row
		u.world = world
		u.uid = int(row.get("uid", i + 1))
		u.pos = Vector2(float(row.pos[0]), float(row.pos[1]))
		u.max_hp = trace.f32(float(row.max_hp))
		u.hp = trace.f32(float(row.hp))
		u.dead = bool(row.dead)
		u.faction = int(row.get("side", 0))
		u.controller = 0 if party.has(i) else -1
		u.stats = {"sight": 1000.0}
		world.adopt_prepared_unit(u)
		units.append(u)
	return units

func _vm(world: GameWorld, trace: Node) -> Array:
	var vm := ScriptVM.new()
	vm.world = world
	vm.ast = ScriptParser.new()
	var session: Session = trace.quest_session()
	session.state = trace.quest_state({}, {})
	vm.session = session
	return [vm, session]

func _observe(result, units: Array, vm: ScriptVM, trace: Node) -> Dictionary:
	if result is Array:
		var members := []
		for x in result: members.append(units.find(x))
		members.sort()
		return {"count": result.size(), "members": members}
	var value := 0.0 if result == null else float(result)
	return {"truth": vm._truthy(result), "value_bits": trace.bits(value)}

func capture(kind: String, data: Dictionary, trace: Node) -> Array:
	return _group_case(data, trace) if kind == "perception_group" else _ticks_case(data, trace)

func _group_case(data: Dictionary, trace: Node) -> Array:
	var world := FlatWorld.new()
	world.authority = false
	world.zone = {"type": "game"}
	var ai := SuppliedAI.new(world)
	world.ai = ai
	var units := _units(data, world, trace, false)
	for i in units.size():
		var row: Dictionary = data.units[i]
		for j in row.get("noticed", []) + row.get("corpses", []):
			ai.pairs[Vector2i(units[i].uid, units[int(j)].uid)] = true
	var made := _vm(world, trace)
	var vm: ScriptVM = made[0]
	var inst := ScriptVM.Instance.new()
	trace.quest_groups(data.get("groups", {}), inst, units)
	var expression: Array = trace.quest_expression(data.expression, inst, units)
	var states := [_observe(vm._eval(expression, inst), units, vm, trace)]
	made[1].free()
	world.free()
	return states

func _ticks_case(data: Dictionary, trace: Node) -> Array:
	var world := FlatWorld.new()
	world.authority = false
	world.zone = {"type": "game"}
	world.time = 1.0
	var ai := TickAI.new(world)
	world.ai = ai
	var units := _units(data, world, trace, true)
	ai.everyone = units.duplicate()
	var observer: Dictionary = data.observer
	var w: TermUnit = units[int(data.watcher)]
	w.terms = data.units[int(data.watcher)].merged({"sight": observer.sight, "sight_factor": observer.sight_factor,
		"life": observer.life}, true)
	w.stats = {"sight": float(observer.sight)}
	w.facing = float(observer.facing)
	w.race = {"vision_arc": rad_to_deg(float(observer.cone_half) * 2.0)}
	w.proto = {"peripheral_skills": float(observer.peripheral)}
	for side in observer.hostile_sides:
		world.set_relation(w.faction, int(side), 2)
	var made := _vm(world, trace)
	var vm: ScriptVM = made[0]
	var inst := ScriptVM.Instance.new()
	trace.quest_groups(data.get("groups", {}), inst, units)
	var expression: Array = trace.quest_expression(data.trigger, inst, units)
	var states := []
	for tick: Dictionary in data.ticks:
		world.time += GameUnit.TICK
		for key in tick.get("positions", {}):
			var xy: Array = tick.positions[key]
			units[int(key)].pos = Vector2(float(xy[0]), float(xy[1]))
		for i in tick.get("dead", []):
			units[int(i)].dead = true
		world.rays.clear()
		for key in tick.get("rays", {}):
			world.rays[units[int(key)].uid] = float(tick.rays[key])
		if not w.dead:
			ai.player_perceive(w)
		var noticed := []
		for x in (w.get_meta("noticed", {}) as Dictionary).values():
			noticed.append(units.find(x))
		noticed.sort()
		var result = vm._eval(expression, inst)
		var value := 0.0 if result == null else float(result)
		states.append({"count_bits": trace.bits(value), "fired": vm._truthy(result), "noticed": noticed})
	made[1].free()
	world.free()
	return states
