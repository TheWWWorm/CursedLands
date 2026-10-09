extends Node
## Execute original .mob handlers with several ownership/liveness layouts.
## This probe records spell dispatch; story_coop_effects_net exercises the
## actual effects, save/load and independent client snapshots on the map.
const P := preload("res://src/game/script/script_parser.gd")
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []
var s: Session
var party: Array[GameUnit] = []
var raw := {}
var vms: Array[ProbeVM] = []

class ProbeSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class ProbeVM extends ScriptVM:
	var casts: Array = []
	func _call(name: String, arguments: Array, inst: Instance):
		if name in ["CastSpellUnit", "CastSpellPoint"]:
			casts.append({"name":name, "args":_args(arguments, inst)})
			return null
		if name in ["SwitchLeverState", "EnableLever", "CreateParticleSource", "MoveParticleSource"]:
			return null
		return super._call(name, arguments, inst)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func actor(h: Dictionary, owner: int, uid: int) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u)
	u.uid = uid; u.controller = owner; u.world = s.world
	u.info = {"name":h.get("unit_name", h.name), "complexion":h.complexion}
	u.proto = {"name":h.prototype}; u.pos = Vector2(100+owner*10, 100+owner*10)
	u.set_meta("hero", h); s.world.set_unit(uid, u)
	return u

func fixture() -> void:
	s = ProbeSession.new(); allocations.append(s)
	s.state = CampaignState.new(); s.world = GameWorld.new(); allocations.append(s.world)
	s.world.session = s; s.world.ai = UnitAI.new(s.world)
	s.state.ensure_hero(0, "Human Hero"); s.state.ensure_hero(1, "Human Hero", "Guest A")
	party.append(actor(s.state.heroes[0][0], 0, 1500000001))
	var kel: Dictionary = s.state.heroes[0][0].duplicate(true)
	kel.merc = 2; kel.unit_name = "merc2"; kel.party = ""; kel.controller = 1
	s.state.mercs[2] = kel
	party.append(actor(kel, 1, ScriptVM.name_id("merc2")))
	party.append(actor(s.state.heroes[1][0], 1, 1500000002))
	for i in range(2, 6):
		s.state.ensure_hero(i, "Human Hero", "Guest "+str(i))
		party.append(actor(s.state.heroes[i][0], i, 1500000002+i))
	party[4].dead = true; party[5].hidden = true; party[6].controller = -1
	var pet := GameUnit.new(); allocations.append(pet)
	pet.uid = 999; pet.controller = 1; pet.world = s.world; s.world.set_unit(pet.uid, pet)
	for nid in [338771, 338770, 338769, 1022201, 1022202, 1002001, 3617, 1011001]:
		var o := Node3D.new(); allocations.append(o)
		o.set_meta("ei", {"nid":nid, "position":Vector3(20, 30, 0)})
		s.world.objects[nid] = o; s.world.levers[nid] = {"state":0, "enabled":true}

func vm_for(zone: String, mob: String, adapted := true) -> ProbeVM:
	if not raw.has(mob):
		raw[mob] = EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text
	var vm := ProbeVM.new(); vm.session = s; vm.world = s.world; s.world.vm = vm
	vms.append(vm)
	s.world.zone = {"id":zone, "type":"game"}
	vm.ast = ScriptParser.parse(raw[mob]); vm.briefings = Briefings.new(vm)
	if adapted: Compat.apply(vm.ast, s.state.campaign_id, zone)
	vm._refresh_heroes()
	# _refresh_heroes only replaces globals already declared by the source.
	vm.globals.Heroes = party.duplicate()
	vm.areas[2] = [Vector3(100, 100, 1000)]
	return vm

func run_script(vm: ProbeVM, name: String) -> ScriptVM.Instance:
	vm.spawn(name, [party[0]])
	var inst: ScriptVM.Instance = vm.instances.back()
	vm._run(inst)
	return inst

func cast_count(vm: ProbeVM, u: GameUnit) -> int:
	var count := 0
	for cast: Dictionary in vm.casts:
		if cast.name == "CastSpellUnit" and cast.args[3] == u: count += 1
		if cast.name == "CastSpellPoint" and Vector2(cast.args[3], cast.args[4]) == u.pos: count += 1
	return count

