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
const PRISON_REGISTER := "VTriger#0#416"
const PRISON_WAIT := "VCheck#0#417"
const PRISON_CHAIN := [PRISON_WAIT,"VTriger#0#48","VCheck#0#227","VCheck#0#229","VCheck#0#230",
	"VCheck#0#393","VCheck#0#398","VCheck#0#403","VTriger#0#233","VTriger#0#234","VTriger#0#235",
	"VTriger#0#219","VTriger#0#241","VTriger#0#242","VTriger#0#408","VCheck#0#410",
	"VTriger#0#413","VCheck#0#422","VTriger#0#425"]
const PRISON_SIGNATURE := "f8a52c0d6ecfd0749d7949a8963c296cd60dda87d936ed970f74f4d83a0ab813"
const PRISON_ACTOR := &"prison_actor_reference"
const PRISON_LAST := &"prison_actor_tick"
const PRISON_INTRUDER := &"prison_intruder_reference"
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


## This original prison registers one native area wait per deployed hero.
## Later arrivals need that same wait, not another guard-dispatch loop.
## Admit the complete original area, registration, alarm and pursuit/reset
## family before the existing dispatch adaptation. The stable sorted AST
## fingerprint rejects changed delays as well as missing/changed predicates.
static func apply_prison(ast: ScriptParser) -> void:
	if ast.scripts.has(PRISON_REGISTER+WATCH): return
	var definitions := []
	for name: String in ["VTriger#0#415",PRISON_REGISTER]+PRISON_CHAIN+["VCheck#0#180","VTriger#0#181"]:
		definitions.append([name,ast.scripts.get(name,{})])
	if JSON.stringify(definitions,"",true,true).sha256_text() != PRISON_SIGNATURE: return
	if not ast.world.has([P.S_CALL,PRISON_REGISTER,[[P.N_VAR,"NULL"]]]): return
	# Parameterless: this is shared registration bookkeeping, not the host's
	# individual continuation. CoopVmState projects its seen identities.
	ast.scripts[PRISON_REGISTER+WATCH] = {"params":[],"blocks":[{"conds":[],
		"body":[[P.S_CALL,"RemakeTrapJoin",[[P.N_STR,PRISON_REGISTER]]]]}],
		"registration":{"child":PRISON_WAIT,"caller":"WorldScript","family":PRISON_CHAIN}}


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
	if _prison_enabled(vm):
		if name == PRISON_WAIT: _note_prison_wait(vm,args)
		if name in PRISON_CHAIN and not args.is_empty() and args[0] is GameUnit:
			_remember_prison_actor(vm,vm.instances.back(),vm._ser(args[0]))
	var def: Dictionary = vm.ast.scripts.get(name+WATCH,{})
	if def.is_empty() or not vm.session.lmp.is_empty(): return
	if def.has("registration"):
		if caller != def.registration.caller or vm.instances.any(func(i):return i.sname == name+WATCH): return
		vm.spawn(name+WATCH,[])
		return   # the native For runs first and records its actual children
	if caller != "" and caller != def.trap.caller: return
	vm.spawn(name+WATCH,args)
	# Arm present participants on the same tick as the native roles. The
	# watcher only adds newly present characters afterward.
	join(vm,name,args,vm.instances.back())


static func _note_prison_wait(vm: ScriptVM, args: Array) -> void:
	if args.is_empty() or not args[0] is GameUnit or not is_instance_valid(args[0]): return
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname != PRISON_REGISTER+WATCH or inst.killed: continue
		var seen: Array = inst.locals.get(SEEN,[])
		var key := _key(vm,args[0])
		if not key in seen: seen.append(key)
		inst.locals[SEEN] = seen


static func _prison_enabled(vm: ScriptVM) -> bool:
	return vm.ast != null and vm.ast.scripts.get(PRISON_REGISTER+WATCH,{}).has("registration") \
		and vm.session != null and vm.session.lmp.is_empty()


static func _remember_prison_actor(vm: ScriptVM, inst: ScriptVM.Instance, reference: Variant) -> void:
	# Stable hero references alone need rebinding after deployment. Ordinary
	# UID refs, intentional removals and generic deserialization stay intact.
	if not reference is Dictionary or not reference.get("h") is Array: return
	inst.set_meta(PRISON_ACTOR,reference.duplicate(true))
	inst.set_meta(PRISON_LAST,vm.time)


