extends "./story_coop_captivity.gd"
## Focused serialized-state controls, not a played prison route. Actors,
## positions and edge-case saved rows are prepared; original script bodies,
## native For registration, dispatch/reset calls and Sleep instructions run.
## prison_alarm_late_join.gd separately proves original startup over real ENet.
const Traps := preload("res://src/game/script/story_coop_traps.gd")
const Snapshot := preload("res://src/game/script/coop_vm_state.gd")
const REGISTER := "VTriger#0#416"
const WAIT := "VCheck#0#417"
const REGISTRAR := REGISTER+"#RemakeParticipants"
const INSIDE := Vector2(480,330)
var evidence := {}

func prepare() -> ProbeVM:
	fixture()
	# These controls need only the protagonist and one guest. Parent fixture
	# actors/guard are observational doubles, not authored reinforcement proof.
	for index in [1,2,4]: party[index].controller = -1
	return vm_for()

func live(vm: ScriptVM, name: String, who: GameUnit) -> Array:
	return vm.instances.filter(func(i):return i.sname == name and i.locals.get("this") == who \
		and (not i.killed or not i.frames.is_empty()))

func saved_row(name: String, reference: Dictionary, delay := 0.0) -> Dictionary:
	return {"s":name,"l":{"this":reference},"k":delay > 0,"b":0 if delay > 0 else -1,
		"i":2 if delay > 0 else 0,"f":[{"i":2}] if delay > 0 else [],"w":delay,"p":ScriptVM.POLL}

func reference(owner: int, uid: int) -> Dictionary:
	return {"u":uid,"h":[owner,0]}

func pending(rows: Array, intruder: Variant = null) -> Dictionary:
	return {"globals":{"Heroes":[reference(0,1500000001),reference(1,1500000011)],"Try1":intruder},
		"instances":rows,"areas":{1:[Rect2(451,316,59,36)]}}

func row_for(saved: Dictionary, name: String, owner := 1) -> Dictionary:
	for row: Dictionary in saved.instances:
		if row.s == name and row.l.get("this") is Dictionary and row.l.this.get("h") == [owner,0]: return row
	return {}

func seen(vm: ScriptVM) -> Array:
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname == REGISTRAR: return inst.locals.get(Traps.SEEN,[])
	return []

func same_wait(first: Dictionary, second: Dictionary) -> bool:
	return not first.is_empty() and not second.is_empty() and first.l.this == second.l.this \
		and first.f == second.f and first.i == second.i and first.b == second.b and first.k == second.k \
		and is_equal_approx(first.w,second.w) and is_equal_approx(first.p,second.p)

func detach_actor(who: GameUnit) -> void:
	who.set_meta("orphan_of",who.controller)
	who.controller = -1

func reconnect(who: GameUnit, owner := 1) -> void:
	who.controller = owner
	who.remove_meta("orphan_of")

