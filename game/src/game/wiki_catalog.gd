class_name WikiCatalog
extends RefCounted
## A local encyclopedia of the currently loaded databases. No original content
## is bundled. IDs are navigation tokens; only localized names reach the page.
## Pages are generated on demand as well-formed HTML fragments. WikiHtml renders
## the same fragments in the game without a platform-specific browser dependency.

const CATEGORIES := ["All pages", "Characters", "Allods", "Maps", "Quests", "Items", "Spells", "Creatures", "Materials", "Runes", "Game mechanics"]
const DAMAGE_TYPES := ["Piercing", "Slashing", "Crushing", "Fire", "Acid", "Lightning", "General"]
const ITEM_TYPES := {
	"weapon_sword": "Swords", "weapon_axe": "Axes", "weapon_dagger": "Daggers",
	"weapon_spear": "Spears", "weapon_hammer": "Hammers", "weapon_bow": "Bows", "weapon_crossbow": "Crossbows",
	"armor_helm": "Helmets", "armor_plate": "Chest armour", "armor_leggins": "Leggings",
	"armor_shirt": "Shirts", "armor_pants": "Trousers", "armor_gloves": "Gloves", "armor_boots": "Boots",
	"quest": "Quest items", "wand": "Wands", "potion": "Potions", "loot": "Trophies and valuables", "other": "Other items",
}
const SPELL_NAMES := {
	"detect_life": "Detect Life", "lichdom": "Lichdom", "stench": "Stench", "possession": "Possession",
	"shapechange": "Shapechange", "link": "Link", "comprehend": "Comprehension", "charm": "Charm",
	"campfire": "Campfire", "rick_magic": "Destruction", "curse_magic": "Astral Rift",
}
const MECHANICS := {
	"melee": "Melee and ranged damage",
	"magic": "Magic and spell construction",
	"armor": "Armor and damage types",
	"crafting": "Materials and crafting",
	"attributes": "Attributes and skills",
	"planning": "Build planner",
}

var entries := {}
var ordered: Array[String] = []
var rules := {}
var _families := {}
var _spell_codes := {}
var _creature_names := {}
var _creature_families := {}
var _fixed := {}
var _unlisted := {}
var _family_names := {}
var _placeholder_names := {}
var _campaign: CampaignMap
var _quests := {}
var _quest_zones := {}
var knowledge: WikiKnowledge
var lore: WikiLore
var _search_text := {}
var _map_records := {}


func rebuild() -> void:
	_map_records.clear()
	entries.clear()
	ordered.clear()
	_families.clear()
	_spell_codes.clear()
	_creature_names.clear()
	_creature_families.clear()
	_fixed.clear()
	_unlisted.clear()
	_family_names.clear()
	_placeholder_names.clear()
	_quests.clear()
	_quest_zones.clear()
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
		if GameData.text("spell " + code).strip_edges().is_empty(): _unlisted["spell/" + code.uri_encode()] = true
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
		if not rune_listed(code): _unlisted["rune/" + code.uri_encode()] = true
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
	_prepare_items()
	_index_world()
	lore = WikiLore.new()
	lore.build(self)
	ordered.assign(entries.keys())
	ordered = ordered.filter(func(key: String): return not _unlisted.has(key) and not (entries[key].kind == "spell" and "{" in entries[key].value))
	ordered.sort_custom(func(a: String, b: String): return String(entries[a].title).naturalnocasecmp_to(entries[b].title) < 0)
	knowledge = WikiKnowledge.new()
	knowledge.build(self)
	lore.connect_pages(knowledge)
	_search_text.clear()
	for key: String in ordered:
		var entry: Dictionary = entries[key]
		var words: String = String(entry.title) + " " + knowledge.subtitles.get(key, "")
		for id: String in _families.get(entry.value, []): words += " " + display_item_title(id)
		words += lore.search_text(key)
		_search_text[key] = words


