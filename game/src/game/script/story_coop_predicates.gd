extends RefCounted
## Inspected campaign checks that mean any party participant, rather than a named
## story role. Keep original branch/statement indexes for sleeping saves.
const P := preload("res://src/game/script/script_parser.gd")
const E := preload("res://src/game/script/story_coop_effects.gd")


static func expr(name: String, args: Array) -> Array:
	return [P.N_CALL,name,args]


static func _with_extra(condition: Array) -> Array:
	return expr("RemakePartyAny",[condition.duplicate(true),E.replace(condition,E.role(1),[P.N_VAR,E.TARGET])])


static func _rename_calls(body: Array, names: Dictionary) -> void:
	for st: Array in body:
		if st[0] == P.S_FOR: _rename_calls(st[3],names)
		elif st[0] == P.S_CALL and names.has(st[1]): st[1] = names[st[1]]


static func _paired(ast: ScriptParser, first: String, second: String, names := {}) -> bool:
	if not ast.scripts.has(first) or not ast.scripts.has(second): return false
	var normalized: Dictionary = ast.scripts[second].duplicate(true)
	for b: Dictionary in normalized.blocks:
		b.conds = E.replace(b.conds,E.role(1),E.role(0))
		b.body = E.replace(b.body,E.role(1),E.role(0))
		_rename_calls(b.body,names)
	return normalized == ast.scripts[first]


static func _alarm(ast: ScriptParser, prefix: String) -> void:
	if not _paired(ast,prefix+"1",prefix+"2"): return
	var blocks: Array = ast.scripts[prefix+"2"].blocks
	if blocks.size() != 1 or blocks[0].conds.size() != 1: return
	var cond: Array = blocks[0].conds[0]
	if cond.size() != 3 or cond[0] != P.N_CALL or cond[1] != "GroupHas" or cond[2].back() != E.role(1): return
	blocks[0].conds[0] = _with_extra(cond)


static func _nearest(ast: ScriptParser, name: String, origin: Array, strict: bool) -> void:
	var blocks: Array = ast.scripts.get(name,{}).get("blocks",[])
	if blocks.size() != 2 or E.replace(blocks[1].body,E.role(1),E.role(0)) != blocks[0].body: return
	var compare := expr("IsLess" if strict else "IsGreater",[
		expr("DistanceUnitUnit",[origin,E.role(0)]),expr("DistanceUnitUnit",[origin,E.role(1)])])
	if strict:
		if blocks[0].conds.size() < 2 or blocks[0].conds.back() != compare or blocks[0].conds.slice(0,-1) != blocks[1].conds: return
	elif blocks[0].conds != [expr("Not",[compare])] or blocks[1].conds != [compare]: return
	for i in 2:
		for st: Array in blocks[i].body:
			if st[0] == P.S_CALL and st[1] == "Attack" and st[2].size() == 2 and st[2][1] == E.role(i):
				st[2][1] = expr("RemakeNearestParty",[origin.duplicate(true),E.role(i)])


static func _extra_branch(ast: ScriptParser, name: String, companion_ack := false) -> void:
	var blocks: Array = ast.scripts.get(name,{}).get("blocks",[])
	if blocks.size() != 2 or E.replace(blocks[1].conds,E.role(1),E.role(0)) != blocks[0].conds: return
	var body: Array = blocks[1].body.duplicate(true)
	if companion_ack:
		# This authored branch additionally plays an acknowledgement at Kir.
		# Keep it there for added participants, just as it is for Kel.
		var ack := [P.S_CALL,"CreateFX",[expr("GetX",[E.role(0)]),expr("GetY",[E.role(0)]),expr("GetZ",[E.role(0)]),
			[P.N_NUM,15.0],[P.N_NUM,50.0],[P.N_STR,"Acks\\Scenario\\10.wav"]]]
		if body.count(ack) != 1: return
		body.erase(ack)
	if E.replace(body,E.role(1),E.role(0)) != blocks[0].body: return
	blocks.append({"conds":[expr("RemakeMatchExtra",E.replace(blocks[1].conds,E.role(1),[P.N_VAR,E.TARGET]))],
		"body":E.replace(blocks[1].body,E.role(1),[P.N_VAR,E.TARGET])})


