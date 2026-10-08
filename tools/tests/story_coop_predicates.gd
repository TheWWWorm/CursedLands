extends Node
## Actual map scripts with controlled perception inputs; effect dispatch is
## recorded so unrelated combat, cutscenes and pathfinding cannot mask gates.
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []
var vms: Array[ProbeVM] = []
var raw := {}
var s: Session
var party: Array[GameUnit] = []
var observer: GameUnit
var guard: GameUnit

class ProbeSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var seen := {}
	var actions: Array = []
	func _sees_has(watchers: Array, target) -> bool:
		return watchers.any(func(w):return seen.get(w,[]).has(target))
	func _call(name: String, args: Array, inst: Instance):
		if name in ["Attack","Run","UMSentry","CastSpellPoint","CreateFX","QuestComplete","GameOverMSG","KillUnit","RemoveUnitFromServer"]:
			var values := _args(args,inst)
			actions.append({"name":name,"args":values,"time":time})
			if name == "KillUnit" and _unit(values[0]): values[0].dead = true
			if name == "RemoveUnitFromServer" and _unit(values[0]):
				globals.get("Green",[]).erase(values[0]); world.erase_unit(values[0].uid)
			return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func actor(uid: int, pos: Vector2, owner := -1, hero := {}) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u)
	u.uid = uid; u.pos = pos; u.controller = owner; u.world = s.world
	u.info = {"name":"test","complexion":Vector3.ONE}; u.proto = {"name":"Human Hero"}
	if not hero.is_empty(): u.set_meta("hero",hero)
	s.world.set_unit(uid,u)
	return u

func fixture() -> void:
	s = ProbeSession.new(); allocations.append(s)
	s.state = CampaignState.new(); s.world = GameWorld.new(); allocations.append(s.world)
	s.world.session = s; s.world.ai = UnitAI.new(s.world)
	s.state.ensure_hero(0,"Human Hero"); s.state.ensure_hero(1,"Human Hero","Guest A"); s.state.ensure_hero(2,"Human Hero","Guest B")
	var kel: Dictionary = s.state.heroes[0][0].duplicate(true)
	kel.merc = 2; kel.unit_name = "merc2"; kel.party = ""; kel.controller = 1; s.state.mercs[2] = kel
	party = [actor(1500000001,Vector2(200,200),0,s.state.heroes[0][0]),actor(ScriptVM.name_id("merc2"),Vector2(220,220),1,kel),
		actor(1500000002,Vector2(240,240),1,s.state.heroes[1][0]),actor(1500000003,Vector2(260,260),2,s.state.heroes[2][0])]
	observer = actor(1012005,Vector2(0,0)); guard = actor(1002004,Vector2(0,0))
	actor(1002002,Vector2(20,0)); actor(1002003,Vector2(30,0)); actor(1017004,Vector2.ZERO)
	actor(1017002,Vector2(20,0)); actor(1017003,Vector2(30,0)); actor(1012001,Vector2.ZERO)
	actor(1013001,Vector2.ZERO); actor(1013002,Vector2.ZERO)
	var lever := Node3D.new(); allocations.append(lever)
	lever.set_meta("ei",{"nid":1002001,"position":Vector3.ZERO}); s.world.objects[1002001] = lever
	s.world.levers[1002001] = {"state":1,"enabled":true}

func vm_for(zone: String, mob: String, adapt := true) -> ProbeVM:
	if not raw.has(mob): raw[mob] = EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text
	var vm := ProbeVM.new(); vms.append(vm); vm.world = s.world; vm.session = s; s.world.vm = vm
	s.world.zone = {"id":zone,"type":"game"}; vm.ast = ScriptParser.parse(raw[mob]); vm.briefings = Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,s.state.campaign_id,zone)
	vm.globals = {"Heroes":party.duplicate(),"CityGuard":[guard],"Citiezens":[observer],"VGuard":[observer]}
	for i in [1,3,4]: vm.areas[i] = [Rect2(-500,-500,1000,1000)]
	return vm

func start(vm: ProbeVM, name: String, who = null) -> ScriptVM.Instance:
	vm.spawn(name,[who]); var inst: ScriptVM.Instance = vm.instances.back(); vm._run(inst); return inst

func step(vm: ProbeVM, count := 1) -> void:
	for i in count:
		vm.time += ScriptVM.POLL
		var list := vm.instances.duplicate(); list.reverse()
		for inst: ScriptVM.Instance in list: vm._run(inst)
		vm.instances = vm.instances.filter(func(x):return not x.killed or not x.frames.is_empty())

func actions(vm: ProbeVM, name: String) -> Array:
	return vm.actions.filter(func(x):return x.name == name)