func _index_world() -> void:
	_campaign = CampaignMap.load_from(GameData.texts)
	for zone: Dictionary in _campaign.zones.values():
		if zone.get("type", "") == "edge" or String(zone.get("mpr", "")).is_empty(): continue
		var title := WikiWorldText.text("zone " + String(zone.id)).get_slice("\n", 0).strip_edges()
		if title.is_empty(): continue # Unnamed cutscene and editor locations.
		_add("map/" + String(zone.id).uri_encode(), title, "Maps", "map", zone.id)
	var ids := {}
	for key: String in GameData.texts.entries:
		if key.begins_with("quest "): ids[key.trim_prefix("quest ")] = true
	for row: Dictionary in GameData.db.table("quests"): ids[String(row.name).to_lower()] = true
	for quest: Dictionary in SideQuests.all(): ids[quest.id] = true
	for id: String in ids:
		var text := WikiWorldText.text("quest " + id)
		if text.is_empty(): text = SideQuests.quest_doc(id)
		var title := text.get_slice("\n", 0).strip_edges()
		if title.is_empty(): continue # Editor-only rows have no journal article.
		var optional := SideQuests.get_quest(id)
		_quests[id] = {"doc":JournalPanel._parse(id, text),"row":GameData.db.find("quests", id),"side":optional}
		_add("quest/" + id.uri_encode(), title, "Quests", "quest", id)
		if not optional.is_empty():
			var zone := _campaign.zone_by_map(optional.mpr)
			if not zone.is_empty(): _quest_zones.get_or_add(id, []).append(zone.id)
	# Read only script records. No map, unit, VM or quest is instantiated, and
	# reward/location associations come from authored q.<zone>.<quest> refs.
	var seen := {}
	var pattern := RegEx.create_from_string("(?i)q\\.([a-z0-9_]+)\\.([a-z0-9_]+)")
	for zone: Dictionary in _campaign.zones.values():
		var mob := String(zone.get("mob", ""))
		if mob.is_empty() or seen.has(mob): continue
		seen[mob] = true
		var record := map_records(mob)
		for found: RegExMatch in pattern.search_all(record.script_text):
			var location := found.get_string(1).to_lower()
			var quest := found.get_string(2).to_lower()
			if entries.has("map/"+location.uri_encode()) and _quests.has(quest) and not location in _quest_zones.get_or_add(quest, []):
				_quest_zones[quest].append(location)


## The reference needs unit records and scripts, not scenery, sound or AI patrols.
## Decode each installed map once and share it with lore and relationship indexing.
func map_records(name: String) -> EIMob:
	if not _map_records.has(name):
		var data := GameData.read_file("maps/" + name + ".mob")
		var record := EIMob.new()
		_read_map(record, data, 0, data.size(), "ROOT", {})
		_map_records[name] = record
	return _map_records[name]


static func _read_map(reader: EIMob, data: PackedByteArray, start: int, end: int, parent: String, unit: Dictionary) -> void:
	var at := start
	while at + 8 <= end:
		var id := data.decode_u32(at)
		var size := reader._record_size(data, at, end, id, parent)
		if size < 8 or at + size > end: return
		var kind: String = EIMob.R.get(id, "")
		if kind in ["OBJECTDBFILE", "OBJECTSECTION"]:
			_read_map(reader, data, at + 8, at + size, kind, unit)
		elif kind == "UNIT":
			var entry := {"kind": "UNIT"}
			_read_map(reader, data, at + 8, at + size, kind, entry)
			reader.objects.append(entry)
		elif id in [EIMob.SS_TEXT, EIMob.SS_TEXT_PLAIN] or (parent == "UNIT" and id in [EIMob.OBJNAME, EIMob.UNIT_PROTOTYPE, EIMob.OBJPOSITION, EIMob.UNIT_QUEST_ITEMS, EIMob.UNIT_QUICK_ITEMS]):
			reader._field(data, id, at + 8, size - 8, unit)
		at += size


## Share the public wiki's authored family names and fixed-item rules. Keep
## incomplete prototype pages linkable without filling ordinary search.
func _prepare_items() -> void:
	var owners := {}
	var worn := {}
	for creature: Dictionary in GameData.db.table("monster_prototypes"):
		for spec: String in creature.get("wears", []):
			var id := Items.plain(Items.canonical_equipment(String(Items.parse_stack(spec.to_lower())[0])))
			var base := String(Items.info(id).base)
			var owner := GameUnit.unit_title(String(creature.name).to_lower())
			if owner and not owner in owners.get_or_add(base, []): owners[base].append(owner)
			if not id in worn.get_or_add(base, []): worn[base].append(id)
	var unnamed := 0
	for key: String in entries:
		var entry: Dictionary = entries[key]
		if entry.kind != "item": continue
		var base := String(entry.value)
		var name := recipe_name(base)
		var info := Items.info(base)
		var craftable := Items.has_blueprint(info.table, info.row) and not name.is_empty() and not "_" in name
		var fixed_name := ""
		if not craftable:
			var choices: Array[String] = []
			for id: String in _families[base]:
				if authored_name(id): choices.append(id)
			if choices.is_empty(): choices.assign(worn.get(base, []))
			if choices.is_empty(): choices.append(_families[base][0])
			_families[base] = [choices[0]] as Array[String]
			_fixed[base] = choices[0]
			fixed_name = authored_name(choices[0])
		if not fixed_name.is_empty():
			# A fixed finished item can reuse a craftable prototype's recipe.
			# The recipe's name must not replace the installed item's name.
			entry.title = fixed_name
		elif "_" in name:
			unnamed += 1
			entry.title = RemakeText.t("%s (variant %d)") % [Items.type_text(base), unnamed]
			_placeholder_names[name] = entry.title
			for token in RegEx.create_from_string("[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+").search_all(Items.flavor("bp:" + base)):
				_placeholder_names[token.get_string()] = entry.title
			_unlisted[key] = true
		elif name:
			entry.title = name
		elif not owners.get(base, []).is_empty() and " special " in base:
			name = recipe_name(base.replace(" special ", " "))
			if name and not "_" in name: entry.title = ", ".join(owners[base]) + " · " + name
		elif entry.title == Items.type_text(base):
			unnamed += 1
			entry.title = RemakeText.t("%s (variant %d)") % [entry.title, unnamed]
			_unlisted[key] = true
		_family_names[base] = String(entry.title)


