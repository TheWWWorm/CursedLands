extends RefCounted
## Narrow repairs to authored script contracts, without editing game assets.
const P := preload("res://src/game/script/script_parser.gd")

static func apply(ast: ScriptParser, campaign: String, zone: String) -> void:
	if campaign != CampaignProfile.ASTRAL:
		if campaign == CampaignProfile.ORIGINAL:
			if zone == "gz19h":
				preload("res://src/game/script/story_coop_traps.gd").apply_prison(ast)
				preload("res://src/game/script/story_coop_traps.gd").apply_prison_damage(ast)
				_prison_discovery_checks(ast)
				_prison_route_checks(ast)
			preload("res://src/game/script/story_coop_predicates.gd").apply_original(ast,zone)
			if zone == "gz15h": _prison_party_checks(ast)
		if campaign == CampaignProfile.ORIGINAL and zone == "gz6g":
			# The amulet dragon has three identical native follow/return
			# cycles. Added guests use the third role's original cadence.
			preload("res://src/game/script/story_coop_traps.gd").apply_family(ast, {
				"root":"VCheck#0#404", "peer":"VCheck#0#393", "slot":2, "caller":"WorldScript",
				"chain":{"VTriger#0#401":"VTriger#0#394", "VCheck#0#402":"VCheck#0#396", "VTriger#0#406":"VTriger#0#398"}})
		return
	preload("res://src/game/script/story_coop_effects.gd").apply(ast, zone)
	preload("res://src/game/script/story_coop_traps.gd").apply(ast, zone)
	preload("res://src/game/script/story_coop_predicates.gd").apply(ast, zone)
	if zone == "bz1h":
		_escape_party(ast)
	if zone != "cz1h": return
	# Kel walks to (300.5, 61), but the shipped escape script tests (301, 61).
	# The ordinary route happens to cross the latter's 0.3 m circle. A route
	# around another player can finish correctly without ever crossing it.
	# Match both authored expressions so changed/modded content is untouched.
	var actor := [P.N_CALL, "GetObjectByName", [[P.N_STR, "merc2"]]]
	var move := [P.S_CALL, "MoveToPoint", [actor, [P.N_NUM, 300.5], [P.N_NUM, 61.0]]]
	var has_move := false
	for block: Dictionary in ast.scripts.get("VCheck#0#1", {}).get("blocks", []):
		if block.body.has(move): has_move = true
	if not has_move:
		return
	var check := [P.N_CALL, "IsLess", [[P.N_CALL, "DistanceUnitPoint", [actor, [P.N_NUM, 301.0],
		[P.N_NUM, 61.0]]], [P.N_NUM, 0.3]]]
	for block: Dictionary in ast.scripts.get("VCheck#0#2", {}).get("blocks", []):
		for condition: Array in block.conds:
			if condition == check:
					condition[2][0][2][1][1] = 300.5


## The original prison arms these shared quest/discovery checks once for
## each deployed hero. A late guest otherwise has no thread. Mark only the
## inspected registration loops; the VM also verifies that their complete
## trigger chains never act on the individual. Native bodies and saved
## instruction indexes remain unchanged.
static func _prison_party_checks(ast: ScriptParser) -> void:
	var parents := {
		"VTriger#0#43":["VCheck#0#44"], "VTriger#0#48":["VCheck#0#49"],
		"VTriger#0#109":["VCheck#0#106"], "VTriger#0#208":["VCheck#0#189"],
		"VTriger#0#236":["VCheck#0#237"],
		"VTriger#0#257":["VCheck#0#258","VCheck#0#352","VCheck#0#356"],
		"VTriger#0#290":["VCheck#0#289"], "VTriger#0#294":["VCheck#0#296"],
		"VTriger#0#295":["VCheck#0#297"],
	}
	for parent: String in parents:
		var blocks: Array = ast.scripts.get(parent,{}).get("blocks",[])
		if blocks.size() != 1 or not blocks[0].conds.is_empty(): continue
		var calls := []
		for child: String in parents[parent]: calls.append([P.S_CALL,child,[[P.N_VAR,"VSS#i#val"]]])
		if blocks[0].body != [[P.S_CALL,"KillScript",[]],[P.S_FOR,"VSS#i#val",[P.N_VAR,"Heroes"],calls]]: continue
		for child: String in parents[parent]:
			var def: Dictionary = ast.scripts.get(child,{})
			if def.get("params",[]) != ["this"] or def.blocks.size() != 1 or def.blocks[0].conds.is_empty(): continue
			def.party_check = true


