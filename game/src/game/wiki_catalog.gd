class_name WikiCatalog
extends RefCounted
## A local encyclopedia of the currently loaded databases. No original content
## is bundled. IDs are navigation tokens; only localized names reach the page.
## Pages are generated on demand as well-formed HTML fragments. WikiHtml renders
## the same fragments in the game without a platform-specific browser dependency.

const CATEGORIES := ["All pages", "Items", "Spells", "Creatures", "Materials", "Runes", "Game mechanics"]
const DAMAGE_TYPES := ["Piercing", "Slashing", "Crushing", "Fire", "Acid", "Lightning", "General"]
const MECHANICS := {
	"melee": "Melee and ranged damage",
	"magic": "Magic and spell construction",
	"armor": "Armor and damage types",
	"crafting": "Materials and crafting",
	"attributes": "Attributes and skills",
}

var entries := {}
var ordered: Array[String] = []
var rules := {}
var _families := {}
var _spell_codes := {}
var _creature_names := {}
var _creature_families := {}


func rebuild() -> void:
	entries.clear()
	ordered.clear()
	_families.clear()
	_spell_codes.clear()
	_creature_names.clear()
	_creature_families.clear()
	_add("home", RemakeText.t("Game wiki"), "Game mechanics", "home", "")
	for key: String in MECHANICS:
		_add("mechanics/" + key, RemakeText.t(MECHANICS[key]), "Game mechanics", "mechanics", key)
	for table: String in Items.TABLES:
		for row: Dictionary in GameData.db.table(table):
			var base := String(row.get("name", "")).strip_edges().to_lower()
			if base.is_empty() or base == "material": continue
			var family: Array[String] = []
			var mats := Items.materials_for("bp:" + base)
			if mats.is_empty():
				family.append(base)
			else:
				for mat: Dictionary in mats:
					family.append(base + "." + String(mat.name).to_lower())
			_families[base] = family
			_add(item_key(base), item_title(base), "Items", "item", base)
	for mat: Dictionary in GameData.db.table("materials"):
		var id := Items.material_unit(String(mat.get("name", "")).to_lower())
		_add(item_key(id), item_title(id), "Materials", "material", id)
	for row: Dictionary in GameData.db.table("spell_prototypes"):
		var code := String(row.get("code", "")).strip_edges().to_lower()
		if code.is_empty(): continue
		_spell_codes[code] = true
		_add_spell(code)
	# Authored templates contribute their required-rune variants. Optional and
	# repeated runes are explored with the same constructor/parse builder as
	# the inventory, rather than enumerating an exponential set of strings.
	for table in ["spell_templates", "weapon_spell_templates", "armor_spell_templates"]:
		for row: Dictionary in GameData.db.table(table):
			var code := String(row.get("prototype", "")).strip_edges().to_lower()
			if not _spell_codes.has(code): continue
			var spell := code
			for spec in row.get("required", []):
				var rune := _rune_code(String(spec))
				if not rune.is_empty() and rune_fits(spell, rune):
					spell = Spells.with_mod(spell, rune)
			_add_spell(spell)
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		var code := String(row.get("code", "")).strip_edges().to_lower()
		if code.is_empty(): continue
		_add("rune/" + code.uri_encode(), rune_title(code), "Runes", "rune", code)
	# Include all authored creature/NPC variants, not just those spawned on
	# the current map. The installed edition owns the display name lookup.
	var counts := {}
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		var value := String(row.get("name", "")).to_lower()
		var title := GameUnit.unit_title(value)
		if title.is_empty(): title = RemakeText.t("Creature")
		_creature_names[value] = title
		_creature_families.get_or_add(title, []).append(value)
		counts[title] = int(counts.get(title, 0)) + 1
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		var value := String(row.get("name", "")).to_lower()
		var title: String = _creature_names[value]
		if counts[title] > 1:
			title = RemakeText.t("%s (variant %d)") % [title, _creature_families[_creature_names[value]].find(value) + 1]
		_add("creature/" + value.uri_encode(), title, "Creatures", "creature", value)
	ordered.assign(entries.keys())
	ordered.sort_custom(func(a: String, b: String): return String(entries[a].title).naturalnocasecmp_to(entries[b].title) < 0)


func _add(key: String, title: String, category: String, kind: String, value: String) -> void:
	entries[key] = {"key": key, "title": title, "category": category, "kind": kind, "value": value}