static func recipe_name(base: String) -> String:
	return GameData.text("instr " + base.replace(" ", "_")).get_slice("\n", 0).strip_edges()


static func authored_name(id: String) -> String:
	var info := Items.info(id)
	var prefix: String = {"weapons":"weapon", "armors":"armor", "quick_items":"qitem", "quest_items":"questitem", "loot_items":"litem"}.get(info.table, "")
	for key: String in ["%s %s %s" % [prefix, String(info.base).replace(" ", "_"), String(info.material).replace(" ", "_")], "%s %s" % [prefix, String(info.base).replace(" ", "_")]]:
		var title := GameData.text(key).get_slice("\n", 0).strip_edges()
		if title and not "_" in title: return _quest_name(id,title)
	return ""


static func item_subcategory(id: String) -> String:
	var info := Items.info(id)
	if info.table == "armors": return "armor_" + Items.slot(id).replace("leggings","leggins")
	if info.table == "weapons":
		var types := ["sword", "axe", "dagger", "spear", "hammer", "bow", "crossbow"]
		var type := int(info.row.get("type_id", -1))
		return "weapon_" + types[type] if type >= 0 and type < types.size() else "other"
	if info.table == "quest_items": return "quest"
	if info.table == "loot_items": return "loot"
	if Items.is_wand(id): return "wand"
	if info.table == "quick_items": return "potion"
	return "other"


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


func search(query: String, category := "All pages", subcategory := "") -> Array[String]:
	var ranked := []
	for key: String in ordered:
		var entry: Dictionary = entries[key]
		if category != "All pages" and entry.category != category: continue
		if subcategory and (entry.kind != "item" or item_subcategory(entry.value) != subcategory): continue
		var rank := WikiSearch.score(query, entry.title, _search_text.get(key, entry.title))
		for alias: String in entry.get("aliases", []): rank = maxi(rank, WikiSearch.score(query, alias, ""))
		if rank >= 0: ranked.append({"key":key,"score":rank})
	if ranked.any(func(row):return row.score>=100):ranked=ranked.filter(func(row):return row.score>=100)
	ranked.sort_custom(func(a,b):
		if a.score != b.score: return a.score > b.score
		if not query.strip_edges().is_empty() and entries[a.key].kind != entries[b.key].kind and "character" in [entries[a.key].kind,entries[b.key].kind]: return entries[a.key].kind == "character"
		return String(entries[a.key].title).naturalnocasecmp_to(entries[b.key].title) < 0)
	var out: Array[String] = []
	for row: Dictionary in ranked: out.append(row.key)
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
	if not _fixed.has(base) and Items.has_blueprint(info.table, info.row): out.append("bp:" + base)
	return out