## A disconnected hero can be absent from a loaded map. Keep only this
## source-admitted family's exact continuation dormant until its actor
## returns, including the remaining native poll/Sleep and existing frames.
static func hold_registration(vm: ScriptVM, inst: ScriptVM.Instance) -> bool:
	if not _prison_enabled(vm): return false
	if vm.has_meta(PRISON_INTRUDER):
		if vm.globals.get("Try1") != null:
			vm.remove_meta(PRISON_INTRUDER)
		else:
			var intruder = vm._deser(vm.get_meta(PRISON_INTRUDER))
			if intruder is GameUnit:
				vm.globals.Try1 = intruder
				vm.remove_meta(PRISON_INTRUDER)
	if not inst.has_meta(PRISON_ACTOR): return false
	var last := float(inst.get_meta(PRISON_LAST,vm.time))
	inst.set_meta(PRISON_LAST,vm.time)
	var actor = vm._deser(inst.get_meta(PRISON_ACTOR))
	if actor is GameUnit:
		inst.locals.this = actor
		return false
	if inst.wait_until > last: inst.wait_until += maxf(0.0,vm.time-last)
	if inst.poll > last: inst.poll += maxf(0.0,vm.time-last)
	inst.locals.this = null
	return true


static func save_registration(vm: ScriptVM, saved: Dictionary) -> Dictionary:
	if not _prison_enabled(vm): return saved
	for i in vm.instances.size():
		var inst: ScriptVM.Instance = vm.instances[i]
		if inst.has_meta(PRISON_ACTOR) and saved.instances[i].l.get("this") == null:
			saved.instances[i].l.this = inst.get_meta(PRISON_ACTOR).duplicate(true)
	if vm.has_meta(PRISON_INTRUDER) and saved.globals.get("Try1") == null:
		saved.globals.Try1 = vm.get_meta(PRISON_INTRUDER).duplicate(true)
	return saved


static func restore_registration(vm: ScriptVM, saved: Dictionary) -> void:
	if not _prison_enabled(vm): return
	# Every admitted native definition exists, so per-name instance order
	# matches the saved order even when unrelated missing scripts were skipped.
	var rows := {}
	for row: Dictionary in saved.get("instances",[]):
		if row.get("s") in PRISON_CHAIN: rows.get_or_add(row.s,[]).append(row)
	for inst: ScriptVM.Instance in vm.instances:
		if not rows.has(inst.sname) or rows[inst.sname].is_empty(): continue
		var row: Dictionary = rows[inst.sname].pop_front()
		_remember_prison_actor(vm,inst,row.get("l",{}).get("this"))
	var intruder = saved.get("globals",{}).get("Try1")
	if intruder is Dictionary and intruder.get("h") is Array and vm.globals.get("Try1") == null:
		vm.set_meta(PRISON_INTRUDER,intruder.duplicate(true))


static func _join_registration(vm: ScriptVM, root: String, inst: ScriptVM.Instance) -> void:
	# A saved or newly spawned For(Heroes) still owns its remaining items.
	if vm.instances.any(func(i):return i.sname == root and (not i.killed or not i.frames.is_empty())): return
	var seen: Array = inst.locals.get(SEEN,[])
	inst.locals[SEEN] = seen
	for u: GameUnit in vm._party_records():
		if u.dead or u.hidden: continue
		var key := _key(vm,u)
		if key in seen: continue
		seen.append(key)
		vm.spawn(String(vm.ast.scripts[root+WATCH].registration.child),[u])


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
	if def.has("registration"):
		_join_registration(vm,root,inst)
		return
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
		if def.has("registration"):
			_recover_registration(vm,name,def.registration)
			continue
		if not def.has("trap") or vm.instances.any(func(i): return i.sname == name): continue
		var anchors := vm.instances.filter(func(i): return i.sname in def.family and (not i.killed or not i.frames.is_empty()))
		for anchor: ScriptVM.Instance in anchors:
			var args := []
			for param: String in def.params: args.append(anchor.locals.get(param))
			arm(vm,def.trap.root,args,"")


static func _recover_registration(vm: ScriptVM, name: String, cfg: Dictionary) -> void:
	if not vm.session.lmp.is_empty() or vm.instances.any(func(i):return i.sname == name): return
	var root := name.trim_suffix(WATCH)
	var anchors := vm.instances.filter(func(i):return (i.sname == root or i.sname in cfg.family) \
		and (not i.killed or not i.frames.is_empty()))
	# Without native waiting/pursuit history an older save cannot establish
	# whether this registration ever ran or a character already spent it.
	if anchors.is_empty(): return
	var seen := []
	for anchor: ScriptVM.Instance in anchors:
		var u = anchor.locals.get("this")
		var key := ""
		if u is GameUnit and is_instance_valid(u): key = _key(vm,u)
		elif anchor.has_meta(PRISON_ACTOR):
			var h: Array = anchor.get_meta(PRISON_ACTOR).h
			key = "h:%d:%d" % h
		if key.is_empty(): continue
		if not key in seen: seen.append(key)
	vm.spawn(name,[])
	vm.instances.back().locals[SEEN] = seen
