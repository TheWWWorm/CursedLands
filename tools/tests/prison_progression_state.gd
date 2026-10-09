extends "./prison_late_join.gd"
## Source-admitted shared checks with controlled actors. Network reachability
## is independently exercised through original WorldScript by the ENet fixture.
const Snapshot := preload("res://src/game/script/coop_vm_state.gd")
const FAMILIES := [
	{"root":"VTriger#0#13","checks":["VCheck#0#17"],"triggers":["VTriger#0#19"],
		"points":[Vector2(405,430)],"stages":[{"q.gz19h.q71h":2.0,"q.gz19h.q71h.1":2.0}]},
	{"root":"VTriger#0#296","checks":["VCheck#0#295","VCheck#0#300"],
		"triggers":["VTriger#0#298","VTriger#0#302"],"points":[Vector2(101,250),Vector2(240,46)],
		"stages":[{"q.gz19h.q72h.2":2.0,"q.gz19h.q72h.3":1.0},
			{"q.gz19h.q72h.3":2.0,"q.gz19h.q72h.20":1.0,"q.gz19h.q72h.34":2.0}]},
	{"root":"VTriger#0#333","checks":["VCheck#0#338","VCheck#0#344","VCheck#0#348","VCheck#0#355","VCheck#0#357","VCheck#0#364"],
		"triggers":["VTriger#0#326","VTriger#0#346","VTriger#0#350","VTriger#0#359","VTriger#0#371","VTriger#0#366"],
		"points":[Vector2(326.25,118.25),Vector2(450,105),Vector2(410,170),Vector2(432.75,74.25),Vector2(445.75,84.75),Vector2(391.25,276.25)],
		"stages":[{"q.gz19h.q72h.10":2.0,"q.gz19h.q72h.11":1.0,"q.gz19h.q72h.8":1.0},
			{"q.gz19h.q72h.22":2.0},{"q.gz19h.q72h.16":2.0},
			{"q.gz19h.q72h.23":2.0,"q.gz19h.q72h.24":1.0},
			{"q.gz19h.q72h.25":2.0,"q.gz19h.q72h.26":1.0},
			{"q.gz19h.q72h.6":2.0,"q.gz19h.q72h.7":1.0,"q.gz19h.q72h.4":1.0}]},
]
const BINDINGS := {"MC3":45627,"TCP-B":43974,"TCP-A":43968,"MC1":45622}
var evidence := {"cases":[]}

func fixture(adapt := true) -> ProbeVM:
	s = QuietSession.new(); allocations.append(s); s.online = true
	s.state = CampaignState.new(); s.state.campaign_id = CampaignProfile.ORIGINAL
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s
	s.world.ai = UnitAI.new(s.world); s.world.zone = {"id":"gz19h"}
	leader = actor(0)
	var vm := ProbeVM.new(); vms.append(vm); vm.session = s; vm.world = s.world; s.world.vm = vm
	vm.ast = ScriptParser.parse(raw); vm.briefings = Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz19h")
	vm.globals = {"Heroes":[leader]}
	var points := [Vector2(326.25,118.25),Vector2(432.75,74.25),Vector2(445.75,84.75),Vector2(391.25,276.25)]
	for i in BINDINGS.size():
		var key: String = BINDINGS.keys()[i]
		var object := Node3D.new(); allocations.append(object)
		object.set_meta("ei",{"nid":BINDINGS[key],"position":Vector3(points[i].x,points[i].y,0)})
		s.world.objects[BINDINGS[key]] = object
		vm.globals[key] = object
	return vm

func marked(ast: ScriptParser, names: Array) -> Array:
	return names.filter(func(name):return ast.scripts.get(name,{}).get("party_check",false))

func stage_matches(stages: Dictionary) -> bool:
	return stages.keys().all(func(key):return s.state.get_var(0,key) == stages[key])