func display_item_title(id: String) -> String:
	if not Items.spell_of(id).is_empty(): return display_item_title(Items.plain(id)) + " · " + spell_title(Items.spell_of(id))
	if id.begins_with("bp:"): return RemakeText.t("Blueprint: %s") % _family_names.get(id.substr(3), item_title(id.substr(3)))
	var info := Items.info(id)
	if _fixed.has(info.base): return _family_names.get(info.base, item_title(id))
	var title := item_title(id)
	var generic := Items.type_text(id)
	if _family_names.has(info.base) and (title == generic or title.begins_with(generic + " · ")):
		title = _family_names[info.base]
		if not info.material.is_empty(): title += " · " + item_title(Items.material_unit(info.material))
	return title


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
		if name.is_empty() and mat in ["troll_green2","troll_blue2","tiger_hide2"]:
			var parent := GameData.text("material " + mat.trim_suffix("2")).get_slice("\n",0).strip_edges()
			if parent: name = RemakeText.t("%s (variant %d)") % [parent,2]
		return name if name else RemakeText.t("Material")
	var prefix: String = {"weapons":"weapon", "armors":"armor", "quick_items":"qitem", "quest_items":"questitem", "loot_items":"litem"}.get(i.table, "")
	for key: String in ["%s %s %s" % [prefix, base, mat], "%s %s" % [prefix, base]]:
		var name := GameData.text(key).get_slice("\n", 0).strip_edges()
		if name:
			if not i.mat.is_empty():
				var material := item_title(Items.material_unit(i.material))
				if not material.to_lower() in name.to_lower(): name += " · " + material
			return _quest_name(id,name)
	var special := Items._special_text(i).get_slice("\n", 0).strip_edges()
	if special:
		if not i.mat.is_empty():
			var material := item_title(Items.material_unit(i.material))
			if not material.to_lower() in special.to_lower(): special += " · " + material
		return special
	var recipe := recipe_name(i.base)
	if recipe and not "_" in recipe:
		return recipe + (" · " + item_title(Items.material_unit(i.material)) if not i.material.is_empty() else "")
	var title := Items.type_text(id)
	if title.is_empty(): title = RemakeText.t("Item")
	if not i.material.is_empty(): title += " · " + item_title(Items.material_unit(i.material))
	return title


static func _quest_name(id: String, original: String) -> String:
	# These two EN/DE archive records contain a translator's placeholder.
	# Their original Russian names are Кукла and Рог; preserve modded names.
	if original in ["[Must be, but need no translation]","[Must be, but needs no translation]"]:
		if id=="voodoowand":return RemakeText.t("Doll")
		if id=="dragonwand":return RemakeText.t("Horn")
	return original


static func spell_title(spell: String) -> String:
	var code := spell.get_slice("{", 0)
	var title := GameData.text("spell " + code).get_slice("\n", 0).strip_edges()
	if title.is_empty(): title = RemakeText.t(SPELL_NAMES.get(code, "Spell"))
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
	if code.begins_with("ee"): return RemakeText.t("Scripted power modifier (%s)") % num(row.get("value", 0))
	if code.begins_with("c") and code.substr(1).is_valid_int(): return RemakeText.t("Scripted target modifier (%s)") % num(row.get("value", 0))
	# Some unused-but-buildable original runes have an authored name only
	# in the database. Translate those names through the normal text catalogue.
	if RemakeText.TEXTS.has(name): return RemakeText.t(name)
	return RemakeText.t("Rune %d") % (GameData.db.table("spell_modifiers").find(row) + 1)


static func rune_listed(code: String) -> bool:
	# Colour/Effect editor records and unnamed placeholders are not ordinary
	# obtainable runes. Keep deep links for authored equipment/spell variants.
	return not GameData.text("modifier " + code).strip_edges().is_empty()


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
			if not variant in choices and not valid_item_variant(key,variant): variant = choices[0]
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
		"character", "allod":
			body = lore.html(key)
			preview = lore.model(key)
		"map":
			body = _map_page(entry.value)
			preview = map_preview(entry.value)
		"quest":
			body = _quest_page(entry.value)
			for location: String in _quest_zones.get(entry.value, []):
				preview = map_preview(location)
				if not preview.is_empty():
					preview = preview.duplicate()
					preview.caption = RemakeText.t("Location: %s") % entries["map/" + location.uri_encode()].title
					break
		"mechanics": body = _mechanics(entry.value)
	body += knowledge.html(key) if knowledge != null else ""
	var model := ""
	if not preview.is_empty():
		model = '<figure><object type="application/x-cursedlands-model" data="wiki://model/%s/%s"/><figcaption>%s</figcaption></figure>' % [preview.kind, String(preview.value).uri_encode(), esc(RemakeText.t("3D preview"))]
	var title := display_item_title(variant) if entry.kind == "item" else String(entry.title)
	var html := "<article><h1>%s</h1>%s%s</article>" % [esc(title), model, body]
	for internal: String in _placeholder_names: html = html.replace(esc(internal), esc(_placeholder_names[internal]))
	return {"html": html, "preview": preview_descriptor(preview), "variant": variant,
		"subtitle":knowledge.subtitles.get(key,""),"pins":knowledge.pins.get(key,[]),
		"guide":quest_guide(entry.value) if entry.kind=="quest" else ""}


func craftable(key: String) -> bool:
	return entries.has(key) and entries[key].kind == "item" and not _fixed.has(entries[key].value) and Items.valid_blueprint("bp:" + String(entries[key].value))


