class_name Items
extends RefCounted
## Item model. An item is a string "<base>.<material>" (e.g. "stone axe.rock",
## "gipat medium plate.thin") or a plain base for materialless items
## ("tiny potion 1"). Stacks are "id [count]" in the databases. All numbers come
## from items.idb; material combination follows the original's item builder.

const ARMOR_SLOTS := ["helm", "plate", "shirt", "leggins", "pants", "gloves", "boots"]
const TABLES := ["weapons", "armors", "quick_items", "quest_items", "loot_items"]

static var _cache := {}


## {id, base, material, table, row, mat} for an item string.
static func info(id: String) -> Dictionary:
	id = unworn(id).strip_edges().to_lower()
	if _cache.has(id):
		return _cache[id]
	var base := id.get_slice("|", 0)   # "<item>|<spell>" = enchanted item
	var material := ""
	var dot := base.rfind(".")
	if dot > 0:
		material = base.substr(dot + 1)
		base = base.substr(0, dot)
	var out := {"id": id, "base": base, "material": material, "table": "", "row": {}, "mat": {}}
	for t in TABLES:
		var row := GameData.db.find(t, base)
		if not row.is_empty():
			out.table = t
			out.row = row
			break
	if material:
		out.mat = GameData.db.find("materials", material)
	_cache[id] = out
	return out


## 3D look of an item for the belt / inventory: the original names the
## model figures.res "initqi<N>item" (quick items; quest "initqu<N>item") and
##  its skin textures.res "qitem%04d", "qitem%04d.<material code>"
## when the prototype has a material (quest "quitem%04d"), N = the
## prototype's texture1.
## Weapons "initwe<code><N>weapon" and armour "initar<code><N>armor"
## (codes by type_id: sw ax dg sp hm bw cb
## hl pl lg sh pt bt gl) are skinned with the unit redress layer under the
## "unhuma" mask -> "layer". Loot items
## "initlitr<N>item" / "litem%04d", materials "initlimt<index>item" /
## "material%04d". {} if unknown.
## Blueprints, keystones and runes (loot kind 2):
## a weapon / armour blueprint is the item's model skinned with the plain
## "<code>_%02d.%d" texture (texture1, texture2), a potion / wand blueprint
## the quick item's look, a keystone (spell) "initqi1item" with
## "prototype%04d" and a rune "initqi1item" with "modifier%04d" (modifier
## index). Approx.: the keystone's picture is the prototype's texture_type
## (the original reads prototype field).
static func look(id: String) -> Dictionary:
	if id.begins_with("spell:") or id.begins_with("rune:"):
		var n := -1
		if id.begins_with("spell:"):
			n = int(Spells.parse(id.substr(6)).proto.get("texture_type", -1))
		else:
			var mods := GameData.db.table("spell_modifiers")
			for k in mods.size():
				if String(mods[k].get("code", "")).to_lower() == id.substr(5):
					n = k
		var tex := ("prototype%04d" if id.begins_with("spell:") else "modifier%04d") % n
		return {"model": "initqi1item", "texture": tex} if n >= 0 and GameData.has_figure("initqi1item.fig") else {}
	if id.begins_with("bp:"):
		var r := blueprint_row(id)
		if r.table in ["weapons", "armors"]:
			var l := look(id.substr(3))
			if l.is_empty():
				return {}
			var codes: Array = ["sw", "ax", "dg", "sp", "hm", "bw", "cb"] if r.table == "weapons" \
				else ["hl", "pl", "lg", "sh", "pt", "bt", "gl"]
			var t := "%s_%02d.%d" % [codes[int(r.row.get("type_id", 0))], int(r.row.get("texture1", 0)),
				int(r.row.get("texture2", 0))]
			return {"model": l.model, "texture": t} if GameData.textures.has(t + ".mmp") else l
		return look(id.substr(3))
	var i := info(plain(id))
	if i.base == "material" and not i.mat.is_empty():
		#  mode 1: "initlimt<material index>item" (materials.idb order).
		var mi := GameData.db.table("materials").find(i.mat)
		var mm := "initlimt%ditem" % mi
		return {"model": mm, "texture": "material%04d" % mi} if mi >= 0 and GameData.has_figure(mm + ".fig") else {}
	if i.row.is_empty():
		return {}
	var n := int(i.row.get("texture1", 0))
	if i.table == "loot_items":
		var lm := "initlitr%ditem" % n
		return {"model": lm, "texture": "litem%04d" % n} if GameData.has_figure(lm + ".fig") else {}
	if i.table in ["weapons", "armors"]:
		var codes: Array = ["sw", "ax", "dg", "sp", "hm", "bw", "cb"] if i.table == "weapons" \
			else ["hl", "pl", "lg", "sh", "pt", "bt", "gl"]
		var t := int(i.row.get("type_id", -1))
		if t < 0 or t >= codes.size():
			return {}
		var m := ("initwe%s%dweapon" if i.table == "weapons" else "initar%s%darmor") % [codes[t], n]
		if not GameData.has_figure(m + ".fig"):
			return {}
		return {"model": m, "layer": "%s_%02d.%s.%d" % [codes[t], n, String(i.mat.get("code", "")),
			int(i.row.get("texture2", 0))]}
	var fmt: String = {"quick_items": "initqi%ditem", "quest_items": "initqu%ditem"}.get(i.table, "")
	var model := fmt % n if fmt else ""
	var prefix: String = {"quest_items": "quitem", "loot_items": "litem"}.get(i.table, "qitem")
	var tex := "%s%04d" % [prefix, n]
	var code := String(i.mat.get("code", "")).to_lower() if not i.mat.is_empty() else ""
	if code and String(i.row.get("material_type", "none")).to_lower() != "none" \
			and GameData.textures.has(tex + "." + code + ".mmp"):
		tex += "." + code
	return {"model": model, "texture": tex} if model and GameData.has_figure(model + ".fig") else {}


