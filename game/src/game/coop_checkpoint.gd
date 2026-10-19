extends RefCounted
## Provenance for a complete shared story checkpoint. Personal training and
## inventory are independent; changing story, location or chapter invalidates
## the receipt. This is a consistency checksum, not client authentication.

static func story(st: CampaignState, zone := "") -> Dictionary:
	var vars := {}
	for key: String in st.vars:
		if key.begins_with("0:"): vars[key.substr(2)] = st.vars[key]
	return {"vars":vars, "visited":st.visited, "side_quests":st.side_quests,
		"quest_items":st.quest_items, "zone":st.current_zone if zone.is_empty() else zone,
		"party_context":CoopProgress.PartyProgress.capture(st)}

static func signature(data: Dictionary) -> String:
	var context: Variant = data.get("party_context")
	if not context is Dictionary or not context.get("roster") is Array or context.roster.is_empty(): return ""
	var lead: Variant = context.roster[0]
	if not lead is Dictionary: return ""
	var vars := {}
	for key: String in data.get("vars", {}):
		var value := float(data.vars[key])
		if value != 0.0 and not CoopProgress.excluded(key): vars[key] = value
	var visited: Array = data.get("visited", {}).keys() if data.get("visited") is Dictionary else Array(data.get("visited", []))
	visited.sort()
	return JSON.stringify([vars, visited, data.get("side_quests", {}), data.get("quest_items", {}),
		data.get("zone", ""), context.get("current_party", ""), lead.get("prototype", ""),
		lead.get("unit_name", "Hero")], "", true).sha256_text()

static func receipts(st: CampaignState) -> Dictionary:
	var out := {}
	var current := signature(story(st))
	var world := world_signature(st)
	for sid: String in st.coop.get("applied", {}):
		var entry: Variant = st.coop.applied[sid]
		if entry is Dictionary and entry.get("checkpoint", "") == current and not current.is_empty() \
				and entry.get("checkpoint_world", "") == world:
			out[sid] = current
	return out

static func world_signature(st: CampaignState) -> String:
	# Killing/looting in solo play may leave quest variables unchanged. A
	# changed persistent world is still independent progress, not a receipt.
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(st.zones))
	return hash.finish().hex_encode()

static func eligible(e: Dictionary, data: Dictionary, st: CampaignState, zone: String) -> bool:
	var sid := String(e.get("sid", ""))
	var receipt := String(data.get("checkpoints", {}).get(sid, ""))
	if receipt.is_empty() or receipt != signature(data): return false
	if String(e.get("checkpoint_host", "")) != signature(story(st, zone)): return false
	if String(e.get("checkpoint_world", "")) != world_signature(st): return false
	# A different authored party/body still uses the existing chapter guards.
	var old: Variant = e.get("party_context")
	var incoming: Variant = data.get("party_context")
	return old is Dictionary and incoming is Dictionary \
		and old.get("current_party") == incoming.get("current_party") \
		and not old.get("roster", []).is_empty() and not incoming.get("roster", []).is_empty() \
		and old.roster[0].get("prototype") == incoming.roster[0].get("prototype")

static func adopt(e: Dictionary, st: CampaignState) -> void:
	var current := story(st)
	# The selected origin is unchanged since its acknowledged shared save.
	# Replace its story with the host's chosen shared checkpoint, including
	# removals; carry its own character, equipment and purse through normally.
	e.vars = current.vars.duplicate(true)
	e.visited = st.visited.duplicate()
	e.side_quests = st.side_quests.duplicate(true)
	e.quest_items = st.quest_items.duplicate(true)
	var credited := {}
	for key: String in current.vars:
		if not CoopProgress.excluded(key): credited[key] = current.vars[key]
	e.credits = {"vars":credited, "visited":st.visited.duplicate(),
		"side_quests":st.side_quests.duplicate(true), "quest_items":st.quest_items.duplicate(true),
		"zones":st.zones.duplicate(true)}
	e.replace_checkpoint = true

static func clear_story(st: CampaignState) -> void:
	for key: String in st.vars.keys():
		if key.begins_with("0:") and not CoopProgress.excluded(key.substr(2)): st.set_var(0, key.substr(2), 0.0)
	st.quests.clear(); st.visited.clear(); st.zones.clear()
	st.quest_items.clear(); st.side_quests.clear()
