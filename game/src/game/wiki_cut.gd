class_name WikiCut
extends RefCounted
## Models, colours, creatures and equipment present in the loaded data but not
## used by the campaign's maps, and creature colours that maps do use. Every
## list is calculated from the installed databases, archives and map records,
## so a data mod changes it; nothing here is a hand-maintained inventory.

## Figures that the engine draws itself, without a creature record.
const ENGINE_FIGURES := {"unmobi": {"texture": "bird00", "title": "Messenger bird",
	"text": "The bird that flies to your hero when a whole quest is completed. It is scenery: it has no statistics and cannot be attacked."}}
## Authored descriptions of known unused figures. Others use generic text.
## "texture" names an original skin made for the same UV layout.
const FIGURES := {
	"unmoog": {"title": "Early ogre model", "texture": "ogre00",
		"text": "An earlier ogre figure in an older model format, which the released game can still read. It matches the Gipath ogre except for its hips, which carry a skull on the belt. The remake gives this belt to the Gipath ogres."},
	"unmoel1": {"title": "Lava elemental model",
		"text": "The lava elemental figure. No creature of this campaign uses it."},
	"unanwigi": {"title": "Unfinished beast model",
		"text": "A large four-legged beast with a jaw, ears and a long tail. It has animations, but no creature record and no texture of its own, so it is shown untextured."},
}
## Visually checked names for unused colours; others use the species name.
const PALETTES := {"lizardman02": "Black lizard", "lizardman03": "Dark blue lizard"}
const SPECIES := {"Lizardman": "Lizard", "Bat": "Foxbat", "Boar": "Boar", "Horse": "Horse"}
## The main menu's signpost has a creature record but is not a creature.
const ENGINE_PROTOTYPES := ["mainmenu"]
## A new game creates the hero from this prototype, outside any map.
const PLAYER_PROTOTYPES := ["human hero"]
## Human figures whose redress skins and portraits (face<sex><skin>) are
## selected by a prototype's "skin" index.
const FACE_MODELS := {"unhufe": "f", "unhuma": "m"}
## Inventory figures per item table: figure prefix, texture prefix (Items.look).
const ITEM_MODEL_TABLES := {"quest_items": ["initqu", "quitem"], "quick_items": ["initqi", "qitem"],
	"loot_items": ["initlitr", "litem"]}
## Visually identified unused inventory figures; others use generic titles.
const ITEM_MODELS := {"initqu0item": "Compass", "initqu1item": "Scissors",
	"initqi22item": "Bundle of arrows", "initqi23item": "Bundle of arrows", "initqi24item": "Bundle of arrows",
	"initqi25item": "Bundle of arrows", "initqi30item": "Lockpicks", "initqi31item": "Lockpicks",
	"initqi32item": "Lockpicks", "initqi33item": "Lockpicks", "initqi34item": "File", "initqi35item": "File",
	"initqi36item": "Crowbar", "initqi37item": "Crowbar"}
## Overview notes per item table.
const ITEM_KINDS := {"quest_items": "Quest item", "quick_items": "Usable item", "loot_items": "Trophy"}

var _catalog_ref: WeakRef
var catalog: WikiCatalog:
	get: return _catalog_ref.get_ref()
var appearances := {}      # prototype -> {texture: {map key: count}}
var _counts := {}          # prototype -> {texture: count}
var _templates := {}       # prototype -> {figure: count}
var _placed := {}          # prototype -> true
var _placed_items := {}    # item base -> true
var _scripts := ""
var figures: Array[String] = []
var palettes := {}         # texture -> {race, prototype}
var modelless: Array[String] = []   # race names
var faces := {}            # "<mask>_<skin>" -> {mask, skin, prototype, portrait}
var item_models := {}      # figure -> {table, texture ("" without one)}


