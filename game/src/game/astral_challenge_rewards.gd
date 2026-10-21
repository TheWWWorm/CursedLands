extends RefCounted
## Reviewed LiA challenge rewards, deliberately additional to original data.
## Authored placement IDs and source values keep new/modded enemies unchanged.
## The campaign claim survives saves, travel, resurrection and population resets.
static func rows() -> Dictionary:
	return preload("res://src/game/astral_challenge_reward_data.gd").ROWS

static func claim(w: GameWorld, victim: GameUnit, killer: GameUnit) -> Dictionary:
	var s := w.session
	if s == null or not w.authority or s.state.campaign_id != CampaignProfile.ASTRAL or not s.lmp.is_empty() \
		or not is_instance_valid(killer) or XpRules.party_of(killer) < 0 or XpRules.party_of(victim) >= 0 \
		or victim.has_meta("hero") or not victim.dead:
		return {}
	var zone := String(w.zone.get("id", ""))
	var name := String(victim.proto.get("name", "")).to_lower()
	var row: Dictionary = rows().get(zone, {}).get(name, {})
	if row.is_empty() or not row.ids.has(victim.uid): return {}
	for key: String in row.source:
		var value: Variant = victim.proto.get(key)
		if row.source[key] is Array:
			if typeof(value) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY]: return {}
			value = Array(value)
		if typeof(value) == TYPE_FLOAT and row.source[key] is float:
			if PackedFloat32Array([value])[0] != PackedFloat32Array([row.source[key]])[0]: return {}
		elif value != row.source[key]: return {} # preserve active data-mod changes
	var flag := "remake.challenge_reward.%s.%d" % [zone, victim.uid]
	if s.state.get_var(0, flag) != 0.0: return {}
	s.state.set_var(0, flag, 1.0)
	return {"xp":float(row.xp), "items":Array(row.items).duplicate()}