func _add_spell(spell: String) -> void:
	var key := "spell/" + spell.uri_encode()
	_add(key, spell_title(spell), "Spells", "spell", spell)


func _rune_code(spec: String) -> String:
	spec = spec.strip_edges().to_lower()
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		if spec.to_lower() in [String(row.get("name", "")).to_lower(), String(row.get("code", "")).to_lower()]:
			return String(row.code).to_lower()
	# Templates also refer to a rune family (e.g. effect rather than its
	# rank). Pick the lowest-complexity authored member for a starting page;
	# the interactive constructor exposes the remaining ranks.
	var candidates := []
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		if not spec.is_empty() and String(row.get("code", "")).to_lower().begins_with(spec): candidates.append(row)
	candidates.sort_custom(func(a, b): return float(a.get("complex", 0)) < float(b.get("complex", 0)))
	if not candidates.is_empty(): return String(candidates[0].code).to_lower()
	return ""


func search(query: String, category := "All pages") -> Array[String]:
	var words := query.strip_edges().to_lower().split(" ", false)
	var out: Array[String] = []
	for key: String in ordered:
		var entry: Dictionary = entries[key]
		if category != "All pages" and entry.category != category: continue
		var haystack := (String(entry.title) + " " + RemakeText.t(entry.category)).to_lower()
		var matches := true
		for word: String in words:
			if not word in haystack:
				matches = false
				break
		if matches: out.append(key)
	return out


static func item_key(id: String) -> String:
	id = Items.canonical_equipment(id)
	if id.begins_with("bp:"): id = id.substr(3)
	var info := Items.info(id)
	var family := id if info.base == "material" else String(info.base)
	return "item/" + family.uri_encode()


func variants_for(key: String) -> Array[String]:
	var out: Array[String] = []
	if not entries.has(key) or entries[key].kind != "item": return out
	var base := String(entries[key].value)
	out.assign(_families.get(base, [base]))
	var info := Items.info(base)
	if Items.has_blueprint(info.table, info.row): out.append("bp:" + base)
	return out


static func item_link(id: String, title: String) -> String:
	return link(item_key(id) + "?version=" + id.uri_encode(), title)


## Items.title's final compatibility fallback is an internal specification.
## Resolve the actual localized archives first; unnamed database rows get
## their localized item type and material instead of leaking that fallback.
static func item_title(id: String) -> String:
	if id.begins_with("bp:"):
		var title := GameData.text("instr " + id.substr(3).replace(" ", "_")).get_slice("\n", 0).strip_edges()
		return RemakeText.t("Blueprint: %s") % (title if title else item_title(id.substr(3)))
	if Items.is_spell_piece(id): return spell_title(Items.spell_code(id))
	var i := Items.info(id)
	var base := String(i.base).replace(" ", "_")
	var mat := String(i.material).replace(" ", "_")
	if i.base == "material":
		var name := GameData.text("material " + mat).get_slice("\n", 0).strip_edges()
		return name if name else RemakeText.t("Material")
	var prefix: String = {"weapons":"weapon", "armors":"armor", "quick_items":"qitem", "quest_items":"questitem", "loot_items":"litem"}.get(i.table, "")
	for key: String in ["%s %s %s" % [prefix, base, mat], "%s %s" % [prefix, base]]:
		var name := GameData.text(key).get_slice("\n", 0).strip_edges()
		if name:
			if not i.mat.is_empty():
				var material := item_title(Items.material_unit(i.material))
				if not material.to_lower() in name.to_lower(): name += " · " + material
			return name
	var special := Items._special_text(i).get_slice("\n", 0).strip_edges()
	if special:
		if not i.mat.is_empty():
			var material := item_title(Items.material_unit(i.material))
			if not material.to_lower() in special.to_lower(): special += " · " + material
		return special
	var title := Items.type_text(id)
	if title.is_empty(): title = RemakeText.t("Item")
	if not i.material.is_empty(): title += " · " + item_title(Items.material_unit(i.material))
	return title


static func spell_title(spell: String) -> String:
	var code := spell.get_slice("{", 0)
	var title := GameData.text("spell " + code).get_slice("\n", 0).strip_edges()
	if title.is_empty(): title = RemakeText.t("Spell")
	var mods := Spells.mods_of(spell)
	if mods.is_empty(): return title
	var counts := {}
	for mod: String in mods: counts[mod] = int(counts.get(mod, 0)) + 1
	var names: Array[String] = []
	for mod: String in counts:
		names.append(rune_title(mod) + (" ×%d" % counts[mod] if counts[mod] > 1 else ""))
	return title + " (" + ", ".join(names) + ")"


