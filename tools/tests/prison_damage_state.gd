extends Node
## Native conditions, frames and timers with controlled actor/lever state.
## Damage/spell calls are recorded here; the ENet fixture executes real damage.
const Compat := preload("res://src/game/script/story_compat.gd")
const Traps := preload("res://src/game/script/story_coop_traps.gd")
const Snapshot := preload("res://src/game/script/coop_vm_state.gd")
const REGISTER := "VTriger#0#76"
const REGISTRAR := REGISTER+"#RemakeParticipants"
const WAIT := "VCheck#0#87"
const SLEEP := "VTriger#0#90"
const POINT := Vector2(339,94)
const CHECKS := ["VCheck#0#86",WAIT,"VCheck#0#88","VCheck#0#115","VCheck#0#116","VCheck#0#117",
	"VCheck#0#118","VCheck#0#119","VCheck#0#120","VCheck#0#121","VCheck#0#122"]
const NAMES := [REGISTER,"VTriger#0#113","VCheck#0#86","VTriger#0#150",WAIT,SLEEP,
	"VCheck#0#88","VTriger#0#95","VCheck#0#115","VTriger#0#153","VCheck#0#116","VTriger#0#154",
	"VCheck#0#117","VTriger#0#155","VCheck#0#118","VTriger#0#156","VCheck#0#119","VTriger#0#157",
	"VCheck#0#120","VTriger#0#158","VCheck#0#121","VTriger#0#159","VCheck#0#122","VTriger#0#160"]
const BINDINGS := {"MCK1":45621,"MCK3":45626,"MCK5":45630}
var checks := 0
var failures := 0
var raw := ""
var s: Session
var allocations: Array[Node] = []
var vms: Array[ProbeVM] = []
var evidence := {}

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var actions := []
	func _call(name: String, args: Array, inst: Instance):
		if name in ["InflictDamage","CastSpellPoint"]:
			var values := _args(args,inst)
			var who = values[0] if name == "InflictDamage" else inst.locals.get("this")
			actions.append({"name":name,"script":inst.sname,"time":time,
				"owner":who.controller if who is GameUnit else -99,
				"uid":who.uid if who is GameUnit else -99,
				"dead":who.dead if who is GameUnit else false,
				"amount":values[1] if name == "InflictDamage" else 0})
			return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func actor(owner: int, at := Vector2(100,100)) -> GameUnit:
	s.state.ensure_hero(owner,"Human Hero","Actor "+str(owner))
	var u := GameUnit.new(); allocations.append(u)
	u.uid = 1500000001+owner; u.controller = owner; u.pos = at; u.world = s.world
	u.info = {"name":"Hero"+str(owner),"complexion":Vector3.ONE}; u.proto = {"name":"Human Hero"}
	u.set_meta("hero",s.state.heroes[owner][0]); s.world.set_unit(u.uid,u)
	return u

func setup(owners := [0]) -> Array:
	s = QuietSession.new(); allocations.append(s); s.online = true
	s.state = CampaignState.new(); s.state.campaign_id = CampaignProfile.ORIGINAL
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s
	s.world.ai = UnitAI.new(s.world); s.world.zone = {"id":"gz19h"}
	for key: String in BINDINGS:
		var obj := Node3D.new(); allocations.append(obj)
		obj.set_meta("ei",{"nid":BINDINGS[key],"position":Vector3.ZERO})
		s.world.objects[BINDINGS[key]] = obj; s.world.levers[BINDINGS[key]] = {"state":0}
	var actors := []
	for owner: int in owners: actors.append(actor(owner))
	return actors

func vm_for(adapt := true, changed_alarm := false) -> ProbeVM:
	var vm := ProbeVM.new(); vms.append(vm); vm.session = s; vm.world = s.world; s.world.vm = vm
	vm.ast = ScriptParser.parse(raw); vm.briefings = Briefings.new(vm)
	if changed_alarm: vm.ast.scripts["VCheck#0#230"].blocks[0].conds.append([ScriptParser.N_NUM,0.0])
	if adapt: Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz19h")
	vm.globals = {"Heroes":s.world.party_units()}
	for key: String in BINDINGS: vm.globals[key] = s.world.objects[BINDINGS[key]]
	return vm

