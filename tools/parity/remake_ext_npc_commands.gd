extends RefCounted
## Remake side of cases_ext_npc_commands.py. Commands run through production
## ScriptVM._run (one S_CALL body per command); queries through ScriptVM._call.
## The remake AI record (GameUnit.mode / mode_data, meta "um", "ai_state",
## "ai_target", UnitAI alarms, GameWorld.diplomacy) is mapped to the native
## motivation-list schema below. See docs/original-parity-npc-commands.md.

const ORDER := {"guard": 0, "patrol": 1, "sentry": 2, "suspection": 3, "aggression": 4,
	"corpse_watcher": 5, "player": 6, "fear": 7, "tamed": 8, "follow": 10}

## quest_units records supplied ground heights on the world.
class NpcWorld extends GameWorld:
	var heights := {}
	func ground_at(x: float, y: float) -> float:
		return float(heights.get(Vector2(x, y), 0.0))

func kinds() -> Array:
	return ["npc_motivation", "npc_diplomacy", "npc_alarm"]

func capture(kind: String, data: Dictionary, trace: Node) -> Array:
	var world := NpcWorld.new()
	var session: Session = trace.quest_session()
	session.state = trace.quest_state({}, data)
	var vm := ScriptVM.new()
	vm.world = world
	vm.session = session
	vm.ast = ScriptParser.new()
	# Supplied .mob diplomacy matrix: all neutral, then the listed entries.
	world.diplomacy.resize(1024)
	world.diplomacy.fill(1)
	for row: Array in data.get("diplomacy", []):
		world.diplomacy[int(row[0]) * 32 + int(row[1])] = int(row[2])
	var units: Array = trace.quest_units(data.get("units", []), world)
	var registry := {}
	for i in units.size():
		if units[i] is GameUnit:
			_prepare(units[i], data.units[i], trace)
			registry[units[i].uid] = units[i]
	# The native fixture's world unit container (world+0x40) holds every
	# unit; its alarm spatial registry (world+0x12d70) stays empty, so alarm
	# descriptor switching is outside both sides (alarm units unregistered).
	if kind != "npc_alarm":
		world.units = registry
	world.ai._tick_n = int(data.get("tick", 0))
	var inst := ScriptVM.Instance.new()
	var states := []
	match kind:
		"npc_motivation": states = _motivation(data, vm, inst, units, trace)
		"npc_diplomacy": states = _diplomacy(data, vm, inst, units, trace)
		"npc_alarm": states = _alarm(data, vm, inst, units, world, trace)
	world.units = {}
	vm.world = null
	trace.free_quest_units(units)
	session.free()
	world.free()
	return states

## A fresh native logic object has an empty motivation list and AI state 0:
## the remake's "none" calm mode with no non-calm motivations.
func _prepare(u: GameUnit, row: Dictionary, trace: Node) -> void:
	u.controller = -1
	u.faction = int(row.get("side", 0))
	u.mode = "none"
	u.mode_data = {}
	u.set_meta("um", UnitAI.MOT_NONE.duplicate())
	var d: Dictionary = row.get("descriptor", {})
	var point: Array = d.get("point", [0, 0, 0])
	u.info["logic"] = [{"logic_model": int(d.get("model", 0)), "aggression": int(d.get("aggression", 0)),
		"alarm_raise": int(d.get("alarm_raise", 0)), "alarm_cond": int(d.get("alarm_cond", 0)),
		"guard_point": Vector3(trace.f32(float(point[0])), trace.f32(float(point[1])), trace.f32(float(point[2]))),
		"guard_radius": trace.f32(float(d.get("radius", -1.0)))}]

func _run(statement: Dictionary, vm: ScriptVM, inst: ScriptVM.Instance, units: Array, trace: Node) -> void:
	var expr: Array = trace.quest_expression(statement, inst, units)
	inst.frames = [{"body": [[ScriptParser.S_CALL, expr[1], expr[2]]], "i": 0}]
	inst.killed = false
	vm.time += ScriptVM.SLEEP_UNIT
	vm._run(inst)

func _query(expression: Dictionary, vm: ScriptVM, inst: ScriptVM.Instance, units: Array, trace: Node) -> int:
	var result = vm._eval(trace.quest_expression(expression, inst, units), inst)
	return trace.bits(0.0 if result == null else float(result))

func _index(units: Array, value) -> int:
	if value == null or not (value is Object) or not is_instance_valid(value):
		return -1
	var i := units.find(value)
	return i if i >= 0 else -2

func _point(trace: Node, p: Vector2) -> Array:
	return [trace.bits(p.x), trace.bits(p.y), 0]

func _configured(trace: Node, value: float, key: String):
	return key if value < 0.0 else trace.bits(value)

