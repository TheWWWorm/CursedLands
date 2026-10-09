extends "./prison_late_join.gd"
## Focused source and saved-VM controls with synthetic actors/chest positions.
## Original registration and quest bodies run; the separate ENet fixture proves
## these calls are reached by the shipped startup on the actual map.
const Snapshot := preload("res://src/game/script/coop_vm_state.gd")
const FAMILIES := [
	{"root":"VTriger#0#264","checks":["VCheck#0#265","VCheck#0#269","VCheck#0#271","VCheck#0#258"],
		"triggers":["VTriger#0#273","VTriger#0#261"],"quest":"q.gz19h.qk16h",
		"points":[Vector2(91.5,476),Vector2(103,494),Vector2(115.5,476),Vector2(112,500)]},
	{"root":"VTriger#0#278","checks":["VCheck#0#279","VCheck#0#280"],
		"triggers":["VTriger#0#284","VTriger#0#285"],"quest":"q.gz19h.qk17h",
		"points":[Vector2(79,318),Vector2(112,500)]},
]
var evidence := {"cases":[]}

func fixture(adapt := true) -> ProbeVM:
	s = QuietSession.new(); allocations.append(s); s.online = true
	s.state = CampaignState.new(); s.state.campaign_id = CampaignProfile.ORIGINAL
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s
	s.world.ai = UnitAI.new(s.world); s.world.zone = {"id":"gz19h"}
	leader = actor(0)
	var chest := Node3D.new(); allocations.append(chest)
	chest.set_meta("ei",{"nid":736257,"position":Vector3(112,500,0)})
	s.world.objects[736257] = chest
	var vm := ProbeVM.new(); vms.append(vm); vm.session = s; vm.world = s.world; s.world.vm = vm
	vm.ast = ScriptParser.parse(raw); vm.briefings = Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz19h")
	vm.globals = {"Heroes":[leader],"HChest1":chest}
	return vm

func marked(ast: ScriptParser, names: Array) -> Array:
	return names.filter(func(name):return ast.scripts.get(name,{}).get("party_check",false))

