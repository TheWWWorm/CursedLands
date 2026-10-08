extends Node
## Compare an added guest with the original third-companion dragon cycle.
## The real original instructions, timers and serialized VM frames execute;
## AI orders are recorded without unrelated map combat or presentation.
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []
var s: Session
var party: Array[GameUnit] = []
var dragon: GameUnit
var raw := ""
var vms: Array[ProbeVM] = []

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var actions: Array = []
	func _call(name: String, args: Array, inst: Instance):
		if name in ["UMClear","UMFear","UMAggression","UMFollow","Guard","SendStringEvent"]:
			actions.append({"name":name,"args":_args(args,inst),"time":time})
			return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func actor(h: Dictionary, owner: int, uid: int) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u)
	u.uid=uid; u.world=s.world; u.controller=owner; u.pos=Vector2(200,200)
	u.info={"name":h.get("unit_name",h.get("name","Dragon")),"complexion":Vector3.ONE}
	u.proto={"name":h.get("prototype","Human Hero")}
	if not h.is_empty(): u.set_meta("hero",h)
	s.world.set_unit(uid,u)
	return u

func guest(index: int) -> GameUnit:
	s.state.ensure_hero(index,"Human Hero","Guest "+str(index))
	return actor(s.state.heroes[index][0],index,1500000100+index)

func fixture() -> void:
	s=QuietSession.new(); allocations.append(s)
	s.state=CampaignState.new(); s.world=GameWorld.new(); allocations.append(s.world)
	s.state.campaign_id=CampaignProfile.ORIGINAL
	s.world.session=s; s.world.ai=UnitAI.new(s.world); s.world.zone={"id":"gz6g","type":"game"}
	s.state.ensure_hero(0,"Human Hero")
	party=[actor(s.state.heroes[0][0],0,1500000001)]
	for number in [2,3]:
		var h: Dictionary=s.state.heroes[0][0].duplicate(true)
		h.merc=number; h.unit_name="merc"+str(number); h.party=""; h.controller=1
		s.state.mercs[number]=h; party.append(actor(h,1,ScriptVM.name_id(h.unit_name)))
	party.append(guest(1)); party.append(guest(2))
	dragon=actor({},-1,1155); dragon.pos=Vector2(78,336)
	s.state.quest_items[ScriptVM.new()._quest_item_name(55.0)]=true

func vm_for(adapt := true) -> ProbeVM:
	var vm:=ProbeVM.new(); vms.append(vm); vm.session=s; vm.world=s.world; s.world.vm=vm
	vm.ast=ScriptParser.parse(raw); vm.briefings=Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,s.state.campaign_id,"gz6g")
	vm.globals={"Heroes":party.duplicate(),"YDragon":dragon}
	return vm

func step(vm: ProbeVM, count := 1) -> void:
	for n in count:
		vm.time+=ScriptVM.POLL
		var rows:=vm.instances.duplicate(); rows.reverse()
		for inst: ScriptVM.Instance in rows: vm._run(inst)
		vm.instances=vm.instances.filter(func(i):return not i.killed or not i.frames.is_empty())

func arm(vm: ProbeVM) -> void:
	for name in ["VCheck#0#390","VCheck#0#393","VCheck#0#404"]: vm.spawn(name,[null],"WorldScript")

func calls(vm: ProbeVM, name: String) -> Array:
	return vm.actions.filter(func(x):return x.name==name)

func trace(vm: ProbeVM, target: GameUnit) -> Array:
	return vm.actions.map(func(x):return [x.name,x.args.map(func(v):
		if v is GameUnit: return "target" if v==target else ("dragon" if v==dragon else v.uid)
		return v),snappedf(x.time,.0001)])

func cycle(adapt: bool, index: int) -> Array:
	fixture(); party[index].pos=dragon.pos
	var vm:=vm_for(adapt); arm(vm); step(vm,2)
	check(calls(vm,"UMFollow").is_empty(),"dragon waits the original three ticks before following")
	step(vm,6)
	var follow:=calls(vm,"UMFollow")
	check(follow.size()==1 and follow[0].args[1]==party[index],"dragon follows the nearby "+("guest" if index==3 else "original third companion"))
	check(s.state.get_var(0,"GFol")==1,"follow flag starts with authored order")
	dragon.pos.y=294; step(vm,4)
	check(calls(vm,"Guard").size()==1 and calls(vm,"Guard")[0].args==[dragon,78.0,336.0,7.0],"departure keeps the original home and guard radius")
	check(s.state.get_var(0,"GFol")==1,"departure does not clear following before original delay")
	step(vm,155)
	check(s.state.get_var(0,"GFol")==0,"departure clears follow flag after original delay")
	dragon.pos=Vector2(78,336); step(vm,8)
	check(calls(vm,"UMFollow").size()==2,"original cycle rearms the same participant")
	return trace(vm,party[index])