static func rune_title(code: String) -> String:
	var title := GameData.text("modifier " + code).get_slice("\n", 0).strip_edges()
	if title: return title
	var row := Spells.mod_row(code)
	var name := String(row.get("name", ""))
	# Some unused-but-buildable original runes have an authored name only
	# in the database. Translate those names through the normal text catalogue.
	if RemakeText.TEXTS.has(name): return RemakeText.t(name)
	return RemakeText.t("Rune %d") % (GameData.db.table("spell_modifiers").find(row) + 1)


func page(key: String, variant := "") -> Dictionary:
	if not entries.has(key):
		return {"html": "<article><h1>%s</h1></article>" % esc(RemakeText.t("Page unavailable")), "preview": {}}
	var entry: Dictionary = entries[key]
	var body := ""
	var preview := {}
	match entry.kind:
		"home": body = _home()
		"item":
			var choices := variants_for(key)
			if not variant in choices: variant = choices[0]
			body = _item(variant)
			preview = {"kind": "item", "value": variant}
		"material":
			body = _material(entry.value)
			preview = {"kind": "item", "value": entry.value}
		"spell":
			body = _spell(entry.value)
			preview = {"kind": "item", "value": "spell:" + entry.value}
		"rune":
			body = _rune(entry.value)
			preview = {"kind": "item", "value": "rune:" + entry.value}
		"creature":
			body = _creature(entry.value)
			preview = {"kind": "creature", "value": entry.value}
		"mechanics": body = _mechanics(entry.value)
	var model := ""
	if not preview.is_empty():
		model = '<figure><object type="application/x-cursedlands-model" data="wiki://model/%s/%s"/><figcaption>%s</figcaption></figure>' % [preview.kind, String(preview.value).uri_encode(), esc(RemakeText.t("3D preview"))]
	return {"html": "<article><h1>%s</h1>%s%s</article>" % [esc(entry.title), model, body], "preview": preview, "variant": variant}


func _home() -> String:
	var out := paragraph(RemakeText.t("Explore the items, spells and creatures in your installed game. Values and variants come from the loaded game data, including active data mods."))
	var rows := []
	for category: String in CATEGORIES.slice(1):
		rows.append([link("category/" + category.uri_encode(), RemakeText.t(category)), str(search("", category).size())])
	out += table_html([RemakeText.t("Contents"), RemakeText.t("Pages")], rows)
	out += heading(RemakeText.t("Game mechanics"))
	for key: String in MECHANICS: out += paragraph(link("mechanics/" + key, RemakeText.t(MECHANICS[key])), true)
	out += paragraph(RemakeText.t("Creature pages show database prototypes. Map scripts, difficulty, equipment, temporary effects and co-op scaling can change a creature encountered in play."))
	return out


func _item(id: String) -> String:
	var is_bp := id.begins_with("bp:")
	var value := id.substr(3) if is_bp else id
	var info := Items.info(value)
	var out := paragraph(Items.flavor(id))
	var rows := []
	if is_bp:
		rows.append([esc(RemakeText.t("Components")), num(Items.components(id))])
	else:
		rows.append([esc(RemakeText.t("Weight")), num(Items.weight(id))])
		rows.append([esc(RemakeText.t("Base value")), num(Items.price(id))])
		rows.append([esc(RemakeText.t("Durability")), num(Items.max_durability(id))])
		rows.append([esc(RemakeText.t("Rune slots")), num(Items.slots(id))])
		if not info.mat.is_empty():
			var material := Items.material_unit(info.material)
			rows.append([esc(RemakeText.t("Material")), link(item_key(material), item_title(material))])
		if info.table == "weapons":
			var damage := Items.damage(id)
			rows.append([esc(RemakeText.t("Damage")), "%s–%s" % [num(damage.x), num(damage.y)]])
			rows.append([esc(RemakeText.t("Attack rating")), num(info.row.get("attack", 0))])
			rows.append([esc(RemakeText.t("Defense rating")), num(info.row.get("defence", 0))])
			rows.append([esc(RemakeText.t("Range")), num(info.row.get("range", 0))])
		if info.table == "quick_items":
			rows.append([esc(RemakeText.t("Charge capacity")), num(Items.energy(id))])
			var spell := Items.potion_spell(id)
			if _spell_codes.has(spell.get_slice("{", 0)):
				rows.append([esc(RemakeText.t("Spell")), _spell_link(spell)])
	out += table_html([RemakeText.t("Property"), RemakeText.t("Value")], rows)
	if not is_bp and info.table == "weapons":
		out += heading(RemakeText.t("Damage types")) + _damage_table(Items.damage_types(id), true)
	if not is_bp and info.table == "armors":
		out += heading(RemakeText.t("Armor: primary coverage")) + _damage_table(Items.armor_layer(id))
		out += heading(RemakeText.t("Armor: secondary coverage")) + _damage_table(Items.armor_layer(id, 1))
	if Items.has_blueprint(info.table, info.row) and not is_bp:
		out += paragraph(item_link("bp:" + info.base, RemakeText.t("Blueprint and materials")), true)
	if info.table == "weapons":
		out += paragraph(link("mechanics/melee", RemakeText.t("Melee and ranged damage")), true)
	out += paragraph(link("mechanics/armor" if info.table == "armors" else "mechanics/crafting", RemakeText.t("How these values work")), true)
	return out