func definitions() -> void:
	var pristine := ScriptParser.parse(raw)
	var adapted := ScriptParser.parse(raw)
	Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(pristine.errors.is_empty() and adapted.errors.is_empty(),"original prison source parses without errors")
	for cfg: Dictionary in FAMILIES:
		check(marked(adapted,cfg.checks) == cfg.checks,cfg.root+": all and only inspected checks are marked")
		var names: Array = [cfg.root]+cfg.checks+cfg.triggers
		check(names.all(func(name):return adapted.scripts[name].params == pristine.scripts[name].params \
			and adapted.scripts[name].blocks == pristine.scripts[name].blocks),
			cfg.root+": complete native conditions, bodies and saved indexes stay unchanged")
		for name: String in names:
			for part: String in ["missing","parameter","condition","body"]:
				var changed := ScriptParser.parse(raw)
				if part == "missing": changed.scripts.erase(name)
				elif part == "parameter": changed.scripts[name].params.append("extra")
				elif part == "condition": changed.scripts[name].blocks[0].conds.append([ScriptParser.N_NUM,0.0])
				else: changed.scripts[name].blocks[0].body.append([ScriptParser.S_CALL,"Nop",[]])
				Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
				check(marked(changed,cfg.checks).is_empty(),cfg.root+": fail closed on "+part+" of "+name)
		for name: String in cfg.checks:
			var changed := ScriptParser.parse(raw)
			# Every inspected predicate ends in its authored radius or Y bound.
			changed.scripts[name].blocks[0].conds[0][2][-1][1] += 1.0
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(marked(changed,cfg.checks).is_empty(),cfg.root+": fail closed on changed geometry of "+name)
		var changed_loop := ScriptParser.parse(raw)
		changed_loop.scripts[cfg.root].blocks[0].body[1][2] = [ScriptParser.N_VAR,"OtherHeroes"]
		Compat.apply(changed_loop,CampaignProfile.ORIGINAL,"gz19h")
		var other: Dictionary = FAMILIES[1] if cfg == FAMILIES[0] else FAMILIES[0]
		check(marked(changed_loop,cfg.checks).is_empty() and marked(changed_loop,other.checks) == other.checks,
			cfg.root+": changed registration group is rejected independently of the other family")
		for mode: String in ["missing","duplicate","different_argument"]:
			var changed := ScriptParser.parse(raw)
			var call := [ScriptParser.S_CALL,cfg.root,[[ScriptParser.N_VAR,"NULL"]]]
			if mode == "missing": changed.world.erase(call)
			else:
				if mode == "different_argument": call[2][0] = [ScriptParser.N_NUM,1.0]
				changed.world.append(call)
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(marked(changed,cfg.checks).is_empty(),cfg.root+": fail closed on "+mode+" startup call")
	var all_checks: Array = FAMILIES[0].checks+FAMILIES[1].checks
	check(adapted.scripts.keys().filter(func(name):return adapted.scripts[name].get("party_check",false)).size() == all_checks.size(),
		"no unrelated prison check gains shared eligibility")
	for mode: String in ["missing","duplicate","replacement","conflicting_assignment"]:
		var changed := ScriptParser.parse(raw)
		var binding := [ScriptParser.S_SET,"HChest1",[ScriptParser.N_CALL,"GetObjectByID",[[ScriptParser.N_STR,"736257"]]]]
		if mode in ["duplicate","conflicting_assignment"]:
			if mode == "conflicting_assignment": binding[2][2][0][1] = "980428"
			changed.world.append(binding)
		else:
			changed.world.erase(binding)
			if mode == "replacement":
				binding[2][2][0][1] = "980428"
				changed.world.append(binding)
		Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
		check(marked(changed,all_checks).is_empty(),"fail closed on "+mode+" HChest1 binding")
	for scope: Array in [[CampaignProfile.ASTRAL,"gz19h"],[CampaignProfile.ORIGINAL,"gz18h"]]:
		var outside := ScriptParser.parse(raw)
		Compat.apply(outside,scope[0],scope[1])
		check(marked(outside,all_checks).is_empty(),"discovery adaptation stays in original gz19h: "+str(scope))
	check(adapted.world == pristine.world,"startup body and its instruction positions are unchanged")
	check(["VCheck#0#286","VCheck#0#281","VTriger#0#288"].all(func(name):return adapted.scripts[name] == pristine.scripts[name]),
		"HChest2 opening, reward and quest completion remain completely authored")
	var before := adapted.scripts.duplicate(true)
	Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(adapted.scripts == before,"repeated source adaptation is idempotent")

func eligibility() -> void:
	for cfg: Dictionary in FAMILIES:
		for i in cfg.checks.size():
			var vm := fixture(); starts(vm,cfg.root)
			var guest := actor(1,cfg.points[i])
			check(vm._world_event(cfg.checks[i]),cfg.checks[i]+": existing VM analysis confirms a quest-only action chain")
			step(vm,4)
			var chest: bool = i == cfg.checks.size()-1
			check(s.state.get_var(0,cfg.quest+".2") == (2 if chest else 1),cfg.checks[i]+": late guest executes the original stage")
			check(vm._world_done.get(cfg.checks[i]) == 1,cfg.checks[i]+": selected shared check records the guest's event ownership")
			check(leader.pos == Vector2(10,10) and guest.pos == cfg.points[i],cfg.checks[i]+": no actor is moved to a story role")
		for inactive: String in ["dead","hidden","disconnected"]:
			var vm := fixture(); starts(vm,cfg.root)
			var guest := actor(1,cfg.points[0])
			guest.dead = inactive == "dead"; guest.hidden = inactive == "hidden"
			if inactive == "disconnected": guest.controller = -1
			step(vm,4)
			check(s.state.get_var(0,cfg.quest) == 0,cfg.root+": ignores "+inactive+" guest")
			guest.dead = false; guest.hidden = false; guest.controller = 1
			step(vm,4)
			check(s.state.get_var(0,cfg.quest) == 1,cfg.root+": eligible returning guest activates original discovery")
		for mode: String in ["solo","lmp"]:
			var vm := fixture()
			if mode == "solo": s.online = false
			else: s.lmp = {"test":true}
			starts(vm,cfg.root); actor(1,cfg.points[0]); step(vm,4)
			check(s.state.get_var(0,cfg.quest) == 0,cfg.root+": "+mode+" retains original per-character eligibility")
			leader.pos = cfg.points[0]; step(vm,4)
			check(s.state.get_var(0,cfg.quest) == 1,cfg.root+": native protagonist still triggers in "+mode)