## These prison discoveries are shared quest state: the original For loops
## give checks to initial heroes, but none to a late guest.
## Keep the native waits and their saved positions; only their eligible
## subjects expand, using the VM's existing once-per-world safety analysis.
static func _prison_discovery_checks(ast: ScriptParser) -> void:
	var chest := [P.S_SET,"HChest1",[P.N_CALL,"GetObjectByID",[[P.N_STR,"736257"]]]]
	if ast.world.count(chest) != 1 or ast.world.filter(func(st):
		return st[0] == P.S_SET and st[1] == "HChest1").size() != 1: return
	var subject := [P.N_VAR,"this"]
	var near_chest := [P.N_CALL,"IsLess",[[P.N_CALL,"DistanceUnitUnit",
		[subject,[P.N_VAR,"HChest1"]]],[P.N_NUM,7.0]]]
	var conditions := []
	for point: Vector3 in [Vector3(98,476,7),Vector3(103,486,15),Vector3(109,476,7)]:
		conditions.append([P.N_CALL,"IsLess",[[P.N_CALL,"DistanceUnitPoint",
			[subject,[P.N_NUM,point.x],[P.N_NUM,point.y]]],[P.N_NUM,point.z]]])
	conditions.append(near_chest)
	_prison_discovery_family(ast,"VTriger#0#264",
		["VCheck#0#265","VCheck#0#269","VCheck#0#271","VCheck#0#258"],conditions,
		["VTriger#0#273","VTriger#0#261"],"q.gz19h.qk16h")
	# The second discovery also names HChest1 in the shipped source. Its
	# separate HChest2 opening/reward chain remains entirely untouched.
	_prison_discovery_family(ast,"VTriger#0#278",["VCheck#0#279","VCheck#0#280"],
		[[P.N_CALL,"UnitInSquare",[subject,[P.N_NUM,45.0],[P.N_NUM,306.0],
			[P.N_NUM,113.0],[P.N_NUM,330.0]]],near_chest],
		["VTriger#0#284","VTriger#0#285"],"q.gz19h.qk17h")


static func _prison_discovery_family(ast: ScriptParser, root: String, names: Array,
		conditions: Array, triggers: Array, quest: String) -> void:
	if ast.world.count([P.S_CALL,root,[[P.N_VAR,"NULL"]]]) != 1 \
			or ast.world.filter(func(st):return st[0] == P.S_CALL and st[1] == root).size() != 1: return
	var subject := [P.N_VAR,"this"]
	var kill := [P.S_CALL,"KillScript",[]]
	var expected := {}
	var calls := []
	for i in names.size():
		var trigger: String = triggers[1] if i == names.size()-1 else triggers[0]
		expected[names[i]] = {"params":["this"],"blocks":[{"conds":[conditions[i]],
			"body":[kill,[P.S_CALL,trigger,[subject]]]}]}
		calls.append([P.S_CALL,names[i],[[P.N_VAR,"VSS#i#val"]]])
	expected[root] = {"params":["this"],"blocks":[{"conds":[],"body":[kill,
		[P.S_FOR,"VSS#i#val",[P.N_VAR,"Heroes"],calls]]}]}
	var stages := {triggers[0]:[["",1.0],[".1",2.0],[".2",1.0]],
		triggers[1]:[[".2",2.0],[".3",1.0]]}
	for name: String in stages:
		var body := [kill]
		for stage: Array in stages[name]:
			body.append([P.S_CALL,"GSSetVarMax",[[P.N_NUM,0.0],
				[P.N_STR,quest+stage[0]],[P.N_NUM,stage[1]]]])
		expected[name] = {"params":["this"],"blocks":[{"conds":[],"body":body}]}
	# Validate the complete inspected family before marking any definition.
	# A changed radius, actor action, reward or delay remains wholly authored.
	for name: String in expected:
		var actual: Dictionary = ast.scripts.get(name,{})
		if actual.get("params",[]) != expected[name].params or actual.get("blocks",[]) != expected[name].blocks: return
	for name: String in names: ast.scripts[name].party_check = true


