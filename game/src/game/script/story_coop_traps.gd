extends RefCounted
## Independent original trap/follow threads for extra campaign participants. A small
## watcher remembers which character slots were armed, including late joins.
## Child threads reuse native conditions, Sleep and save/resume machinery.
const P := preload("res://src/game/script/script_parser.gd")
const Effects := preload("res://src/game/script/story_coop_effects.gd")
const KEY := "Remake#TrapCharacter"
const SEEN := "Remake#TrapSeen"
const COPY := "#RemakeParticipant"
const WATCH := "#RemakeParticipants"
const FAMILIES := {
	"gz36j": {"root":"Trap#0#4", "peer":"Trap#0#3", "slot":1, "caller":"WorldScript"},
	"gz1h": {"root":"Lift#66", "peer":"Lift#65", "slot":2, "caller":"Lift#63"},
	"gz9g": {"root":"VCheck#4#8", "peer":"VCheck#4#7", "slot":1, "caller":"VCheck#4#5", "cooldown":"VCheck#4#8a", "peer_cooldown":"VCheck#4#7a"},
}


static func _replace_calls(body: Array, names: Array) -> void:
	for st: Array in body:
		if st[0] == P.S_CALL and st[1] in names:
			st[1] += COPY
			st[2].append([P.N_VAR, KEY])


static func apply(ast: ScriptParser, zone: String) -> void:
	if not FAMILIES.has(zone): return
	apply_family(ast, FAMILIES[zone])


static func apply_family(ast: ScriptParser, cfg: Dictionary) -> void:
	var root: String = cfg.root
	if ast.scripts.has(root+WATCH): return
	var original: Dictionary = ast.scripts.get(root, {})
	var pairs := {root:cfg.peer}
	if cfg.has("cooldown"):
		pairs[cfg.cooldown] = cfg.peer_cooldown
	pairs.merge(cfg.get("chain",{}))
	for name: String in pairs:
		var def: Dictionary = ast.scripts.get(name,{})
		var peer: Dictionary = ast.scripts.get(pairs[name],{})
		if def.is_empty() or peer.is_empty() or def.blocks.size() != 1: return
		var expected: Dictionary = def.duplicate(true)
		var b: Dictionary = expected.blocks[0]
		b.conds = Effects.replace(b.conds, Effects.role(cfg.slot), Effects.role(cfg.slot-1))
		b.body = Effects.replace(b.body, Effects.role(cfg.slot), Effects.role(cfg.slot-1))
		for call: String in pairs:
			b.body = Effects.replace(b.body, [P.S_CALL,call,[[P.N_VAR,"this"]]], [P.S_CALL,pairs[call],[[P.N_VAR,"this"]]])
		if expected != peer: return
	var names: Array = pairs.keys()
	# Generate definitions only. Original scripts and saved instruction indexes
	# are untouched; the arm hook is limited to the inspected original caller.
	for name: String in names:
		var def: Dictionary = ast.scripts[name].duplicate(true)
		def.params.append(KEY)
		for b: Dictionary in def.blocks:
			var actor := [P.N_CALL,"RemakeTrapActor",[[P.N_VAR,KEY],[P.N_NUM,float(cfg.slot+1)]]]
			b.conds = Effects.replace(b.conds, Effects.role(cfg.slot), actor)
			b.body = Effects.replace(b.body, Effects.role(cfg.slot), actor)
			if name == root: b.conds.push_front([P.N_CALL,"IsAlive",[actor]])
			_replace_calls(b.body,names)
		ast.scripts[name+COPY] = def
	var args := [[P.N_STR,root]]
	for param: String in original.params: args.append([P.N_VAR,param])
	ast.scripts[root+WATCH] = {"params":original.params.duplicate(),
		"blocks":[{"conds":[],"body":[[P.S_CALL,"RemakeTrapJoin",args]]}],
		"trap":cfg.duplicate(true), "family":names}


static func arm(vm: ScriptVM, name: String, args: Array, caller: String) -> void:
	var def: Dictionary = vm.ast.scripts.get(name+WATCH,{})
	if def.is_empty() or not vm.session.lmp.is_empty(): return
	if caller != "" and caller != def.trap.caller: return
	vm.spawn(name+WATCH,args)
	# Arm present participants on the same tick as the native roles. The
	# watcher only adds newly present characters afterward.
	join(vm,name,args,vm.instances.back())


static func _key(vm: ScriptVM, u: GameUnit) -> String:
	var h := vm._hero_key(u)
	if not h.is_empty(): return "h:%d:%d" % h
	var record: Dictionary = u.get_meta("hero",{})
	return "m:%d" % int(record.merc) if record.has("merc") else "u:%d" % u.uid


static func actor(vm: ScriptVM, key: String, covered: int) -> GameUnit:
	var parts := key.split(":")
	var u: GameUnit
	if parts.size() == 3 and parts[0] == "h":
		var owner := int(parts[1]); var index := int(parts[2])
		var roster: Array = vm.session.state.heroes.get(owner,[])
		if index < 0 or index >= roster.size(): return null
		# Trap polls only need live controlled party members. Avoid the saved
		# reference resolver's full-world scan on every condition evaluation.
		for member: GameUnit in vm.world.party_units():
			if member.controller == owner and is_same(member.get_meta("hero",{}),roster[index]):
				u = member
				break
	elif parts.size() == 2 and parts[0] == "m":
		for member: GameUnit in vm.world.party_units():
			if int(member.get_meta("hero",{}).get("merc",-1)) == int(parts[1]):
				u = member
				break
	elif parts.size() == 2 and parts[0] == "u": u = vm.world.units.get(int(parts[1]))
	if not is_instance_valid(u) or u.dead or u.hidden or u.controller < 0: return null
	return null if vm._story_records().slice(0,covered).has(u) else u


static func join(vm: ScriptVM, root: String, args: Array, inst: ScriptVM.Instance) -> void:
	var def: Dictionary = vm.ast.scripts.get(root+WATCH,{})
	if def.is_empty() or not vm.session.lmp.is_empty(): return
	var covered: int = int(def.trap.slot)+1
	var story := vm._story_records().slice(0,covered)
	var seen: Array = inst.locals.get(SEEN,[])
	for u: GameUnit in vm.world.party_units():
		if u.dead or u.hidden or story.has(u) or not (u.has_meta("hero") or u.has_meta("script_control")): continue
		var key := _key(vm,u)
		if key in seen: continue
		seen.append(key)
		vm.spawn(root+COPY,args+[key])
	inst.locals[SEEN] = seen


## Old saves have native trap/cooldown threads but no extra-participant
## watcher. Recover only those proven active families. New saves retain the
## watcher and each child's native wait, so reconnects cannot re-arm a hit.
static func recover(vm: ScriptVM) -> void:
	for name: String in vm.ast.scripts:
		var def: Dictionary = vm.ast.scripts[name]
		if not def.has("trap") or vm.instances.any(func(i): return i.sname == name): continue
		var anchors := vm.instances.filter(func(i): return i.sname in def.family and (not i.killed or not i.frames.is_empty()))
		for anchor: ScriptVM.Instance in anchors:
			var args := []
			for param: String in def.params: args.append(anchor.locals.get(param))
			arm(vm,def.trap.root,args,"")