func _material(id: String) -> String:
	var mat: Dictionary = Items.info(id).mat
	var rows := []
	for field: Array in [["damage", "Damage multiplier"], ["weight", "Weight multiplier"], ["durability", "Durability multiplier"], ["price", "Base value"], ["mana", "Charge capacity"], ["slots", "Rune slots"], ["skill", "Required skill"]]:
		rows.append([esc(RemakeText.t(field[1])), num(mat.get(field[0], 0))])
	var out := paragraph(Items.flavor(id)) + table_html([RemakeText.t("Property"), RemakeText.t("Value")], rows)
	out += heading(RemakeText.t("Resistance multipliers")) + _damage_table(PackedFloat32Array(mat.get("resist", [])))
	out += heading(RemakeText.t("Items using this material"))
	var uses := []
	for base: String in _families:
		for variant: String in _families[base]:
			if Items.info(variant).material == Items.info(id).material:
				uses.append([item_link(variant, item_title(variant))])
	out += table_html([RemakeText.t("Items")], uses)
	out += paragraph(link("mechanics/crafting", RemakeText.t("Materials and crafting")), true)
	return out


func _spell(spell: String) -> String:
	var p := Spells.parse(spell)
	var rows := []
	for field: Array in [["effect", "Power"], ["mana", "Stamina cost"], ["complex", "Complexity"], ["range", "Range"], ["area", "Area"], ["radius", "Radius"], ["duration", "Duration (ticks)"], ["targets", "Targets"], ["price", "Base value"]]:
		rows.append([esc(RemakeText.t(field[1])), num(p[field[0]])])
	var school: String = Skills.SCHOOL.get(p.subtype, "")
	if school:
		rows.push_front([esc(RemakeText.t("School")), esc(Skills.title(school))])
	var out := paragraph(_description("spell " + String(p.code)))
	out += table_html([RemakeText.t("Property"), RemakeText.t("Value")], rows)
	if Spells.DAMAGE_SCHOOLS.has(p.code):
		var type := int(Spells.DAMAGE_TYPE_INDEX.get(Spells.DAMAGE_SCHOOLS[p.code], 6))
		out += paragraph(RemakeText.t("Damage type: %s") % RemakeText.t(DAMAGE_TYPES[type]))
	var installed := Spells.mods_of(spell)
	if not installed.is_empty():
		out += heading(RemakeText.t("Installed runes"))
		for code: String in installed:
			out += paragraph(link("rune/" + code.uri_encode(), rune_title(code)), true)
	out += paragraph(RemakeText.t("Use the rune selector to explore legal variants. The preview uses the inventory's spell builder; your character and inventory are unchanged."))
	out += paragraph(link("mechanics/magic", RemakeText.t("Magic and spell construction")), true)
	return out


func _rune(code: String) -> String:
	var row := Spells.mod_row(code)
	var rows := []
	for field: Array in [["mana", "Stamina cost"], ["value", "Modifier value"], ["complex", "Complexity"], ["price", "Base value"]]:
		rows.append([esc(RemakeText.t(field[1])), num(row.get(field[0], 0))])
	var out := paragraph(_description("modifier " + code)) + table_html([RemakeText.t("Property"), RemakeText.t("Value")], rows)
	out += heading(RemakeText.t("Compatible spells"))
	var spells := []
	for spell: String in _spell_codes:
		if rune_fits(spell, code): spells.append([_spell_link(spell)])
	return out + table_html([RemakeText.t("Spells")], spells)


