extends Node
## Original independent trap families: ownership, rearming, late joins and
## save/resume. Hits are observed without running unrelated combat/visuals.
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []
var vms: Array[ProbeVM] = []
var s: Session
var party: Array[GameUnit] = []
var raw := {}

class ProbeSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var hits: Array = []
	func _call(name: String, args: Array, inst: Instance):
		if name in ["KillUnit","CastSpellUnit"]:
			var values := _args(args,inst)
			var u := _unit(values[0] if name == "KillUnit" else values[3])
			if u and not u.dead:
				hits.append({"unit":u,"time":time,"call":name})
				if name == "KillUnit": u.dead = true
			return null
		return super._call(name,args,inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func actor(h: Dictionary, owner: int, uid: int) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u)
	u.uid = uid; u.controller = owner; u.world = s.world
	u.info = {"name":h.get("unit_name",h.name),"complexion":h.complexion}; u.proto = {"name":h.prototype}
	u.set_meta("hero",h); s.world.set_unit(uid,u)
	return u

func guest(owner: int) -> GameUnit:
	s.state.ensure_hero(owner,"Human Hero","Guest "+str(owner))
	return actor(s.state.heroes[owner][0],owner,1500000100+owner)

func fixture() -> void:
	s = ProbeSession.new(); allocations.append(s)
	s.state = CampaignState.new(); s.world = GameWorld.new(); allocations.append(s.world)
	s.world.session = s; s.world.ai = UnitAI.new(s.world)
	s.state.ensure_hero(0,"Human Hero")
	party = [actor(s.state.heroes[0][0],0,1500000001)]
	for number in [2,3]:
		var h: Dictionary = s.state.heroes[0][0].duplicate(true)
		h.merc = number; h.unit_name = "merc"+str(number); h.party = ""; h.controller = 1
		s.state.mercs[number] = h
		party.append(actor(h,1,ScriptVM.name_id(h.unit_name)))
	party.append(guest(1)); party.append(guest(2))
	for nid in [1357456,1011002]:
		var o := Node3D.new(); allocations.append(o)
		o.set_meta("ei",{"nid":nid,"position":Vector3(20,30,0)})
		s.world.objects[nid] = o; s.world.levers[nid] = {"state":1,"enabled":true}

func vm_for(zone: String, mob: String, adapted := true) -> ProbeVM:
	if not raw.has(mob): raw[mob] = EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text
	var vm := ProbeVM.new(); vms.append(vm); vm.session = s; vm.world = s.world; s.world.vm = vm
	s.world.zone = {"id":zone,"type":"game"}; vm.ast = ScriptParser.parse(raw[mob]); vm.briefings = Briefings.new(vm)
	if adapted: Compat.apply(vm.ast,s.state.campaign_id,zone)
	return vm

func step(vm: ProbeVM, count := 1) -> void:
	for n in count:
		vm.time += ScriptVM.POLL
		var rows := vm.instances.duplicate(); rows.reverse()
		for inst: ScriptVM.Instance in rows: vm._run(inst)
		vm.instances = vm.instances.filter(func(i): return not i.killed or not i.frames.is_empty())

func hits(vm: ProbeVM, u: GameUnit) -> Array:
	return vm.hits.filter(func(h): return h.unit == u)

func arm(vm: ProbeVM, names: Array) -> void:
	for name: String in names: vm.spawn(name,[null])

func roundtrip(vm: ProbeVM, zone: String, mob: String) -> ProbeVM:
	var saved := vm.save_state()
	var restored := vm_for(zone,mob); restored._restore(saved); Compat.recover(restored)
	return restored