func build(source: WikiCatalog) -> void:
	_catalog_ref = weakref(source)
	# Side-quest and multiplayer maps are playable as well: read every map,
	# but link appearances only to maps that have an article.
	var zones := {}
	for zone: Dictionary in catalog._campaign.zones.values():
		var mob := String(zone.get("mob", "")).to_lower()
		var map_key := "map/" + String(zone.id).uri_encode()
		if mob and catalog.entries.has(map_key): zones.get_or_add(mob, []).append(map_key)
	for file: String in GameFiles.files(GameData.root.path_join("maps")):
		if not file.to_lower().ends_with(".mob"): continue
		var mob := file.get_basename().to_lower()
		var record := catalog.map_records(mob)
		_scripts += "\n" + record.script_text.to_lower()
		for unit: Dictionary in record.objects:
			var proto := String(unit.get("prototype", "")).to_lower()
			if proto.is_empty(): continue
			_placed[proto] = true
			var template := String(unit.get("template", ""))
			if template:
				var figures_used: Dictionary = _templates.get_or_add(proto, {})
				figures_used[template] = int(figures_used.get(template, 0)) + 1
			for field: String in ["weapons", "armors", "quest_items", "quick_items"]:
				for spec: String in unit.get(field, []):
					_placed_items[_base(spec)] = true
			var texture := String(unit.get("texture", ""))
			if texture.is_empty(): continue
			var per: Dictionary = _counts.get_or_add(proto, {})
			per[texture] = int(per.get(texture, 0)) + 1
			for map_key: String in zones.get(mob, []):
				var maps: Dictionary = appearances.get_or_add(proto, {}).get_or_add(texture, {})
				maps[map_key] = int(maps.get(map_key, 0)) + 1
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		if not placed(String(row.name).to_lower()): continue
		for field: String in ["wears", "items"]:
			for spec: String in row.get(field, []): _placed_items[_base(spec)] = true
		for field: String in ["weapon", "second_weapon"]:
			if row.get(field, ""): _placed_items[_base(String(row[field]))] = true
	for row: Dictionary in GameData.db.table("npcs"):
		for field: String in ["weapons", "quest_items"]:
			for spec: String in row.get(field, []): _placed_items[_base(spec)] = true
	_find_figures()
	_find_palettes()
	_find_faces()
	_find_item_models()
	catalog._add("cut/overview", RemakeText.t("Cut content"), "Cut content", "cut", "")
	for template: String in figures:
		catalog._add("cut/figure/" + template.uri_encode(), figure_title(template), "Cut content", "cut_figure", template)
	for texture: String in palettes:
		catalog._add("cut/palette/" + texture.uri_encode(), palette_title(texture), "Cut content", "cut_palette", texture)
	for id: String in faces:
		catalog._add("cut/face/" + id.uri_encode(), face_title(id), "Cut content", "cut_face", id)
	for model: String in item_models:
		catalog._add("cut/item/" + model.uri_encode(), item_model_title(model), "Cut content", "cut_item_model", model)
	for template: String in ENGINE_FIGURES:
		if GameData.has_figure(template + ".mod"):
			catalog._add("figure/" + template.uri_encode(), RemakeText.t(ENGINE_FIGURES[template].title), "Creatures", "figure", template)


static func _base(spec: String) -> String:
	return String(Items.info(Items.plain(String(Items.parse_stack(spec.to_lower())[0]))).base)


func _creature_races() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for race: Dictionary in GameData.db.table("race_models"):
		if int(race.get("type_id", 0)) != 0x32: out.append(race)
	return out


## Creature figures that no race record, map or engine effect uses.
func _find_figures() -> void:
	var used := {}
	for race: Dictionary in GameData.db.table("race_models"):
		used[String(race.get("mask", "")).to_lower()] = true
	for proto: String in _templates:
		for template: String in _templates[proto]: used[template] = true
	for race: Dictionary in _creature_races():
		var mask := String(race.get("mask", "")).to_lower()
		if not GameData.has_figure(mask + ".mod") and not race.get("textures", []).is_empty() \
				and not String(race.name) in modelless:
			modelless.append(String(race.name))
	for file: String in GameData.figures.names_with_suffix(".mod"):
		var template := file.trim_suffix(".mod")
		if not (template.begins_with("unan") or template.begins_with("unmo")): continue
		if used.has(template) or ENGINE_FIGURES.has(template): continue
		figures.append(template)