func _creature(value: String) -> String:
	var p := GameData.db.find("monster_prototypes", value)
	var race := GameData.db.find("race_models", String(p.get("base_race", "")))
	var rows := []
	for field: Array in [["hp", "Health"], ["mana", "Stamina"], ["to_hit", "Attack rating"], ["parry", "Defense rating"], ["absorption", "Natural armor"], ["attack_range", "Range"], ["tuning_actions", "Action speed"], ["tuning_move", "Movement multiplier"], ["experience", "Experience"], ["base_level", "Level"]]:
		rows.append([esc(RemakeText.t(field[1])), num(p.get(field[0], 0))])
	rows.append([esc(RemakeText.t("Damage")), "%s–%s" % [num(p.get("damage_min", 0)), num(float(p.get("damage_min", 0)) + float(p.get("damage_max", 0)))]])
	var out := paragraph(_description("unit " + value.replace(" ", "_")))
	out += paragraph(RemakeText.t("These are base prototype values, before map overrides, difficulty and temporary effects."))
	out += table_html([RemakeText.t("Property"), RemakeText.t("Value")], rows)
	var attack: Array = Array(race.get("attack", []))
	if attack.size() >= 7:
		out += heading(RemakeText.t("Damage types")) + _damage_table(PackedFloat32Array(attack.slice(0, 7)), true)
	var factors: Array = Array(race.get("defence", []))
	var armor := PackedFloat32Array()
	for i in 7:
		armor.append((float(factors[i]) if i < factors.size() else 1.0) * float(p.get("absorption", 0)))
	out += heading(RemakeText.t("Natural armor by damage type")) + _damage_table(armor)
	var equipment := []
	for spec in p.get("wears", []): _equipment_link(equipment, String(spec))
	for field in ["weapon", "second_weapon"]: _equipment_link(equipment, String(p.get(field, "")))
	if not equipment.is_empty():
		out += heading(RemakeText.t("Equipment")) + table_html([RemakeText.t("Items"), RemakeText.t("Count")], equipment)
	var spells := []
	for spec in p.get("spells", []):
		var spell := String(spec).replace(" ", "").to_lower()
		if _spell_codes.has(spell.get_slice("{", 0)): spells.append([_spell_link(spell)])
	if not spells.is_empty():
		out += heading(RemakeText.t("Spells")) + table_html([RemakeText.t("Spells")], spells)
	var items := []
	for spec in p.get("items", []): _equipment_link(items, String(spec))
	if not items.is_empty():
		out += heading(RemakeText.t("Carried items")) + table_html([RemakeText.t("Items"), RemakeText.t("Count")], items)
	var drops := []
	for field in ["loot", "rare_loot"]:
		var data: Array = Array(p.get(field, []))
		if data.size() >= 4 and float(data[3]) > 0.0:
			drops.append([num(data[0]) + "%", "%s–%s" % [num(maxi(1, int(data[2]))), num(maxi(1, int(data[3])))]])
	if not drops.is_empty():
		out += heading(RemakeText.t("Possible gold drops")) + table_html([RemakeText.t("Chance"), RemakeText.t("Amount")], drops)
	var family: Array = _creature_families.get(_creature_names[value], [])
	if family.size() > 1:
		var variants := []
		for variant: String in family:
			var key := "creature/" + variant.uri_encode()
			variants.append([link(key, entries[key].title), num(GameData.db.find("monster_prototypes", variant).get("hp", 0))])
		out += heading(RemakeText.t("Creature variants")) + table_html([RemakeText.t("Creatures"), RemakeText.t("Health")], variants)
	return out


func _equipment_link(rows: Array, spec: String) -> void:
	if spec.is_empty(): return
	var stack := Items.parse_stack(spec.to_lower())
	var id := String(stack[0])
	var key := item_key(id)
	if entries.has(key): rows.append([item_link(id, item_title(id)), str(stack[1])])


func _spell_link(spell: String) -> String:
	var key := "spell/" + spell.uri_encode()
	if not entries.has(key): _add_spell(spell)
	return link(key, spell_title(spell))