static func apply(ast: ScriptParser, zone: String) -> void:
	if zone == "gz1h":
		var seen := expr("GroupHas",[expr("UnitSee",[expr("GetObject",[[P.N_NUM,1012005.0]])]),E.role(1)])
		for name: String in ["VCheck#5#2","VCheck#5#3"]:
			for b: Dictionary in ast.scripts.get(name,{}).get("blocks",[]):
				if b.conds.has(expr("Not",[seen])) and b.conds.has(expr("Not",[E.replace(seen,E.role(1),E.role(0))])):
					b.conds = E.replace(b.conds,seen,_with_extra(seen))
	if zone == "gz3d1": _alarm(ast,"VGAlarm#0#")
	if zone in ["gz10g","gz15g"]:
		_alarm(ast,"VCityGuard#0#")
		_nearest(ast,"VCityGuard#1#0",[P.N_VAR,"this"],false)
	if zone == "gz16g": _nearest(ast,"VCheck#0#6",[P.N_VAR,"this"],false)
	if zone == "gz21k":
		_nearest(ast,"VCheck#1#3",expr("GetObject",[[P.N_NUM,1002004.0]]),true)
		_nearest(ast,"VCheck#6#2",expr("GetObject",[[P.N_NUM,1017004.0]]),true)
	if zone == "gz22k":
		_extra_branch(ast,"VCheck#2#3")
		_extra_branch(ast,"VCheck#3#2",true)
	if zone in ["gz32j","gz34j","gz35j"]:
		var names := {"Caboom#1#2":"Caboom#0#2","Caboom#1#3":"Caboom#0#3"}
		if not _paired(ast,"Caboom#0#1","Caboom#1#1",names) or not _paired(ast,"Caboom#0#2","Caboom#1#2"): return
		for i in [1,2]:
			var near := expr("IsLess",[expr("DistanceUnitUnit",[[P.N_VAR,"i" if i == 1 else "this"],E.role(1)]),[P.N_NUM,2.0]])
			for b: Dictionary in ast.scripts["Caboom#1#"+str(i)].blocks:
				b.conds = E.replace(b.conds,near,_with_extra(near))


## The prison alarm records its intruder in Try1, then dispatches only the
## three original roles. Share the last role's existing priority/cooldown
## chain with an added intruder rather than start competing guard loops.
static func apply_original(ast: ScriptParser, zone: String) -> void:
	if zone != "gz19h": return
	var root: Dictionary = ast.scripts.get("VCheck#0#230",{})
	var peer: Dictionary = ast.scripts.get("VCheck#0#229",{})
	var orders: Dictionary = ast.scripts.get("VTriger#0#235",{})
	var peer_orders: Dictionary = ast.scripts.get("VTriger#0#234",{})
	if root.is_empty() or peer.is_empty() or orders.is_empty() or peer_orders.is_empty(): return
	if root.blocks.size()!=1 or orders.blocks.size()!=1: return
	var expected := root.duplicate(true)
	expected.blocks[0].conds = E.replace(expected.blocks[0].conds,E.role(2),E.role(1))
	_rename_calls(expected.blocks[0].body,{"VCheck#0#403":"VCheck#0#398"})
	if expected != peer: return
	expected = orders.duplicate(true)
	expected.blocks[0].body = E.replace(expected.blocks[0].body,E.role(2),E.role(1))
	_rename_calls(expected.blocks[0].body,{"VTriger#0#242":"VTriger#0#241"})
	if expected != peer_orders: return
	var target := expr("RemakeCaptivityTarget",[[P.N_VAR,"Try1"]])
	root.blocks[0].conds = E.replace(root.blocks[0].conds,E.role(2),target)
	var sentry := [P.S_CALL,"UMSentry",[[P.N_VAR,"i"],expr("GetX",[E.role(2)]),expr("GetY",[E.role(2)])]]
	orders.blocks[0].body = E.replace(orders.blocks[0].body,sentry,[P.S_CALL,"RemakeSentryTarget",[[P.N_VAR,"i"],target]])


static func captivity_target(vm: ScriptVM, intruder: GameUnit) -> GameUnit:
	var story := vm._story_records().slice(0,3)
	if intruder == null or story.has(intruder): return story[2] if story.size()>2 else null
	if intruder.dead or intruder.hidden or intruder.controller<0: return null
	return intruder if vm.world.party_units().has(intruder) and (intruder.has_meta("hero") or intruder.has_meta("script_control")) else null


static func any_extra(vm: ScriptVM, args: Array, inst: ScriptVM.Instance) -> float:
	if vm._truthy(vm._eval(args[0],inst)): return 1.0
	var had := inst.locals.has(E.TARGET)
	var previous = inst.locals.get(E.TARGET)
	var result := E.match_extra(vm,[args[1]],inst)
	if had: inst.locals[E.TARGET] = previous
	else: inst.locals.erase(E.TARGET)
	return result


static func nearest(vm: ScriptVM, origin, native: GameUnit) -> GameUnit:
	if origin == null: return native
	var point := vm._xy(origin)
	var result := native
	var distance := point.distance_squared_to(native.pos) if native else INF
	for u: GameUnit in E.additional(vm):
		var d := point.distance_squared_to(u.pos)
		# Preserve the native branch's tie choice and coordinated attackers'
		# shared reference point; only a strictly closer extra replaces it.
		if d < distance:
			distance = d
			result = u
	return result