func alarms() -> void:
	for row: Array in [["gz10g","zone10","VCityGuard#0#2"],["gz15g","zone15","VCityGuard#0#2"],["gz3d1","zone3dun1","VGAlarm#0#2"]]:
		fixture(); var vm := vm_for(row[0],row[1]); vm.seen = {observer:[party[2]],guard:[party[2]]}
		var inst := start(vm,row[2])
		check(inst.killed,row[1]+": extra guest can trigger original alarm")
		if row[0] == "gz3d1":
			check(s.state.get_var(0,"q.gz3d1.q13oh.5") == 3 and actions(vm,"GameOverMSG").is_empty(),"Prison alarm keeps its quest outcome and delayed failure")
			step(vm,32); check(actions(vm,"GameOverMSG").size() == 1,"Prison alarm completes original failure once")
		else:
			step(vm,2); check(actions(vm,"Attack").size() == 1,"City alarm starts original guard attack chain")
		for inactive in ["dead","hidden","disconnected"]:
			party[2].dead = inactive == "dead"; party[2].hidden = inactive == "hidden"; party[2].controller = -1 if inactive == "disconnected" else 1
			vm = vm_for(row[0],row[1]); vm.seen = {observer:[party[2]],guard:[party[2]]}; inst = start(vm,row[2])
			check(not inst.killed,row[1]+": ignored "+inactive+" extra guest")
		party[2].dead = false; party[2].hidden = false; party[2].controller = 1
		vm = vm_for(row[0],row[1]); vm.seen = {observer:[party[1]],guard:[party[1]]}; inst = start(vm,row[2])
		check(inst.killed,row[1]+": guest-owned Kel retains native alarm")
	fixture()
	for name in ["VCheck#5#2","VCheck#5#3"]:
		var vm := vm_for("gz1h","zone1"); vm.seen[observer] = [party[2]]
		var inst := start(vm,name)
		check(not inst.killed,name+": visible guest prevents unseen-party quest progress")
		vm.seen.clear(); step(vm)
		check(inst.killed,name+": progress resumes when whole party is unseen")

func nearest() -> void:
	for row: Array in [["gz10g","zone10","VCityGuard#1#0",1,false],["gz15g","zone15","VCityGuard#1#0",1,false],
		["gz16g","zone16","VCheck#0#6",1,false],["gz21k","zone21","VCheck#1#3",3,true],["gz21k","zone21","VCheck#6#2",3,true]]:
		fixture(); party[0].pos = Vector2(10,0); party[1].pos = Vector2(-15,0); party[2].pos = Vector2(2,0); party[3].pos = Vector2(30,0)
		var vm := vm_for(row[0],row[1]); start(vm,row[2],guard)
		check(actions(vm,"Attack").size() == row[3] and actions(vm,"Attack").all(func(x):return x.args[1] == party[2]),row[2]+": coordinated attack chooses closer guest")
		party[3].pos = Vector2(1,0); vm = vm_for(row[0],row[1]); start(vm,row[2],guard)
		check(actions(vm,"Attack").all(func(x):return x.args[1] == party[3]),row[2]+": closest of multiple guests wins")
		party[2].hidden = true; party[3].dead = true; vm = vm_for(row[0],row[1]); start(vm,row[2],guard)
		check(actions(vm,"Attack").all(func(x):return x.args[1] == party[0]),row[2]+": inactive extras leave native target")
		party[2].hidden = false; party[3].dead = false; party[2].pos = Vector2(10,0); party[3].pos = Vector2(30,0); party[1].pos = Vector2(-10,0)
		vm = vm_for(row[0],row[1]); start(vm,row[2],guard)
		check(actions(vm,"Attack").all(func(x):return x.args[1] == party[1 if row[4] else 0]),row[2]+": native tie priority retained")
		if row[4]:
			vm = vm_for(row[0],row[1]); vm.areas[1] = []; s.world.levers[1002001].state = 0; start(vm,row[2],guard)
			check(actions(vm,"Attack").is_empty(),row[2]+": original lever/area gate remains required")

func quest_branches() -> void:
	fixture(); party[2].pos = Vector2(13.01,0)
	var vm := vm_for("gz22k","zone22"); var inst := start(vm,"VCheck#2#3")
	check(not inst.killed,"Ingos proximity keeps original 13 metre limit")
	party[2].pos = Vector2(12.99,0); step(vm)
	check(inst.killed and s.state.get_var(0,"q.gz22k.q12k.3") == 1,"Ingos proximity admits extra guest")
	vm = vm_for("gz22k","zone22"); vm.seen[party[2]] = [s.world.units[1013002]]
	s.state.set_var(0,"q.gz22k.q13k",0); inst = start(vm,"VCheck#3#2")
	check(not inst.killed,"Ingos sight event keeps original quest gate")
	s.state.set_var(0,"q.gz22k.q13k",1); step(vm)
	var casts := actions(vm,"CastSpellPoint")
	check(casts.size() == 1 and Vector2(casts[0].args[3],casts[0].args[4]) == party[2].pos,"Ingos sight event fires fireworks at triggering guest")
	var saved := vm.save_state(); vm = vm_for("gz22k","zone22"); vm._restore(saved); step(vm,32)
	check(actions(vm,"CastSpellPoint").is_empty() and actions(vm,"QuestComplete").size() == 1 and s.state.get_var(0,"q.gz22k.q13k") == 2,"Saved guest event resumes reward without replaying fireworks")
	var fx := actions(vm,"CreateFX")
	check(fx.size() == 1 and Vector2(fx[0].args[0],fx[0].args[1]) == party[0].pos,"Companion acknowledgement stays at original protagonist")
	step(vm,62)
	check(actions(vm,"RemoveUnitFromServer").size() == 2 and s.state.get_var(0,"z.bz22k") == 2,"Guest event completes original delayed NPC departure")
	fixture(); vm = vm_for("gz22k","zone22",false); vm.seen[party[1]] = [s.world.units[1013002]]; s.state.set_var(0,"q.gz22k.q13k",1)
	start(vm,"VCheck#3#2"); saved = vm.save_state(); vm = vm_for("gz22k","zone22"); vm._restore(saved); step(vm,32)
	check(actions(vm,"CastSpellPoint").is_empty() and actions(vm,"QuestComplete").size() == 1,"Old companion branch save resumes at original instruction")