## The spell an item is enchanted with ("" if none).
static func spell_of(id: String) -> String:
	id = unworn(id)
	return id.get_slice("|", 1) if "|" in id else ""


## The item without its enchantment (and without wear).
static func plain(id: String) -> String:
	return unworn(id).get_slice("|", 0)


## --- Wear. Worn items carry the durability they have lost: "<item>[|spell]@<lost>".
## the original: durability -= amount / stack count; at ai.reg [RPG]
## "Item Durability Critical" (0.3) of the maximum the owner is warned, at 0 the
## item is unusable (tutorial it012: it moves to the inventory).

static func unworn(id: String) -> String:
	return id.get_slice("@", 0)


static func wear(id: String) -> float:
	return float(id.get_slice("@", 1)) if "@" in id else 0.0


static func with_wear(id: String, lost: float) -> String:
	var base := unworn(id)
	lost = snappedf(clampf(lost, 0.0, max_durability(base)), 0.1)
	return base if lost <= 0.0 else "%s@%s" % [base, str(lost)]


## Maximum durability: prototype durability x material durability (item builder).
static func max_durability(id: String) -> float:
	var i := info(id)
	if i.row.is_empty():
		return 0.0
	# prototype × material in single precision
	# (the info row truncates it,: 1010 × 3.8f = 3838, not 3837).
	return _f32(float(i.row.get("durability", 0.0)) * (float(i.mat.get("durability", 1.0)) if not i.mat.is_empty() else 1.0))


static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


static func durability(id: String) -> float:
	return maxf(0.0, max_durability(id) - wear(id))


static func is_broken(id: String) -> bool:
	return max_durability(id) > 0.0 and roundi(durability(id)) < 1