## Textures of a creature race's colour series that no map record uses. A
## prototype placed without a texture uses its race list entry.
func _find_palettes() -> void:
	var used := {}
	for proto: String in _counts:
		for texture: String in _counts[proto]: used[texture] = true
	var series := RegEx.create_from_string("^(.*?)\\d+l?$")
	for race: Dictionary in _creature_races():
		var mask := String(race.get("mask", "")).to_lower()
		if not GameData.has_figure(mask + ".mod"): continue
		var listed: Array = Array(race.get("textures", [])).map(func(t): return String(t).to_lower())
		var protos := _race_prototypes(String(race.name))
		if protos.any(func(proto: String): return proto in ENGINE_PROTOTYPES): continue
		for proto: String in protos:
			if _placed.has(proto) and not _counts.has(proto):
				var skin := int(GameData.db.find("monster_prototypes", proto).get("skin", 0))
				if skin >= 0 and skin < listed.size(): used[listed[skin]] = true
		if protos.is_empty(): continue
		var candidates := listed.duplicate()
		for texture: String in listed:
			var found := series.search(texture)
			if found == null: continue
			var pattern := RegEx.create_from_string("^" + found.get_string(1) + "\\d\\dl?\\.mmp$")
			for file: String in GameData.textures.names_with_suffix(".mmp"):
				if pattern.search(file) and not file.trim_suffix(".mmp") in candidates:
					candidates.append(file.trim_suffix(".mmp"))
		for texture: String in candidates:
			if used.has(texture) or palettes.has(texture) or not GameData.textures.has(texture + ".mmp"): continue
			palettes[texture] = {"race": String(race.name), "prototype": _representative(protos)}


## Human skins (and their portraits) that no prototype's "skin" index selects.
## The preview dresses a placed prototype of the same figure in the skin.
func _find_faces() -> void:
	for mask: String in FACE_MODELS:
		var used := {}
		var shown := ""
		for row: Dictionary in GameData.db.table("monster_prototypes"):
			var race := GameData.db.find("race_models", String(row.get("base_race", "")))
			if String(race.get("mask", "")).to_lower() != mask: continue
			used[int(row.get("skin", 0))] = true
			var proto := String(row.name).to_lower()
			if shown.is_empty() or (placed(proto) and not placed(shown)): shown = proto
		var skins := Array(GameData.redress.names_with_suffix(".mmp")).filter(
			func(n: String) -> bool: return n.begins_with(mask + "skin_") and n.trim_prefix(mask + "skin_").get_basename().is_valid_int())
		skins.sort()
		for file: String in skins:
			var skin := int(file.trim_prefix(mask + "skin_").get_basename())
			if used.has(skin) or shown.is_empty(): continue
			faces["%s_%02d" % [mask, skin]] = {"mask": mask, "skin": skin, "prototype": shown,
				"portrait": GameData.textures.has("face%s%02d.mmp" % [FACE_MODELS[mask], skin])}


## Inventory figures (Items.look's naming) that no item record's texture
## index selects.
func _find_item_models() -> void:
	for table: String in ITEM_MODEL_TABLES:
		var prefix: String = ITEM_MODEL_TABLES[table][0]
		var used := {}
		for row: Dictionary in GameData.db.table(table): used[int(row.get("texture1", 0))] = true
		var found := []
		for file: String in GameData.figures.names_with_suffix("item.fig"):
			var number := file.trim_prefix(prefix).trim_suffix("item.fig")
			if file.begins_with(prefix) and number.is_valid_int() and not used.has(int(number)): found.append(int(number))
		found.sort()
		for n: int in found:
			var texture := "%s%04d" % [ITEM_MODEL_TABLES[table][1], n]
			item_models["%s%ditem" % [prefix, n]] = {"table": table, "texture": texture if GameData.textures.has(texture + ".mmp") else ""}


func face_title(id: String) -> String:
	var info: Dictionary = faces[id]
	var series := 0
	for other: String in faces:
		if faces[other].mask == info.mask: series += 1
		if other == id: break
	return RemakeText.t("Unused female face %d" if info.mask == "unhufe" else "Unused male face %d") % series