func step(vm: ProbeVM, count: int) -> void:
	for i in count:
		vm._refresh_heroes(); vm.time += ScriptVM.POLL
		var current := vm.instances.duplicate(); current.reverse()
		for inst: ScriptVM.Instance in current: vm._run(inst)
		vm.instances = vm.instances.filter(func(inst):return not inst.killed or not inst.frames.is_empty())

func start(vm: ProbeVM) -> void:
	vm.spawn(REGISTER,[null],"WorldScript"); step(vm,4)

func pending(vm: ScriptVM, name: String, who: GameUnit) -> Array:
	return vm.instances.filter(func(inst):return inst.sname == name and inst.locals.get("this") == who \
		and (not inst.killed or not inst.frames.is_empty()))

func row_for(saved: Dictionary, name: String, owner: int) -> Dictionary:
	for row: Dictionary in saved.instances:
		if row.s == name and row.l.get("this") is Dictionary and row.l.this.get("h") == [owner,0]: return row
	return {}

func same_sleep(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.s == b.s and a.l.this == b.l.this \
		and a.k == b.k and a.b == b.b and a.i == b.i and a.f == b.f \
		and is_equal_approx(a.w,b.w) and is_equal_approx(a.p,b.p)

func seen(vm: ScriptVM) -> Array:
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname == REGISTRAR: return inst.locals.get(Traps.SEEN,[])
	return []

func definitions() -> void:
	var native := ScriptParser.parse(raw)
	var adapted := ScriptParser.parse(raw); Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(native.errors.is_empty() and adapted.errors.is_empty(),"mounted original source parses")
	check(adapted.scripts.has(REGISTRAR) and adapted.scripts[REGISTRAR].params.is_empty(),
		"full native damage family admits a parameterless independent registrar")
	check(NAMES.all(func(name):return native.scripts[name] == adapted.scripts[name]),
		"all 24 native definitions remain byte-for-byte equal as parsed data")
	check(CHECKS.all(func(name):return not adapted.scripts[name].get("party_check",false)),
		"individual traps never acquire shared eligibility")
	for name: String in NAMES:
		for mode: String in ["missing","parameter","condition","body"]:
			var changed := ScriptParser.parse(raw)
			if mode == "missing": changed.scripts.erase(name)
			elif mode == "parameter": changed.scripts[name].params.append("extra")
			elif mode == "condition": changed.scripts[name].blocks[0].conds.append([ScriptParser.N_NUM,0.0])
			else: changed.scripts[name].blocks[0].body.append([ScriptParser.S_CALL,"Nop",[]])
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(not changed.scripts.has(REGISTRAR),"reject "+mode+" in native "+name)
	for mode: String in ["sleep","damage","spell","rearm"]:
		var changed := ScriptParser.parse(raw)
		var body: Array = changed.scripts[SLEEP].blocks[0].body
		if mode == "sleep": body[3][2][0][1] += 1.0
		elif mode == "damage": body[2][2][1][1] += 1.0
		elif mode == "spell": body[1][2][0][1] = "poison"
		else: body[4][1] = "VCheck#0#88"
		Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
		check(not changed.scripts.has(REGISTRAR),"changed "+mode+" rejects the complete trap family")
	for mode: String in ["missing","duplicate","changed_argument"]:
		var changed := ScriptParser.parse(raw)
		var call := [ScriptParser.S_CALL,REGISTER,[[ScriptParser.N_VAR,"NULL"]]]
		if mode == "missing": changed.world.erase(call)
		else:
			if mode == "changed_argument": call[2][0] = [ScriptParser.N_NUM,1.0]
			changed.world.append(call)
		Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
		check(not changed.scripts.has(REGISTRAR),"reject "+mode+" startup registration")
	for key: String in BINDINGS:
		for mode: String in ["missing","duplicate","replacement","conflicting_assignment"]:
			var changed := ScriptParser.parse(raw)
			var binding := [ScriptParser.S_SET,key,[ScriptParser.N_CALL,"GetObjectByID",[[ScriptParser.N_STR,str(BINDINGS[key])]]]]
			if mode in ["missing","replacement"]: changed.world.erase(binding)
			if mode in ["replacement","conflicting_assignment"]: binding[2][2][0][1] = "123456"
			if mode != "missing": changed.world.append(binding)
			Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
			check(not changed.scripts.has(REGISTRAR),"reject "+mode+" native lever binding "+key)
	for scope: Array in [[CampaignProfile.ASTRAL,"gz19h"],[CampaignProfile.ORIGINAL,"gz15h"]]:
		var changed := ScriptParser.parse(raw); Compat.apply(changed,scope[0],scope[1])
		check(not changed.scripts.has(REGISTRAR),"damage registrar is absent outside original gz19h: "+str(scope))
	check(native.world == adapted.world,"startup body and saved instruction indexes stay unchanged")
	var again := adapted.scripts.duplicate(true); Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(again == adapted.scripts,"repeated source adaptation is idempotent")
	setup(); var vm := vm_for(true,true)
	check(vm.ast.scripts.has(REGISTRAR) and not vm.ast.scripts.has(Traps.PRISON_REGISTER+Traps.WATCH),
		"changed alarm definitions do not disable the independently admitted damage family")
	s.lmp = {"test":true}; start(vm)
	check(not vm.instances.any(func(inst):return inst.sname == REGISTRAR),"LMP never starts a damage registrar")

func registration() -> void:
	var actors := setup(); var vm := vm_for(); start(vm)
	check(CHECKS.all(func(name):return pending(vm,name,actors[0]).size() == 1),"initial hero has one of each native trap")
	var guest := actor(1); step(vm,4)
	check(CHECKS.all(func(name):return pending(vm,name,guest).size() == 1 \
		and pending(vm,name,actors[0]).size() == 1),"late arrival gains all eleven waits without duplicating early actor")
	var size := vm.instances.size(); Compat.recover(vm); Compat.recover(vm); step(vm,8)
	check(vm.instances.size() == size and seen(vm) == ["h:0:0","h:1:0"],"polling/recovery cannot duplicate either character's registration")
	for inactive: String in ["dead","hidden","disconnected"]:
		setup(); vm = vm_for(); start(vm); guest = actor(1)
		guest.dead = inactive == "dead"; guest.hidden = inactive == "hidden"
		if inactive == "disconnected": guest.controller = -1; guest.set_meta("orphan_of",1)
		step(vm,4)
		check(CHECKS.all(func(name):return pending(vm,name,guest).is_empty()),"new "+inactive+" actor is not armed prematurely")
		guest.dead = false; guest.hidden = false; guest.controller = 1; guest.remove_meta("orphan_of")
		step(vm,4)
		check(CHECKS.all(func(name):return pending(vm,name,guest).size() == 1),"newly eligible "+inactive+" actor gains all original waits once")
	# The original first three predicates are disabled by their own levers.
	actors = setup([0,1]); vm = vm_for(); start(vm)
	for id: int in BINDINGS.values(): s.world.levers[id].state = 1
	actors[1].pos = POINT; step(vm,4)
	check(vm.actions.is_empty(),"authored lever gate prevents late participant damage")
	s.world.levers[BINDINGS.MCK3].state = 0; step(vm,2)
	check(vm.actions.size() == 2 and vm.actions[1].name == "InflictDamage" and vm.actions[1].owner == 1,
		"opening original predicate gate exposes only that actor to native damage call")

func native_trace(adapt: bool, online := true, disconnected := false) -> Array:
	var actors := setup([0,1]); s.online = online
	var vm := vm_for(adapt); start(vm)
	actors[0].pos = POINT; step(vm,2); actors[0].dead = true
	step(vm,17); actors[1].pos = POINT; step(vm,2)
	if disconnected: actors[1].controller = -1; actors[1].set_meta("orphan_of",1)
	step(vm,43)
	actors[0].pos = Vector2(100,100)
	step(vm,22)
	return vm.actions.duplicate(true)

func traces() -> void:
	var original := native_trace(false)
	var changed := native_trace(true)
	check(original == changed and original.size() == 8,"staggered actor damage/dead-state/timer trace matches complete original execution")
	check(original.filter(func(action):return action.name == "InflictDamage" and action.owner == 0).any(
		func(action):return action.dead),"native dead actor keeps its authored rearm calls")
	check(native_trace(false,false) == native_trace(true,false),"ordinary solo execution keeps the same native actor trace")
	var disconnected := native_trace(false,true,true)
	check(disconnected == native_trace(true,true,true) and disconnected.any(func(action):return action.owner == -1),
		"present disconnected follower retains complete native damage and cooldown trace")
	evidence.native_trace = original; evidence.candidate_trace = changed
	evidence.native_disconnected_trace = disconnected

func saved_absence(changed_alarm := false) -> void:
	var actors := setup([0,1]); var guest: GameUnit = actors[1]
	var vm := vm_for(true,changed_alarm); start(vm)
	guest.pos = POINT; step(vm,2)
	var sleep := row_for(vm.save_state(),SLEEP,1)
	check(not sleep.is_empty() and sleep.w > 0 and sleep.f == [{"i":4}],"guest reaches original Sleep(60) with native frame (changed alarm="+str(changed_alarm)+")")
	if sleep.is_empty(): return
	guest.controller = -1; guest.set_meta("orphan_of",1); s.world.erase_unit(guest.uid); step(vm,80)
	var first := vm.save_state()
	check(same_sleep(sleep,row_for(first,SLEEP,1)),"genuinely absent actor preserves entire remaining native Sleep and identity")
	var restored := vm_for(true,changed_alarm); restored._restore(first); Compat.recover(restored); step(restored,90)
	var second := restored.save_state()
	check(same_sleep(sleep,row_for(second,SLEEP,1)),"first absent reload holds frame/index/timer without replaying effects")
	var again := vm_for(true,changed_alarm); again._restore(second); Compat.recover(again); step(again,95)
	var third := again.save_state()
	check(same_sleep(sleep,row_for(third,SLEEP,1)) and again.actions.is_empty(),"second absent reload retains the exact dormant cooldown")
	check(third.instances.filter(func(row):return row.s in NAMES and row.l.get("this") is Dictionary \
		and row.l.this.get("h") == [1,0]).size() == 11,"absent saves retain exactly eleven native actor continuations")
	var old_uid := guest.uid; s.world.erase_unit(old_uid); guest.uid += 500; s.world.set_unit(guest.uid,guest)
	var recycled := GameUnit.new(); allocations.append(recycled); recycled.uid = old_uid; recycled.world = s.world
	recycled.controller = -1; recycled.info = {"name":"unrelated","complexion":Vector3.ONE}; s.world.set_unit(old_uid,recycled)
	guest.controller = 1; guest.remove_meta("orphan_of"); step(again,1)
	var active := pending(again,SLEEP,guest)
	check(active.size() == 1 and active[0].locals.this != recycled \
		and is_equal_approx(active[0].wait_until-again.time,float(sleep.w)-ScriptVM.POLL),
		"rejoin resolves stable character across UID reuse and resumes remaining Sleep")
	step(again,62)
	check(again.actions.size() == 2 and again.actions.all(func(action):return action.uid == guest.uid),
		"returned character alone completes one native damage/rearm cycle")
	check(pending(again,SLEEP,guest).size() == 1 and pending(again,WAIT,guest).is_empty(),
		"rejoin never adds a second idle wait beside the continuing cycle")
	evidence["absent_"+str(changed_alarm)] = {"initial":sleep,"first":row_for(first,SLEEP,1),
		"second":row_for(second,SLEEP,1),"third":row_for(third,SLEEP,1),"old_uid":old_uid,"return_uid":guest.uid}

func legacy_and_solo() -> void:
	var actors := setup([0]); var vm := vm_for(false); start(vm)
	var old := vm.save_state()
	var restored := vm_for(); restored._restore(old); var guest := actor(1)
	Compat.recover(restored); step(restored,4)
	check(CHECKS.all(func(name):return pending(restored,name,guest).size() == 1 \
		and pending(restored,name,actors[0]).size() == 1),"proven old native wait history recovers a later character exactly once")
	var empty := vm_for(); empty._restore({"instances":[],"globals":{}}); Compat.recover(empty)
	check(empty.instances.is_empty(),"old save without any native family history is not guessed")
	actors = setup([0,1]); vm = vm_for(false); start(vm)
	actors[1].pos = POINT; step(vm,2); var legacy_sleep := vm.save_state()
	actors[1].controller = -1; actors[1].set_meta("orphan_of",1)
	s.world.erase_unit(actors[1].uid)
	restored = vm_for(); restored._restore(legacy_sleep); Compat.recover(restored); step(restored,90)
	check(seen(restored).has("h:1:0") and same_sleep(row_for(legacy_sleep,SLEEP,1),row_for(restored.save_state(),SLEEP,1)),
		"legacy absent cooldown supplies seen identity without rearming that character")
	actors = setup([0,1]); vm = vm_for(); start(vm)
	actors[0].pos = POINT; step(vm,2); step(vm,17); actors[1].pos = POINT; step(vm,2)
	var authority := vm.save_state(); var original_bytes := var_to_bytes(authority)
	var own_sleep := row_for(authority,SLEEP,1)
	var own_deadline: float = own_sleep.w
	var host_deadline: float = row_for(authority,SLEEP,0).w
	actors = setup(); s.online = false; var solo := vm_for()
	solo._restore(Snapshot.mark_zones({"gz19h":{"vm":authority}},1).gz19h.vm); Compat.recover(solo)
	var projected := solo.save_state()
	check(var_to_bytes(authority) == original_bytes,"solo projection leaves authority snapshot immutable")
	check(seen(solo) == ["h:0:0"] and projected.instances.size() == 12,
		"solo return keeps recipient's registrar identity and eleven individual continuations")
	check(pending(solo,SLEEP,actors[0]).size() == 1 and is_equal_approx(row_for(projected,SLEEP,0).w,own_deadline),
		"recipient retains own Sleep rather than inheriting the host's earlier deadline")
	actors[0].pos = POINT
	step(solo,int(ceil(host_deadline/ScriptVM.POLL))+3)
	check(solo.actions.is_empty(),"host's former deadline cannot spend returned solo actor's cooldown")
	step(solo,25)
	check(solo.actions.size() == 2 and solo.actions.all(func(action):return action.owner == 0),
		"solo actor resumes exactly one native damage/rearm cycle on its own timer")
	var count := solo.instances.size(); Compat.recover(solo); Compat.recover(solo); step(solo,2)
	check(solo.instances.size() == count,"solo recovery cannot duplicate individual continuations")
	evidence.solo = {"authority_guest_sleep":own_sleep,"projected_sleep":row_for(projected,SLEEP,0)}

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	evidence.original_script_sha256 = raw.sha256_text()
	definitions(); registration(); traces(); saved_absence(); saved_absence(true); legacy_and_solo()
	evidence.merge({"checks":checks,"failures":failures,
		"scope":"Controlled actor/lever state and recorded native damage/spell calls; original predicates, instruction frames, registration and Sleep run. Actual damage and original-startup reachability are exercised separately over ENet. No full physical route, rendering, reward-economy or performance claim."})
	FileAccess.open("user://prison-damage-state.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	for vm: ProbeVM in vms: vm.instances.clear(); vm.globals.clear(); vm.briefings = null; vm.world = null; vm.session = null
	for node: Node in allocations:
		if node is GameWorld: node.vm = null; node.ai = null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	print("PRISON_DAMAGE_STATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
