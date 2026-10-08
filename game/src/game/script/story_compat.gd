extends RefCounted
## Narrow repairs to authored script contracts, without editing game assets.
const P := preload("res://src/game/script/script_parser.gd")

static func apply(ast: ScriptParser, campaign: String, zone: String) -> void:
	if campaign != CampaignProfile.ASTRAL:
		if campaign == CampaignProfile.ORIGINAL:
			preload("res://src/game/script/story_coop_predicates.gd").apply_original(ast,zone)
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
