extends RefCounted
## Co-op adaptations for inspected, paired LiA spell scripts. Named moves,
## cutscenes, individual traps and protagonist-only attacks stay authored.
const P := preload("res://src/game/script/script_parser.gd")
const TARGET := "Remake#EffectTarget"
const PARTY_CASTS := {
	"gz1h": ["PortalFire"],
	"gz5h": ["Tiger#1#1", "Tiger#2#1", "Tiger#3#1"],
	"gz10g": ["VCheck#3#5", "VCheck#3#6"],
	"gz36j": ["Healing#0#1", "Healing#1#1"],
}
const SHARED_TRAPS := {
	"gz16g": ["VCheck#0#4"],
	"gz21k": ["Trap#0#1", "Trap#1#1", "Trap#1#2", "Trap#1#3", "Trap#1#4"],
}


static func role(index: int) -> Array:
	return [P.N_CALL, "GetUnitOfPlayer", [[P.N_NUM, 0.0], [P.N_NUM, float(index)]]]


static func replace(value, from: Array, to: Array):
	if value is Array:
		if value == from: return to.duplicate(true)
		return value.map(func(v): return replace(v, from, to))
	return value


static func apply(ast: ScriptParser, zone: String) -> void:
	if zone == "gz7g": _gipat_arrival(ast)
	for name: String in PARTY_CASTS.get(zone, []):
		for block: Dictionary in ast.scripts.get(name, {}).get("blocks", []):
			for statement: Array in block.body:
				if statement[0] != P.S_CALL or statement[1] not in ["CastSpellUnit", "CastSpellPoint"]: continue
				var first: Array = replace(statement, role(1), role(0))
				# Only expand the second of otherwise identical casts. Replacing
				# one statement keeps old saved frame indexes, including Sleep.
				if first == statement or not block.body.has(first): continue
				statement[2].push_front([P.N_STR, statement[1]])
				statement[1] = "RemakePartyCast"
	for name: String in SHARED_TRAPS.get(zone, []):
		var blocks: Array = ast.scripts.get(name, {}).get("blocks", [])
		if blocks.size() != 2: continue
		var first: Dictionary = blocks[0]
		var second: Dictionary = blocks[1]
		# These traps share one shot/cooldown between the two branches. Extra
		# participants take the companion's branch, after both authored ones.
		# In Ingos only the protagonist has the original item-60 exemption.
		if replace(second.body, role(1), role(0)) != first.body: continue
		if not second.body.any(func(st: Array): return st[0] == P.S_CALL and st[1] == "CastSpellUnit" and st[2].back() == role(1)): continue
		var conditions: Array = replace(second.conds, role(1), [P.N_VAR, TARGET])
		if conditions == second.conds: continue
		blocks.append({"conds": [[P.N_CALL, "RemakeMatchExtra", conditions]],
			"body": replace(second.body, role(1), [P.N_VAR, TARGET])})