func gates() -> void:
	fixture(); var vm:=vm_for(); arm(vm)
	party[3].pos=dragon.pos+Vector2(5.01,0); step(vm,8)
	check(calls(vm,"UMFollow").is_empty(),"guest keeps original strict five metre range")
	party[3].pos=dragon.pos; s.state.quest_items.clear(); step(vm,8)
	check(calls(vm,"UMFollow").is_empty(),"guest still needs the original amulet")
	s.state.quest_items[vm._quest_item_name(55.0)]=true; s.state.set_var(0,"DFol",1); step(vm,8)
	check(calls(vm,"UMFollow").is_empty(),"guest keeps original DFol gate")
	s.state.set_var(0,"DFol",0)
	for field in ["hidden","dead","disconnected"]:
		party[3].hidden=field=="hidden"; party[3].dead=field=="dead"; party[3].controller=-1 if field=="disconnected" else 1
		step(vm,8); check(calls(vm,"UMFollow").is_empty(),"dragon ignores "+field+" guest")
	party[3].hidden=false; party[3].dead=false; party[3].controller=1; step(vm,8)
	check(calls(vm,"UMFollow").size()==1,"returning eligible guest can trigger its waiting cycle")
	var late:=guest(3); late.pos=dragon.pos; step(vm,8)
	check(calls(vm,"UMFollow").size()==2 and calls(vm,"UMFollow")[1].args[1]==late,"late guest joins an already armed dragon cycle")

func persistence() -> void:
	fixture(); party[3].pos=dragon.pos
	var vm:=vm_for(); arm(vm); step(vm,2)
	var saved:=vm.save_state(); vm=vm_for(); vm._restore(saved); Compat.recover(vm); step(vm,6)
	check(calls(vm,"UMFollow").size()==1 and calls(vm,"UMFollow")[0].args[1]==party[3],"saved follow delay retains guest identity and dispatches once")
	dragon.pos.y=294; step(vm,4)
	saved=vm.save_state(); vm=vm_for(); vm._restore(saved); Compat.recover(vm)
	var count:=vm.instances.size(); Compat.recover(vm)
	check(vm.instances.size()==count,"saved guest cycle recovery is idempotent")
	step(vm,155)
	check(calls(vm,"Guard").is_empty() and calls(vm,"UMFollow").is_empty() and s.state.get_var(0,"GFol")==0,"saved departure wait resumes without replaying orders")
	fixture(); vm=vm_for(false); arm(vm); step(vm,2)
	saved=vm.save_state(); vm=vm_for(); vm._restore(saved); Compat.recover(vm)
	party[3].pos=dragon.pos; step(vm,8)
	check(calls(vm,"UMFollow").size()==1,"old save arms a missing guest cycle")

func structural() -> void:
	fixture(); var original:=vm_for(false).ast; var adapted:=vm_for().ast
	check(original.world==adapted.world,"original startup instructions stay byte-for-byte equivalent")
	check(original.scripts.keys().all(func(n):return original.scripts[n]==adapted.scripts[n]),"all original body indexes, target roles and timings stay intact")
	var before:=adapted.scripts.duplicate(true); Compat.apply(adapted,CampaignProfile.ORIGINAL,"gz6g")
	check(before==adapted.scripts,"adaptation is idempotent")
	Compat.apply(original,CampaignProfile.ASTRAL,"gz6g")
	check(original.scripts.size()==vm_for(false).ast.scripts.size(),"base dragon adaptation does not run in LiA")
	original.scripts["VTriger#0#401"].blocks[0].body.append([ScriptParser.S_CALL,"Nop",[]])
	var count:=original.scripts.size(); Compat.apply(original,CampaignProfile.ORIGINAL,"gz6g")
	check(original.scripts.size()==count,"changed modded follow chain is not cloned")

func _ready() -> void:
	# The private Retroid harness currently imports LiA assets. Its pure VM
	# test uses the same extracted original script with synthetic actors.
	raw=FileAccess.get_file_as_string("user://base-zone6-script.txt") if GameData.campaign_id==CampaignProfile.ASTRAL \
		else EIMob.load_bytes(GameData.read_file("maps/zone6.mob")).script_text
	var native:=cycle(false,2); var extra:=cycle(true,3)
	check(native==extra,"guest's complete follow/departure/rearm trace matches original companion")
	check(cycle(true,2)==native,"guest-owned third story member is not given a duplicate cycle")
	gates(); persistence(); structural()
	for vm in vms: vm.briefings=null; vm.instances.clear(); vm.globals.clear(); vm.actions.clear()
	vms.clear()
	for n in allocations:
		if n is GameWorld: n.units={}; n.vm=null
	for n in allocations: n.free()
	print("STORY_COOP_DRAGON ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
