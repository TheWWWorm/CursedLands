extends Node
## Save/projection controls with independent source and destination rosters.
const Refs := preload("res://src/game/actor_refs.gd")
const VMProjection := preload("res://src/game/script/coop_vm_state.gd")
var checks:=0
var failures:=0
var allocations:Array[Node]=[]
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func session() -> Session:
	var s:=Session.new();allocations.append(s);s.state=CampaignState.new()
	s.world=GameWorld.new();allocations.append(s.world);s.world.session=s
	s.world.vm=ScriptVM.new();s.world.vm.session=s;s.world.vm.world=s.world
	return s
func hero(s:Session,owner:int,index:int,uid:int,role:="") -> GameUnit:
	var row:={"name":"Same display name","prototype":"Human Hero"}
	if not role.is_empty():row.unit_name=role
	s.state.heroes.get_or_add(owner,[]).append(row)
	var u:=GameUnit.new();allocations.append(u);u.world=s.world;u.uid=uid;u.controller=owner;u.set_meta("hero",row);s.world.set_unit(uid,u)
	return u
func pet(s:Session,uid:int,key:="") -> GameUnit:
	var u:=GameUnit.new();allocations.append(u);u.world=s.world;u.uid=uid;u.controller=0;u.set_meta("tame_stage",3)
	if not key.is_empty():u.set_meta("pet_id",key)
	s.world.set_unit(uid,u)
	return u
func _ready() -> void:
	var source:=session();var dest:=session()
	var host:=hero(source,0,0,101)
	var companion:=hero(source,0,1,102,"Kel")
	var guest:=hero(source,1,0,103)
	var other:=hero(source,2,0,104)
	var solo:=hero(dest,0,0,900)
	var returned_companion:=hero(dest,0,1,901,"Kel")
	solo.get_meta("hero").name="Restored original display name"
	var p:=pet(source,105);var ref:=Refs.of(p)
	var returned_pet:=pet(dest,101,String(ref[1]))
	var payload:={"caster":Refs.of(guest),"target":Refs.of(p),"host":Refs.of(host),"other":Refs.of(other),"companion":Refs.of(companion)}
	var before:=var_to_bytes(payload)
	var projected:Dictionary=Refs.project_value(payload,1)
	check(before==var_to_bytes(payload),"projection leaves source checkpoint unchanged")
	check(Refs.resolve(dest.world,projected.caster)==solo,"recipient survives controller and display-name changes")
	check(Refs.resolve(dest.world,projected.target)==returned_pet,"pet survives UID reuse and ownership change")
	check(Refs.resolve(dest.world,projected.host)==null and Refs.resolve(dest.world,projected.other)==null,"unrelated protagonists never resolve to same-name solo hero")
	check(Refs.resolve(dest.world,projected.companion)==returned_companion,"shared authored companion retains its role")
	returned_companion.get_meta("hero").unit_name="Nalo"
	check(Refs.resolve(dest.world,projected.companion)==null,"replaced roster slot cannot steal a named companion reference")
	returned_companion.get_meta("hero").unit_name="Kel"
	var legacy:=["hero","Restored original display name",1]
	check(Refs.resolve(dest.world,Refs.project(legacy,1))==solo,"older name/controller effect records still load")
	check(Refs.resolve(dest.world,Refs.project(["hero","Restored original display name",0],1))==null,"older host reference cannot alias recipient by name")
	var vm_pet:Dictionary=source.world.vm._ser(p)
	check(dest.world.vm._deser(vm_pet)==returned_pet,"VM and spells share the same pet identity")
	var physical:Dictionary=VMProjection._physical_value({"target":source.world.vm._ser(guest),"host":source.world.vm._ser(host),"companion":source.world.vm._ser(companion)},1)
	check(dest.world.vm._deser(physical.target)==solo and physical.host==null,"script combat target projection distinguishes physical participants")
	check(dest.world.vm._deser(physical.companion)==returned_companion,"script combat references retain shared companion identity")
	dest.world.erase_unit(returned_pet.uid)
	check(dest.world.vm._deser(vm_pet)==null,"missing pet reference cannot fall back to its saved numeric ID")
	var legacy_body:={"parts":[],"magic":[]}
	CampaignState.apply_body(returned_pet,legacy_body)
	check(int(returned_pet.get_meta("tame_stage"))==3,"old body records do not erase existing pet identity")
	# A restored dynamic corpse can occupy the allocator's first candidate.
	dest.world.set_unit(1500000001,returned_pet)
	check(dest.world.new_uid()==1500000002,"new deployment IDs skip restored dynamic actors")
	for s:Session in [source,dest]:
		s.world.units={};s.world.vm=null;s.world=null
	allocations.reverse()
	for n:Node in allocations:n.free()
	print("SAVE_ACTOR_REFS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
