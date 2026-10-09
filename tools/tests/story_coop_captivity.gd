extends Node
## Actual prison instructions, controlled actor positions and recorded orders.
## Compares extra intruders with the original third-role dispatch/cooldown.
const Compat := preload("res://src/game/script/story_compat.gd")
const SHARED_CHECKS := ["VCheck#0#265","VCheck#0#269","VCheck#0#271","VCheck#0#258",
	"VCheck#0#279","VCheck#0#280","VCheck#0#17","VCheck#0#295","VCheck#0#300",
	"VCheck#0#338","VCheck#0#344","VCheck#0#348","VCheck#0#355","VCheck#0#357","VCheck#0#364"]
var checks := 0
var failures := 0
var raw := ""
var allocations: Array[Node] = []
var vms: Array[ProbeVM] = []
var s: Session
var party: Array[GameUnit] = []
var guard: GameUnit

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var actions: Array = []
	func _mode(_o, mode: String, data: Dictionary) -> void:
		actions.append([mode,data.duplicate(true),time])
	func _call(name: String, args: Array, inst: Instance):
		if name=="Run": actions.append([name,{},time]); return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)

func actor(record: Dictionary, controller: int, uid: int) -> GameUnit:
	var u:=GameUnit.new(); allocations.append(u)
	u.world=s.world; u.uid=uid; u.controller=controller; u.pos=Vector2(100,100)
	u.info={"name":record.get("unit_name","guard"),"complexion":Vector3.ONE}; u.proto={"name":"Human Hero"}
	if not record.is_empty(): u.set_meta("hero",record)
	s.world.set_unit(uid,u)
	return u

func fixture() -> void:
	s=QuietSession.new(); allocations.append(s); s.state=CampaignState.new(); s.state.campaign_id=CampaignProfile.ORIGINAL
	s.world=GameWorld.new(); allocations.append(s.world); s.world.session=s; s.world.ai=UnitAI.new(s.world); s.world.zone={"id":"gz19h"}
	s.state.ensure_hero(0,"Human Hero"); party=[actor(s.state.heroes[0][0],0,1500000001)]
	for n in [2,3]:
		var h: Dictionary=s.state.heroes[0][0].duplicate(true)
		h.merc=n; h.unit_name="merc"+str(n); h.party=""; h.controller=1; s.state.mercs[n]=h
		party.append(actor(h,1,ScriptVM.name_id(h.unit_name)))
	for n in [1,2]:
		s.state.ensure_hero(n,"Human Hero","Guest "+str(n)); party.append(actor(s.state.heroes[n][0],n,1500000010+n))
	guard=actor({},-1,45655)

func vm_for(adapt:=true) -> ProbeVM:
	var vm:=ProbeVM.new(); vms.append(vm); vm.session=s; vm.world=s.world; s.world.vm=vm
	vm.ast=ScriptParser.parse(raw); vm.briefings=Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz19h")
	vm.globals={"Heroes":party.duplicate(),"a1":[guard],"Try1":null}; vm.areas[1]=[Rect2(451,316,59,36)]
	return vm

func step(vm: ProbeVM, count: int) -> void:
	for i in count:
		vm.time+=ScriptVM.POLL
		var live:=vm.instances.duplicate(); live.reverse()
		for inst: ScriptVM.Instance in live: vm._run(inst)
		vm.instances=vm.instances.filter(func(inst):return not inst.killed or not inst.frames.is_empty())

func trace(role: int, adapt: bool) -> Array:
	fixture(); party[role].pos=Vector2(480,330)
	var vm:=vm_for(adapt); vm.spawn("VCheck#0#417",[party[role]]); step(vm,85)
	return vm.actions.duplicate(true)

func without_shared_metadata(scripts: Dictionary) -> Dictionary:
	var out := scripts.duplicate(true)
	for name: String in SHARED_CHECKS:
		if out.get(name,{}).get("party_check") == true: out[name].erase("party_check")
	return out

