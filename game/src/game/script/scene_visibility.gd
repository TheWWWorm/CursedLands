extends RefCounted
## Completed startup decisions are absent from a saved VM. Reconcile the
## declarative visibility subset against current campaign flags on reentry.
## Never restart WorldScript, rewards, AddMob, removals or timed story actions.
const P = preload("res://src/game/script/script_parser.gd")
const READS := {"GSGetVar":2, "GetObjectByName":1, "GetObjectByID":1,
	"IsEqual":2, "IsGreater":2, "IsLess":2, "Not":1, "IsEqualString":2}


static func rules(ast: ScriptParser) -> Array:
	var out := []
	if not ast.errors.is_empty(): return out
	for call: Array in ast.world:
		if call[0] != P.S_CALL or not ast.scripts.has(call[1]): continue
		if call[2].size() != ast.scripts[call[1]].params.size(): continue
		var info := {"names":{}, "flags":false, "hide":false}
		if _family(ast, call[1], info, {}) and info.flags and info.hide \
				and call[2].all(func(e): return _expression(e, info)):
			out.append({"call":call, "names":info.names})
	return out


static func _expression(e: Array, info: Dictionary) -> bool:
	if e.size() < 2: return false
	if e[0] in [P.N_NUM, P.N_STR, P.N_VAR]: return e.size() == 2
	if e[0] != P.N_CALL or e.size() != 3 or not READS.has(e[1]) \
			or e[2].size() != READS[e[1]]: return false
	if e[1] == "GSGetVar": info.flags = true
	return e[2].all(func(arg): return _expression(arg, info))


static func _family(ast: ScriptParser, name: String, info: Dictionary, visiting: Dictionary) -> bool:
	if visiting.has(name): return false
	if info.names.has(name): return true
	var def: Dictionary = ast.scripts.get(name, {})
	var blocks: Array = def.get("blocks", [])
	# Every choice must terminate immediately, including its default. A
	# condition without an else is an ordinary persistent wait, not a rule.
	if blocks.is_empty() or not blocks[-1].conds.is_empty(): return false
	visiting[name] = true
	for block: Dictionary in blocks:
		if not block.conds.all(func(e): return _expression(e, info)): return false
		if block.body.is_empty() or block.body[0] != [P.S_CALL,"KillScript",[]]: return false
		for call: Array in block.body.slice(1):
			if call[0] != P.S_CALL or not call[2].all(func(e): return _expression(e, info)): return false
			if call[1] == "HideObject":
				if call[2].size() != 2 or call[2][1] not in [[P.N_NUM,0.0],[P.N_NUM,1.0]]: return false
				info.hide = true
			elif not ast.scripts.has(call[1]) or call[2].size() != ast.scripts[call[1]].params.size() \
					or not _family(ast, call[1], info, visiting): return false
	visiting.erase(name)
	info.names[name] = true
	return true


static func refresh(vm: ScriptVM) -> void:
	# An unfinished startup or family still owns its original execution.
	if vm.instances.any(func(i): return i.sname == "WorldScript" and i.src == ""): return
	for rule: Dictionary in rules(vm.ast):
		if vm.instances.any(func(i): return rule.names.has(i.sname)): continue
		_run(vm, rule.call[1], vm._args(rule.call[2], ScriptVM.Instance.new()))


static func _run(vm: ScriptVM, name: String, args: Array) -> void:
	var def: Dictionary = vm.ast.scripts[name]
	var inst := ScriptVM.Instance.new()
	for i in mini(def.params.size(), args.size()): inst.locals[def.params[i]] = args[i]
	for block: Dictionary in def.blocks:
		if not block.conds.all(func(e): return vm._truthy(vm._eval(e, inst))): continue
		for call: Array in block.body.slice(1):
			var values := vm._args(call[2], inst)
			if call[1] == "HideObject":
				var actor: Variant = values[0]
				if not actor is Object or not is_instance_valid(actor): continue
				# Visibility never resurrects/recreates actors or overrides a
				# recruited hero's ownership and presentation.
				if actor is GameUnit and (actor.dead or actor.has_meta("hero") or actor.controller >= 0): continue
				vm._hide(actor, vm._truthy(values[1]))
			else:
				_run(vm, call[1], values)
		return
