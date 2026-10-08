extends RefCounted
## Narrow repairs to authored script contracts, without editing game assets.
const P := preload("res://src/game/script/script_parser.gd")

static func apply(ast: ScriptParser, campaign: String, zone: String) -> void:
	if campaign != CampaignProfile.ASTRAL:
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
## exact authored staging to every live guest before releasing that attack.
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
	var i := 0
	for guest: GameUnit in escape_guests(vm):
		i += 1
		guest.set_gait(3)
		guest.command({"type":"move", "to":to+Vector2(0,-1.1*i), "run":true, "story_move":true})
		guest.set_meta("ai_state",1)


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
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL: return
	preload("res://src/game/script/story_coop_traps.gd").recover(vm)
	var zone := String(vm.world.zone.get("id", ""))
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
