class_name Perks
extends RefCounted
const TrainingRefund := preload("res://src/game/training_refund.gd")
## The original skill tree (perks.pdb): weapon and school specialisations,
## health, mana, regeneration, quickness, backstab and attribute perks.
## Heroes buy perks with experience; each needs the previous rank.

## Weapon type (items.idb) -> perk prefix.
const WEAPON_PERK := {"sword": "sword", "axe": "axe", "dagger": "dagger", "spear": "spear",
	"hammer": "bludgeon", "bow": "bow", "crossbow": "xbow"}


static func get_perk(code: String) -> Dictionary:
	for r in GameData.db.table("perks"):
		if String(r.code) == code:
			return r
	return {}


static func title(code: String) -> String:
	var r := get_perk(code)
	var t := GameData.text("perk " + code)
	# texts.res: "<rank>\n<full name>"; some entries only repeat the rank.
	var short := t.get_slice("\n", 0).strip_edges()
	var full := t.get_slice("\n", 1).strip_edges() if t.count("\n") >= 1 else ""
	if full and full != short:
		return full
	# Russian ranks often repeat just their rank. Use the localized family
	# rather than falling back to the English name stored in the database.
	var family := GameData.text("perk " + code.rstrip("0123456789") + "0").get_slice("\n", 0).strip_edges()
	if family:
		return "%s (%s)" % [family, short] if short else family
	return String(r.get("name", code))


## Charge the increase in the cheapest legal allocation price. These
## differences telescope: the same final ranks always cost the same XP.
## Keep the original curve, global multiplier, prerequisites and rounding.
const MAX_PRICE := 9007199254740991 # largest exactly represented integer XP
static var _price_signature: Array = []
static var _price_rows := {}
static var _shapes: Array = []
static var _shape_ids := {}
static var _totals := {}
static var _bounds := {}
static var _allocations := {}
static var _rank_prices := {}
static var _quotes := {}


static func cost(code: String, h: Dictionary = {}) -> int:
	_price_cache()
	if has(h, code) or not _price_rows.has(code): return 0
	var known: Array = h.get("perks", [])
	var key := PackedStringArray(known)
	key.sort()
	var quotes: Dictionary = _quotes.get_or_add(key, {})
	if quotes.has(code): return int(quotes[code])
	var before := total_price(known)
	var after := known.duplicate()
	after.append(code)
	var price := maxi(1, int(minf(MAX_PRICE, total_price(after) - before)))
	quotes[code] = price
	return price


## Old saves retain rank acquisition order. Keep its price difference as a
## one-time refund credit when migrating, including their starting abilities.
static func legacy_total(known: Array) -> float:
	var seen := {}
	var total := 0.0
	for value: Variant in known:
		var code := String(value).to_lower()
		if seen.has(code) or get_perk(code).is_empty(): continue
		total += _rounded_price(_rank_price(code) * pow(GameData.ai_value("RPG", "Perk Power Base", 2.0), seen.size()))
		seen[code] = true
	return total


static func _rank_price(code: String) -> float:
	var row := get_perk(code)
	var req := String(row.get("required_perk", "none"))
	var prev := float(get_perk(req).get("cost", 0.0))
	return maxf(0.0, Skills.curve(float(row.get("cost", 0.0))) - Skills.curve(prev))


static func _rounded_price(p: float) -> float:
	if p <= 0.0:
		return 0.0
	var step := pow(10.0, floorf(log(p) / log(10.0)))
	if p / step < 4.0:
		if step <= 10.0:
			return floorf(p)
		step *= 0.1
	return floorf(p / step + 0.5) * step


static func round_price(p: float) -> int:
	return int(minf(MAX_PRICE, _rounded_price(p)))


static func _price_cache() -> void:
	var signature := [GameData.db, GameData.ai_value("RPG", "Skill Val 1", 50.0),
		GameData.ai_value("RPG", "Skill Val 2", 5.0), GameData.ai_value("RPG", "Perk Power Base", 2.0)]
	if signature != _price_signature:
		_price_signature = signature
		_price_rows.clear(); _shapes.clear(); _shape_ids.clear(); _totals.clear(); _bounds.clear(); _allocations.clear(); _quotes.clear()
		_rank_prices.clear()
		for row: Dictionary in GameData.db.table("perks"):
			_price_rows[String(row.code)] = row
			_rank_prices[String(row.code)] = _rank_price(String(row.code))
	elif _totals.size() > 8192:
		_totals.clear(); _bounds.clear(); _allocations.clear(); _quotes.clear()


## A shape groups interchangeable prerequisite chains with identical prices.
## Native families are linear; missing ranks in older NPC records are not
## invented or charged for. Only ranks actually owned enter the allocation.
static func total_price(known: Array) -> float:
	_price_cache()
	var have := {}
	for value: Variant in known:
		var code := String(value).to_lower()
		if _price_rows.has(code): have[code] = true
	var allocation := PackedStringArray(have.keys())
	allocation.sort()
	if _allocations.has(allocation): return float(_allocations[allocation])
	var parents := {}
	for code: String in have:
		parents[String(_price_rows[code].get("required_perk", "none"))] = true
	var state := PackedInt32Array()
	for leaf: String in have:
		if parents.has(leaf): continue
		var chain: Array[float] = []
		var code := leaf
		while have.has(code):
			chain.push_front(float(_rank_prices[code]))
			code = String(_price_rows[code].get("required_perk", "none"))
		var parent := -1
		for price: float in chain:
			var ids: Dictionary = _shape_ids.get_or_add(parent, {})
			if not ids.has(price):
				ids[price] = _shapes.size()
				var ranks: Array = [] if parent < 0 else Array(_shapes[parent].ranks).duplicate()
				ranks.append(price)
				_shapes.append({"parent":parent,"price":price,"ranks":ranks})
			parent = int(ids[price])
		state.append(parent)
	state.sort()
	var price := _minimum_price(state)
	_allocations[allocation] = price
	return price


