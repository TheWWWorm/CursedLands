extends Node
## Native prison quest rectangles and discovery threads, with controlled
## positions. No simulation, rendering or rewards are replaced by assertions.
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []
var vms: Array[ProbeVM] = []
var raw := ""
var s: Session
var leader: GameUnit

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var writes: Array = []
	func _call(name: String, args: Array, inst: Instance):
		if name in ["GSSetVar","GSSetVarMax"]: writes.append(_args(args,inst))
		if name == "SendStringEvent": return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func actor(owner: int, at := Vector2(10,10)) -> GameUnit:
	s.state.ensure_hero(owner,"Human Hero","Guest "+str(owner))
	var u := GameUnit.new(); allocations.append(u)
	u.uid = 1500000001+owner; u.controller = owner; u.pos = at; u.world = s.world
	u.info = {"name":"Hero"+str(owner),"complexion":Vector3.ONE}; u.proto = {"name":"Human Hero"}
	u.set_meta("hero",s.state.heroes[owner][0]); s.world.set_unit(u.uid,u)
	return u

func fixture(adapt := true) -> ProbeVM:
	s = QuietSession.new(); allocations.append(s); s.online = true
	s.state = CampaignState.new(); s.state.campaign_id = CampaignProfile.ORIGINAL
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s
	s.world.ai = UnitAI.new(s.world); s.world.zone = {"id":"gz15h"}
	leader = actor(0)
	var vm := ProbeVM.new(); vms.append(vm); vm.session = s; vm.world = s.world; s.world.vm = vm
	vm.ast = ScriptParser.parse(raw); vm.briefings = Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz15h")
	vm.globals = {"Heroes":[leader]}
	for key: String in ["Healing01","Healing02","Healing03","MainGates","HSecondBridge"]:
		var obj := Node3D.new(); allocations.append(obj)
		obj.set_meta("ei",{"position":Vector3(300,300,0)}); vm.globals[key] = obj
	return vm

func step(vm: ProbeVM, count: int) -> void:
	for i in count:
		vm._refresh_heroes(); vm.time += ScriptVM.POLL
		var current := vm.instances.duplicate(); current.reverse()
		for inst: ScriptVM.Instance in current: vm._run(inst)
		vm.instances = vm.instances.filter(func(inst): return not inst.killed or not inst.frames.is_empty())

func starts(vm: ProbeVM, parent: String) -> void:
	vm.spawn(parent,[null]); step(vm,2)

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone15.mob")).script_text
	var rows := [
		["VTriger#0#43",Vector2(50,275),"q.gz15h.qh1h",1],
		["VTriger#0#48",Vector2(244,50),"q.gz15h.qh2h",1],
		["VTriger#0#109",Vector2(209,318),"q.gz15h.q60h",2],
		["VTriger#0#236",Vector2(112,319),"q.gz15h.q62h.6",1],
		["VTriger#0#257",Vector2(200,319),"q.gz15h.q60h.1",2],
		["VTriger#0#290",Vector2(300,300),"q.gz15h.qh3h",1],
		["VTriger#0#294",Vector2(300,300),"q.gz15h.qh4h",1],
		["VTriger#0#295",Vector2(300,300),"q.gz15h.qh5h",1],
	]
	for row: Array in rows:
		var vm := fixture(); s.state.set_var(0,"q.gz15h.q60h",1); s.state.set_var(0,"q.gz15h.q62h",1)
		starts(vm,row[0]); var u := actor(1,row[1]); step(vm,4)
		check(s.state.get_var(0,row[2]) == row[3],row[0]+": late guest activates original quest/discovery")
		check(leader.pos == Vector2(10,10),row[0]+": host can remain away from the trigger")
		check(u.pos == row[1],row[0]+": guest is not teleported to a native role")
	for inactive: String in ["dead","hidden","disconnected"]:
		var vm := fixture(); s.state.set_var(0,"q.gz15h.q60h",1); starts(vm,"VTriger#0#109")
		var u := actor(1,Vector2(209,318)); u.dead = inactive=="dead"; u.hidden = inactive=="hidden"; u.controller = -1 if inactive=="disconnected" else 1
		step(vm,4); check(s.state.get_var(0,"q.gz15h.q60h") == 1,"ignores "+inactive+" guest")
		if inactive == "disconnected": u.controller = 1
		else: u.dead = false; u.hidden = false
		step(vm,4); check(s.state.get_var(0,"q.gz15h.q60h") == 2,"eligible returning guest activates quest: "+inactive)
	var vm := fixture(false); s.state.set_var(0,"q.gz15h.q60h",1); starts(vm,"VTriger#0#109")
	var saved := vm.save_state(); vm = fixture(); s.state.set_var(0,"q.gz15h.q60h",1); vm._restore(saved)
	actor(1,Vector2(209,318)); step(vm,4)
	check(s.state.get_var(0,"q.gz15h.q60h") == 2,"native old-save wait accepts a later guest without replaying startup")
	vm = fixture(); starts(vm,"VTriger#0#43"); actor(1,Vector2(50,275)); actor(2,Vector2(50,275))
	vm.spawn("VCheck#0#44",[leader]); step(vm,4)
	check(vm.writes.count([0.0,"q.gz15h.qh1h",1.0]) == 1,"multiple waiting copies and guests fire one shared event")
	saved = vm.save_state(); vm = fixture(); vm._restore(saved); actor(1,Vector2(50,275))
	starts(vm,"VTriger#0#43"); step(vm,4)
	check(vm.writes.is_empty(),"saved completed trigger is not replayed on reconnect/re-registration")
	vm = fixture(); s.online = false; starts(vm,"VTriger#0#43"); actor(1,Vector2(50,275)); step(vm,4)
	check(s.state.get_var(0,"q.gz15h.qh1h") == 0,"ordinary single-player keeps original per-character checks")
	leader.pos = Vector2(50,275); step(vm,4)
	check(s.state.get_var(0,"q.gz15h.qh1h") == 1,"single-player native protagonist trigger still works")
	vm = fixture(); vm.ast.scripts["VTriger#0#268"].blocks[0].body.append([ScriptParser.S_CALL,"Run",[[ScriptParser.N_VAR,"this"]]])
	starts(vm,"VTriger#0#43"); actor(1,Vector2(50,275)); step(vm,4)
	check(s.state.get_var(0,"q.gz15h.qh1h") == 0,"character-specific modified chain is not broadened")
	vm = fixture(); vm.ast.scripts["VTriger#0#43"].blocks[0].body[1][2] = [ScriptParser.N_VAR,"OtherGroup"]
	vm.ast.scripts["VCheck#0#44"].erase("party_check"); Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz15h")
	check(not vm.ast.scripts["VCheck#0#44"].has("party_check"),"modified registration loop is left intact")
	vm = fixture(); var original := ScriptParser.parse(raw)
	check(vm.ast.world == original.world and vm.ast.scripts.keys() == original.scripts.keys(),"native startup and script names stay unchanged")
	var bodies_unchanged := true
	for name: String in original.scripts:
		if vm.ast.scripts[name].blocks != original.scripts[name].blocks: bodies_unchanged = false
	check(bodies_unchanged,"all native conditions, bodies and saved instruction indexes stay unchanged")
	for v: ProbeVM in vms: v.briefings = null; v.world = null; v.session = null
	for node: Node in allocations:
		if node is GameWorld: node.vm = null; node.ai = null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	print("PRISON_LATE_JOIN ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