func definitions() -> void:
	var pristine := ScriptParser.parse(raw)
	var admitted := ScriptParser.parse(raw)
	Compat.apply(admitted,CampaignProfile.ORIGINAL,"gz19h")
	check(admitted.scripts.has(REGISTRAR),"complete original source admits the single registrar")
	check(admitted.scripts[REGISTRAR].params.is_empty(),"registrar has no host actor parameter")
	var frozen := admitted.scripts.duplicate(true)
	Compat.apply(admitted,CampaignProfile.ORIGINAL,"gz19h")
	check(admitted.scripts == frozen,"repeated adaptation is idempotent")
	var names: Array = ["VTriger#0#415",REGISTER]+Traps.PRISON_CHAIN+["VCheck#0#180","VTriger#0#181"]
	for name: String in names:
		var changed := ScriptParser.parse(raw)
		changed.scripts[name].blocks[0].body.append([ScriptParser.S_CALL,"Nop",[]])
		Compat.apply(changed,CampaignProfile.ORIGINAL,"gz19h")
		check(not changed.scripts.has(REGISTRAR),"altered original definition fails closed: "+name)
	for name: String in [REGISTER,WAIT,"VTriger#0#425"]:
		var missing := ScriptParser.parse(raw)
		missing.scripts.erase(name)
		Compat.apply(missing,CampaignProfile.ORIGINAL,"gz19h")
		check(not missing.scripts.has(REGISTRAR),"missing original definition fails closed: "+name)
	var uncalled := ScriptParser.parse(raw)
	uncalled.world.erase([ScriptParser.S_CALL,REGISTER,[[ScriptParser.N_VAR,"NULL"]]])
	Compat.apply(uncalled,CampaignProfile.ORIGINAL,"gz19h")
	check(not uncalled.scripts.has(REGISTRAR),"missing authored startup call cannot arm registration")
	for scope: Array in [[CampaignProfile.ASTRAL,"gz19h"],[CampaignProfile.ORIGINAL,"gz15h"]]:
		var outside := ScriptParser.parse(raw)
		Compat.apply(outside,scope[0],scope[1])
		check(not outside.scripts.has(REGISTRAR),"registrar stays within original gz19h scope: "+str(scope))
	check(pristine.scripts[WAIT] == admitted.scripts[WAIT],"native area predicate and body remain exactly unchanged")
	var vm := prepare()
	s.lmp = {"control":true}
	vm.spawn(REGISTER,[null],"WorldScript"); step(vm,3)
	check(not vm.instances.any(func(i):return i.sname == REGISTRAR),"original multiplayer mode does not install a live registrar")

func registration() -> void:
	print("REGISTRATION_SETUP begin")
	var vm := prepare()
	print("REGISTRATION_SETUP prepared")
	var guest: GameUnit = party[3]
	detach_actor(guest)
	print("REGISTRATION_SETUP spawn")
	vm.spawn(REGISTER,[null],"WorldScript")
	print("REGISTRATION_SETUP spawned ",vm.instances.size())
	# Parent For reads its actual group; disconnected guest is absent.
	vm.globals.Heroes = [party[0]]
	print("REGISTRATION_SETUP step")
	step(vm,3)
	check(live(vm,WAIT,party[0]).size() == 1 and live(vm,WAIT,guest).is_empty(),"native For registers the initially present actor once")
	reconnect(guest); step(vm,3)
	check(live(vm,WAIT,guest).size() == 1 and live(vm,WAIT,party[0]).size() == 1,"later actor gets one native wait without duplicating the early actor")
	var count := vm.instances.size()
	Compat.recover(vm); Compat.recover(vm); step(vm,6)
	check(vm.instances.size() == count,"recovery and continued polling cannot duplicate registration")
	var snapshot := vm.save_state()
	projection(snapshot,false)