## Rune code needed to enchant this item ("it" weapons trigger on hit, "ic"
## armour works while worn), "" if it cannot hold a spell.
static func enchant_rune(id: String) -> String:
	if spell_of(id) != "" or id.begins_with("rune:") or id.begins_with("spell:"):
		return ""
	match kind(id):
		"weapon": return "it"
		"armor": return "ic"
	return ""


## Whether spell (a known spell id) can be put on item with its rune. The original's
## item constructor takes whatever spell lies in its spell slot
##  and attaches it unchecked; the
## weapon / armour spell templates of spells.sdb are only read by the shops
## and the German edition has none.
static func can_enchant(id: String, spell: String) -> bool:
	return not enchant_rune(id).is_empty() and not Spells.parse(spell).proto.is_empty()


## Splits "material.thick [2]" into ["material.thick", 2].
## Database item spec "<item>[<n>]" (stack) or "<item>[<spell>]" (enchanted,
## e.g. briefings' "unique sword.steel[weak{it}]") -> [item id, count], the
## spell kept as "<item>|<spell>".
static func from_spec(s: String) -> Array:
	s = s.strip_edges().to_lower()
	var b := s.find("[")
	if b < 0:
		return [s, 1]
	var inner := s.substr(b + 1).trim_suffix("]").strip_edges()
	var base := s.substr(0, b).strip_edges()
	if inner.is_valid_int():
		return [base, maxi(1, inner.to_int())]
	return [base + "|" + inner.replace(" ", ""), 1]


static func parse_stack(s: String) -> Array:
	s = s.strip_edges()
	var n := 1
	var b := s.find("[")
	if b >= 0:
		n = maxi(1, s.substr(b + 1).to_int())
		s = s.substr(0, b).strip_edges()
	return [s.to_lower(), n]


static func split_list(v) -> PackedStringArray:
	var out := PackedStringArray()
	var items: Array = Array(v) if (v is Array or v is PackedStringArray) else str(v).split(";")
	for x in items:
		var s := str(x).strip_edges()
		if s and s != "<null>":
			out.append(s)
	return out


static func kind(id: String) -> String:
	if id.begins_with("rune:"):
		return "rune"
	if id.begins_with("bp:"):
		return "blueprint"
	var i := info(id)
	match i.table:
		"weapons": return "weapon"
		"armors": return "armor"
		"quick_items": return "quick"
		"quest_items": return "quest"
		"loot_items": return "material" if i.base == "material" else "loot"
	return ""


static func slot(id: String) -> String:
	var i := info(id)
	if i.table == "weapons":
		return "weapon"
	if i.table == "armors":
		return String(i.row.get("type", "")).to_lower()
	return ""


static func title(id: String) -> String:
	if "@" in id:
		return title(unworn(id))
	if "|" in id:
		return "%s [%s]" % [title(plain(id)), Spells.title(spell_of(id)).get_slice(" (", 0)]
	if id.begins_with("spell:"):
		return "Spell: " + Spells.title(id.substr(6))
	if id.begins_with("rune:"):
		return "Rune: " + Spells.mod_title(id.substr(5))
	if id.begins_with("bp:"):
		return "%s: %s" % [blueprint_kind(id), title(id.substr(3))]
	var i := info(id)
	var key_base := String(i.base).replace(" ", "_")
	var key_mat := String(i.material).replace(" ", "_")
	var prefix: String = {"weapons": "weapon", "armors": "armor", "quick_items": "qitem", "quest_items": "questitem",
		"loot_items": "litem"}.get(i.table, "")
	for key in ["%s %s %s" % [prefix, key_base, key_mat], "%s %s" % [prefix, key_base]]:
		var t := GameData.text(key)
		if t:
			return t.get_slice("\n", 0).strip_edges()
	if i.base == "material" and i.material:
		var t := GameData.text("material " + key_mat)
		if t:
			return t.get_slice("\n", 0).strip_edges()
	var name := String(i.base).capitalize()
	if i.material:
		var m := GameData.text("matshort " + key_mat).get_slice("\n", 0).strip_edges()
		name += " (%s)" % (m if m else String(i.material).capitalize())
	return name


