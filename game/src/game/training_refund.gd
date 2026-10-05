extends RefCounted
## Remake redistribution. Keep paid training separate from the character's
## starting allocations and script gifts; only successful purchases enter it.

const KEY := "training_refund"
const VERSION := 1
const LEGACY_REASON := "This older character's paid training cannot be reconstructed safely. New characters keep an exact purchase record."
const COPIED_PARTIES := ["JunParty", "HeroAlone"]
const FREE_SKILLS := {"b.daughter.z18": "sense", "b.mthief.MThief1": "science"}


static func start(h: Dictionary) -> void:
	var origin := String(h.get("prototype", ""))
	var npc := GameData.db.find("npcs", origin)
	h[KEY] = {"version": VERSION, "origin": origin,
		"base_exp": float(npc.get("experience", 0.0)),
		"base_skills": Dictionary(h.get("skills", {})).duplicate(),
		"base_perks": Array(h.get("perks", [])).duplicate(),
		"skills": {}, "perks": [], "spent": 0.0, "ambiguous": false}


static func record_skill(h: Dictionary, skill: String, cost: int) -> void:
	prepare(h)
	var record: Dictionary = h[KEY]
	record.skills[skill] = int(record.skills.get(skill, 0)) + 1
	record.spent = float(record.spent) + cost


static func record_perk(h: Dictionary, code: String, cost: int) -> void:
	prepare(h)
	var record: Dictionary = h[KEY]
	record.perks.append(code)
	record.spent = float(record.spent) + cost


static func amount(h: Dictionary) -> float:
	var record: Variant = h.get(KEY)
	return float(record.spent) if _valid(h, record) and not bool(record.ambiguous) else 0.0


static func reason(h: Dictionary) -> String:
	var record: Variant = h.get(KEY)
	if not _valid(h, record) or bool(record.ambiguous):
		return LEGACY_REASON
	return "No spent points to refund." if float(record.spent) <= 0.0 else ""


static func refund(h: Dictionary) -> bool:
	prepare(h)
	if amount(h) <= 0.0:
		return false
	var record: Dictionary = h[KEY]
	var skills: Dictionary = Dictionary(h.get("skills", {})).duplicate()
	var perks: Array = Array(h.get("perks", [])).duplicate()
	for skill: String in record.skills:
		skills[skill] = int(skills.get(skill, 0)) - int(record.skills[skill])
		if int(skills[skill]) == 0 and not record.base_skills.has(skill):
			skills.erase(skill)
	# Remove from the end so a free starting rank is never taken in place of a
	# purchased one. The native rank prerequisites prevent duplicate purchases.
	for code: String in record.perks:
		perks.remove_at(perks.rfind(code))
	h.skills = skills
	h.perks = perks
	h.exp = float(h.get("exp", 0.0)) + float(record.spent)
	record.skills = {}
	record.perks = []
	record.spent = 0.0
	return true


## Imported records keep the same ledger through their existing sanitizer.
## Invalid metadata is unavailable, rather than a partial refund labelled all.
static func sanitize(h: Dictionary, value: Variant) -> Dictionary:
	if _valid(h, value):
		return Dictionary(value).duplicate(true)
	var copy := h.duplicate(true)
	start(copy)
	copy[KEY].ambiguous = true
	return copy[KEY]


static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _tolerance(h: Dictionary) -> float:
	# Old gains round the available and total XP separately to float32. Use
	# the budget only to identify a unique integer cost from native purchases,
	# never itself as a refund amount. Close competing costs stay unavailable.
	var scale := maxf(absf(float(h.get("exp_total", 0.0))), absf(float(h.get("exp", 0.0))))
	return maxf(0.0001, scale * 0.0000038)


