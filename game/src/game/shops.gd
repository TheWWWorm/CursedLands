class_name Shops
## Traders ("constr<N>" topics), the original shop records.
##
## Records (built at a new game: single player
##  network game; kept in the save
## chunk 4). Single player: id 1 items only (1, 0; basecam smith)
## 2 spells only (bz2g witch), 3 and 4 both (bz8k Shopper, bz14h Kuzn), 5 both
## with every deal coefficient 0 (only zone19's commented-out Rick). The other
## records' coefficients are Items.COEF. The network-game table (ids 1, 3, 4, 5,
## all selling items and spells) belongs to the original's own multiplayer maps and has
## no record 2 (the campaign's bz2g witch); the remake's co-op plays the
## single-player campaign, so it uses this table (a remake decision: the original
## has no co-op campaign).
##
## Goods (lists, generated when the
## camp screen opens and the record's restock flag is set):
## every database row whose "shops" mask has bit (id - 1) — weapons, armours,
## quick items, materials, spell prototypes, runes — plus the prototypes of
## what the party sold here. The flag is set at a new game and
## in single player, by script QuestComplete (builtin 0x9f
##  sets it on every record).
const RECORDS := {
	1: {"items": true, "spells": false},
	2: {"items": false, "spells": true},
	3: {"items": true, "spells": true},
	4: {"items": true, "spells": true},
	5: {"items": true, "spells": true, "free": true},
}
## (1) (the original's own network game):
## records 1, 3, 4, 5, each 1 and 1 (items and spells) and the
## usual coefficients (record 5 too: 1, 0.5, 0.2, 0.1, 1, 0.5, 0.2, 0.1, 0.2).
## The bases' traders: bz1mpg smith 1, bz2mpg Shopper 3, bz3mpg Kuzn 4,
## bz4mpg golem 5.
const NET_RECORDS := {
	1: {"items": true, "spells": true},
	3: {"items": true, "spells": true},
	4: {"items": true, "spells": true},
	5: {"items": true, "spells": true},
}
## The original multiplayer game (Session.lmp) uses NET_RECORDS.
static var network := false


static func records() -> Dictionary:
	return NET_RECORDS if network else RECORDS


static func exists(id: int) -> bool:
	return records().has(id)


static func sells_items(id: int) -> bool:
	return bool(records().get(id, {}).get("items", false))


static func sells_spells(id: int) -> bool:
	return bool(records().get(id, {}).get("spells", false))


## Deal coefficients copied into the camp screen (record..).
static func coef(id: int) -> Array:
	if bool(records().get(id, {}).get("free", false)):
		return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	return Items.COEF


## A shop's saved state: goods {item id: count}, restock flag, and the
## prototypes sold to it ("sold": table -> [names]).
static func blank() -> Dictionary:
	return {"restock": true, "goods": {}, "sold": {}}


static func _mask(row: Dictionary, id: int) -> bool:
	return Items._in_shop(row, id - 1)


static func _lc(v) -> String:
	return String(v).to_lower()


## the record's prototype lists (+ what was sold here).
static func lists(id: int, sold: Dictionary) -> Dictionary:
	var out := {"_idx": id - 1}
	for t in ["weapons", "armors", "quick_items", "materials", "spell_prototypes", "spell_modifiers"]:
		var rows := []
		var key := "code" if t.begins_with("spell") else "name"
		var seen := {}
		for row in GameData.db.table(t):
			if _mask(row, id):
				rows.append(row)
				seen[_lc(row.get(key, ""))] = true
		for n: String in sold.get(t, []):
			if seen.has(n):
				continue
			for row in GameData.db.table(t):
				if _lc(row.get(key, "")) == n:
					rows.append(row)
					seen[n] = true
					break
		out[t] = rows
	return out


static func _rand(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi) if lo < hi else hi


static func _shuffled(rng: RandomNumberGenerator, a: Array) -> Array:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = b[i]
		b[i] = b[j]
		b[j] = t
	return b


static func _add(goods: Dictionary, id: String, n: int) -> void:
	if n > 0:
		goods[id] = int(goods.get(id, 0)) + n