func party_casts() -> void:
	var cases := [
		["gz1h", "zone1", "PortalFire", 0, 1],
		["gz5h", "zone5", "Tiger#1#1", 338771, 1],
		["gz5h", "zone5", "Tiger#2#1", 338770, 1],
		["gz5h", "zone5", "Tiger#3#1", 338769, 1],
		["gz10g", "zone10", "VCheck#3#5", 0, 1],
		["gz10g", "zone10", "VCheck#3#6", 0, 1],
		["gz36j", "zonefinal", "Healing#0#1", 1022201, 4],
		["gz36j", "zonefinal", "Healing#1#1", 1022202, 4],
	]
	for row: Array in cases:
		for i in party.size(): party[i].pos = Vector2(382+i*20, 260+i*20)
		s.state.set_var(0, "q.gz10g.q25g.3", 1); s.state.set_var(0, "q.gz10g.q25g.4", 1)
		var vm := vm_for(row[0], row[1])
		if row[3]:
			s.world.levers[row[3]].state = 0
			var waiting := run_script(vm, row[2])
			check(vm.casts.is_empty() and not waiting.killed, row[2]+": lever gate is required")
			vm.instances.clear(); s.world.levers[row[3]].state = 1
		run_script(vm, row[2])
		for i in party.size():
			check(cast_count(vm, party[i]) == (row[4] if i < 4 else 0), row[2]+": casts for party slot "+str(i))
		check(vm.casts.size() == 4*row[4], row[2]+": no pet, dead, hidden, disconnected or duplicate Kel casts")
		if row[2] == "PortalFire":
			check(vm.casts.all(func(c): return Vector2(c.args[1], c.args[2]) == c.args[3].pos), "Portal fire source follows each recipient")
		if row[0] == "gz10g":
			check(vm.casts.all(func(c): return Vector2(c.args[1], c.args[2]) == Vector2(c.args[3], c.args[4])), "Invisibility source and point follow each recipient")
		party[2].controller = -1; party[3].controller = -1
		s.state.set_var(0, "q.gz10g.q25g.3", 1); s.state.set_var(0, "q.gz10g.q25g.4", 1)
		vm = vm_for(row[0], row[1]); run_script(vm, row[2])
		check(vm.casts.size() == 2*row[4], row[2]+": original two-member casts unchanged")
		party[2].controller = 1; party[3].controller = 2

func traps() -> void:
	var cases := [
		["gz16g", "zone16", "VCheck#0#4", 0, Vector2(20,30), 8.0],
		["gz21k", "zone21", "Trap#0#1", 1002001, Vector2(446.3,280), 15.0],
		["gz21k", "zone21", "Trap#1#1", 3617, Vector2(120.8,347.5), 15.0],
		["gz21k", "zone21", "Trap#1#2", 3617, Vector2(149.3,265.3), 15.0],
		["gz21k", "zone21", "Trap#1#3", 3617, Vector2(108.9,263.2), 15.0],
		["gz21k", "zone21", "Trap#1#4", 3617, Vector2(79.8,263.5), 15.0],
	]
	for row: Array in cases:
		for u: GameUnit in party: u.pos = Vector2(2000,2000)
		if row[3]: s.world.levers[row[3]].state = 0
		var vm := vm_for(row[0], row[1])
		var inst := run_script(vm, row[2])
		party[2].pos = row[4] + Vector2(row[5]+.01, 0)
		vm.time += 1; vm._run(inst)
		check(vm.casts.is_empty(), row[2]+": outside range stays safe")
		party[2].pos = row[4]; party[3].pos = row[4]+Vector2(1,0)
		if row[3]:
			s.world.levers[row[3]].state = 1; vm.time += 1; vm._run(inst)
			check(vm.casts.is_empty(), row[2]+": disarmed lever protects guests")
			s.world.levers[row[3]].state = 0
		vm.time += 1; vm._run(inst)
		check(vm.casts.size() == 1 and cast_count(vm, party[2]) == 1, row[2]+": first eligible guest triggers shared shot")
		vm.time += .5; vm._run(inst)
		check(vm.casts.size() == 1 and inst.killed, row[2]+": second guest does not duplicate the spent shot")
		for inactive in ["dead", "hidden", "disconnected"]:
			party[3].pos = Vector2(2000,2000)
			party[2].dead = inactive == "dead"; party[2].hidden = inactive == "hidden"
			party[2].controller = -1 if inactive == "disconnected" else 1
			vm = vm_for(row[0], row[1]); run_script(vm, row[2])
			check(vm.casts.is_empty(), row[2]+": ignores "+inactive+" guest")
		party[2].dead = false; party[2].hidden = false; party[2].controller = 1
		party[0].pos = row[4]
		vm = vm_for(row[0], row[1]); run_script(vm, row[2])
		check(vm.casts.size() == 1 and cast_count(vm, party[0]) == 1, row[2]+": protagonist branch keeps original priority")
		party[0].pos = Vector2(2000,2000); party[1].pos = row[4]
		vm = vm_for(row[0], row[1]); run_script(vm, row[2])
		check(vm.casts.size() == 1 and cast_count(vm, party[1]) == 1, row[2]+": guest-owned Kel keeps original priority")
		if row[0] == "gz16g":
			party[1].pos = Vector2(2000,2000)
			vm = vm_for(row[0], row[1]); run_script(vm, row[2])
			var cooldown: ScriptVM.Instance = vm.instances.back(); vm._run(cooldown)
			check(cooldown.sname == "VCheck#0#5" and is_equal_approx(cooldown.wait_until, 25*ScriptVM.SLEEP_UNIT), "Acid trap keeps original 25-tick cooldown")
			var saved := vm.save_state(); var resumed := vm_for(row[0], row[1]); resumed._restore(saved)
			resumed.time = 25*ScriptVM.SLEEP_UNIT+.01
			resumed._run(resumed.instances.back()); resumed._run(resumed.instances.back())
			check(cast_count(resumed, party[2]) == 1, "Acid trap re-arms for guest after save and cooldown")
	# The northern boundary is independent of the radial condition.
	for u: GameUnit in party: u.pos = Vector2(2000,2000)
	party[2].pos = Vector2(446.3,292)
	var vm := vm_for("gz21k", "zone21"); run_script(vm, "Trap#0#1")
	check(vm.casts.is_empty(), "Ingos trap preserves its y<289 boundary for guests")
	party[0].pos = Vector2(149.3,265.3); party[2].pos = Vector2(2000,2000)
	vm = vm_for("gz21k", "zone21")
	s.state.quest_items[vm._quest_item_name(60)] = true
	run_script(vm,"Trap#1#2")
	check(vm.casts.is_empty(), "Original item-60 exemption still protects only the protagonist branch")
	party[2].pos = party[0].pos
	run_script(vm,"Trap#1#2")
	check(cast_count(vm,party[2]) == 1 and cast_count(vm,party[0]) == 0, "Guest follows original companion rule when protagonist is exempt")
	s.state.quest_items.clear()