## These remaining original prison loops also watch only startup heroes.
## Their children advance shared route stages; no child moves the intruder,
## opens a lever or gives a personal reward. The final portal's explicit
## protagonist gate and the separate quest reward continuations stay native.
static func _prison_route_checks(ast: ScriptParser) -> void:
	var subject := [P.N_VAR,"this"]
	var x := [P.N_CALL,"GetX",[subject]]
	var y := [P.N_CALL,"GetY",[subject]]
	_prison_route_family(ast,"VTriger#0#13",{
		"VCheck#0#17":[[
			[P.N_CALL,"IsLess",[x,[P.N_NUM,410.0]]],
			[P.N_CALL,"IsLess",[y,[P.N_NUM,434.0]]],
			[P.N_CALL,"IsGreater",[x,[P.N_NUM,400.0]]],
			[P.N_CALL,"IsGreater",[y,[P.N_NUM,427.0]]]],
			"VTriger#0#19",{"q.gz19h.q71h":2.0,"q.gz19h.q71h.1":2.0}]})
	_prison_route_family(ast,"VTriger#0#296",{
		"VCheck#0#295":[[[P.N_CALL,"UnitInSquare",[subject,[P.N_NUM,56.0],
			[P.N_NUM,237.0],[P.N_NUM,147.0],[P.N_NUM,263.0]]]],
			"VTriger#0#298",{"q.gz19h.q72h.2":2.0,"q.gz19h.q72h.3":1.0}],
		"VCheck#0#300":[[[P.N_CALL,"UnitInSquare",[subject,[P.N_NUM,220.0],
			[P.N_NUM,2.0],[P.N_NUM,260.0],[P.N_NUM,90.0]]]],
			"VTriger#0#302",{"q.gz19h.q72h.3":2.0,"q.gz19h.q72h.20":1.0,"q.gz19h.q72h.34":2.0}]})
	var checks := {}
	for row: Array in [
		["VCheck#0#338","MC3",7.0,"VTriger#0#326",{".10":2.0,".11":1.0,".8":1.0}],
		["VCheck#0#344",Vector2(450,105),10.0,"VTriger#0#346",{".22":2.0}],
		["VCheck#0#348",Vector2(410,170),10.0,"VTriger#0#350",{".16":2.0}],
		["VCheck#0#355","TCP-B",7.0,"VTriger#0#359",{".23":2.0,".24":1.0}],
		["VCheck#0#357","TCP-A",7.0,"VTriger#0#371",{".25":2.0,".26":1.0}],
		["VCheck#0#364","MC1",7.0,"VTriger#0#366",{".6":2.0,".7":1.0,".4":1.0}],
	]:
		var distance: Array
		if row[1] is Vector2:
			distance = [P.N_CALL,"DistanceUnitPoint",[subject,[P.N_NUM,row[1].x],[P.N_NUM,row[1].y]]]
		else: distance = [P.N_CALL,"DistanceUnitUnit",[subject,[P.N_VAR,row[1]]]]
		var stages := {}
		for suffix: String in row[4]: stages["q.gz19h.q72h"+suffix] = row[4][suffix]
		checks[row[0]] = [[[P.N_CALL,"IsLess",[distance,[P.N_NUM,row[2]]]]],row[3],stages]
	_prison_route_family(ast,"VTriger#0#333",checks,
		{"MC3":"45627","TCP-B":"43974","TCP-A":"43968","MC1":"45622"})