func saved_states() -> void:
	for cfg: Dictionary in FAMILIES:
		var vm := fixture(false); starts(vm,cfg.root)
		var pending := vm.save_state()
		var source_bytes := var_to_bytes(pending)
		vm = fixture(); vm._restore(pending)
		check(vm.instances.size() == cfg.checks.size() and vm.instances.all(func(inst):return inst.frames.is_empty() and not inst.killed),
			cfg.root+": old unmarked save restores the original native waits without another registrar")
		# Its original owner is deliberately absent at the next load. A shared
		# predicate must accept another live actor without rebinding that owner.
		vm = fixture(); leader.controller = -1; vm._restore(pending)
		check(vm.instances.all(func(inst):return inst.locals.get("this") == null),cfg.root+": old wait owner can be absent during restore")
		actor(1,cfg.points[0]); step(vm,4)
		check(s.state.get_var(0,cfg.quest) == 1,cfg.root+": old absent-owner wait accepts an eligible late guest")
		check(var_to_bytes(pending) == source_bytes,cfg.root+": restore leaves the old native snapshot immutable")
		# Per-check one-shot test: only the first predicate is true at this
		# point. Other authored approach predicates may legitimately reach the
		# same idempotent GSSetVarMax body later; that native behavior is intact.
		vm = fixture(); starts(vm,cfg.root)
		actor(1,cfg.points[0]); actor(2,cfg.points[0])
		vm.spawn(cfg.checks[0],[leader]); step(vm,4)
		check(vm.writes.count([0.0,cfg.quest,1.0]) == 1,cfg.root+": duplicate copies of one marked check fire one shared event")
		var completed := vm.save_state()
		var vars := s.state.vars.duplicate(true)
		vm = fixture(); s.state.vars = vars; vm._restore(completed)
		actor(1,cfg.points[0]); vm.spawn(cfg.checks[0],[leader]); step(vm,4)
		check(vm.writes.is_empty() and s.state.get_var(0,cfg.quest) == 1,cfg.root+": saved completed check cannot replay writes for a returning guest")
		# Actual serialized co-op projection preserves the host-owned shared
		# pending wait for the recipient's solo hero without changing its body.
		vm = fixture(); s.online = false; leader.pos = cfg.points[0]
		var marked_zone := Snapshot.mark_zones({"gz19h":{"vm":pending}},1)
		vm._restore(marked_zone.gz19h.vm)
		check(vm.instances.size() == cfg.checks.size() and vm.instances.all(func(inst):return inst.locals.get("this") == leader),
			cfg.root+": guest solo projection retains and maps the shared native waits")
		step(vm,4)
		check(s.state.get_var(0,cfg.quest) == 1,cfg.root+": returned solo hero executes the pending original discovery")
		check(var_to_bytes(pending) == source_bytes,cfg.root+": solo projection cannot mutate the authority snapshot")
		evidence.cases.append({"root":cfg.root,"quest":cfg.quest,"pending":pending,"spent_world_done":completed.world_done})

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	evidence.original_script_sha256 = raw.sha256_text()
	definitions()
	eligibility()
	saved_states()
	for vm: ProbeVM in vms: vm.briefings = null; vm.world = null; vm.session = null
	for node: Node in allocations:
		if node is GameWorld: node.vm = null; node.ai = null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	evidence.merge({"checks":checks,"failures":failures,
		"scope":"Original parsed source, prepared actor/chest positions and explicit native registration in a focused VM state fixture. The separate real ENet original-startup early/late controls establish actual registration reachability. No rendering, full-route or network timing claim."})
	FileAccess.open("user://prison-discovery-state.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_DISCOVERY_STATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
