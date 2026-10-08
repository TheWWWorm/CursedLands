extends RefCounted
## A guest's resumable story parties. These records never deploy in the host's
## world: original party operations run on this private copy, using the guest's
## own character/bags. Shared story companions and personally owned dependents
## are refreshed at a credited checkpoint.

static func capture(st: CampaignState) -> Dictionary:
	return {"version": 1, "current_party": st.current_party,
		"roster": st.heroes.get(0, []), "parties": st.parties,
		"money": st.money, "items": st.items, "party_bags": st.party_bags,
		"mercs": st.mercs, "pets": st.pets}.duplicate(true)


static func record_ok(h: Variant) -> bool:
	if not h is Dictionary or not h.get("prototype") is String:
		return false
	for k in ["name", "unit_name", "party", "voice"]:
		if h.has(k) and not h[k] is String: return false
	for k in ["str", "dex", "int", "exp", "exp_total", "level", "hp", "mana", "controller", "merc"]:
		if h.has(k) and (not (h[k] is int or h[k] is float) or not is_finite(float(h[k]))): return false
	for k in ["armors", "weapons", "quick", "spells", "perks"]:
		if h.has(k) and (not (h[k] is Array or h[k] is PackedStringArray) or not Array(h[k]).all(func(x): return x is String)):
			return false
	for k in ["skills", "body", CampaignState.TrainingRefund.KEY]:
		if h.has(k) and not h[k] is Dictionary: return false
	return true


static func read(value: Variant) -> CampaignState:
	if not value is Dictionary or value.get("version") != 1 \
			or not value.get("current_party") is String or not value.get("roster") is Array \
			or not value.get("parties") is Dictionary or not value.get("party_bags") is Dictionary \
			or not value.get("mercs") is Dictionary or not value.get("pets") is Array \
			or not value.get("items") is Array or not value.get("money") is int:
		return null
	# The imported context is used only for its owner's progress copy. Bound its
	# size and reject broken containers instead of partially losing a party.
	if value.parties.size() > 32 or value.party_bags.size() > 32 or value.mercs.size() > 64 \
			or value.pets.size() > 128 or var_to_bytes(value).size() > 2097152:
		return null
	for roster in [value.roster] + value.parties.values():
		if not roster is Array or roster.size() > 32:
			return null
		for h in roster:
			if not record_ok(h):
				return null
	for name in value.parties:
		if not name is String or name.length() > 64 or name == value.current_party:
			return null
	for name in value.party_bags:
		var b: Variant = value.party_bags[name]
		if not name is String or not b is Dictionary or not b.get("items") is Array or not b.get("money") is int:
			return null
	for n in value.mercs:
		if not (n is int or (n is String and n.is_valid_int())) or not record_ok(value.mercs[n]):
			return null
	for pet in value.pets:
		if not pet is Dictionary or not pet.get("rec") is Dictionary:
			return null
	var d: Dictionary = value.duplicate(true)
	var st := CampaignState.new()
	st.current_party = d.current_party
	st.heroes[0] = d.roster
	for k in ["parties", "party_bags", "money", "items", "mercs", "pets"]:
		st.set(k, d[k])
	return st


static func apply(st: CampaignState, context: CampaignState) -> void:
	var previous := st.mercs.keys()
	st.current_party = context.current_party
	st.heroes[0] = context.heroes.get(0, []).duplicate(true)
	for k in ["parties", "party_bags", "items", "mercs", "pets"]:
		st.set(k, context.get(k).duplicate(true))
	st.money = context.money
	# Hiring flags are not general quest credit. They belong to the companion
	# record returned to this particular player.
	for n in previous:
		if not st.mercs.has(n): st.set_var(0, "apartyn%d" % int(n), 0.0)
	for n in st.mercs:
		st.set_var(0, "apartyn%d" % int(n), 1.0)
		st.set_var(0, "adeadn%d" % int(n), 1.0 if st.mercs[n].get("dead", false) else 0.0)