static func _prison_route_family(ast: ScriptParser, root: String, checks: Dictionary,
		bindings := {}) -> void:
	if ast.world.count([P.S_CALL,root,[[P.N_VAR,"NULL"]]]) != 1 \
			or ast.world.filter(func(st):return st[0] == P.S_CALL and st[1] == root).size() != 1: return
	for key: String in bindings:
		var binding := [P.S_SET,key,[P.N_CALL,"GetObjectByID",[[P.N_STR,bindings[key]]]]]
		if ast.world.count(binding) != 1 or ast.world.filter(func(st):
			return st[0] == P.S_SET and st[1] == key).size() != 1: return
	var kill := [P.S_CALL,"KillScript",[]]
	var expected := {}
	var calls := []
	for name: String in checks:
		var row: Array = checks[name]
		expected[name] = {"params":["this"],"blocks":[{"conds":row[0],
			"body":[kill,[P.S_CALL,row[1],[[P.N_VAR,"this"]]]]}]}
		var body := [kill]
		for key: String in row[2]:
			body.append([P.S_CALL,"GSSetVarMax",[[P.N_NUM,0.0],[P.N_STR,key],[P.N_NUM,row[2][key]]]])
		expected[row[1]] = {"params":["this"],"blocks":[{"conds":[],"body":body}]}
		calls.append([P.S_CALL,name,[[P.N_VAR,"VSS#i#val"]]])
	expected[root] = {"params":["this"],"blocks":[{"conds":[],"body":[kill,
		[P.S_FOR,"VSS#i#val",[P.N_VAR,"Heroes"],calls]]}]}
	# Admit each complete family atomically, including its original geometry,
	# registration order, bindings and quest writes. Mods keep their own rules.
	for name: String in expected:
		var actual: Dictionary = ast.scripts.get(name,{})
		if actual.get("params",[]) != expected[name].params or actual.get("blocks",[]) != expected[name].blocks: return
	for name: String in checks: ast.scripts[name].party_check = true


## The slave-camp escape predates co-op: only Kir and Kel receive its
## running order, and only their arrival starts Terror's attack. Extend the
## staging to every live guest before releasing that attack. Guests must
## continue beyond the two original marks, leaving room to flee the first
## fireball rather than crowding Kir and Kel as soon as they cross the gate.
static func _escape_party(ast: ScriptParser) -> void:
	var hero := [P.N_CALL,"GetUnitOfPlayer",[[P.N_NUM,0.0],[P.N_NUM,0.0]]]
	var move := [P.S_CALL,"MoveToPoint",[hero,[P.N_NUM,407.0],[P.N_NUM,82.0]]]
	var found := false
	for b: Dictionary in ast.scripts.get("VCheck#1#1",{}).get("blocks",[]):
		if b.body.has(move): found = true
	if not found: return
	var ready := [P.N_CALL,"IsLess",[[P.N_CALL,"GetY",[hero]],[P.N_NUM,84.0]]]
	for b: Dictionary in ast.scripts.get("VCheck#1#1a",{}).get("blocks",[]):
		if b.conds.has(ready):
			b.conds.append([P.N_CALL,"RemakeEscapeReady",[]])


static func escape_guests(vm: ScriptVM) -> Array:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL or vm.world.zone.get("id", "") != "bz1h": return []
	var story := vm._story_records()
	return vm._party_records().filter(func(u: GameUnit): return u.controller > 0 and not story.has(u) and not u.dead and not u.hidden)


static func story_move(vm: ScriptVM, script: String, unit: GameUnit, to: Vector2) -> void:
	if script != "VCheck#1#1" or to != Vector2(407,82): return
	var story := vm._story_records()
	if story.is_empty() or unit != story[0]: return
	var guests := escape_guests(vm)
	for i in guests.size(): _run_escape_guest(guests[i],i)