## A constructed spell is an ephemeral page. It is deliberately excluded from
## the search index so browsing never fills the catalogue with combinations.
func add_variant(spell: String) -> String:
	var code := spell.get_slice("{", 0)
	if not _spell_codes.has(code): return ""
	if Spells.mods_of(spell).size() > Spells.MAX_MODS: return ""
	var built := code
	for mod: String in Spells.mods_of(spell):
		if not rune_fits(built, mod): return ""
		built = Spells.with_mod(built, mod)
	_add_spell(built)
	return "spell/" + built.uri_encode()


static func rune_fits(spell: String, code: String) -> bool:
	return Spells.constr_rune_fits(spell.get_slice("{", 0), Spells.mods_of(spell).size(), code)


func _mechanics(topic: String) -> String:
	var out := paragraph(RemakeText.t("The formulas below describe this engine's current rules. Item and spell examples are calculated from your loaded game data."))
	match topic:
		"melee":
			out += heading(RemakeText.t("Weapon damage"))
			out += paragraph(RemakeText.t("Minimum damage = prototype minimum × material damage multiplier. Maximum damage = (prototype minimum + prototype damage range) × material damage multiplier. A strike rolls between those bounds, applies damage effects, and has a minimum raw damage of 1."))
			out += paragraph(RemakeText.t("Each damage type receives its share of the strike. Natural armor and the equipment layers covering the struck body part then absorb that type separately."))
			out += heading(RemakeText.t("Chance to hit"))
			out += paragraph(RemakeText.t("Roll = max(0, Attack + 2 × k − (B + 1)), where k is a uniformly chosen integer from 0 to B. A hit succeeds when max(0, Roll − aimed-strike penalty) ≥ Defense. B comes from the attacker's random-hit tuning."))
			out += table_html([RemakeText.t("Aimed strike"), RemakeText.t("Attack penalty")], [[esc(RemakeText.t("Head")), num(Combat.aim_penalty(0))], [esc(RemakeText.t("Torso")), num(Combat.aim_penalty(1))], [esc(RemakeText.t("Limb")), num(Combat.aim_penalty(2))]])
			out += paragraph(RemakeText.t("Bows and crossbows have zero defensive weapon rating. Ranged projectiles retain the damage rolled when fired. Backstabs use the configured base multiplier plus the backstab perk divided by 100."))
			out += table_html([RemakeText.t("Property"), RemakeText.t("Value")], [[esc(RemakeText.t("Base backstab multiplier")), num(GameData.ai_value("RPG", "BackstabAdd", 3.0))]])
			out += paragraph(link("mechanics/armor", RemakeText.t("Armor and damage types")), true)
		"armor":
			out += paragraph(RemakeText.t("For each damage type: remaining damage = max(minimum damage, incoming damage − natural armor − covering armor layers). Layers are applied from the outside inward. Different damage types do not absorb one another."))
			var formula := int(rules.get("armor_formula", GameData.option("armor_formula")))
			out += paragraph(RemakeText.t("Active armor rule: %s") % RemakeText.t("At least 20% of each incoming damage type passes through armor." if formula == 1 else "Armor can absorb damage completely."))
			out += paragraph(RemakeText.t("An item's protection for a damage type = coverage absorption × coverage type factor × material resistance. Primary and secondary coverage can differ. Broken equipment provides no protection."))
			out += table_html([RemakeText.t("Body part"), RemakeText.t("Covering equipment")], [[esc(RemakeText.t("Head")), esc(RemakeText.t("Helmet"))], [esc(RemakeText.t("Torso")), esc(RemakeText.t("Plate and shirt"))], [esc(RemakeText.t("Arms")), esc(RemakeText.t("Plate, shirt and gloves"))], [esc(RemakeText.t("Legs")), esc(RemakeText.t("Leggings, pants and boots"))]])
			out += paragraph(RemakeText.t("Magic uses the armor for its actual damage type, which can differ from its knowledge school. Protection effects contribute the strongest matching protection. Lasting magic scales both damage and absorption per tick and distributes damage across body parts."))
		"magic":
			out += heading(RemakeText.t("Spell damage"))
			out += paragraph(RemakeText.t("For a damaging spell, raw power starts at its calculated effect. If duration exceeds one tick, the tick factor is 4 / duration; both power and armor absorption are scaled by that factor. Matching natural armor and the strongest matching protection effect are subtracted first, then worn armor acts on each body part's share. The active armor rule sets the minimum damage."))
			out += paragraph(RemakeText.t("Runes modify the prototype's effect, area, range, duration, targets or stamina cost. Changes of the same kind add relative to the prototype; they do not multiply one another. Each rune also adds its stamina cost, complexity and value."))
			out += paragraph(RemakeText.t("Area radius = √(area / π). Stamina cost cannot fall below the prototype's cost. Duration modifiers add whole ticks. Filter and item-enchantment runes change targeting rather than power."))
			out += paragraph(RemakeText.t("A character needs sufficient knowledge of the spell's school and sufficient maximum stamina to equip it. A legal rune also needs a compatible prototype and available rune slots."))
			out += table_html([RemakeText.t("Property"), RemakeText.t("Value")], [[esc(RemakeText.t("Maximum runes per spell")), str(Spells.MAX_MODS)]])
			out += heading(RemakeText.t("Calculated examples"))
			var samples := []
			for code: String in _spell_codes:
				if not Spells.DAMAGE_SCHOOLS.has(code): continue
				var p := Spells.parse(code)
				samples.append([_spell_link(code), num(p.effect), num(p.mana), num(p.radius)])
			out += table_html([RemakeText.t("Spell"), RemakeText.t("Power"), RemakeText.t("Stamina cost"), RemakeText.t("Radius")], samples)
		"crafting":
			out += paragraph(RemakeText.t("A recipe accepts materials of its authored material type. Each listed material variant is built with the same item calculations used by the inventory and shops."))
			out += paragraph(RemakeText.t("Weight = prototype weight × material weight multiplier. Durability = prototype durability × material durability multiplier. Value = prototype value + component count × material value. Charge capacity and rune slots combine prototype and material values."))
			out += paragraph(RemakeText.t("The blueprint view lists the component count. Material buttons show completed variants on the same item page. Material pages show multipliers and link to compatible items. Shop buy, sell and repair prices can differ from the base value."))
			out += paragraph(link("category/Materials", RemakeText.t("Browse materials")), true)
		"attributes":
			out += paragraph(RemakeText.t("Hero Attack combines the weapon rating, the corresponding combat skill and Dexterity − 25, then applies relevant perks. Melee Defense uses the melee skill and defensive weapon rating; bows and crossbows give zero weapon Defense."))
			out += paragraph(RemakeText.t("Health and stamina pools use earned experience, attributes and the game's configured growth curves. Maximum equipment load starts at Strength × 12. Action speed starts at Dexterity × 0.2 + 10; perks and effects can change these values."))
			out += heading(RemakeText.t("Calculated examples"))
			var examples := []
			for attribute in [15, 25, 40]:
				examples.append([str(attribute), num(Skills.base_pool(0.0, attribute)), num(Skills.base_pool(0.0, attribute, "MP"))])
			out += table_html([RemakeText.t("Attribute at zero earned experience"), RemakeText.t("Health"), RemakeText.t("Stamina")], examples)
	return out