func item_model_title(model: String) -> String:
	var name := RemakeText.t(ITEM_MODELS[model]) if ITEM_MODELS.has(model) else RemakeText.t("Unused item model")
	var same := 0
	var index := 0
	for other: String in item_models:
		if ITEM_MODELS.get(other, "") == ITEM_MODELS.get(model, ""):
			same += 1
			if other == model: index = same
	return RemakeText.t("%s (variant %d)") % [name, index] if same > 1 else name


func _race_prototypes(race: String) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		if String(row.get("base_race", "")) == race: out.append(String(row.name).to_lower())
	return out


func _representative(protos: Array[String]) -> String:
	var best := protos[0]
	for proto: String in protos:
		if _counts.get(proto, {}).size() > _counts.get(best, {}).size(): best = proto
	return best


func figure_title(template: String) -> String:
	if FIGURES.has(template): return RemakeText.t(FIGURES[template].title)
	return RemakeText.t("Unused creature model %d") % (figures.find(template) + 1)


func palette_title(texture: String) -> String:
	if PALETTES.has(texture): return RemakeText.t(PALETTES[texture])
	var info: Dictionary = palettes[texture]
	var species := RemakeText.t(SPECIES[info.race]) if SPECIES.has(info.race) else GameUnit.unit_title(info.prototype)
	if species.is_empty(): species = RemakeText.t("Creature")
	var series := 0
	for other: String in palettes:
		if palettes[other].race == info.race: series += 1
		if other == texture: break
	return RemakeText.t("%s: unused colour %d") % [species, series]


## The figure maps give this creature when it differs from its race's own,
## e.g. Lost in Astral's jungle skeletons. Empty when the race figure is used.
func template_for(proto: String) -> String:
	var per: Dictionary = _templates.get(proto, {})
	var best := ""
	for template: String in per:
		if best.is_empty() or per[template] > per[best]: best = template
	var race := GameData.db.find("race_models", String(GameData.db.find("monster_prototypes", proto).get("base_race", "")))
	return "" if best.is_empty() or best == String(race.get("mask", "")).to_lower() else best


func placed(proto: String) -> bool:
	return _placed.has(proto) or ('"' + proto + '"') in _scripts or proto in ENGINE_PROTOTYPES or proto in PLAYER_PROTOTYPES


## Colours the maps give this creature, most frequent first.
func appearance_choices(proto: String) -> Array[String]:
	var out: Array[String] = []
	var per: Dictionary = _counts.get(proto, {})
	out.assign(per.keys())
	out.sort_custom(func(a: String, b: String): return per[a] > per[b] or per[a] == per[b] and a < b)
	if out.size() < 2: out.clear()
	return out


func appearance_label(proto: String, texture: String) -> String:
	return RemakeText.t("Appearance %d") % (appearance_choices(proto).find(texture) + 1)


func obtainable(base: String) -> bool:
	if _placed_items.has(base) or ('"' + base + '.') in _scripts or ('"' + base + '"') in _scripts: return true
	for edge: Dictionary in catalog.knowledge.links.get(WikiCatalog.item_key(base), []):
		if edge.relation in ["stock", "reward"]: return true
	return false


func equipment() -> Array[String]:
	var out: Array[String] = []
	for key: String in catalog.ordered:
		var entry: Dictionary = catalog.entries[key]
		if entry.kind != "item": continue
		var table := String(Items.info(entry.value).table)
		if table in ["weapons", "armors"] and not obtainable(entry.value): out.append(key)
	return out


func unplaced_creatures() -> Array[String]:
	var out: Array[String] = []
	for key: String in catalog.ordered:
		if catalog.entries[key].kind == "creature" and not placed(catalog.entries[key].value): out.append(key)
	return out