static func _run_escape_guest(guest: GameUnit, index: int) -> void:
	guest.set_gait(3)
	guest.command({"type":"move", "to":Vector2(407,78.5-1.5*index), "run":true, "story_move":true})
	guest.set_meta("ai_state",1)


static func escape_ready(vm: ScriptVM) -> bool:
	var guests := escape_guests(vm)
	var ready := true
	for i in guests.size():
		var guest: GameUnit = guests[i]
		if guest.pos.y < 80.0: continue
		ready = false
		# A temporary crowd can exhaust a route, and a guest can join after
		# the single authored MoveToPoint. Continue idle guests during this
		# arrival wait without replacing an active player command.
		if guest.is_idle(): _run_escape_guest(guest,i)
	return ready


## The stationary call switch only starts Lift#01 once in the original.
## Reuse it at the lower stop so a separated party can call the lift back.
## The original up/down threads, timing and moving controls remain in charge.
static func lift_recall(vm: ScriptVM, nid: int) -> void:
	if nid != 1369841 or vm.session.state.campaign_id != CampaignProfile.ASTRAL \
			or vm.world.zone.get("id", "") != "gz1d2": return
	var w := vm.world
	var lift: Node3D = w.objects.get(2240358)
	if lift == null or lift.get_meta("ei", {}).get("template", "") != "stbr6": return
	if not vm.ast.scripts.has("Lift#11") or not vm.ast.scripts.has("Lift#12"): return
	if vm.instances.any(func(i): return i.sname == "Lift#01" and (not i.killed or not i.frames.is_empty())): return
	if int(w.levers.get(338779, {}).get("state", -1)) != 0 \
			or int(w.levers.get(1357456, {}).get("state", -1)) != 0 \
			or not is_equal_approx(float(lift.get_meta("ei").position.z), -0.3): return
	var time := w.lever_sys.set_state(338779, 1)
	vm.session.broadcast({"t":"lever", "nid":338779, "state":1, "time":time})


## Earlier saves kept VM waits but lost the corresponding walking orders.
## Recover inspected active trap families and the two proven escape waits.
static func recover(vm: ScriptVM) -> void:
	# Only definitions installed by apply() can be recovered, in either campaign.
	preload("res://src/game/script/story_coop_traps.gd").recover(vm)
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL: return
	var zone := String(vm.world.zone.get("id", ""))
	if zone == "gz1h":
		_recover_terror(vm)
	if zone == "bz2h":
		_recover_kel(vm)
	if zone == "bz1h" and vm.instances.any(func(i): return i.sname == "VCheck#1#1a" and not i.killed):
		# Old saves kept this arrival wait without guest escape orders.
		var hero := vm._by_name("Hero") as GameUnit
		if hero: story_move(vm,"VCheck#1#1",hero,Vector2(407,82))
		return
	if zone not in ["bz1r", "cz1h"]: return
	if not vm.instances.any(func(i): return i.sname == "VCheck#0#2" and not i.killed): return
	var u := vm.briefings._actor_unit("hero" if zone == "bz1r" else "merc2", 0)
	if u == null or not u.is_idle(): return
	var at := Vector2(50,150) if zone == "bz1r" else Vector2(300.5,61)
	var actor := [P.N_CALL,"GetObjectByName",[[P.N_STR,"Hero" if zone == "bz1r" else "merc2"]]]
	var test := [P.N_CALL,"IsLess",[[P.N_CALL,"DistanceUnitPoint",[actor,[P.N_NUM,at.x],[P.N_NUM,at.y]]],
		[P.N_NUM,0.5 if zone == "bz1r" else 0.3]]]
	for block: Dictionary in vm.ast.scripts.get("VCheck#0#2",{}).get("blocks",[]):
		if block.conds.has(test) and u.pos.distance_to(at) >= float(test[2][1][1]):
			u.command({"type":"move", "to":at, "run":false, "story_move":true})
			u.set_meta("ai_state",1)
			return