func valid_item_variant(key: String, id: String) -> bool:
	if not craftable(key) or not Items.plain(id) in variants_for(key): return false
	var spell := Items.spell_of(id)
	return not spell.is_empty() and not add_variant(spell).is_empty() and Items.can_enchant(Items.plain(id),spell)


## Plain material variants use the same inventory builder; enchantment is
## admitted only by its actual type, item-rune, complexity and energy rules.
func construct_item(key: String, material_item: String, spell := "") -> String:
	if not craftable(key) or not material_item in variants_for(key) or material_item.begins_with("bp:"): return ""
	if spell.is_empty(): return material_item
	var id := material_item + "|" + spell
	return id if valid_item_variant(key,id) else ""


func item_builder_data(id: String) -> Dictionary:
	var plain := Items.plain(id)
	return {"kind":Items.kind(plain),"slots":Items.slots(plain),"energy":Items.energy(plain),
		"raw_price":Items._price(plain),"price":Items.price(plain),"weight":Items.weight(plain),
		"components":Items.components("bp:" + String(Items.info(plain).base)),"construction_coefficient":float(Items.COEF[Items.Deal.CONSTR])}


func constructor_data() -> Dictionary:
	var spells := {}; var runes := {}
	for key: String in search("", "Spells"):
		var code := String(entries[key].value)
		var p := Spells.parse(code).duplicate()
		p.erase("proto")
		p.erase("name")
		p.title = spell_title(code)
		p.school = Skills.SCHOOL.get(p.get("subtype",""), p.get("subtype",""))
		p.allowed = Array(Spells.parse(code).proto.get("mods",[]))
		spells[code] = p
	for key: String in search("", "Runes"):
		var code := String(entries[key].value)
		var row := Spells.mod_row(code)
		runes[code] = {"code":code,"title":rune_title(code),"type":row.get("type",9),"value":row.get("value",0),
			"mana":row.get("mana",0),"complex":row.get("complex",0),"price":row.get("price",0)}
	var planner := {"hp":[],"mp":[],"skills":{},"skill_cost":[GameData.ai_value("RPG","Skill Val 1",50),GameData.ai_value("RPG","Skill Val 2",5)]}
	for skill: String in Skills.LIST: planner.skills[skill]=Skills.title(skill)
	for i in 5:
		for field: String in ["hp","mp"]: planner[field].append(GameData.ai_value("RPG","%s Val %d" % [field.to_upper(),i+1],[25.0,30.0,50.0,1.1,1.61][i]))
	return {"max_runes":Spells.MAX_MODS,"spells":spells,"runes":runes,"planner":planner}


func _map_page(id: String) -> String:
	var zone := _campaign.zone(id)
	var text := WikiWorldText.text("zone " + id)
	var out := paragraph(text.substr(text.find("\n")+1)) if "\n" in text else ""
	out += lore.html("map/" + id.uri_encode())
	var allod := WikiWorldText.text("allod " + String(zone.get("allod", ""))).get_slice("\n",0).strip_edges()
	var island_key := WikiLore.allod_key(zone.get("allod", ""))
	if allod: out += table_html([RemakeText.t("Property"),RemakeText.t("Value")], [[esc(RemakeText.t("Island")),link(island_key,allod) if entries.has(island_key) else esc(allod)]])
	var pending: Array = zone.get("exits", {}).values().map(func(exit: Dictionary): return String(exit.get("to", "")))
	var visited := {id:true}
	var routes := []
	while not pending.is_empty():
		var destination := String(pending.pop_front())
		if visited.has(destination): continue
		visited[destination] = true
		var key := "map/" + destination.uri_encode()
		if entries.has(key): routes.append([link(key,entries[key].title)]); continue
		var next := _campaign.zone(destination)
		for exit: Dictionary in next.get("exits",{}).values(): pending.append(String(exit.get("to","")))
	if not routes.is_empty(): out += heading(RemakeText.t("Connected locations")) + table_html([RemakeText.t("Maps")],routes)
	var quests := []
	for quest: String in _quest_zones:
		if id in _quest_zones[quest]: quests.append([link("quest/"+quest.uri_encode(),entries["quest/"+quest.uri_encode()].title)])
	if not quests.is_empty(): out += heading(RemakeText.t("Quests")) + table_html([RemakeText.t("Quests")],quests)
	return out


func map_preview(id: String) -> Dictionary:
	var zone := _campaign.zone(id)
	var texture := String(zone.get("objtex", zone.get("minimap", "")))
	var dimensions: Vector2i = zone.get("size", Vector2i.ONE)
	if texture and GameData.textures.has(texture.to_lower()+".mmp"):
		return {"kind":"map", "value":texture.to_lower(), "dimensions":[dimensions.x,dimensions.y]}
	if zone.get("type", "") == "brief" and not String(zone.get("mpr", "")).is_empty():
		return {"kind":"scene", "value":id, "caption":RemakeText.t("Original location scene")}
	return {}


