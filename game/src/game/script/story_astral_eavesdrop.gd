extends RefCounted
## Repair the original q12h dead-speaker branch without claiming it was heard.
## Normal stealth geometry, timers, rescue and rewards remain authored.
const P := preload("res://src/game/script/script_parser.gd")
const FINGERPRINTS := {
	"VCheck#5#1": "383be3cbf5829d1d19aa26c058905eeaceb0030a2a9bcfe1347bbbcfc7fe4199",
	"VCheck#5#2": "09f6fdb5cce892d653ee106a3fd83a265e31d81aef6a62496c2d882897420bf6",
	"VCheck#5#3": "b7bcdbd4318269335b3a8acd9039ff1a612e0e74b6e2a40248f59324675d1140",
	"VCheck#5#4": "f0edab1d055d69a78a403afc8b7ef3850f8b631b29e9835a6b827a5c65f93b62",
	"VCheck#5#5": "95a8a5af4049a7c7a6516892eb38eca60817ddc18c14938a8d2ab7d84eebc0ed",
	"VCheck#5#6": "a3e6b4fb49c8bcdaa216d34b8d0531e8d075f97f603713d4da0d79a38e7662dc",
	"VCheck#5#7": "43965af63eac95c6735520f6726b451869ca5e48cc9953d87b20d925c34d7756",
	"VCheck#5#8": "955951743dd5fab203c1d0fb3852306a55a1863341f1a139d3dc948b99a31c3d"
}
const QUEST := "q.gz1h.q12h"

static func apply(ast: ScriptParser) -> void:
	for name: String in FINGERPRINTS:
		if JSON.stringify(ast.scripts.get(name, {})).sha256_text() != FINGERPRINTS[name]: return
	ast.set_meta(&"astral_eavesdrop", true)
	for name: String in ["VCheck#5#2", "VCheck#5#3"]:
		# Preserve statement positions for suspended saves. A failed listening
		# stage must never turn into a completed one after resurrection.
		ast.scripts[name].blocks[0].conds.append([P.N_CALL, "IsLess", [
			[P.N_CALL, "GSGetVar", [[P.N_NUM, 0.0], [P.N_STR, QUEST+".2"]]], [P.N_NUM, 3.0]]])

static func recover(vm: ScriptVM) -> void:
	if not vm.ast.has_meta(&"astral_eavesdrop") or vm.session.state.campaign_id != CampaignProfile.ASTRAL \
		or String(vm.world.zone.get("id", "")) != "gz1h": return
	var state := vm.session.state
	if state.get_var(0, QUEST) != 1.0 or state.get_var(0, QUEST+".2") == 2.0: return
	if state.get_var(0, QUEST+".2") == 3.0 and (not _dead(vm, 1012005) or state.get_var(0, QUEST+".3") >= 2.0): return
	var first := _dead(vm, 1012004)
	var second := _dead(vm, 1012005)
	if not first and not second: return
	_raise(state, ".1", 2.0)
	_raise(state, ".2", 3.0)
	_raise(state, ".4", 1.0)
	# The independent original guard/captive watcher still owns rescue,
	# escort, the completion reward and captive-death failure.
	if second: _raise(state, ".3", 2.0)
	vm.session.sync_state()

static func _dead(vm: ScriptVM, id: int) -> bool:
	var u: GameUnit = vm.world.units.get(id, vm.world.looted.get(id))
	return u != null and u.dead and String(u.proto.get("name", "")).to_lower() == "q12h human citizen m"

static func _raise(state: CampaignState, suffix: String, value: float) -> void:
	state.set_var(0, QUEST+suffix, maxf(state.get_var(0, QUEST+suffix), value))