## Old builds could reload zone1evil.mob after Terror's removal, then save
## that resurrected actor as alive. Absence-based migration cannot repair
## those saves. The original escape flag and despawn bodies establish that
## this Portal actor has already left. A save in the seven-tick disappearance
## animation still has a running removal frame; let that frame finish normally.
static func _recover_terror(vm: ScriptVM) -> void:
	if vm.session.state.get_var(0,"q.gz1h.q02h.2") != 2.0: return
	if not vm.world.get_meta("added_mobs",[]).any(func(file): return String(file).to_lower() == "zone1evil.mob"): return
	var target := [P.N_CALL,"GetObject",[[P.N_NUM,666666.0]]]
	var done := [P.S_CALL,"GSSetVarMax",[[P.N_NUM,0.0],[P.N_STR,"q.gz1h.q02h.2"],[P.N_NUM,2.0]]]
	var remove := [P.S_CALL,"RemoveUnitFromServer",[target]]
	var names := ["VCheck#1#8a","VTriger#1#2"]
	for name: String in names:
		var blocks: Array = vm.ast.scripts.get(name,{}).get("blocks",[])
		if blocks.size() != 1: return
		var body: Array = blocks[0].body
		var at := body.find(remove)
		if not body.has(done) or at < 1 or body[at-1] != [P.S_CALL,"Sleep",[[P.N_NUM,7.0]]]: return
	if vm.instances.any(func(i): return i.sname in names and not i.frames.is_empty()): return
	var terror: GameUnit = vm.world.units.get(666666)
	if terror:
		vm.world.remove_unit(terror)
		GameData.trace("restored completed Portal escape: removed resurrected Terror")


## Older builds deleted Kel when the first Shelter briefing removed him
## from FPrison. Native scripts keep that actor hidden, then reveal him when
## Shaina's disguise hand-in finishes. Only repair this inspected old-save
## contract; new snapshots explicitly track actors detached from a party.
static func _recover_kel(vm: ScriptVM) -> void:
	var st := vm.session.state
	var saved: Dictionary = st.zones.get("bz2h", {})
	if saved.has("detached") or st.get_var(0,"b.bz2h.brief_6") != 2.0 \
			or st.get_var(0,"adeadn2") != 0.0 or vm._by_name("merc2") != null: return
	var nid := ScriptVM.name_id("merc2")
	if nid in saved.get("dead", []) or nid in saved.get("removed", []): return
	var actor := [P.N_CALL,"GetObjectByName",[[P.N_STR,"merc2"]]]
	var place := [P.S_CALL,"SetCP",[actor,[P.N_NUM,83.5],[P.N_NUM,233.0],[P.N_NUM,0.0]]]
	var remove := [P.S_CALL,"RemoveUnitFromParty",[[P.N_NUM,0.0],[P.N_STR,"FPrison::merc2"]]]
	var hide := [P.S_CALL,"HideObject",[actor,[P.N_NUM,1.0]]]
	var reveal := [P.S_CALL,"HideObject",[actor,[P.N_NUM,0.0]]]
	if not vm.ast.scripts.get("Start",{}).get("blocks",[]).any(func(b):return b.body.has(place)): return
	if not vm.ast.scripts.get("#OnBriefingComplete",{}).get("blocks",[]).any(func(b):return b.body.has(remove) and b.body.has(hide)): return
	if not vm.ast.scripts.get("VCheck#1#2",{}).get("blocks",[]).any(func(b):return b.body.has(reveal)): return
	var rec := {"kind":"UNIT", "type":50, "nid":nid, "name":"merc2", "prototype":"merc2",
		"parent_template":"merc2", "position":Vector3(83.5,233,0), "player":0}
	var kel := vm.world.spawn_unit(rec)
	if kel == null: return
	kel.controller = -1
	kel.set_meta("detached_party_npc", true)
	kel.hidden = st.get_var(0,"Trans") < 1.0
	kel.visible = not kel.hidden
	kel.facing = atan2(-1.0, 1.0)
	GameData.trace("restored missing Shelter Kel from the original briefing contract")