func absent_and_spent() -> void:
	var vm := prepare()
	var guest: GameUnit = party[3]
	vm.globals.Heroes = [party[0],guest]
	vm.spawn(REGISTER,[null],"WorldScript"); step(vm,3)
	guest.pos = INSIDE
	for n in 30:
		step(vm,1)
		if live(vm,"VTriger#0#242",guest).any(func(i):return not i.frames.is_empty() and i.wait_until > vm.time): break
	var sleep := row_for(vm.save_state(),"VTriger#0#242")
	check(not sleep.is_empty() and sleep.w > 0 and sleep.f == [{"i":2}],"guest naturally reaches original Sleep(20) with its saved frame")
	check(live(vm,WAIT,guest).is_empty() and seen(vm).has("h:1:0"),"fired initial wait is spent while its native pursuit remains pending")
	if sleep.is_empty(): return
	var authority := s
	var members := party
	var original_guard := guard
	projection(vm.save_state(),true)
	# projection() uses separate prepared allocations; return to this VM's
	# authority/actors for absent-load preservation checks.
	s = authority; party = members; guard = original_guard
	detach_actor(guest); step(vm,7)
	var first := vm.save_state()
	check(same_wait(sleep,row_for(first,"VTriger#0#242")),"disconnect holds the original remaining delay, poll and instruction")
	var restored := vm_for(); restored._restore(first); Compat.recover(restored); step(restored,9)
	var second := restored.save_state()
	check(same_wait(sleep,row_for(second,"VTriger#0#242")),"absent reload preserves raw actor identity and remaining native wait")
	check(second.globals.Try1 == first.globals.Try1,"absent reload-save preserves unresolved original Try1")
	var again := vm_for(); again._restore(second); Compat.recover(again); step(again,11)
	var third := again.save_state()
	check(same_wait(sleep,row_for(third,"VTriger#0#242")),"second absent reload retains frame and delay without a fresh idle wait")
	check(not again.instances.any(func(i):return i.sname == WAIT and i.has_meta(Traps.PRISON_ACTOR) \
		and i.get_meta(Traps.PRISON_ACTOR).h == [1,0]),"spent guest has no duplicate idle watcher while absent")
	# Explicit UID-recycling control: the original numeric id now names an
	# unrelated actor. Only the saved hero identity may bind the continuation.
	var old_uid := guest.uid
	s.world.erase_unit(old_uid); guest.uid += 500; s.world.set_unit(guest.uid,guest)
	var recycled := actor({},-1,old_uid)
	reconnect(guest); step(again,1)
	var active := live(again,"VTriger#0#242",guest)
	check(active.size() == 1 and guest.uid != old_uid and active[0].locals.this != recycled,"rejoin binds the exact hero despite recycled old unit id")
	check(again.globals.Try1 == guest,"saved alarm intruder rebinds to that returning hero")
	check(active.size() == 1 and is_equal_approx(active[0].wait_until-again.time,float(sleep.w)-ScriptVM.POLL),"first present tick resumes the remaining Sleep rather than resetting it")
	step(again,45)
	check(live(again,WAIT,guest).is_empty() and live(again,"VCheck#0#227",guest).size() == 1,
		"return and continued pursuit do not repeat the initial alarm activation")
	# The native dead-intruder branch intentionally re-arms after Sleep(1).
	guest.dead = true
	var rearm := []
	for n in 40:
		step(again,1)
		var sleeping := live(again,"VTriger#0#425",guest)
		if sleeping.any(func(i):return not i.frames.is_empty() and i.wait_until > again.time):
			rearm.append({"phase":"sleep","time":again.time,"remaining":sleeping[0].wait_until-again.time})
			guest.pos = Vector2(100,100)
			guest.dead = false
			break
	check(rearm.size() == 1 and is_equal_approx(rearm[0].remaining,ScriptVM.POLL),"original reset reaches its own one-tick Sleep(1)")
	step(again,2)
	check(live(again,WAIT,guest).size() == 1,"SEEN does not suppress the original explicit rearm")
	rearm.append({"phase":"rearmed","time":again.time,"watchers":live(again,WAIT,guest).size()})
	evidence.authored_rearm = rearm
	evidence.absent_wait = {"initial":sleep,"first_absent_save":row_for(first,"VTriger#0#242"),
		"second_absent_save":row_for(second,"VTriger#0#242"),"third_absent_save":row_for(third,"VTriger#0#242"),
		"old_uid":old_uid,"return_uid":guest.uid}

func legacy_and_priority() -> void:
	var vm := prepare()
	var guest: GameUnit = party[3]
	var old := pending([saved_row(WAIT,reference(0,party[0].uid))])
	vm._restore(old); Compat.recover(vm); step(vm,3)
	check(live(vm,WAIT,guest).size() == 1 and live(vm,WAIT,party[0]).size() == 1,"old host-side idle anchor recovers the missing late guest once")
	var without_history := vm_for(); without_history._restore(pending([])); Compat.recover(without_history)
	check(without_history.instances.is_empty(),"old save without native history is not guessed or rearmed")
	var marked := Snapshot.mark_zones({"gz19h":{"vm":old}},1)
	var projected := Snapshot.restore(vm,marked.gz19h.vm)
	var alone := vm_for(); alone._restore(projected); Compat.recover(alone)
	check(alone.instances.is_empty(),"solo projection of host-only legacy history has no invented guest anchor")
	var sleeping := pending([saved_row(WAIT,reference(0,party[0].uid)),
		saved_row("VTriger#0#242",reference(1,guest.uid),13*ScriptVM.POLL)],reference(1,guest.uid))
	detach_actor(guest)
	var absent := vm_for(); absent._restore(sleeping); Compat.recover(absent); step(absent,3)
	check(seen(absent).has("h:1:0"),"old absent actor's raw continuation supplies its stable seen identity")
	check(not absent.instances.any(func(i):return i.sname == WAIT and i.locals.get("this") == guest),"legacy recovery does not add an idle wait beside a spent continuation")
	party[0].pos = INSIDE; step(absent,2)
	check(absent.globals.Try1 == party[0] and not absent.has_meta(Traps.PRISON_INTRUDER),"a later real host alarm replaces the absent saved intruder")
	reconnect(guest); step(absent,1)
	check(absent.globals.Try1 == party[0],"returning guest cannot overwrite the later authored alarm target")