func _quest_page(id: String) -> String:
	var quest: Dictionary = _quests[id]
	var doc: Dictionary = quest.doc
	var out := paragraph(doc.text)
	if not doc.subs.is_empty():
		out += heading(RemakeText.t("Objectives"))
		for objective: Dictionary in doc.subs.values():
			out += paragraph(objective.title)
	var locations := []
	for location: String in _quest_zones.get(id,[]):
		var key := "map/" + location.uri_encode()
		if entries.has(key): locations.append([link(key,entries[key].title)])
	if not locations.is_empty(): out += heading(RemakeText.t("Locations")) + table_html([RemakeText.t("Maps")],locations)
	var source: Dictionary = quest.side if not quest.side.is_empty() else quest.row
	var reward := []
	var experience := float(source.get("exp",source.get("experience",0)))
	if experience > 0: reward.append([esc(RemakeText.t("Experience")),num(experience)])
	if float(source.get("money",0)) > 0: reward.append([esc(RemakeText.t("Gold")),num(source.money)])
	if not reward.is_empty():
		out += heading(RemakeText.t("Authored rewards")) + table_html([RemakeText.t("Property"),RemakeText.t("Value")],reward)
		out += paragraph(RemakeText.t("These are the authored base rewards. Scripts, choices and game rules can change the final reward."))
	return out


## Select an authored skin for this exact equipment model, including female
## costumes. A representative material is labelled rather than drawn white.
static func preview_descriptor(descriptor: Dictionary) -> Dictionary:
	if descriptor.is_empty() or descriptor.kind != "item": return descriptor
	var look := Items.look(descriptor.value)
	if not look.has("layer"): return descriptor
	for mask: String in ["unhuma", "unhufe"]:
		if _has_layer(mask, look.layer):
			if mask == "unhuma": return descriptor
			var result := descriptor.duplicate()
			result.merge({"mask":mask,"layer":look.layer,"representative":false})
			return result
	var info := Items.info(descriptor.value)
	for material: Dictionary in Items.materials_for("bp:" + String(info.base)):
		var candidate := Items.look(String(info.base) + "." + String(material.name).to_lower())
		if candidate.get("model", "") != look.model: continue
		for mask: String in ["unhuma", "unhufe"]:
			var skin := String(candidate.get("layer", ""))
			if skin and _has_layer(mask, skin):
				var result := descriptor.duplicate()
				result.merge({"mask":mask,"layer":skin,"representative":true})
				return result
	return {}


static func _has_layer(mask: String, layer: String) -> bool:
	return GameData.redress.has(mask + layer + ".mmp") or GameData.textures.has(layer + ".mmp")


func quest_guide(id: String) -> String:
	var out := ""
	for objective: Dictionary in _quests[id].doc.subs.values():
		if objective.text:
			out += heading(objective.title) + paragraph(objective.text)
	return out


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
		if info.table == "weapons":
			var damage := Items.damage(id)
			rows.append([esc(RemakeText.t("Damage")), "%s–%s" % [num(damage.x), num(damage.y)]])
			rows.append([esc(RemakeText.t("Attack rating")), num(info.row.get("attack", 0))])
			rows.append([esc(RemakeText.t("Defense rating")), num(info.row.get("defence", 0))])
			rows.append([esc(RemakeText.t("Range")), num(info.row.get("range", 0))])
		rows.append([esc(RemakeText.t("Weight")), num(Items.weight(id))])
		rows.append([esc(RemakeText.t("Base value")), num(Items.price(id))])
		rows.append([esc(RemakeText.t("Durability")), num(Items.max_durability(id))])
		rows.append([esc(RemakeText.t("Rune slots")), num(Items.slots(id))])
		rows.append([esc(RemakeText.t("Charge capacity")), num(Items.energy(id))])
		var enchantment := Items.spell_of(id)
		if not enchantment.is_empty(): rows.append([esc(RemakeText.t("Spell")),_spell_link(enchantment)])
		if not info.mat.is_empty():
			var material := Items.material_unit(info.material)
			rows.append([esc(RemakeText.t("Material")), link(item_key(material), item_title(material))])
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
	if not _fixed.has(info.base) and Items.has_blueprint(info.table, info.row) and not is_bp:
		out += paragraph(item_link("bp:" + info.base, RemakeText.t("Blueprint and materials")), true)
		out += table_html([RemakeText.t("Property"),RemakeText.t("Value")], [[esc(RemakeText.t("Components")),num(Items.components("bp:"+info.base))],
			[esc(RemakeText.t("Construction cost")),num(int(Items.price(id)*Items.COEF[Items.Deal.CONSTR]))]])
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
	for key: String in search("", "Spells"):
		var spell := String(entries[key].value)
		if rune_fits(spell, code): spells.append([_spell_link(spell)])
	return out + table_html([RemakeText.t("Spells")], spells)