func definitions() -> void:
	var native := ScriptParser.parse(raw)
	var adapted := ScriptParser.parse(raw)
	Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(native.errors.is_empty() and adapted.errors.is_empty(),"mounted original source parses cleanly")
	var all_checks := ["VCheck#0#265","VCheck#0#269","VCheck#0#271","VCheck#0#258","VCheck#0#279","VCheck#0#280"]
	for cfg: Dictionary in FAMILIES:
		all_checks.append_array(cfg.checks)
		check(marked(adapted,cfg.checks) == cfg.checks,cfg.root+": exactly the inspected family checks are admitted")
		var names: Array = [cfg.root]+cfg.checks+cfg.triggers
		check(names.all(func(name):return adapted.scripts[name].params == native.scripts[name].params \
			and adapted.scripts[name].blocks == native.scripts[name].blocks),
			cfg.root+": all native conditions, bodies and instruction indexes remain identical")
		for name: String in names:
			for part: String in ["missing","parameter","condition","body"]:
				var changed := ScriptParser.parse(raw)
				if part == "missing": changed.scripts.erase(name)
				elif part == "parameter": changed.scripts[name].params.append("extra")
				elif part == "condition": changed.scripts[name].blocks[0].conds.append([ScriptParser.N_NUM,0.0])
				else: changed.scripts[name].blocks[0].body.append([ScriptParser.S_CALL,"Run",[[ScriptParser.N_VAR,"this"]]])
				Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
				check(marked(changed,cfg.checks).is_empty(),cfg.root+": reject "+part+" of "+name)
		for name: String in cfg.checks:
			var changed := ScriptParser.parse(raw)
			changed.scripts[name].blocks[0].conds[0][2][-1][1] += 1.0
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(marked(changed,cfg.checks).is_empty(),cfg.root+": reject changed geometry of "+name)
		for mode: String in ["missing","duplicate","different_argument"]:
			var changed := ScriptParser.parse(raw)
			var call := [ScriptParser.S_CALL,cfg.root,[[ScriptParser.N_VAR,"NULL"]]]
			if mode == "missing": changed.world.erase(call)
			else:
				if mode == "different_argument": call[2][0] = [ScriptParser.N_NUM,1.0]
				changed.world.append(call)
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(marked(changed,cfg.checks).is_empty(),cfg.root+": reject "+mode+" startup registration")
		var changed := ScriptParser.parse(raw)
		changed.scripts[cfg.root].blocks[0].body[1][2] = [ScriptParser.N_VAR,"OtherHeroes"]
		Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
		check(marked(changed,cfg.checks).is_empty() and FAMILIES.filter(func(other):return other != cfg).all(
			func(other):return marked(changed,other.checks) == other.checks),cfg.root+": changed group rejects this family independently")
	for key: String in BINDINGS:
		for mode: String in ["missing","duplicate","replacement","conflicting_assignment"]:
			var changed := ScriptParser.parse(raw)
			var binding := [ScriptParser.S_SET,key,[ScriptParser.N_CALL,"GetObjectByID",[[ScriptParser.N_STR,str(BINDINGS[key])]]]]
			if mode in ["duplicate","conflicting_assignment"]:
				if mode == "conflicting_assignment": binding[2][2][0][1] = "123456"
				changed.world.append(binding)
			else:
				changed.world.erase(binding)
				if mode == "replacement":
					binding[2][2][0][1] = "123456"
					changed.world.append(binding)
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(marked(changed,FAMILIES[2].checks).is_empty(),"reject "+mode+" landmark binding "+key)
	check(marked(adapted,adapted.scripts.keys()).size() == all_checks.size() and marked(adapted,all_checks) == all_checks,
		"only the six qualified discoveries and nine inspected route checks are shared")
	for scope: Array in [[CampaignProfile.ASTRAL,"gz19h"],[CampaignProfile.ORIGINAL,"gz18h"]]:
		var outside := ScriptParser.parse(raw)
		Compat.apply(outside,scope[0],scope[1])
		check(FAMILIES.all(func(cfg):return marked(outside,cfg.checks).is_empty()),"route adaptation is absent outside original gz19h: "+str(scope))
	check(adapted.world == native.world,"original startup statements and indexes remain unchanged")
	check(["VCheck#0#12","VTriger#0#15","VCheck#0#26","VCheck#0#27","VTriger#0#29","VCheck#0#32","VCheck#0#33","VTriger#0#35"].all(
		func(name):return adapted.scripts[name] == native.scripts[name]),"portal gate, completion, rewards and travel are untouched")
	var before := adapted.scripts.duplicate(true)
	Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(adapted.scripts == before,"repeated adaptation is idempotent")

