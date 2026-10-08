extends RefCounted
## Full redistribution of trainable allocations, including innate abilities
## and skill gifts. Base STR/DEX/INT, equipment and lifetime XP are separate.
const KEY := "training_refund"
const VERSION := 2
static var _skill_signature: Array = []
static var _skill_prices: Array[float] = [0.0]


static func start(h: Dictionary) -> void:
	h[KEY] = {"version": VERSION, "credit": 0.0}


static func record_skill(h: Dictionary, _skill: String, _cost: int) -> void:
	prepare(h)


static func record_perk(h: Dictionary, _code: String, _cost: int) -> void:
	prepare(h)


static func _skill_value(h: Dictionary) -> float:
	var signature := [GameData.ai_value("RPG", "Skill Val 1", 50.0), GameData.ai_value("RPG", "Skill Val 2", 5.0)]
	if signature != _skill_signature:
		_skill_signature = signature
		_skill_prices = [0.0]
	var total := 0.0
	for skill: String in Skills.LIST:
		var level := clampi(Skills.level(h, skill), 0, 100)
		while _skill_prices.size() <= level:
			var n := _skill_prices.size() - 1
			_skill_prices.append(_skill_prices[-1] + maxi(1, Skills.span_cost(n, n + 1)))
		total += _skill_prices[level]
	return total


static func amount(h: Dictionary) -> float:
	prepare(h)
	return _skill_value(h) + Perks.total_price(h.get("perks", [])) + float(h[KEY].credit)


static func reason(h: Dictionary) -> String:
	return "No allocated points to refund." if amount(h) <= 0.0 else ""


static func refund(h: Dictionary) -> bool:
	var value := amount(h)
	if value <= 0.0:
		return false
	var skills: Dictionary = Dictionary(h.get("skills", {})).duplicate()
	for skill: String in Skills.LIST:
		skills[skill] = 0
	h.skills = skills
	h.perks = []
	h.exp = float(h.get("exp", 0.0)) + value
	start(h) # the old pricing credit is consumed exactly once
	return true


## Version 1 protected starting allocations and rejected ambiguous histories.
## An older hero's ordered perk list is enough to value the old price. Retain
## any overpayment as a one-time credit; subsequent purchases charge the new
## allocation difference, so buying and resetting cannot mint points.
static func prepare(h: Dictionary, _free_skills: Dictionary = {}, _origin := "") -> void:
	var value: Variant = h.get(KEY)
	if value is Dictionary and value.get("version") == VERSION \
			and (value.get("credit") is float or value.get("credit") is int) \
			and is_finite(float(value.credit)) and float(value.credit) >= 0.0:
		return
	var known: Array = h.get("perks", [])
	var credit := maxf(0.0, Perks.legacy_total(known) - Perks.total_price(known))
	h[KEY] = {"version": VERSION, "credit": credit}


static func sanitize(h: Dictionary, value: Variant) -> Dictionary:
	var copy := h.duplicate(true)
	copy[KEY] = value
	prepare(copy)
	var out: Dictionary = copy[KEY].duplicate()
	# Imported XP uses the same existing billion-point ceiling.
	out.credit = minf(float(out.credit), 1.0e9)
	return out


static func migrate_state(state) -> void:
	for roster: Array in state.heroes.values() + state.parties.values():
		for h: Variant in roster:
			if h is Dictionary: prepare(h)
	for h: Variant in state.mercs.values():
		if h is Dictionary: prepare(h)