## Extra creature article sections: map colours and a missing placement.
func creature_html(proto: String) -> String:
	var out := ""
	var choices := appearance_choices(proto)
	if not choices.is_empty():
		out += WikiCatalog.heading(RemakeText.t("Appearances"))
		out += WikiCatalog.paragraph(RemakeText.t("Maps place this creature in more than one colour. Choose one in the version selector to see it."))
		var rows := []
		for texture: String in choices:
			var maps := []
			var by_map: Dictionary = appearances.get(proto, {}).get(texture, {})
			for map_key: String in by_map: maps.append(WikiCatalog.link(map_key, catalog.entries[map_key].title))
			rows.append([WikiCatalog.link("creature/" + proto.uri_encode() + "?version=" + texture.uri_encode(), appearance_label(proto, texture)), ", ".join(maps)])
		out += WikiCatalog.table_html([RemakeText.t("Appearance"), RemakeText.t("Found in")], rows)
	if not placed(proto):
		out += WikiCatalog.paragraph(esc(RemakeText.t("No map in this campaign places this creature variant.")) + " " + WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)
	return out


func item_html(base: String) -> String:
	if not String(Items.info(base).table) in ["weapons", "armors"] or obtainable(base): return ""
	return WikiCatalog.paragraph(esc(RemakeText.t("Nothing in this campaign provides this item: no trader, map, creature, script or quest reward.")) + " " + WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)


static func esc(value: String) -> String:
	return WikiCatalog.esc(value)


func page(entry: Dictionary) -> Dictionary:
	match entry.kind:
		"cut": return {"body": _overview(), "preview": {}}
		"cut_figure":
			var template := String(entry.value)
			var body := WikiCatalog.paragraph(RemakeText.t(FIGURES[template].text) if FIGURES.has(template) \
				else RemakeText.t("No creature record or map uses this model."))
			var preview := {}
			if not (EIFigure.get_model(template).get("parts", {}) as Dictionary).is_empty():
				var appearance := {"template": template}
				if FIGURES.get(template, {}).has("texture"): appearance.texture = FIGURES[template].texture
				preview = {"kind": "creature", "value": "", "identity": template, "appearance": appearance}
			body += WikiCatalog.paragraph(WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)
			return {"body": body, "preview": preview}
		"cut_palette":
			var texture := String(entry.value)
			var info: Dictionary = palettes[texture]
			var body := WikiCatalog.paragraph(RemakeText.t("This colour is in the texture archive, but no map of this campaign places a creature with it."))
			if _trials_palette(texture):
				body += WikiCatalog.paragraph(RemakeText.t("The remake's Trials mode uses this colour for higher-ranked recruits."))
			var related := "creature/" + String(info.prototype).uri_encode()
			if catalog.entries.has(related):
				body += WikiCatalog.table_html([RemakeText.t("Related page")], [[WikiCatalog.link(related, catalog.entries[related].title)]])
			body += WikiCatalog.paragraph(WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)
			return {"body": body, "preview": {"kind": "creature", "value": info.prototype, "identity": texture,
				"appearance": {"texture": texture}}}
		"cut_face":
			var info: Dictionary = faces[String(entry.value)]
			var body := WikiCatalog.paragraph(RemakeText.t("This skin is in the archives, but no character record of this campaign selects it. The preview shows it on a character of the same build."))
			body += WikiCatalog.paragraph(RemakeText.t("A matching portrait is in the archives as well.") if info.portrait \
				else RemakeText.t("There is no matching portrait."))
			body += WikiCatalog.paragraph(WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)
			return {"body": body, "preview": {"kind": "creature", "value": info.prototype, "identity": String(entry.value),
				"appearance": {"skin": info.skin}}}
		"cut_item_model":
			var model := String(entry.value)
			var info: Dictionary = item_models[model]
			var text := RemakeText.t("No item record uses this inventory model, so the game never shows it.")
			if ITEM_MODELS.has(model):
				text = (RemakeText.t("Apparent object: %s.") % RemakeText.t(ITEM_MODELS[model])) + " " + text
			var body := WikiCatalog.paragraph(text)
			if info.texture.is_empty():
				body += WikiCatalog.paragraph(RemakeText.t("It has no texture, so it cannot be shown."))
			body += WikiCatalog.paragraph(WikiCatalog.link("cut/overview", RemakeText.t("Cut content")), true)
			var preview := {} if info.texture.is_empty() else {"kind": "item", "value": "", "identity": model,
				"look": {"model": model, "texture": info.texture}}
			return {"body": body, "preview": preview}
		"figure":
			var template := String(entry.value)
			return {"body": WikiCatalog.paragraph(RemakeText.t(ENGINE_FIGURES[template].text)),
				"preview": {"kind": "creature", "value": "", "identity": template,
					"appearance": {"template": template, "texture": ENGINE_FIGURES[template].texture}}}
	return {"body": "", "preview": {}}