## Ordinary, non-party prototype values. This deliberately ignores the running
## session's difficulty so both editions of the comparison remain available.
func creature_difficulty(value: String) -> Dictionary:
	var p := GameData.db.find("monster_prototypes", value)
	var race := GameData.db.find("race_models", String(p.get("base_race", "")))
	var bow := int(p.get("weapon_type_id", -1)) in [5, 6]
	var hard := {"attack":int(p.get("to_hit", 0)), "defense":0 if bow else int(p.get("parry", 0)), "armor":float(p.get("absorption", 0))}
	var easy := {"attack":int(hard.attack * GameData.ai_value("DifficultyLevels", "Attack", 1.0, 1)),
		"defense":int(hard.defense * GameData.ai_value("DifficultyLevels", "Defence", 1.0, 1)),
		"armor":hard.armor * GameData.ai_value("DifficultyLevels", "Absorption", 1.0, 1)}
	var armor := []
	var factors: Array = Array(race.get("defence", []))
	for i in 7:
		var factor := float(factors[i]) if i < factors.size() else 1.0
		armor.append([easy.armor * factor, hard.armor * factor])
	return {"easy":easy, "hard":hard, "armor":armor}


static func _difficulty_row(label: String, easy, hard) -> Array:
	var a := num(easy) if not easy is String else String(easy)
	var b := num(hard) if not hard is String else String(hard)
	if a != b: a = "<strong>%s</strong>" % a; b = "<strong>%s</strong>" % b
	return [esc(label), a if a == b else a + " / " + b]


