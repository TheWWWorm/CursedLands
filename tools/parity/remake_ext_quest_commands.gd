extends RefCounted
## Remake side of cases_ext_quest_commands.py: production ScriptVM._run on a
## persistent body with a Session/CampaignState fixture. The adapter maps the
## resulting production state to the native observation schema:
##   gs       CampaignState._gs_table(0) {capacity, count, buckets} with each
##            key's float32 value from CampaignState.get_var(0, key)
##   bag      CampaignState.quest_items keys (insertion order) -> quest_items
##            script_id from GameData.db (-1 when the name has no row)
##   money    CampaignState.money
##   levers   GameWorld.levers[uid].state / .enabled (default true)
##   groups   the global group Array -> fixture unit indices
##   journal  recording = ScriptVM._q_recording; compiled = ScriptVM.qobjs
##            entries with defined = true, in insertion order. Objective rows
##            [name, arg, value]: QObjArea/QObjGetItem store their number as
##            text in the remake, mapped to ("", float32 bits of that text);
##            the others map to (text, float32 bits of the second argument).

class CommandWorld extends GameWorld:
	func ground_at(_x: float, _y: float) -> float:
		return 0.0

const KINDS := ["quest_cmd_gsvar", "quest_cmd_items", "quest_cmd_groups", "quest_cmd_levers", "quest_cmd_journal"]
const NUMERIC_OBJECTIVES := ["QObjArea", "QObjGetItem"]

func kinds() -> Array:
	return KINDS

func _statement(statement: Dictionary, inst: ScriptVM.Instance, units: Array, trace: Node) -> Array:
	if statement.has("set"):
		return [ScriptParser.S_SET, String(statement.set), trace.quest_expression(statement.value, inst, units)]
	if String(statement.call) == "For":
		var key := "iterator_" + String(statement.args[0].iterator)
		inst.locals[key] = null
		var body := []
		for child: Dictionary in statement.body:
			body.append(_statement(child, inst, units, trace))
		return [ScriptParser.S_FOR, key, trace.quest_expression(statement.args[1], inst, units), body]
	var args := []
	for arg in statement.args:
		args.append(trace.quest_expression(arg, inst, units))
	return [ScriptParser.S_CALL, String(statement.call), args]

func _script_id(name: String) -> int:
	var row: Dictionary = GameData.db.find("quest_items", name)
	return int(row.get("script_id", -1)) if not row.is_empty() else -1

func _gs(state: CampaignState, trace: Node) -> Dictionary:
	var table: Dictionary = state._gs_table(0)
	var indices: Array = table.buckets.keys()
	indices.sort()
	var chains := []
	for i in indices:
		var chain := []
		for key: String in table.buckets[i]:
			chain.append([key, trace.bits(state.get_var(0, key))])
		if not chain.is_empty():
			chains.append([int(i), chain])
	return {"capacity": int(table.capacity), "count": int(table.count), "chains": chains}

func _journal(vm: ScriptVM, trace: Node) -> Dictionary:
	var compiled := []
	for quest: String in vm.qobjs:
		var record: Dictionary = vm.qobjs[quest]
		if not record.get("defined", false):
			continue
		var objectives := []
		for o: Array in record.objs:
			var kind := String(o[0])
			if kind in NUMERIC_OBJECTIVES:
				objectives.append([kind, "", trace.bits(String(o[1]).to_float())])
			else:
				objectives.append([kind, String(o[1]), trace.bits(float(o[2]))])
		compiled.append({"quest": quest, "objectives": objectives})
	return {"recording": vm._q_recording, "compiled": compiled}

func capture(_kind: String, data: Dictionary, trace: Node) -> Array:
	var world := CommandWorld.new()
	var session: Session = trace.quest_session()
	var state := CampaignState.new()
	state.day = 1
	state.world_time = 0.0
	state.money = int(data.get("money", 0))
	session.state = state
	for pair: Array in data.get("variables", []):
		state.set_var(0, String(pair[0]), trace.f32(float(pair[1])))
	for name: String in data.get("quest_items", []):
		state.add_item(name.to_lower())
	var units := []
	var rows: Array = data.get("units", [])
	for row: Dictionary in rows:
		var u := GameUnit.new()
		u.world = world
		u.uid = int(row.get("uid", 1))
		var pos: Array = row.get("pos", [0, 0])
		u.pos = Vector2(float(pos[0]), float(pos[1]))
		u.max_hp = trace.f32(float(row.get("max_hp", 10)))
		u.hp = trace.f32(float(row.get("hp", 10)))
		u.dead = bool(row.get("dead", false))
		if row.get("lever") is Dictionary:
			var lever: Dictionary = row.lever
			world.levers[u.uid] = {"state": int(lever.state), "states": int(lever.states),
				"cycled": 1 if bool(lever.get("cycled", false)) else 0, "enabled": bool(lever.get("enabled", true))}
		units.append(u)
	world.lever_sys = LeverSystem.new(world)
	var vm := ScriptVM.new()
	vm.world = world
	vm.session = session
	vm.ast = ScriptParser.new()
	for name: String in data.get("globals", {}):
		vm.globals[name] = trace.f32(float(data.globals[name]))
	for name: String in data.get("groups", []):
		vm.globals["group_" + name] = []
	var inst := ScriptVM.Instance.new()
	var body := []
	for statement: Dictionary in data.body:
		body.append(_statement(statement, inst, units, trace))
	inst.frames = [{"body": body, "i": 0}]
	var observations := []
	for expr in data.get("observe", []):
		observations.append(trace.quest_expression(expr, inst, units))
	var states := []
	for index in data.ticks.size():
		vm.time = (index + 1) * ScriptVM.SLEEP_UNIT
		vm._run(inst)
		var bag := []
		for name: String in state.quest_items:
			bag.append(_script_id(name))
		var levers := []
		for i in rows.size():
			if rows[i].get("lever") is Dictionary:
				var record: Dictionary = world.levers.get(int(rows[i].get("uid", 1)), {})
				levers.append({"state": int(record.get("state", 0)), "enabled": bool(record.get("enabled", true))})
		var groups := {}
		for name: String in data.get("groups", []):
			var members := []
			for member in vm.globals.get("group_" + name, []):
				members.append(units.find(member))
			groups[name] = members
		var values := {}
		for name: String in data.get("globals", {}):
			values[name] = trace.bits(float(vm.globals[name]))
		var observed := []
		for expr in observations:
			var result = vm._eval(expr, inst)
			observed.append(trace.bits(0.0 if result == null else float(result)))
		states.append({"gs": _gs(state, trace), "bag": bag, "money": int(state.money), "levers": levers,
			"groups": groups, "journal": _journal(vm, trace), "globals": values,
			"observed_bits": observed, "finished": inst.frames.is_empty(), "killed": inst.killed})
	vm.world = null
	for u in units:
		u.free()
	session.free()
	world.free()
	return states
