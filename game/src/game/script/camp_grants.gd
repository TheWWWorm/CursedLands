extends RefCounted
## LiA's clerk initializes Kir and Kel, once per character. Extra campaign
## heroes share Kir's choice; Kel remains one named companion, regardless of
## which peer controls him. Receipts travel with the character's own save.
const KEY := "lia_camp_choice"
const HERO := {
	"a": {"str": 5, "dex": -5, "science": 6},
	"b": {"str": 5, "dex": -5, "science": 6},
	"c": {"str": 5, "dex": -5, "science": 6},
	"d": {"str": -4, "dex": 5, "science": 6},
	"e": {"str": -5, "int": 5, "science": 6},
	"f": {"str": -5, "int": 5},
}
const KEL := {
	"a": {"str": 5, "dex": -5, "science": 6, "melee": 3},
	"b": {"str": -4, "dex": 5, "science": 2, "melee": 3},
	"c": {"str": -5, "int": 5, "science": 2, "melee": 3},
	"d": {"str": -4, "dex": 5, "archery": 3},
	"e": {"str": -4, "dex": 5, "archery": 3},
	"f": {"str": -5, "int": 5, "astral": 3},
}

static func chosen(st: CampaignState) -> String:
	if st.campaign_id != CampaignProfile.ASTRAL:
		return ""
	var found := ""
	for branch: String in HERO:
		if st.get_var(0, "b.Clerk.brief_3" + branch) == 2.0:
			if not found.is_empty(): return ""
			found = branch
	return found

static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("branch") in HERO or value.get("role") not in ["hero", "kel"] \
			or not value.get("effects") is Array:
		return {}
	var plan: Dictionary = (HERO if value.role == "hero" else KEL)[value.branch]
	var effects := []
	for effect: Variant in value.effects:
		if effect is String and plan.has(effect) and not effects.has(effect):
			effects.append(effect)
	return {"branch": value.branch, "role": value.role, "effects": effects}

static func grant(h: Dictionary, branch: String, role: String, effect: String, unit: GameUnit = null) -> bool:
	var receipt := sanitize(h.get(KEY))
	if not receipt.is_empty() and (receipt.branch != branch or receipt.role != role or receipt.effects.has(effect)):
		return false
	if receipt.is_empty(): receipt = {"branch": branch, "role": role, "effects": []}
	var amount := int((HERO if role == "hero" else KEL)[branch][effect])
	if effect in ["str", "dex", "int"]:
		h[effect] = float(h.get(effect, 25.0)) + amount
		if effect != "int":
			var c: Vector3 = unit.info.get("complexion", h.get("complexion", Vector3(.5,.5,.5))) if unit else h.get("complexion", Vector3(.5,.5,.5))
			if effect == "str": c.y += 0.2
			else: c.x = maxf(c.x - 0.2, 0.0)
			if unit: Combat.set_complexion(unit, h, c)
			else: h.complexion = c
	else:
		h.get_or_add("skills", {})[effect] = Skills.level(h, effect) + amount
	receipt.effects.append(effect)
	h[KEY] = receipt
	return true

## Only intercept the six proven initialization scripts and their exact
## authored deltas. Other script grants keep their single-target semantics.
static func apply(vm: ScriptVM, script: String, call_name: String, args: Array, unit: GameUnit) -> bool:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL or vm.world.zone.get("id") != "bz1h" \
			or not vm.session.lmp.is_empty() or unit == null or not script.begins_with("VCheck#0#"):
		return false
	var number := script.trim_prefix("VCheck#0#")
	if number not in ["2", "3", "4", "5", "6", "7"]: return false
	var branch: String = ["a", "b", "c", "d", "e", "f"][int(number) - 2]
	if chosen(vm.session.state) != branch: return false
	var hd := CampaignState.script_character(unit, true)
	if hd.is_empty(): return false
	var role := "kel" if unit.uid == ScriptVM.name_id("merc2") else "hero" if unit.controller == 0 \
		and unit.has_meta("hero") and not hd.has("merc") else ""
	if role.is_empty(): return false
	var effect := String(args[1]).to_lower() if call_name == "GiveSkill" and args.size() == 3 \
		else {"GiveStrength":"str", "GiveDexterity":"dex", "GiveIntelligence":"int"}.get(call_name, "") as String
	var plan: Dictionary = (HERO if role == "hero" else KEL)[branch]
	if args.size() < 2 or not plan.has(effect) or float(args[-1]) != float(plan[effect]): return false
	var records: Array = [hd]
	if role == "hero" and vm.session.multiplayer_game:
		for index in vm.session.state.heroes:
			var roster: Array = vm.session.state.heroes[index]
			if int(index) > 0 and not roster.is_empty(): records.append(roster[0])
	for record: Dictionary in records:
		var live: GameUnit = null
		for candidate: GameUnit in vm.world.units.values():
			if is_same(CampaignState.script_character(candidate), record):
				live = candidate
				break
		if grant(record, branch, role, effect, live) and live:
			vm.session._refresh_character(live, record)
	vm.session.mark_dirty()
	return true

## A reliable chosen branch plus untouched prototype attributes identifies
## the old 25/25/25 guest failure. Modified legacy records are left alone.
## Partial new receipts can safely finish after reload or a later join.
static func catch_up(st: CampaignState, index: int) -> bool:
	if index <= 0: return false
	var branch := chosen(st)
	var roster: Array = st.heroes.get(index, [])
	if branch.is_empty() or roster.is_empty(): return false
	var h: Dictionary = roster[0]
	var receipt := sanitize(h.get(KEY))
	if receipt.is_empty():
		if String(h.get("prototype", "")).nocasecmp_to("Human Hero") != 0: return false
		var npc := GameData.db.find("npcs", "Human Hero")
		for attr in ["str", "dex", "int"]:
			if float(h.get(attr, 0.0)) != float(npc.get(attr, 25.0)): return false
	var changed := false
	for effect: String in HERO[branch]:
		changed = grant(h, branch, "hero", effect) or changed
	return changed