## Restock (items, spells): the goods are replaced.
## `school_max`: subtype -> the party's best knowledge (over the
## party, min / max per school kept; only the max is read).
static func generate(id: int, sold: Dictionary, school_max: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var l := lists(id, sold)
	var goods := {}
	var runes := _best_runes(l.spell_modifiers)
	if sells_items(id):
		_gen_items(goods, l, runes, rng)
	if sells_spells(id):
		_gen_spells(goods, l, runes, school_max, rng)
	return goods


static func _gen_items(goods: Dictionary, l: Dictionary, runes: Dictionary, rng: RandomNumberGenerator) -> void:
	# each material of the record gets a pool of rand(20..50)
	# units the ready items are made from.
	var pool := []
	for m: Dictionary in l.materials:
		pool.append({"row": m, "n": _rand(rng, 20, 50)})
	# Ready items, rand(40..50) prototypes of each kind (weapons
	#  armours, quick items).
	_gen_ready(goods, l.weapons, pool, _templates("weapon_spell_templates", l), runes, rng, true)
	_gen_ready(goods, l.armors, pool, _templates("armor_spell_templates", l), runes, rng, true)
	_gen_ready(goods, l.quick_items, pool, [], runes, rng, false)
	# Blueprints ("instruction weapon / armor / quick item"), rand(1..3) of every
	# prototype (no scrolls).
	for t in ["weapons", "armors", "quick_items"]:
		for row: Dictionary in l[t]:
			if t == "quick_items" and _lc(row.get("type", "")) == "scroll":
				continue
			_add(goods, "bp:" + _lc(row.name), _rand(rng, 1, 3))
	# Materials: rand(20..50) of the record's materials, each
	# rand(20..50) units.
	var mats: Array = l.materials
	var n := _rand(rng, 20, 50)
	if n < mats.size():
		mats = _shuffled(rng, mats).slice(0, n)
	for m: Dictionary in mats:
		_add(goods, Items.material_unit(_lc(m.name)), _rand(rng, 20, 50))


## rand(40..50) prototypes (all when fewer, else a random pick)
## "wand" types are never made ready. A prototype with a material type takes
## one of the pool's materials of that type with at least "components" units
## left: p = the prototype's price, each candidate in pool order is taken with
## chance |(price - p/7) / (p/7 - p/5)| % when 2p/7 - p/5 <= its price <= p/5,
## else 10 %; none taken -> a random candidate; no candidate -> no item. The
## pool loses "components" units. Weapons and armour are then enchanted with
## chance 50 % (random table % 101 < 50): every template spell
## (with chance 0) whose complexity fits the prototype's + the
## material's "slots" is a candidate, one is picked at random
## and put on the item if its stamina is at most their "mana". Potions
## (quick item id 8) come in stacks of rand(20..49).
static func _gen_ready(goods: Dictionary, protos: Array, pool: Array, templates: Array, runes: Dictionary,
		rng: RandomNumberGenerator, enchant: bool) -> void:
	var n := _rand(rng, 40, 50)
	var pick := protos
	if n < protos.size():
		pick = _shuffled(rng, protos).slice(0, n)
	for p: Dictionary in pick:
		if _lc(p.get("type", "")) == "wand":
			continue
		var mt := _lc(p.get("material_type", "none"))
		var mat := {}
		if mt != "none" and mt != "":
			var comps := maxi(1, int(p.get("components", 1)))
			var cands := []
			for e: Dictionary in pool:
				if _lc(e.row.get("type", "")) == mt and int(e.n) >= comps:
					cands.append(e)
			if cands.is_empty():
				continue
			var price := float(p.get("price", 0.0))
			var lo := price / 7.0
			var hi := price * 0.2
			var chosen = null
			for e: Dictionary in cands:
				var chance := 10
				var mp := float(e.row.get("price", 0.0))
				if lo + lo - hi <= mp and mp <= hi:
					chance = int(absf((mp - lo) / (lo - hi) * 100.0))
				if rng.randi_range(1, 100) < chance:
					chosen = e
					break
			if chosen == null:
				chosen = _shuffled(rng, cands)[0]
			chosen.n = int(chosen.n) - comps
			mat = chosen.row
		var item := _lc(p.name) + ("." + _lc(mat.name) if not mat.is_empty() else "")
		if enchant and not mat.is_empty() and rng.randi_range(0, 100) < 50 and not templates.is_empty():
			var cap := float(p.get("slots", 0)) + float(mat.get("slots", 0))
			var spells := _template_spells(templates, runes, {"*": cap}, 0, rng)
			if not spells.is_empty():
				var sp: String = spells[rng.randi_range(0, spells.size() - 1)] if spells.size() >= 2 else spells[0]
				if float(Spells.parse(sp).mana) <= float(p.get("mana", 0.0)) + float(mat.get("mana", 0.0)):
					item += "|" + sp
		var count := 1
		if int(p.get("item_id", -1)) == 8:
			count = 20 + rng.randi_range(0, 29)
		_add(goods, item, count)


##  (ready spells from spells.sdb "spell templates", up to 10 tries
## until there are as many as keystones), (keystones, rand(1..3)
## each), (runes, rand(20..50) each).
static func _gen_spells(goods: Dictionary, l: Dictionary, runes: Dictionary, school_max: Dictionary, rng: RandomNumberGenerator) -> void:
	var templates := _templates("spell_templates", l)
	var ready := []
	for t in 10:
		ready = _template_spells(templates, runes, school_max, 50, rng)
		if ready.size() >= l.spell_prototypes.size():
			break
	for sp: String in ready:
		_add(goods, "spell:" + sp, 1)
	for row: Dictionary in l.spell_prototypes:
		_add(goods, "spell:" + _lc(row.code), _rand(rng, 1, 3))
	for row: Dictionary in l.spell_modifiers:
		_add(goods, "rune:" + _lc(row.code), _rand(rng, 20, 50))


## the record's runes by group — a, d, e, m, r, t by their first
## letter keeping the highest "value", f* / i* by their first two letters.
static func _best_runes(mods: Array) -> Dictionary:
	var out := {}
	for r: Dictionary in mods:
		var c := _lc(r.code)
		if c.is_empty():
			continue
		match c[0]:
			"a", "d", "e", "m", "r", "t":
				var k := c[0]
				if not out.has(k) or float(out[k].get("value", 0.0)) < float(r.get("value", 0.0)):
					out[k] = r
			"f", "i":
				out[c.substr(0, 2)] = r
	return out


## Templates of the record (mask bit) whose prototype it sells.
static func _templates(table: String, l: Dictionary) -> Array:
	var have := {}
	for row: Dictionary in l.spell_prototypes:
		have[_lc(row.code)] = true
	var out := []
	for t: Dictionary in GameData.db.table(table):
		var proto := _lc(t.get("prototype", ""))
		if have.has(proto) and Items._in_shop(t, int(l._idx)):
			out.append({"proto": proto, "required": t.get("required", []), "optional": t.get("optional", []),
				"power": _lc(t.get("power", "")), "row": t})
	return out


static func _rune_key(code: String) -> String:
	code = code.to_lower()
	if code.is_empty():
		return ""
	return code.substr(0, 2) if code[0] in ["f", "i"] else code.substr(0, 1)


## each template, taken with chance (rand % 101 >= `skip`)
## starts from its keystone and required runes; if the complexity is within
## the party's best knowledge of the school (rounded) and it has fewer than 9
## runes, each optional rune is added with chance 50 % (rand % 101 > 49) while it
## fits and there are fewer than 8, then the power rune is repeated while it fits
## (up to 8 runes; a mana rune stops once the stamina is down to the keystone's).
static func _template_spells(templates: Array, runes: Dictionary, school_max: Dictionary, skip: int, rng: RandomNumberGenerator) -> Array:
	var out := []
	for t: Dictionary in templates:
		if rng.randi_range(0, 100) < skip:
			continue
		var proto := Spells.parse(String(t.proto))
		if proto.proto.is_empty():
			continue
		var limit := roundi(float(school_max.get(String(proto.subtype), school_max.get("*", 0.0))))
		var cx := int(proto.proto.get("complex", 0))
		var base_mana := float(proto.proto.get("mana", 0.0))
		var mana := base_mana
		var mods := []
		for r in t.required:
			var rr: Dictionary = runes.get(_rune_key(String(r)), {})
			if not rr.is_empty():
				mods.append(_lc(rr.code))
				mana += float(rr.get("mana", 0.0))
				cx += int(rr.get("complex", 0))
		if cx > limit or mods.size() >= 9:
			continue
		for r in t.optional:
			if mods.size() > 7:
				break
			if rng.randi_range(0, 100) > 49:
				var rr: Dictionary = runes.get(_rune_key(String(r)), {})
				if not rr.is_empty() and cx + int(rr.get("complex", 0)) <= limit:
					mods.append(_lc(rr.code))
					mana += float(rr.get("mana", 0.0))
					cx += int(rr.get("complex", 0))
		var pw: Dictionary = runes.get(_rune_key(String(t.power)), {})
		if not pw.is_empty() and cx + int(pw.get("complex", 0)) <= limit:
			var is_m := _lc(pw.code).begins_with("m")
			while mods.size() < 8:
				mods.append(_lc(pw.code))
				cx += int(pw.get("complex", 0))
				if is_m:
					mana += float(pw.get("value", 0.0)) * base_mana
				mana += float(pw.get("mana", 0.0))
				if (is_m and mana <= base_mana) or limit < cx + int(pw.get("complex", 0)):
					break
		out.append(String(t.proto) + ("{%s}" % ";".join(mods) if not mods.is_empty() else ""))
	return out