## Relax the prerequisites and rounding to bound the cheapest possible order.
## Descending raw prices minimize an increasing multiplier. Original rounding
## is at least 8/9 of its input, or floor(input) for prices below 40. The
## subtraction covers truncation and floating-point error; this bound only
## prunes impossible winners, never approximates the returned price.
static func _price_bound(state: PackedInt32Array) -> float:
	if _bounds.has(state): return float(_bounds[state])
	var rates: Array[float] = []
	for id: int in state: rates.append_array(_shapes[id].ranks)
	rates.sort()
	var multiplier := float(_price_signature[3])
	if multiplier >= 1.0: rates.reverse()
	var raw := 0.0
	for i in rates.size(): raw += rates[i] * pow(multiplier, i)
	var bound := maxf(0.0, raw * (8.0 / 9.0) - rates.size() - absf(raw) * 1.0e-12)
	_bounds[state] = bound
	return bound


## Every legal order ends in a leaf. Try each distinct priced leaf and solve
## its prefix, reusing identical families and previously priced allocations.
static func _minimum_price(state: PackedInt32Array) -> float:
	if state.is_empty(): return 0.0
	if _totals.has(state): return float(_totals[state])
	var count := 0
	for id: int in state: count += _shapes[id].ranks.size()
	var choices: Array = []
	for i in state.size():
		var id := state[i]
		if i > 0 and state[i-1] == id: continue
		var rest := state.duplicate()
		rest.remove_at(i)
		var parent := int(_shapes[id].parent)
		if parent >= 0: rest.append(parent)
		rest.sort()
		var last := _rounded_price(float(_shapes[id].price) * pow(float(_price_signature[3]), count - 1))
		choices.append({"rest":rest,"last":last,"bound":last + _price_bound(rest)})
	choices.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.bound) < float(b.bound))
	var best := INF
	for choice: Dictionary in choices:
		if float(choice.bound) >= best: continue
		best = minf(best, float(choice.last) + _minimum_price(choice.rest))
	_totals[state] = best
	return best


static func has(h: Dictionary, code: String) -> bool:
	return code in h.get("perks", [])


## Perks this hero could learn next (first rank or the rank after a known one).
static func available(h: Dictionary) -> Array:
	var out := []
	for r in GameData.db.table("perks"):
		var code := String(r.code)
		if has(h, code):
			continue
		var req := String(r.get("required_perk", "none"))
		if req == "none" or req == "" or has(h, req):
			out.append(code)
	return out


static func learn(h: Dictionary, code: String) -> bool:
	if not code in available(h):
		return false
	var c := cost(code, h)
	if float(h.get("exp", 0.0)) < c:
		return false
	TrainingRefund.record_perk(h, code, c)
	h.exp = float(h.get("exp", 0.0)) - c
	var list: Array = h.get("perks", [])
	list.append(code)
	h.perks = list
	return true


## Highest modifier among the known ranks of a perk family ("sword" -> sword3...).
static func best(h: Dictionary, prefix: String) -> float:
	var v := 0.0
	for code: String in h.get("perks", []):
		if code.rstrip("0123456789") == prefix:
			v = maxf(v, float(get_perk(code).get("modifier", 0)))
	return v


## Attribute bonus (str/dex/int perks add their modifier).
static func attr_bonus(h: Dictionary, attr: String) -> float:
	return best(h, attr)


## Apply the perk effects to derived stats (called from Combat.hero_stats).
static func apply(u: GameUnit, h: Dictionary, weapon_type: String) -> void:
	if h.get("perks", []).is_empty():
		u.stats.erase("backstab")
		u.stats.erase("regen_hp")
		u.stats.erase("regen_mana")
		u.stats.erase("quick")
		return
	u.stats.max_load *= 1.0 + best(h, "lift") / 100.0
	var wp := best(h, WEAPON_PERK.get(weapon_type, "")) if WEAPON_PERK.has(weapon_type) else 0.0
	# +5 Attack and Defence per rank; bow and crossbow perks give no Defence.
	u.stats.to_hit += wp
	if not weapon_type in ["bow", "crossbow"]:
		u.stats.parry += wp
	var hp_frac := u.hp / u.max_hp if u.max_hp > 0.0 and u.hp > 0.0 else 1.0
	u.max_hp *= 1.0 + best(h, "health") / 100.0
	u.hp = u.max_hp * hp_frac
	u.max_mana *= 1.0 + best(h, "mana") / 100.0
	u.stats.backstab = best(h, "bs")
	u.stats.regen_hp = best(h, "vitality")
	u.stats.regen_mana = best(h, "spirit")
	u.stats.quick = best(h, "quickness")