## Preserve the authored role/body and original personal display name while
## carrying back the guest's earned skills, gear and purse. A substitute such
## as Shaina/Nalo keeps its own record; the imported protagonist waits.
static func personal(st: CampaignState, hero: Dictionary, purse: Dictionary, positions: bool) -> void:
	var name := CoopProgress.main_party(st)
	var roster := st._party_roster(name, true)
	var old: Dictionary = roster[0] if not roster.is_empty() else {}
	var h := CoopProgress.sanitize_hero(hero)
	if not h.is_empty():
		for k in ["prototype", "unit_name", "complexion", "voice", "name"]:
			if old.has(k): h[k] = old[k]
			elif k == "unit_name": h.erase(k)   # keep the original main Hero fallback
		var body: Dictionary = hero if positions and st.current_party == name else old
		for k in ["pos", "mana", "gait", "hp", "body", "dead", "blood_pool"]:
			if body.has(k): h[k] = body[k].duplicate(true) if body[k] is Dictionary or body[k] is Array else body[k]
			elif k in ["pos", "mana", "gait"]: h.erase(k)
		if roster.is_empty(): roster.append(h)
		else: roster[0] = h
	var bag := st._bag(name)
	bag.items = CoopProgress._items(purse.get("items", []))
	bag.money = maxi(0, int(purse.get("money", 0)))
	if name == st.current_party:
		st.items = bag.items
		st.money = bag.money
	elif st.campaign_id == CampaignProfile.ORIGINAL and st.current_party in ["HeroAlone", "JunParty"]:
		var active := st._party_roster(st.current_party)
		if not active.is_empty():
			st.copy_stats("Hero", st.current_party + "::" + String(active[0].get("unit_name", "Hero")))


## Use the same implementation as the real campaign, in the same order.
static func operation(st: CampaignState, op: String, args: Array) -> void:
	match op:
		"CreateParty": st.create_party(str(args[1]))
		"AddUnitToParty":
			var ref := str(args[1])
			st.add_party_unit(ref.get_slice("::", 0) if "::" in ref else "", ref.get_slice("::", 1) if "::" in ref else ref, str(args[2]))
		"CopyStats": st.copy_stats(str(args[1]), str(args[2]))
		"CopyItems": st.copy_items(str(args[1]), str(args[2]))
		"SetCurrentParty": st.set_current_party(str(args[1]))
		"CopyLoot", "AddLoot": st.move_loot(str(args[1]), str(args[2]), op == "CopyLoot")
		"RemoveUnitFromParty":
			var h := st.party_member(str(args[1]))
			if h.has("merc"): st.mercs.erase(int(h.merc))
			else: st.remove_party_unit(str(args[1]))
		"FixItems": st.fix_items()


static func protagonist(party: String, index: int, h: Dictionary) -> bool:
	return (party == "JunParty" and index == 0) or String(h.get("unit_name", "Hero" if party.is_empty() and index == 0 else "")).to_lower().begins_with("hero")


static func companion(h: Dictionary, lead: Dictionary) -> Dictionary:
	var out := h.duplicate(true)
	out.controller = 0
	for key in ["follow", "follow_live"]:
		var ref: Variant = out.get(key)
		if ref is Array and ref.size() >= 3 and ref[0] == "hero":
			out[key] = ["hero", String(lead.get("unit_name", lead.get("name", "Hero"))), 0]
	return out


static func dependents(st: CampaignState, host: CampaignState, entry: Dictionary) -> void:
	var lead := CoopProgress.main_hero(st)
	# Units authored inside a named party are shared narrative roles (Kel,
	# Nalo, Shaina), independent of who controlled them in co-op.
	for party: String in [host.current_party] + host.parties.keys():
		var source := host._party_roster(party)
		var dest := st._party_roster(party)
		for i in mini(source.size(), dest.size()):
			if not protagonist(party, i, source[i]):
				dest[i] = companion(source[i], lead)
	# Keep companions left in the imported save. Refresh/dismiss ones that
	# joined this session; other players' optional hires stay with their owner.
	for n in entry.get("context_mercs", []): st.mercs.erase(n)
	var carried := []
	for n in host.mercs:
		var m: Dictionary = host.mercs[n]
		if int(m.get("controller", 0)) == int(entry.idx) or host.campaign_id == CampaignProfile.ASTRAL:
			st.mercs[n] = companion(m, lead)
			carried.append(n)
	entry.context_mercs = carried
	# Imported animals were not brought into the host's world. Preserve them;
	# replace this session's personal animals as a group, including deaths.
	var previous: Array = entry.get("context_pets", [])
	for p in previous: st.pets.erase(p)
	var current := []
	for p: Dictionary in host.pets:
		if int(p.get("controller", 0)) == int(entry.idx):
			var own := companion(p, lead)
			st.pets.append(own)
			current.append(own.duplicate(true))
	entry.context_pets = current