func oneshot(zone: String, mob: String, names: Array, point: Vector2, covered: int) -> void:
	fixture()
	for u: GameUnit in party: u.pos = Vector2(0,0)
	var vm := vm_for(zone,mob); arm(vm,names); step(vm,3)
	check(vm.hits.is_empty(),zone+": no hit before entering the authored area")
	party[3].pos = point
	if zone == "gz36j": s.state.set_var(0,"q.gz36j.q22j.5",1)
	else: s.world.levers[1357456].state = 0
	step(vm,3); check(vm.hits.is_empty(),zone+": original quest/lever gate protects guest")
	if zone == "gz36j": s.state.set_var(0,"q.gz36j.q22j.5",0)
	else: s.world.levers[1357456].state = 1
	step(vm,2)
	check(hits(vm,party[3]).size() == 1 and party[3].dead,zone+": first guest receives own lethal trap")
	party[4].controller = -1; party[4].pos = point; step(vm,3)
	check(hits(vm,party[4]).is_empty(),zone+": disconnected guest is not hit")
	party[4].controller = 2; party[4].hidden = true; step(vm,3)
	check(hits(vm,party[4]).is_empty(),zone+": hidden guest is not hit")
	party[4].hidden = false; step(vm,2)
	check(hits(vm,party[4]).size() == 1,zone+": second guest retains an independent shot")
	party[3].dead = false; party[4].dead = false; step(vm,8)
	check(hits(vm,party[3]).size() == 1 and hits(vm,party[4]).size() == 1,zone+": revival does not repeat a spent activation")
	check(party.slice(0,covered).all(func(u): return not u.dead),zone+": named roles are not moved or killed by guest trigger")
	party[2].pos = point; step(vm,2)
	check(hits(vm,party[2]).size() == 1,zone+": third story member is covered exactly once")
	var late := guest(3); late.pos = point; step(vm,3)
	check(hits(vm,late).size() == 1,zone+": late participant joins an already-armed trap")
	var saved := vm.save_state()
	# Recreated deployment IDs must not reset hero/companion trap state.
	for u: GameUnit in party+[late]:
		s.world.erase_unit(u.uid); u.uid += 500; s.world.set_unit(u.uid,u); u.dead = false
	vm = vm_for(zone,mob); vm._restore(saved); Compat.recover(vm); step(vm,5)
	check(vm.hits.is_empty(),zone+": save/redeployment retains spent hero and mercenary shots")
	var count := vm.instances.size(); Compat.recover(vm); Compat.recover(vm)
	check(vm.instances.size() == count,zone+": recovery is idempotent")
	var later := guest(4); later.pos = point; step(vm,3)
	check(hits(vm,later).size() == 1,zone+": new participant after reload gets an independent shot")
	arm(vm,names); step(vm,2)
	check(hits(vm,party[3]).size() == 1 and hits(vm,party[4]).size() == 1,zone+": a new native activation re-arms existing guests once")

func acid() -> void:
	fixture()
	for u: GameUnit in party: u.pos = Vector2(200,200)
	party[1].pos = Vector2(20,30); party[3].pos = Vector2(20,30)
	var vm := vm_for("gz9g","zone9")
	arm(vm,["VCheck#4#7","VCheck#4#8"]); step(vm)
	check(hits(vm,party[1]).size() == 1 and hits(vm,party[3]).size() == 1,"Acid: guest and native role start on the same tick")
	step(vm,5); party[4].pos = Vector2(20,30); step(vm)
	check(hits(vm,party[4]).size() == 1 and hits(vm,party[4])[0].time > hits(vm,party[3])[0].time,"Acid: second guest starts an independent cooldown")
	step(vm,90)
	check(hits(vm,party[1]).size() >= 3 and hits(vm,party[1]).map(func(h):return h.time) == hits(vm,party[3]).map(func(h):return h.time),"Acid: guest retains native cadence over repeated cycles")
	check(hits(vm,party[4]).size() <= hits(vm,party[1]).size(),"Acid: other player's cycles do not re-arm this guest")
	var before := hits(vm,party[3]).size()
	party[3].controller = -1; step(vm,60)
	check(hits(vm,party[3]).size() == before,"Acid: no shots while disconnected")
	party[3].controller = 1; step(vm,2)
	check(hits(vm,party[3]).size() == before+1,"Acid: reconnect resumes its already-ready thread once")
	step(vm,7)
	var saved := vm.save_state()
	var native_waits := vm.instances.filter(func(i):return i.sname == "VCheck#4#8a").map(func(i):return maxf(0.0,i.wait_until-vm.time))
	var restored := vm_for("gz9g","zone9"); restored._restore(saved); Compat.recover(restored)
	var resumed_waits := restored.instances.filter(func(i):return i.sname == "VCheck#4#8a").map(func(i):return i.wait_until)
	check(native_waits == resumed_waits,"Acid: original pending cooldown survives adaptation and save")
	vm.hits.clear()
	var uninterrupted := [[],[],[]]; var resumed := [[],[],[]]
	for n in 45:
		step(vm); step(restored)
		for i in 3:
			var u: GameUnit = [party[1],party[3],party[4]][i]
			uninterrupted[i].append(hits(vm,u).size()); resumed[i].append(hits(restored,u).size())
	for i in 3: check(uninterrupted[i] == resumed[i],"Acid: resumed 45-tick hit schedule matches uninterrupted participant "+str(i))

