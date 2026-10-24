extends RefCounted
## Suslanger's gate patrol must lose a fleeing party. Preserve the authored
## alarm, search-area rearming, delays and saved continuation indexes.
const P := preload("res://src/game/script/script_parser.gd")

static func apply(ast: ScriptParser) -> void:
	# The complete original alarm family must have passed compatibility
	# admission; changed mod dispatches must retain their own pursuit rules.
	if not ast.scripts.has("VTriger#0#416#RemakeParticipants"): return
	var alive := [P.N_CALL,"IsAlive",[[P.N_VAR,"Try1"]]]
	var group := [P.N_VAR,"a1"]
	var names := ["VCheck#0#393","VCheck#0#398","VCheck#0#403"]
	var next := ["VTriger#0#233","VCheck#0#410","VCheck#0#422"]
	for i in names.size():
		var blocks: Array = ast.scripts.get(names[i],{}).get("blocks",[])
		if blocks.size()!=2 or not blocks[0].conds.has(alive) or not blocks[1].conds.is_empty() \
				or blocks[0].body != [[P.S_CALL,"KillScript",[]],[P.S_CALL,next[i],[[P.N_VAR,"this"]]]]: return
	var dead := [P.N_CALL,"Every",[[P.N_VAR,"i"],group,[P.N_CALL,"IsDead",[[P.N_VAR,"i"]]]]]
	var finish: Array = ast.scripts.get("VCheck#0#439",{}).get("blocks",[])
	if finish.size()!=1 or finish[0].conds != [dead] \
			or finish[0].body != [[P.S_CALL,"KillScript",[]],[P.S_CALL,"VTriger#0#438",[[P.N_VAR,"this"]]]]: return
	for name: String in names:
		ast.scripts[name].blocks[0].conds.append([P.N_CALL,"RemakeGuardContact",[group,[P.N_VAR,"Try1"]]])
	finish[0].conds = [[P.N_CALL,"RemakeGuardsEscaped",[group]]]

static func contact(vm: ScriptVM, guards: Array, target: GameUnit) -> bool:
	if target == null or target.dead or target.hidden: return false
	# The authored gate alarm summons distant reinforcements into its area.
	# Once the intruder leaves that area, updates require actual guard contact.
	if _inside_gate(vm, target.pos): return true
	# Contact is a guard sensing the intruder now (sight, cone and terrain ray),
	# not its noticed list: as in the original (5caa00) an NPC keeps a living
	# hostile there after losing sight, which would never let the party escape.
	for guard in guards:
		if is_instance_valid(guard) and guard is GameUnit and not guard.dead \
				and vm.world.ai.can_notice(guard, target, float(guard.stats.sight)): return true
	return false

static func _inside_gate(vm: ScriptVM, point: Vector2) -> bool:
	return vm._is_in_area(1, point)

static func escaped(vm: ScriptVM, guards: Array) -> bool:
	if guards.is_empty(): return false
	if guards.all(func(u):return not is_instance_valid(u) or u.dead): return true
	var party := vm.world.party_units().filter(func(u):return not u.dead and not u.hidden)
	if party.is_empty(): return false
	for u: GameUnit in party:
		if contact(vm,guards,u): return false
	return true