func _ready() -> void:
	raw=EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	for n in 3:
		var native:=trace(n,false); var updated:=trace(n,true)
		check(not native.is_empty() and native==updated,"original role "+str(n)+" keeps complete guard order/timer trace")
	var original:=trace(2,false)
	for n in [3,4]: check(trace(n,true)==original,"extra guest "+str(n)+" receives original third-role pursuit cadence")
	for flag in ["Pr1","Pr2"]:
		fixture(); party[3].pos=Vector2(480,330); s.state.set_var(0,flag,1)
		var vm:=vm_for(); vm.spawn("VCheck#0#417",[party[3]]); step(vm,12)
		check(vm.actions.is_empty(),flag+" retains original-role priority")
		s.state.set_var(0,flag,0); step(vm,4)
		check(vm.actions.any(func(a):return a[0]=="sentry" and a[1].point==party[3].pos),flag+" release lets guards pursue guest")
	for inactive in ["dead","hidden","disconnected"]:
		fixture(); party[3].pos=Vector2(480,330); party[3].dead=inactive=="dead"; party[3].hidden=inactive=="hidden"; party[3].controller=-1 if inactive=="disconnected" else 1
		var vm:=vm_for(); vm.spawn("VCheck#0#417",[party[3]]); step(vm,40)
		check(vm.actions.is_empty(),"inactive intruder cannot dispatch guards: "+inactive)
		vm.globals.Try1=party[3]; vm.spawn("VTriger#0#235",[party[3]]); step(vm,1)
		check(not vm.actions.any(func(a):return a[0]=="sentry"),"pending dispatch cannot target unrelated native actor: "+inactive)
	fixture(); party[3].pos=Vector2(480,330)
	var vm:=vm_for(); vm.spawn("VCheck#0#417",[party[3]]); step(vm,10)
	var saved:=vm.save_state(); vm=vm_for(); vm._restore(saved); step(vm,2)
	check(vm.actions.is_empty(),"saved pursuit does not shorten original cooldown")
	step(vm,30); check(vm.actions.any(func(a):return a[0]=="sentry" and a[1].point==party[3].pos),"saved guest pursuit resumes with same target")
	var pristine:=ScriptParser.parse(raw); var adapted:=vm_for().ast
	check(pristine.world==adapted.world,"original startup remains unchanged")
	var registrar := "VTriger#0#416#RemakeParticipants"
	var damage_registrar := "VTriger#0#76#RemakeParticipants"
	check(adapted.scripts.size()==pristine.scripts.size()+2 and adapted.scripts.has(registrar) \
		and adapted.scripts.has(damage_registrar),"only the two named native-family registrars are added")
	var native := without_shared_metadata(adapted.scripts)
	check(pristine.scripts.keys().all(func(name):return name in ["VCheck#0#230","VTriger#0#235"] \
		or pristine.scripts[name]==native[name]),"every other native definition and saved instruction index is unchanged; only fifteen named shared tags are allowed")
	check(pristine.scripts["VCheck#0#12"]==adapted.scripts["VCheck#0#12"],"authored protagonist-only portal gate stays unchanged")
	var again:=adapted.scripts.duplicate(true); Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz19h")
	check(again==adapted.scripts,"captivity adaptation is idempotent")
	var changed:=ScriptParser.parse(raw); changed.scripts["VCheck#0#230"].blocks[0].conds.append([ScriptParser.N_NUM,0.0])
	var before:=changed.scripts.duplicate(true); Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
	var changed_native := without_shared_metadata(changed.scripts); changed_native.erase(damage_registrar)
	check(before==changed_native and not changed.scripts.has(registrar) and changed.scripts.has(damage_registrar),
		"changed alarm dispatch retains native definitions and the independently admitted damage registrar")
	check(SHARED_CHECKS.all(func(name):return changed.scripts[name].get("party_check",false)),
		"independently inspected discoveries and route stages remain available with changed alarm dispatch")
	for row: Array in [[1500000001.0,1500000002.0,0.0],[1500000001.0,1500000001.0,1.0],
		[1.25,1.2500001,1.0],[1.25,1.26,0.0],[party[0],party[1],0.0],[party[0],party[0],1.0],[party[0],0.0,0.0]]:
		vm.globals.lhs=row[0]; vm.globals.rhs=row[1]
		check(vm._call("IsEqual",[[ScriptParser.N_VAR,"lhs"],[ScriptParser.N_VAR,"rhs"]],ScriptVM.Instance.new())==row[2],
			"script equality distinguishes exact IDs/objects and retains fractional tolerance")
	for v: ProbeVM in vms: v.briefings=null; v.world=null; v.session=null
	for node: Node in allocations:
		if node is GameWorld: node.vm=null; node.ai=null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	print("STORY_COOP_CAPTIVITY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