func queued_intruder() -> void:
	var vm := prepare()
	var old_intruder: GameUnit = party[3]
	var newcomer: GameUnit = party[0]
	detach_actor(old_intruder)
	vm._restore(pending([saved_row(WAIT,reference(0,newcomer.uid)),
		saved_row("VTriger#0#242",reference(1,old_intruder.uid),13*ScriptVM.POLL)],reference(1,old_intruder.uid)))
	Compat.recover(vm)
	newcomer.pos = INSIDE; step(vm,1)
	check(vm.instances.any(func(i):return i.sname == "VTriger#0#48" and i.locals.get("this") == newcomer \
		and i.frames.is_empty()),"newcomer's native alarm is queued before its body executes")
	detach_actor(newcomer)
	reconnect(old_intruder); step(vm,1)
	check(vm.globals.Try1 == old_intruder,"queued then absent newcomer cannot discard the saved intruder before assignment")
	check(s.state.get_var(0,"g1") == 0,"held queued alarm has not executed its original success/body statements")
	reconnect(newcomer,0); step(vm,1)
	check(vm.globals.Try1 == newcomer,"returning newcomer replaces Try1 when its original body actually executes")

func projection(saved: Dictionary, spent: bool) -> void:
	var original := var_to_bytes(saved)
	var projected := Snapshot.restore(s.world.vm,Snapshot.mark_zones({"gz19h":{"vm":saved}},1).gz19h.vm)
	check(var_to_bytes(saved) == original,"solo projection leaves authority snapshot immutable (spent="+str(spent)+")")
	var registrar: Array = projected.instances.filter(func(i):return i.s == REGISTRAR)
	check(registrar.size() == 1 and registrar[0].l.get(Traps.SEEN,[]) == ["h:0:0"],
		"shared registrar retains only recipient's remapped identity (spent="+str(spent)+")")
	var solo := prepare()
	for u: GameUnit in party:
		if u != party[0]: u.controller = -1
	s.state.heroes = {0:s.state.heroes[0]}
	solo._restore(projected); Compat.recover(solo); step(solo,3)
	check(live(solo,WAIT,party[0]).size() == (0 if spent else 1),"returned solo hero has exactly its own pending/spent wait (spent="+str(spent)+")")
	if spent:
		check(live(solo,"VTriger#0#242",party[0]).size() == 1,"spent guest returns with its original pending pursuit delay")
	var count := solo.instances.size(); Compat.recover(solo); step(solo,3)
	check(solo.instances.size() == count,"solo recovery does not rearm or duplicate the recipient (spent="+str(spent)+")")

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	definitions(); registration(); absent_and_spent(); legacy_and_priority(); queued_intruder()
	evidence.merge({"checks":checks,"failures":failures,"scope":"Prepared actors and serialized edge cases around original native definitions; no full route, network, reinforcement or combat acceptance."})
	FileAccess.open("user://prison-alarm-state.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	for vm: ProbeVM in vms:
		vm.instances.clear(); vm.globals.clear(); vm.briefings = null; vm.world = null; vm.session = null
	for node: Node in allocations:
		if node is GameWorld: node.vm = null; node.ai = null
	for node: Node in allocations:
		if is_instance_valid(node): node.free()
	print("PRISON_ALARM_STATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