func _creature(value: String) -> String:
	var p := GameData.db.find("monster_prototypes", value)
	var race := GameData.db.find("race_models", String(p.get("base_race", "")))
	var difficulty := creature_difficulty(value)
	var comparison := []
	for field: Array in [["hp", "Health"], ["mana", "Stamina"]]:
		comparison.append(_difficulty_row(RemakeText.t(field[1]), p.get(field[0], 0), p.get(field[0], 0)))
	var damage := "%s–%s" % [num(p.get("damage_min", 0)), num(float(p.get("damage_min", 0)) + float(p.get("damage_max", 0)))]
	comparison.append(_difficulty_row(RemakeText.t("Damage"), damage, damage))
	for field: Array in [["attack", "Attack rating"], ["defense", "Defense rating"], ["armor", "Natural armor"]]:
		comparison.append(_difficulty_row(RemakeText.t(field[1]), difficulty.easy[field[0]], difficulty.hard[field[0]]))
	var rows := []
	for field: Array in [["attack_range", "Range"], ["tuning_actions", "Action speed"], ["tuning_move", "Movement multiplier"], ["experience", "Experience"], ["base_level", "Level"]]:
		rows.append([esc(RemakeText.t(field[1])), num(p.get(field[0], 0))])
	var out := paragraph(_description("unit " + value.replace(" ", "_")))
	out += heading(RemakeText.t("Difficulty comparison"))
	var headers := [RemakeText.t("Property"), RemakeText.t("Value · Easy / Hard")]
	out += table_html(headers, comparison + rows)
	var attack: Array = Array(race.get("attack", []))
	if attack.size() >= 7:
		out += heading(RemakeText.t("Damage types")) + _damage_table(PackedFloat32Array(attack.slice(0, 7)), true)
	var armor := []
	for i in 7:
		if not is_zero_approx(difficulty.armor[i][1]): armor.append(_difficulty_row(RemakeText.t(DAMAGE_TYPES[i]), difficulty.armor[i][0], difficulty.armor[i][1]))
	if not armor.is_empty(): out += heading(RemakeText.t("Natural armor by damage type")) + table_html([RemakeText.t("Damage type"), RemakeText.t("Value · Easy / Hard")], armor)
	out += paragraph(RemakeText.t("Named characters keep their attack and defense on Easy. Party members also keep their natural armor. These are prototype values; map scripts, equipment and temporary effects can change an individual creature."))
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
		"planning":
			out += paragraph(RemakeText.t("Add equipment and spells from their articles, then compare the load, crafting materials and spell requirements. Share a link to keep the entire plan."))
		"melee":
			out += heading(RemakeText.t("Why do my attacks miss?"))
			out += paragraph(RemakeText.t("Compare your Attack with the target's Defense. Aiming at a head or limb adds a penalty; try the torso when accuracy matters. The weapon, its combat skill, Dexterity and perks contribute to the result."))
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
			out += heading(RemakeText.t("Why does this enemy resist my damage?"))
			out += paragraph(RemakeText.t("Check the damage types on your weapon or spell against the enemy's protection. High protection against fire does not protect against slashing. Equipment only helps where it covers the body, and broken armour provides no protection."))
			out += heading(RemakeText.t("A worked example"))
			out += paragraph(RemakeText.t("For a single damage type, 30 incoming damage against 20 protection leaves 10. Against 40 protection, the original armour rule leaves zero; the 20% minimum rule leaves 6. The active rule is listed below."))
			out += paragraph(RemakeText.t("For each damage type: remaining damage = max(minimum damage, incoming damage − natural armor − covering armor layers). Layers are applied from the outside inward. Different damage types do not absorb one another."))
			var formula := int(rules.get("armor_formula", GameData.option("armor_formula")))
			out += paragraph(RemakeText.t("Active armor rule: %s") % RemakeText.t("At least 20% of each incoming damage type passes through armor." if formula == 1 else "Armor can absorb damage completely."))
			out += paragraph(RemakeText.t("An item's protection for a damage type = coverage absorption × coverage type factor × material resistance. Primary and secondary coverage can differ. Broken equipment provides no protection."))
			out += table_html([RemakeText.t("Body part"), RemakeText.t("Covering equipment")], [[esc(RemakeText.t("Head")), esc(RemakeText.t("Helmet"))], [esc(RemakeText.t("Torso")), esc(RemakeText.t("Plate and shirt"))], [esc(RemakeText.t("Arms")), esc(RemakeText.t("Plate, shirt and gloves"))], [esc(RemakeText.t("Legs")), esc(RemakeText.t("Leggings, pants and boots"))]])
			out += paragraph(RemakeText.t("Magic uses the armor for its actual damage type, which can differ from its knowledge school. Protection effects contribute the strongest matching protection. Lasting magic scales both damage and absorption per tick and distributes damage across body parts."))
		"magic":
			out += heading(RemakeText.t("Why can't I equip this spell?"))
			out += paragraph(RemakeText.t("Your knowledge must meet the finished spell's complexity, and your maximum stamina must cover its cost. Adding runes can raise both requirements. Check the completed spell in the build planner before buying more runes."))
			out += paragraph(link("mechanics/planning",RemakeText.t("Build planner")),true)
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
			out += heading(RemakeText.t("Which material should I choose?"))
			out += paragraph(RemakeText.t("Choose the material on an item page to compare its finished statistics. For enchantments, check rune slots and charge capacity before cost: an affordable material may not support your spell. Add the finished item to a plan to collect the required materials."))
			out += heading(RemakeText.t("Why is this enchantment unavailable?"))
			out += paragraph(RemakeText.t("The spell must fit the item's slots and charge capacity. Weapons and armour also need an item-enchantment rune. The constructor reports incompatible combinations; fixed story items are not crafting recipes."))
			out += paragraph(RemakeText.t("A recipe accepts materials of its authored material type. Each listed material variant is built with the same item calculations used by the inventory and shops."))
			out += paragraph(RemakeText.t("Weight = prototype weight × material weight multiplier. Durability = prototype durability × material durability multiplier. Value = prototype value + component count × material value. Charge capacity and rune slots combine prototype and material values."))
			out += paragraph(RemakeText.t("The blueprint view lists the component count. The material selector shows completed variants on the same item page. Material pages show multipliers and link to compatible items. Shop buy, sell and repair prices can differ from the base value."))
			out += paragraph(link("category/Materials", RemakeText.t("Browse materials")), true)
		"attributes":
			out += heading(RemakeText.t("Which skill unlocks a spell?"))
			out += paragraph(RemakeText.t("Spell knowledge uses its magic-school skill, Intelligence minus 25, and the relevant perk bonus. Extra knowledge unlocks more complex spells; rune construction determines spell power. The planner compares your base knowledge and stamina with each planned spell."))
			out += paragraph(link("mechanics/planning",RemakeText.t("Build planner")),true)
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
		if is_zero_approx(values[i]): continue
		rows.append([esc(RemakeText.t(DAMAGE_TYPES[i])), num(values[i] * (100.0 if percent else 1.0)) + ("%" if percent else "")])
	return table_html([RemakeText.t("Damage type"), RemakeText.t("Share") if percent else RemakeText.t("Value")], rows)


static func esc(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")


static func num(value: Variant) -> String:
	return String.num(float(value), 3).trim_suffix(".0")


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