## The item's description lines: the texts entry of its name (
##  takes the first line as the name, the rest).
static func flavor(id: String) -> String:
	id = plain(unworn(id))
	if id.begins_with("spell:") or id.begins_with("rune:") or id.begins_with("bp:"):
		return ""
	var i := info(id)
	var key_base := String(i.base).replace(" ", "_")
	var key_mat := String(i.material).replace(" ", "_")
	var prefix: String = {"weapons": "weapon", "armors": "armor", "quick_items": "qitem", "quest_items": "questitem",
		"loot_items": "litem"}.get(i.table, "")
	var keys := ["%s %s %s" % [prefix, key_base, key_mat], "%s %s" % [prefix, key_base]]
	if i.base == "material" and i.material:
		keys.append("material " + key_mat)
	for key: String in keys:
		var t := GameData.text(key)
		if t:
			var lines := Array(t.split("\n")).map(func(x): return String(x).strip_edges())
			lines.pop_front()
			return " ".join(lines.filter(func(x): return x != "")).strip_edges()
	return ""


## The type line of the item info (texts "string item_*").
static func type_text(id: String) -> String:
	var key := ""
	match kind(id):
		"weapon": key = "item_weapon"
		"armor": key = "item_armor_upper" if slot(id) in ["helm", "plate", "leggins"] else "item_armor_lower"
		"quick": key = "item_wand" if "wand" in String(info(id).base) else "item_potion"
		"material": key = "item_material"
		"loot": key = "item_loot"
		"quest": key = "item_quest"
		"rune": key = "item_modifier"
		"blueprint": return blueprint_kind(id)
	if id.begins_with("spell:"):
		key = "item_spell"
	if key.is_empty() or not GameData.texts:
		return ""
	return GameData.text("string " + key).get_slice("\n", 0).strip_edges()


## An item as the message window writes it: texts «string
## format_item1» `%s "%s"` (or, count > 1, «format_item2» `%s "%s" (%d)`) with
##  type line (`type_text`) and the item's name; the format's
## own trailing line break is left to the caller.
static func log_text(id: String, count := 1) -> String:
	var kind_t := type_text(id)
	var name := title(id)
	if not GameData.texts:
		return name
	var fmt := GameData.text("string " + ("format_item2" if count > 1 else "format_item1")).strip_edges()
	if fmt.count("%s") != 2:
		return name
	return fmt % ([kind_t, name, count] if count > 1 else [kind_t, name])


## "Weapon blueprint" etc. (texts string item_*_shape); heavy armour is the
## helm, cuirass and leggings layer (camphelp 4-10).
static func blueprint_kind(bp: String) -> String:
	var r := blueprint_row(bp)
	var key := "item_wand_shape"
	match r.table:
		"weapons": key = "item_weapon_shape"
		"armors": key = "item_armor_shape_upper" if String(r.row.get("type", "")).to_lower() in ["helm", "plate", "leggins"] \
				else "item_armor_shape_lower"
	var t := GameData.text("string " + key).strip_edges() if GameData.texts else ""
	return t if t else "Blueprint"


## Shop deal values, the original camp screen (slot
## 0xd8): trunc(price x coef[mode]) (__ftol, truncates); worn
## weapons and armour lose price x coef[8] x (1 - durability / max), and a
## repair costs max(1, trunc(that)). The coefficients are copied
##  from the shop record picked by script var "constr.current"
##  builds every record with the same set:
##   spells buy 1, sell 0.5, construct 0.2, deconstruct 0.1,
##   items  buy 1, sell 0.5, construct 0.2, deconstruct 0.1, repair 0.2.
## Record 5 has all nine at 0 (Shops.coef); `coef` holds the open trader's set.
const COEF := [1.0, 0.5, 0.2, 0.1, 1.0, 0.5, 0.2, 0.1, 0.2]
static var coef: Array = COEF
enum Deal {SPELL_BUY, SPELL_SELL, SPELL_CONSTR, SPELL_DECONSTR, BUY, SELL, CONSTR, DECONSTR, REPAIR}