func old_saves() -> void:
	for row: Array in [["gz36j","zonefinal","Trap#0#4",Vector2(48,76)],["gz1h","zone1","Lift#66",Vector2(165,419)],["gz9g","zone9","VCheck#4#8",Vector2(20,30)]]:
		fixture()
		for u: GameUnit in party: u.pos = Vector2(0,0)
		var old := vm_for(row[0],row[1],false); old.spawn(row[2],[null]); step(old,2)
		var saved := old.save_state(); var vm := vm_for(row[0],row[1]); vm._restore(saved); Compat.recover(vm)
		party[3].pos = row[3]; step(vm,3)
		check(hits(vm,party[3]).size() == 1,row[0]+": old save's active native family recovers guest trap")
		# Missing/inactive families are not invented by recovery.
		vm = vm_for(row[0],row[1]); Compat.recover(vm); step(vm,3)
		check(vm.hits.is_empty() and vm.instances.is_empty(),row[0]+": recovery leaves an unarmed trap unarmed")
	fixture()
	for u: GameUnit in party: u.pos = Vector2(200,200)
	party[1].pos = Vector2(20,30)
	var old := vm_for("gz9g","zone9",false); old.spawn("VCheck#4#8",[null]); step(old,6)
	check(old.instances.any(func(i):return i.sname == "VCheck#4#8a" and i.wait_until > old.time),"Acid: legacy fixture is sleeping inside original cooldown")
	var saved := old.save_state(); var vm := vm_for("gz9g","zone9"); vm._restore(saved); Compat.recover(vm)
	party[3].pos = Vector2(20,30); step(vm,3)
	check(hits(vm,party[3]).size() == 1 and hits(vm,party[1]).is_empty(),"Acid: legacy cooldown recovers missing guest without shortening native wait")

func definitions() -> void:
	for row: Array in [["gz36j","zonefinal","Trap#0#4"],["gz1h","zone1","Lift#66"],["gz9g","zone9","VCheck#4#8"]]:
		fixture(); var vm := vm_for(row[0],row[1]); var before := vm_for(row[0],row[1],false).ast
		check(vm.ast.world == before.world and vm.ast.scripts[row[2]] == before.scripts[row[2]],row[0]+": original arming/indexed trap definitions unchanged")
		var current := vm.ast.scripts.duplicate(true); Compat.apply(vm.ast,s.state.campaign_id,row[0])
		check(vm.ast.scripts == current,row[0]+": generated definitions are idempotent")
		var changed: Dictionary = before.scripts[row[2]].duplicate(true); changed.blocks[0].conds.clear(); before.scripts[row[2]] = changed
		var count := before.scripts.size(); Compat.apply(before,s.state.campaign_id,row[0])
		check(before.scripts.size() == count,row[0]+": divergent modded trap is not cloned")

func _ready() -> void:
	oneshot("gz36j","zonefinal",["Trap#0#3","Trap#0#4"],Vector2(48,76),2)
	oneshot("gz1h","zone1",["Lift#64","Lift#65","Lift#66"],Vector2(165,419),3)
	acid(); old_saves(); definitions()
	for vm: ProbeVM in vms: vm.briefings = null; vm.instances.clear(); vm.hits.clear(); vm.globals.clear()
	vms.clear()
	for n: Node in allocations:
		if n is GameWorld: n.units = {}; n.objects.clear(); n.vm = null
	for n: Node in allocations: n.free()
	print("STORY_COOP_TRAPS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