static func _trials_palette(texture: String) -> bool:
	for family: int in ArenaAppearance.RANK_PALETTES:
		if texture in ArenaAppearance.RANK_PALETTES[family]: return true
	return false


func _overview() -> String:
	var out := WikiCatalog.paragraph(RemakeText.t("These original models, colours, creatures and equipment are in the installed game data, but this campaign does not use them. The lists are calculated from the loaded databases, archives and map records, including active data mods. They describe the authored maps and scripts; they do not prove what the developers planned."))
	var sections := []
	var rows := []
	for template: String in figures:
		var note := "" if not (EIFigure.get_model(template).get("parts", {}) as Dictionary).is_empty() \
			else RemakeText.t("Obsolete format; cannot be shown.")
		rows.append([WikiCatalog.link("cut/figure/" + template.uri_encode(), figure_title(template)), esc(note)])
	sections.append(["Unused creature models", "No creature record, map or game effect uses these models.", rows])
	rows = []
	for texture: String in palettes:
		rows.append([WikiCatalog.link("cut/palette/" + texture.uri_encode(), palette_title(texture)),
			esc(RemakeText.t("Used in Trials") if _trials_palette(texture) else "")])
	sections.append(["Unused colours", "These creature textures have no map placement in this campaign.", rows])
	rows = []
	for id: String in faces:
		rows.append([WikiCatalog.link("cut/face/" + id.uri_encode(), face_title(id)),
			esc(RemakeText.t("Portrait present") if faces[id].portrait else RemakeText.t("No portrait"))])
	sections.append(["Unused faces", "No character record selects these skins and portraits.", rows])
	rows = []
	for model: String in item_models:
		var kind: String = ITEM_KINDS[item_models[model].table]
		var note := RemakeText.t(kind) if item_models[model].texture else "%s; %s" % [RemakeText.t(kind), RemakeText.t("no texture")]
		rows.append([WikiCatalog.link("cut/item/" + model.uri_encode(), item_model_title(model)), esc(note)])
	sections.append(["Unused item models", "No item record uses these inventory models.", rows])
	rows = []
	for race: String in modelless:
		var title := RemakeText.t("Mushroom creature") if race.begins_with("Fungus") else RemakeText.t("Creature")
		if modelless.size() > 1: title = RemakeText.t("%s (variant %d)") % [title, modelless.find(race) + 1]
		rows.append([esc(title), esc(RemakeText.t("Textures and a creature type exist; the model is missing."))])
	sections.append(["Creature types without a model", "These creature types have textures, but their model is absent from the archives.", rows])
	rows = []
	for key: String in unplaced_creatures():
		rows.append([WikiCatalog.link(key, catalog.entries[key].title), esc(catalog.knowledge.subtitles.get(key, ""))])
	sections.append(["Creatures that never appear", "No map of this campaign places these creature variants, and no map script names them.", rows])
	rows = []
	for key: String in equipment():
		rows.append([WikiCatalog.link(key, catalog.entries[key].title), esc(catalog.knowledge.subtitles.get(key, ""))])
	sections.append(["Equipment that cannot be obtained", "No trader, map record, placed creature, script or quest reward provides these weapons and armour.", rows])
	for section: Array in sections:
		if section[2].is_empty(): continue
		out += WikiCatalog.heading(RemakeText.t(section[0])) + WikiCatalog.paragraph(RemakeText.t(section[1]))
		out += WikiCatalog.table_html([RemakeText.t("Related page"), RemakeText.t("Details")], section[2])
	return out