static func _worn_fraction(id: String) -> float:
	var m := max_durability(id)
	return clampf(wear(id) / m, 0.0, 1.0) if m > 0.0 and kind(id) in ["weapon", "armor"] else 0.0


static func deal_price(id: String, mode: int) -> int:
	var p := float(price(id))
	var worn := p * float(coef[Deal.REPAIR]) * _worn_fraction(id)
	if mode == Deal.REPAIR:
		return maxi(1, int(worn)) if worn > 0.0 else 0
	return maxi(0, int(p * float(coef[mode]) - worn))


static func _spellish(id: String) -> bool:
	return id.begins_with("spell:") or id.begins_with("rune:")


static func buy_price(id: String) -> int:
	return deal_price(id, Deal.SPELL_BUY if _spellish(id) else Deal.BUY)


static func sell_price(id: String) -> int:
	return deal_price(id, Deal.SPELL_SELL if _spellish(id) else Deal.SELL)


static func repair_price(id: String) -> int:
	return deal_price(id, Deal.REPAIR)


## --- Item constructor (camphelp 13-15, the original mode 5 and
## ). An item is its blueprint ("bp:<prototype>", camp item type
## 0x3007 kind 2: weapon / armour / quick item prototype) plus as many units of
## one material ("material.<name>") as the prototype's "components", of the
## prototype's material type. Building costs coef[6] x the price of every piece
## (plus the buy price of pieces taken from the shop); taking a deconstructable
## weapon, armour or wand (quick item whose material type is not "none",
## ) apart costs coef[7] x its price and gives the pieces back.
## Approx.: a blueprint's price is its prototype's price, so blueprint +
## materials cost what the ready item costs (price sum).

static func blueprint(id: String) -> String:
	return "bp:" + String(info(id).base)


static func blueprint_row(bp: String) -> Dictionary:
	var i := info(bp.substr(3))
	return {"table": i.table, "row": i.row}


static func material_unit(mat: String) -> String:
	return "material." + mat


## Materials (rows) a blueprint can be built from.
static func materials_for(bp: String) -> Array:
	var r := blueprint_row(bp)
	var mt := String(r.row.get("material_type", "")).to_lower()
	var out := []
	if mt.is_empty() or mt == "none":
		return out
	for m in GameData.db.table("materials"):
		if String(m.get("type", "")).to_lower() == mt:
			out.append(m)
	return out


static func components(bp: String) -> int:
	return maxi(1, int(blueprint_row(bp).row.get("components", 1)))


static func can_deconstruct(id: String) -> bool:
	var i := info(id)
	if i.row.is_empty() or i.mat.is_empty() or not bool(i.row.get("deconstructable", false)):
		return false
	if i.table in ["weapons", "armors"]:
		return true
	return i.table == "quick_items" and String(i.row.get("material_type", "none")).to_lower() != "none"


static func construct_price(bp: String, mat: String) -> int:
	return int(price(bp) * float(coef[Deal.CONSTR])) + components(bp) * int(price(material_unit(mat)) * float(coef[Deal.CONSTR]))


static func deconstruct_price(id: String) -> int:
	return deal_price(plain(id), Deal.DECONSTR)


## Weapon damage range (x = min, y = max). the original item builder (
## weapon): min = "min damage" x material damage, and "max damage"
## x material damage is the random range added to it.
static func damage(id: String) -> Vector2:
	var i := info(id)
	var m := float(i.mat.get("damage", 1.0))
	var a := float(i.row.get("min_damage", 1.0)) * m
	return Vector2(a, a + float(i.row.get("max_damage", 1.0)) * m)