## The first Gipat arrival places Kel separately, then shows Kir and Kel
## arriving through the portal. Extend only that presentation to extra heroes.
## Keep the named SetCP, both original effects and every saved statement index.
static func _gipat_arrival(ast: ScriptParser) -> void:
	var name := "VCheck#0#1"
	if ast.world.count([P.S_CALL,name,[[P.N_VAR,"NULL"]]]) != 1 \
			or ast.world.filter(func(st):return st[0] == P.S_CALL and st[1] == name).size() != 1: return
	var expected := {"params":["this"],"blocks":[{"conds":[[P.N_CALL,"IsEqual",[
		[P.N_CALL,"GSGetVar",[[P.N_NUM,0.0],[P.N_STR,"q.gz7g.q1g"]]],[P.N_NUM,1.0]]]],"body":[
		[P.S_CALL,"KillScript",[]],
		[P.S_CALL,"AddRoundToArea",[[P.N_NUM,1.0],[P.N_NUM,129.5],[P.N_NUM,270.0],[P.N_NUM,5.0]]],
		[P.S_CALL,"AddRectToArea",[[P.N_NUM,2.0],[P.N_NUM,204.0],[P.N_NUM,304.0],[P.N_NUM,217.0],[P.N_NUM,318.0]]],
		[P.S_CALL,"SetCP",[role(1),[P.N_NUM,14.4],[P.N_NUM,208.0],[P.N_NUM,0.0]]],
		[P.S_CALL,"CreateParticleSource",[[P.N_NUM,1.0],[P.N_CALL,"GetX",[role(0)]],
			[P.N_CALL,"GetY",[role(0)]],[P.N_NUM,8.0],[P.N_NUM,1.0],[P.N_STR,"teleport"]]],
		[P.S_CALL,"CreateParticleSource",[[P.N_NUM,2.0],[P.N_CALL,"GetX",[role(1)]],
			[P.N_CALL,"GetY",[role(1)]],[P.N_NUM,7.5],[P.N_NUM,1.0],[P.N_STR,"teleport"]]],
		[P.S_CALL,"Sleep",[[P.N_NUM,20.0]]],
		[P.S_CALL,"GSSetVarMax",[[P.N_NUM,0.0],[P.N_STR,"q.gz7g.q1g.1"],[P.N_NUM,1.0]]],
		[P.S_CALL,"VCheck#0#2",[[P.N_VAR,"this"]]],
	]}]}
	if ast.scripts.get(name,{}) != expected: return
	ast.scripts[name].blocks[0].body[5][1] = "RemakeGipatArrivalParticles"


static func gipat_arrival_particles(vm: ScriptVM, arguments: Array, inst: ScriptVM.Instance) -> void:
	vm._call("CreateParticleSource",arguments,inst)   # Kel's original effect, first
	if not vm.session.lmp.is_empty() or vm.session.state.campaign_id != CampaignProfile.ASTRAL \
			or vm.world.zone.get("id","") != "gz7g" or inst.sname != "VCheck#0#1": return
	var story := vm._story_records()
	for u: GameUnit in vm._party_records():
		if u.controller <= 0 or story.has(u) or u.dead or u.hidden or not u.has_meta("hero") \
				or u.get_meta("hero").has("merc"): continue
		# Kir's authored entry effect has absolute z=8 and size=1. Only XY
		# follows the additional arrival, just as it follows Kir in the source.
		# Share the saved negative-ID allocator with automatic FX sources.
		var id := vm._fx_auto
		vm._fx_auto -= 1
		vm._call("CreateParticleSource",[[P.N_NUM,float(id)],[P.N_NUM,u.pos.x],[P.N_NUM,u.pos.y],
			[P.N_NUM,8.0],[P.N_NUM,1.0],[P.N_STR,"teleport"]],inst)


static func additional(vm: ScriptVM) -> Array:
	if not vm.session.lmp.is_empty(): return []
	var covered := vm._story_records().slice(0, 2)
	return vm.world.party_units().filter(func(u: GameUnit):
		return (u.has_meta("hero") or u.has_meta("script_control")) and not u.dead and not u.hidden and not covered.has(u))


static func cast(vm: ScriptVM, arguments: Array, inst: ScriptVM.Instance) -> void:
	var name: String = arguments[0][1]
	if name not in ["CastSpellUnit", "CastSpellPoint"]: return
	var original := arguments.slice(1)
	vm._call(name, original, inst)
	var extra: Array = replace(original, role(1), [P.N_VAR, TARGET])
	for u: GameUnit in additional(vm):
		inst.locals[TARGET] = u
		vm._call(name, extra, inst)
	inst.locals.erase(TARGET)


static func match_extra(vm: ScriptVM, conditions: Array, inst: ScriptVM.Instance) -> float:
	for u: GameUnit in additional(vm):
		inst.locals[TARGET] = u
		if vm._all(conditions, inst): return 1.0
	inst.locals.erase(TARGET)
	return 0.0