func eligibility() -> void:
	for cfg: Dictionary in FAMILIES:
		for i in cfg.checks.size():
			var vm := fixture(); starts(vm,cfg.root)
			var guest := actor(1,cfg.points[i]); step(vm,4)
			check(vm._world_event(cfg.checks[i]),cfg.checks[i]+": VM independently accepts only shared actions")
			check(stage_matches(cfg.stages[i]),cfg.checks[i]+": late guest executes every original stage assignment")
			check(vm._world_done.get(cfg.checks[i]) == 1,cfg.checks[i]+": shared event records the real guest")
			check(leader.pos == Vector2(10,10) and guest.pos == cfg.points[i],cfg.checks[i]+": neither actor is moved")
		for inactive: String in ["dead","hidden","disconnected"]:
			var vm := fixture(); starts(vm,cfg.root)
			var guest := actor(1,cfg.points[0])
			guest.dead = inactive == "dead"; guest.hidden = inactive == "hidden"
			if inactive == "disconnected": guest.controller = -1
			step(vm,4)
			check(vm.writes.is_empty(),cfg.root+": ignores "+inactive+" guest")
			guest.dead = false; guest.hidden = false; guest.controller = 1
			step(vm,4)
			check(stage_matches(cfg.stages[0]),cfg.root+": newly eligible "+inactive+" guest resumes the pending stage")
		for mode: String in ["solo","lmp"]:
			var vm := fixture()
			if mode == "solo": s.online = false
			else: s.lmp = {"test":true}
			starts(vm,cfg.root); actor(1,cfg.points[0]); step(vm,4)
			check(vm.writes.is_empty(),cfg.root+": "+mode+" retains native actor eligibility")
			leader.pos = cfg.points[0]; step(vm,4)
			check(stage_matches(cfg.stages[0]),cfg.root+": original protagonist still works in "+mode)

func saved_states() -> void:
	for cfg: Dictionary in FAMILIES:
		var vm := fixture(false); starts(vm,cfg.root)
		var pending := vm.save_state()
		var source_bytes := var_to_bytes(pending)
		vm = fixture(); vm._restore(pending)
		check(vm.instances.size() == cfg.checks.size() and vm.instances.all(func(inst):return inst.frames.is_empty() and not inst.killed),
			cfg.root+": old unmarked save restores exact original waits without new registration")
		vm = fixture(); leader.controller = -1; vm._restore(pending)
		check(vm.instances.all(func(inst):return inst.locals.get("this") == null),cfg.root+": native owner may be absent during restore")
		actor(1,cfg.points[0]); step(vm,4)
		check(stage_matches(cfg.stages[0]),cfg.root+": late guest advances an old absent-owner wait")
		vm = fixture(); starts(vm,cfg.root)
		actor(1,cfg.points[0]); actor(2,cfg.points[0]); vm.spawn(cfg.checks[0],[leader]); step(vm,4)
		var first: String = cfg.stages[0].keys()[0]
		check(vm.writes.count([0.0,first,cfg.stages[0][first]]) == 1,cfg.root+": duplicates and simultaneous guests execute one shared assignment")
		var completed := vm.save_state()
		var vars := s.state.vars.duplicate(true)
		vm = fixture(); s.state.vars = vars; vm._restore(completed)
		actor(1,cfg.points[0]); vm.spawn(cfg.checks[0],[leader]); step(vm,4)
		check(vm.writes.is_empty() and stage_matches(cfg.stages[0]),cfg.root+": saved spent check never replays on rejoin")
		vm = fixture(); s.online = false; leader.pos = cfg.points[0]
		var projected := Snapshot.mark_zones({"gz19h":{"vm":pending}},1)
		vm._restore(projected.gz19h.vm)
		check(vm.instances.size() == cfg.checks.size() and vm.instances.all(func(inst):return inst.locals.get("this") == leader),
			cfg.root+": guest solo projection retains and rebinds all original waits")
		step(vm,4)
		check(stage_matches(cfg.stages[0]),cfg.root+": returned solo hero advances the pending native stage")
		check(var_to_bytes(pending) == source_bytes,cfg.root+": restore and solo projection preserve the source snapshot")
		evidence.cases.append({"root":cfg.root,"pending":pending,"spent_world_done":completed.world_done})

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	evidence.original_script_sha256 = raw.sha256_text()
	definitions(); eligibility(); saved_states()
	for vm: ProbeVM in vms: vm.briefings = null; vm.world = null; vm.session = null
	for node: Node in allocations:
		if node is GameWorld: node.vm = null; node.ai = null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	evidence.merge({"checks":checks,"failures":failures,
		"scope":"Mounted original source, prepared actors/landmarks and native registration in a focused VM fixture. The separate actual ENet fixture proves startup reachability. No rendered, route-navigation, reward-economy or performance acceptance."})
	FileAccess.open("user://prison-progression-state.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_PROGRESSION_STATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
