extends RefCounted
## Narrow repairs to authored script contracts, without editing game assets.
const P := preload("res://src/game/script/script_parser.gd")

static func apply(ast: ScriptParser, campaign: String, zone: String) -> void:
	if campaign != CampaignProfile.ASTRAL or zone != "cz1h":
		return
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


## Earlier saves kept VM waits but lost the corresponding walking orders.
## Only the two proven escape waits can be recovered from their exact marks.
static func recover(vm: ScriptVM) -> void:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL: return
	var zone := String(vm.world.zone.get("id", ""))
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