func saved_sleep() -> void:
	var old := vm_for("gz5h", "zone5", false)
	s.world.levers[338771].state = 1
	var inst := run_script(old, "Tiger#1#1")
	check(is_equal_approx(inst.wait_until, 40*ScriptVM.SLEEP_UNIT), "Original shrine save is inside authored Sleep(40)")
	var saved := old.save_state(); var now := vm_for("gz5h", "zone5")
	now._restore(saved); now.time = 40*ScriptVM.SLEEP_UNIT+.01
	now._run(now.instances.back())
	check(now.casts.is_empty() and now.instances.back().sname == "Tiger#1#2", "Old sleeping save resumes cooldown without recasting rewards")

func unchanged_scripts() -> void:
	for row: Array in [["gz7g","zone7"],["cz0k","cz0k"],["gz36j","zonefinal"],["gz5h","zone5"],["gz16g","zone16"],["gz21k","zone21"]]:
		var before := vm_for(row[0],row[1],false).ast
		var after := vm_for(row[0],row[1]).ast
		check(before.world == after.world, row[1]+": world startup unchanged")
		var same := true
		for name: String in before.scripts:
			var original: Array = before.scripts[name].blocks
			var adapted: Array = after.scripts[name].blocks
			for i in original.size():
				if adapted[i].conds != original[i].conds or adapted[i].body.size() != original[i].body.size(): same = false
		check(same, row[1]+": original condition/block/statement indexes preserved")
		if row[0] == "gz7g":
			var normalized := after.scripts.duplicate(true)
			var second: Array = normalized["VCheck#0#1"].blocks[0].body[5]
			check(second[1] == "RemakeGipatArrivalParticles", "zone7: only the audited second particle call is adapted")
			if second[1] == "RemakeGipatArrivalParticles": second[1] = "CreateParticleSource"
			check(before.scripts == normalized, "zone7: every original definition remains exact after particle normalization")
		elif row[0] == "cz0k":
			check(before.scripts == after.scripts, row[1]+": named relocation scripts untouched")
		var twice := after.scripts.duplicate(true)
		Compat.apply(after, s.state.campaign_id, row[0])
		check(after.scripts == twice, row[1]+": applying compatibility twice is idempotent")
		var other_campaign := ScriptParser.parse(raw[row[1]])
		Compat.apply(other_campaign, CampaignProfile.ORIGINAL, row[0])
		check(other_campaign.scripts == before.scripts, row[1]+": base campaign scope stays unchanged")

func _ready() -> void:
	fixture(); party_casts(); traps(); saved_sleep(); unchanged_scripts()
	for vm: ProbeVM in vms:
		vm.briefings = null; vm.instances.clear(); vm.casts.clear(); vm.globals.clear()
	vms.clear()
	for n: Node in allocations:
		if n is GameWorld: n.units = {}; n.objects.clear(); n.vm = null
	for n: Node in allocations: n.free()
	print("STORY_COOP_EFFECTS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