static func _valid(h: Dictionary, value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION \
			or not value.get("origin") is String or not value.get("base_skills") is Dictionary \
			or not value.get("base_perks") is Array or not value.get("skills") is Dictionary \
			or not value.get("perks") is Array or not value.get("ambiguous") is bool \
			or not _number(value.get("spent")) or not _number(value.get("base_exp")):
		return false
	if float(value.spent) < 0.0 or float(value.spent) > 1.0e9 \
			or value.perks.size() > 256 or value.base_perks.size() > 256 \
			or value.skills.size() > Skills.LIST.size() or value.base_skills.size() > 64:
		return false
	if value.skills.is_empty() and value.perks.is_empty() and float(value.spent) != 0.0:
		return false
	var npc := GameData.db.find("npcs", String(value.origin))
	if npc.is_empty() or float(value.base_exp) != float(npc.get("experience", 0.0)):
		return false
	if not bool(value.ambiguous) and (value.base_skills != Skills.from_npc(npc) \
			or value.base_perks != Array(npc.get("perks", [])).map(func(x): return String(x).to_lower())):
		return false
	if not h.get("skills", {}) is Dictionary or not h.get("perks", []) is Array \
			or not _number(h.get("exp")) or not _number(h.get("exp_total")):
		return false
	var skills: Dictionary = h.get("skills", {})
	for skill: Variant in value.skills:
		var n: Variant = value.skills[skill]
		var base: Variant = value.base_skills.get(skill, 0)
		if not skill in Skills.LIST or not _number(n) or float(n) < 0.0 or float(n) > 100.0 or float(n) != int(n) \
				or not _number(base) \
				or not _number(skills.get(skill, 0)) or float(skills.get(skill, 0)) - int(n) < float(base):
			return false
	var remaining: Array = Array(h.get("perks", [])).duplicate()
	for code: Variant in value.perks:
		if not code is String or code.length() > 64 or not remaining.has(code):
			return false
		remaining.remove_at(remaining.rfind(code))
	for code: Variant in value.base_perks:
		if not code is String or not remaining.has(code):
			return false
		remaining.erase(code)
	var budget := float(h.exp_total) - float(value.base_exp) - float(h.exp)
	return float(value.spent) <= budget + _tolerance(h)


## Older remake records preserved the perk purchase order, raw skill levels,
## total XP and unspent XP, but no transaction history. Reconstruct only a
## unique paid cost. Free quest skill grants can happen between purchases.
static func prepare(h: Dictionary, free_skills: Dictionary = {}, origin := "") -> void:
	if h.has(KEY):
		if not _valid(h, h[KEY]):
			h[KEY] = sanitize(h, h[KEY])
		return
	if origin.is_empty():
		origin = String(h.get("prototype", ""))
	var npc := GameData.db.find("npcs", origin)
	start(h)
	var record: Dictionary = h[KEY]
	record.origin = origin
	record.base_exp = float(npc.get("experience", 0.0))
	record.base_skills = Skills.from_npc(npc)
	record.base_perks = Array(npc.get("perks", [])).map(func(x): return String(x).to_lower())
	record.ambiguous = true
	if npc.is_empty() or not _number(h.get("exp")) or not _number(h.get("exp_total")) \
			or not h.get("skills", {}) is Dictionary or not h.get("perks", []) is Array:
		return
	var known: Array = h.get("perks", [])
	var initial: Array = record.base_perks
	if known.size() < initial.size() or known.slice(0, initial.size()) != initial:
		return
	var purchase_perks: Array = known.slice(initial.size())
	var previous := initial.duplicate()
	var perk_spent := 0
	for code: Variant in purchase_perks:
		if not code is String or not code in Perks.available({"perks": previous}):
			return
		perk_spent += Perks.cost(code, {"perks": previous})
		previous.append(code)
	var totals := {perk_spent: true}
	var paid := {}
	for skill: String in Skills.LIST:
		var current: Variant = h.skills.get(skill, 0)
		if not _number(current) or float(current) != int(current):
			return
		var base := int(record.base_skills.get(skill, 0))
		var gift := int(free_skills.get(skill, 0))
		var count := int(current) - base - gift
		if count < 0 or count > 100 - base:
			return
		var options := _skill_costs(skill, base, count, gift)
		if options.is_empty():
			return
		var next := {}
		for total: int in totals:
			for cost: int in options:
				next[total + cost] = true
		totals = next
		if count > 0:
			paid[skill] = count
	var budget := float(h.exp_total) - float(record.base_exp) - float(h.exp)
	var matches: Array[int] = []
	for total: int in totals:
		if absf(float(total) - budget) <= _tolerance(h):
			matches.append(total)
	if matches.size() != 1:
		return
	record.skills = paid
	record.perks = purchase_perks.duplicate()
	record.spent = float(matches[0])
	record.ambiguous = false


static func _skill_costs(skill: String, base: int, count: int, gift: int) -> Array:
	var out := {}
	for before_gift in range(count + 1 if gift > 0 else 1):
		var spent := 0
		var possible := true
		for i in count:
			var level := base + i + (gift if i >= before_gift else 0)
			if level >= 100:
				possible = false
				break
			spent += Skills.cost({"skills": {skill: level}}, skill)
		if possible:
			out[spent] = true
	return out.keys()


static func _free_skills(state, player: int) -> Dictionary:
	var free := {}
	for key: String in FREE_SKILLS:
		var done := float(state.get_var(player, key)) >= 2.0
		# Early remake saves discarded raw GS spelling. This migration does
		# not introduce a runtime case alias for new native GS tables.
		if not done and state.gs_reconstructed:
			done = float(state.get_var(player, key.to_lower())) >= 2.0
		if done:
			free[FREE_SKILLS[key]] = 10
	return free


static func migrate_state(state) -> void:
	var main: Dictionary = state.party_member("Hero")
	var original := String(main.get("prototype", ""))
	for player: Variant in state.heroes:
		var roster: Array = state.heroes[player]
		for i in roster.size():
			if not roster[i] is Dictionary:
				continue
			var copied: bool = int(player) == 0 and i == 0 and state.current_party in COPIED_PARTIES
			var shared_main: bool = int(player) == 0 and i == 0 and (state.current_party.is_empty() or copied)
			prepare(roster[i], _free_skills(state, 0) if shared_main else {}, original if copied else "")
	for party: String in state.parties:
		var roster: Array = state.parties[party]
		for i in roster.size():
			if roster[i] is Dictionary:
				var copied := i == 0 and party in COPIED_PARTIES
				prepare(roster[i], _free_skills(state, 0) if i == 0 and (party.is_empty() or copied) else {},
					original if copied else "")
	for h: Variant in state.mercs.values():
		if h is Dictionary:
			prepare(h)