## Damage type factors of a weapon (weapons "damage" columns).
static func damage_types(id: String) -> PackedFloat32Array:
	var d: Array = Array(info(id).row.get("damage", []))
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	for t in mini(7, d.size()):
		out[t] = float(d[t])
	return out


## Armour of one damage type set of an armour item, the original (item
## builder): per type i, set absorption x set type factor i x material resist i.
## Set 0 protects the item's own body part, set 1 the neighbouring one (shirt and
## plate: torso / arms). Order: piercing, slashing, crushing, thermal, chemical,
## electrical, general.
static func armor_layer(id: String, set_index := 0) -> PackedFloat32Array:
	var i := info(id)
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var a: Array = Array(i.row.get("absorption" if set_index == 0 else "absorption2", []))
	if a.size() < 8:
		return out
	var res: Array = Array(i.mat.get("resist", []))
	for t in 7:
		out[t] = float(a[0]) * float(a[1 + t]) * (float(res[t]) if t < res.size() else 1.0)
	return out


## Average armour of an item's main set (shown in item descriptions).
static func absorption(id: String) -> float:
	var l := armor_layer(id)
	var s := 0.0
	for v in l:
		s += v
	return s / 7.0


static func weight(id: String) -> float:
	var i := info(id)
	# the original item builder: prototype weight x material weight.
	return float(i.row.get("weight", 1.0)) * (float(i.mat.get("weight", 1.0)) if not i.mat.is_empty() else 1.0)


static func price(id: String) -> int:
	if "@" in id:
		return price(unworn(id))
	if id.begins_with("spell:"):
		# The spell builder adds every rune's price to the keystone's.
		return maxi(1, int(float(Spells.parse(id.substr(6)).price)))
	if id.begins_with("rune:"):
		return maxi(1, int(float(Spells.mod_row(id.substr(5)).get("price", 100.0))))
	if id.begins_with("bp:"):
		return maxi(1, int(float(blueprint_row(id).row.get("price", 1.0))))
	if "|" in id:
		return price(plain(id)) + price("spell:" + Spells.parse(spell_of(id)).code) * 2
	var i := info(id)
	var p := float(i.row.get("price", 1.0))
	if i.base == "material" and not i.mat.is_empty():
		return int(float(i.mat.get("price", 1.0)))
	if not i.mat.is_empty():
		# the original item builder: prototype price + components x material price.
		p = p + float(i.row.get("components", 0)) * float(i.mat.get("price", 0.0))
	return maxi(1, int(p))


## The spell a quick item casts on its user ("healing{e1}"), "" if none.
static func potion_spell(id: String) -> String:
	return String(info(id).row.get("spell", "")).replace(" ", "").to_lower()


static func roll_loot(proto: Dictionary, record: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	for s in split_list(proto.get("items", "")):
		var st := parse_stack(s)
		for k in st[1]:
			out.append(st[0])
	for s in record.get("quick_items", []):
		out.append(String(s).to_lower())
	# Quest items the unit carries (.mob UNIT_QUEST_ITEMS, or given by the
	# script builtin GiveUnitQuestItem) are found on it too.
	for s in record.get("quest_items", []):
		out.append(String(s).to_lower())
	# loot / rare_loot = [chance %, category mask, min, max]; money when max > 0.
	for key in ["loot", "rare_loot"]:
		var l = proto.get(key, [])
		if typeof(l) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY] and l.size() >= 4 and float(l[3]) > 0.0:
			if rng.randf() * 100.0 < float(l[0]):
				out.append("money [%d]" % rng.randi_range(maxi(1, int(l[2])), maxi(1, int(l[3]))))
	return out


## A database row's "shops" mask (bit idx = trader record idx + 1, Shops).
static func _in_shop(row: Dictionary, idx: int) -> bool:
	var v = row.get("shops")
	if v is Array or v is PackedInt32Array or v is PackedByteArray:
		return idx < v.size() and bool(v[idx])
	if v is int or v is float:
		return (int(v) >> idx) & 1 == 1
	return false