func green_trace(vm: ProbeVM) -> Array:
	return vm.actions.map(func(x):return [x.name,x.args.map(func(v):return v.uid if v is GameUnit else v),x.time])

func green() -> void:
	for row: Array in [["gz32j","zone32"],["gz34j","zone34"],["gz35j","zone35"]]:
		fixture(); var mine := actor(909,Vector2(20,30)); var other := actor(910,Vector2(60,30)); actor(911,mine.pos,1)
		var vm := vm_for(row[0],row[1]); vm.globals.Green = [mine,other]
		start(vm,"Caboom#1#1"); start(vm,"Caboom#2#1"); step(vm,4)
		check(not mine.dead,row[1]+": pet without hero/script control does not trigger indexed party mines")
		party[2].pos = mine.pos; party[2].hidden = true; step(vm,3)
		check(not mine.dead,row[1]+": hidden extra does not trigger mine")
		party[2].hidden = false; step(vm,12)
		check(mine.dead and not other.dead,row[1]+": only Green creature near guest is killed")
		var casts := actions(vm,"CastSpellPoint")
		check(casts.size() == 1 and Vector2(casts[0].args[3],casts[0].args[4]) == mine.pos and actions(vm,"RemoveUnitFromServer").size() == 1,row[1]+": original death chain explodes and removes the creature once")
		party[2].pos = other.pos; step(vm,16)
		var guest_trace := green_trace(vm)
		check(other.dead and actions(vm,"CastSpellPoint").size() >= 2,row[1]+": original rearm chain covers later guest proximity")
		# The original repeatedly creates waiting threads for all Green units.
		# Compare its full multi-wave dispatch, rather than imposing a new
		# single-cast rule on the pre-existing death-chain implementation.
		fixture(); mine = actor(909,Vector2(20,30)); other = actor(910,Vector2(60,30))
		vm = vm_for(row[0],row[1],false); vm.globals.Green = [mine,other]
		start(vm,"Caboom#1#1"); start(vm,"Caboom#2#1"); step(vm,7)
		party[1].pos = mine.pos; step(vm,12); party[1].pos = other.pos; step(vm,16)
		check(guest_trace == green_trace(vm),row[1]+": guest multi-wave timing and effects match original companion")

func structural() -> void:
	for row: Array in [["gz1h","zone1"],["gz3d1","zone3dun1"],["gz10g","zone10"],["gz15g","zone15"],["gz16g","zone16"],
		["gz21k","zone21"],["gz22k","zone22"],["gz32j","zone32"],["gz34j","zone34"],["gz35j","zone35"]]:
		fixture(); var original := vm_for(row[0],row[1],false).ast; var current := vm_for(row[0],row[1]).ast
		var lengths := current.world == original.world
		for name: String in original.scripts:
			for i in original.scripts[name].blocks.size():
				lengths = lengths and original.scripts[name].blocks[i].body.size() == current.scripts[name].blocks[i].body.size()
		check(lengths,row[1]+": original startup and saved body indexes remain")
		var before := current.scripts.duplicate(true); Compat.apply(current,s.state.campaign_id,row[0])
		check(before == current.scripts,row[1]+": adaptation is idempotent")
		before = original.scripts.duplicate(true); Compat.apply(original,CampaignProfile.ORIGINAL,row[0])
		check(before == original.scripts,row[1]+": original campaign stays outside adaptation")

func _ready() -> void:
	alarms(); nearest(); quest_branches(); green(); structural()
	for vm: ProbeVM in vms: vm.briefings = null; vm.instances.clear(); vm.globals.clear(); vm.seen.clear(); vm.actions.clear()
	vms.clear()
	for n: Node in allocations:
		if n is GameWorld: n.units = {}; n.objects.clear(); n.vm = null
	for n: Node in allocations: n.free()
	print("STORY_COOP_PREDICATES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