## Mapping: calm mode -> its calm motivation; um.fight standard / aggression
## -> Aggression (revenge false), revenge -> Aggression (revenge true);
## um.susp -> Suspection; um.corpse -> CorpseWatcher; um.fear >= 0 -> Fear.
func _motivations(u: GameUnit, units: Array, world: GameWorld, trace: Node) -> Array:
	var out := []
	var data: Dictionary = u.mode_data
	match u.mode:
		"none": pass
		"sentry": out.append({"type": "sentry", "point_bits": _point(trace, data.point)})
		"guard":
			out.append({"type": "guard", "point_bits": _point(trace, data.point),
				"radius": _configured(trace, float(data.get("radius", -1.0)), "GuardRadius"),
				"stay": _configured(trace, float(data.get("stay", -1.0)), "GuardStayTime")})
		"follow": out.append({"type": "follow", "target": _index(units, data.get("target"))})
		"player": out.append({"type": "player"})
		_: out.append({"type": "remake_mode_" + u.mode})
	var m: Dictionary = world.ai.mots(u)
	match String(m.fight):
		"standard", "aggression": out.append({"type": "aggression", "revenge": false})
		"revenge": out.append({"type": "aggression", "revenge": true})
	if m.susp: out.append({"type": "suspection"})
	if m.corpse: out.append({"type": "corpse_watcher"})
	if int(m.fear) >= 0: out.append({"type": "fear", "flag": int(m.fear) != 0})
	out.sort_custom(func(a: Dictionary, b: Dictionary): return int(ORDER.get(a.type, 99)) < int(ORDER.get(b.type, 99)))
	return out

func _ai_state(u, units: Array, world: GameWorld, trace: Node) -> Dictionary:
	if not (u is GameUnit):
		return {"present": false}
	var state := {"present": true, "blocked": bool(u.blocked), "side": int(u.faction)}
	state["motivations"] = _motivations(u, units, world, trace)
	state["ai_state"] = int(u.get_meta("ai_state", 0))
	# ScriptVM.ai_busy discards ai_target whenever the state is 0.
	state["script_target"] = _index(units, u.get_meta("ai_target")) if u.has_meta("ai_state") and u.has_meta("ai_target") else -1
	return state

func _motivation(data: Dictionary, vm: ScriptVM, inst: ScriptVM.Instance, units: Array, trace: Node) -> Array:
	var states := []
	for statement: Dictionary in data.commands:
		_run(statement, vm, inst, units, trace)
		var rows := []
		for index in data.observe:
			rows.append(_ai_state(units[int(index)] if int(index) >= 0 and int(index) < units.size() else null, units, vm.world, trace))
		states.append({"units": rows})
	return states

func _diplomacy(data: Dictionary, vm: ScriptVM, inst: ScriptVM.Instance, units: Array, trace: Node) -> Array:
	var states := []
	for statement: Dictionary in data.commands:
		_run(statement, vm, inst, units, trace)
		var relations := []
		for pair: Array in data.pairs:
			relations.append(_query({"call": "GetDiplomacy", "args": pair}, vm, inst, units, trace))
		var rows := []
		for index in data.observe:
			var enemy := 0
			for side in 32:
				var value := _query({"call": "IsEnemy", "args": [{"unit": int(index)}, side]}, vm, inst, units, trace)
				if value != 0 and value != 0x80000000:
					enemy |= 1 << side
			var u = units[int(index)] if int(index) >= 0 and int(index) < units.size() else null
			rows.append({"side": int(u.faction) if u is GameUnit else null, "enemy_bits": enemy})
		states.append({"relation_bits": relations, "units": rows})
	return states

func _alarm(data: Dictionary, vm: ScriptVM, inst: ScriptVM.Instance, units: Array, world: GameWorld, trace: Node) -> Array:
	var watched := []
	for i in units.size():
		var row = data.units[i]
		if units[i] is GameUnit and row.has("alert"):
			var u: GameUnit = units[i]
			u.info["logic"][0]["alarm_raise"] = int(row.alert["raise"])
			u.set_meta("alarm_left", int(row.alert.countdown))
			if bool(row.alert.alerted):
				world.ai._alert(u)
			watched.append(u)
	var states := []
	for step: Dictionary in data.steps:
		if step.has("command"):
			_run(step.command, vm, inst, units, trace)
		else:
			world.ai.tick()
		var table := []
		for index in data.queries:
			table.append({"on_bits": _query({"call": "IsAlarm", "args": [index]}, vm, inst, units, trace),
				"time_bits": _query({"call": "AlarmTime", "args": [index]}, vm, inst, units, trace),
				"x_bits": _query({"call": "AlarmPosX", "args": [index]}, vm, inst, units, trace),
				"y_bits": _query({"call": "AlarmPosY", "args": [index]}, vm, inst, units, trace)})
		var countdowns := []
		for u: GameUnit in watched:
			countdowns.append(int(u.get_meta("alarm_left", UnitAI.ALARM_COUNT)))
		states.append({"alarms": table, "countdowns": countdowns})
	return states