static func _description(key: String) -> String:
	var lines := Array(GameData.text(key).strip_edges().split("\n"))
	if not lines.is_empty(): lines.pop_front()
	return "\n".join(lines).strip_edges()


static func _damage_table(values: PackedFloat32Array, percent := false) -> String:
	var rows := []
	for i in mini(values.size(), DAMAGE_TYPES.size()):
		rows.append([esc(RemakeText.t(DAMAGE_TYPES[i])), num(values[i] * (100.0 if percent else 1.0)) + ("%" if percent else "")])
	return table_html([RemakeText.t("Damage type"), RemakeText.t("Share") if percent else RemakeText.t("Value")], rows)


static func esc(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")


static func num(value: Variant) -> String:
	return String.num(float(value), 3)


static func heading(value: String) -> String:
	return "<h2>%s</h2>" % esc(value)


static func paragraph(value: String, html := false) -> String:
	return "<p>%s</p>" % (value if html else esc(value).replace("\n", "<br/>")) if value else ""


static func link(key: String, title: String) -> String:
	return '<a href="wiki://%s">%s</a>' % [esc(key), esc(title)]


static func table_html(headers: Array, rows: Array) -> String:
	var out := '<table data-columns="%d"><tr>' % headers.size()
	for header: String in headers: out += "<th>%s</th>" % esc(header)
	out += "</tr>"
	for row: Array in rows:
		out += "<tr>"
		for cell in row: out += "<td>%s</td>" % cell
		out += "</tr>"
	return out + "</table>"
