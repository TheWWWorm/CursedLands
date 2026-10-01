class_name Perks
extends RefCounted
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
	var t := EIText.ansi(GameData.texts.read("perk " + code)) if GameData.texts else ""
	# texts.res: "<rank>\n<full name>"; some entries only repeat the rank.
	var short := t.get_slice("\n", 0).strip_edges()
	var full := t.get_slice("\n", 1).strip_edges() if t.count("\n") >= 1 else ""
	if full and full != short:
		return full
	return String(r.get("name", code))


## Price of a perk rank, the original: the skill experience curve between
## this rank's "cost" and the previous rank's, times ai.reg "Perk Power Base" (2)
## to the power of all perk ranks the hero already has, rounded to one significant
## digit (two when the leading digit is below 4).
static func cost(code: String, h: Dictionary = {}) -> int:
	var row := get_perk(code)
	var req := String(row.get("required_perk", "none"))
	var prev := float(get_perk(req).get("cost", 0.0)) if req != "none" and req != "" else 0.0
	var p := Skills.curve(float(row.get("cost", 0.0))) - Skills.curve(prev)
	p *= pow(GameData.ai_value("RPG", "Perk Power Base", 2.0), Array(h.get("perks", [])).size())
	return round_price(p)


static func round_price(p: float) -> int:
	if p <= 0.0:
		return 0
	var step := pow(10.0, floorf(log(p) / log(10.0)))
	if p / step < 4.0:
		if step <= 10.0:
			return int(p)
		step *= 0.1
	return int(floorf(p / step + 0.5) * step)


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
