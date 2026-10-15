extends Node
## Run through --tool with an installed GOG edition and --wiki-output=/directory.
## Exports reference articles only; never copies game archives or player data.

var family_names := {}
var unlisted := {}
var craftable := {}
var fixed := {}

func _ready() -> void:
	var output := ""
	var plan_path := ""
	var text_path := ""
	var language := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-output="): output = arg.trim_prefix("--wiki-output=")
		if arg.begins_with("--wiki-image-plan="): plan_path = arg.trim_prefix("--wiki-image-plan=")
		if arg.begins_with("--wiki-texts="): text_path = arg.trim_prefix("--wiki-texts=")
		if arg.begins_with("--wiki-language="): language = arg.trim_prefix("--wiki-language=")
	if output.is_empty():
		printerr("Missing --wiki-output")
		get_tree().quit(1)
		return
	if text_path:
		var localized: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(text_path))
		GameData._text_cache.merge(localized, true)
	if language:
		assert(language in ["en", "ru", "de"])
		RemakeText.lang = language
	# LiA adds alternate material records without separate text entries.
	# Use the named parent material and a localized variant label.
	for code: String in ["troll_green2", "troll_blue2", "tiger_hide2"]:
		if GameData.text("material " + code).strip_edges().is_empty():
			var original := GameData.text("material " + code.trim_suffix("2"))
			if original:
				var lines := original.split("\n", true, 1)
				GameData._text_cache["material " + code] = RemakeText.t("%s (variant %d)") % [lines[0], 2] + ("\n" + lines[1] if lines.size() > 1 else "")
	var unnamed_spells := {}
	var names_path: String = get_script().resource_path.get_base_dir().path_join("wiki_spell_names.json")
	var spell_names: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(names_path))
	for row: Dictionary in GameData.db.table("spell_prototypes"):
		var code := String(row.code).to_lower()
		if GameData.text("spell " + code).strip_edges().is_empty():
			unnamed_spells[code] = true
			assert(spell_names.has(code), "Missing spell translation: " + code)
			GameData._text_cache["spell " + code] = spell_names[code][RemakeText.lang]
	var catalog := WikiCatalog.new()
	catalog.rules = {"armor_formula": 0}
	catalog.rebuild()
	var placeholder_names := {}
	var unnamed := 0
	var owners := {}
	var worn_items := {}
	for creature: Dictionary in GameData.db.table("monster_prototypes"):
		for spec: String in creature.get("wears", []):
			var id := Items.plain(Items.canonical_equipment(String(Items.parse_stack(spec.to_lower())[0])))
			var base := String(Items.info(id).base)
			var owner := GameUnit.unit_title(String(creature.name).to_lower())
			if owner and not owner in owners.get_or_add(base, []): owners[base].append(owner)
			if not id in worn_items.get_or_add(base, []): worn_items[base].append(id)
	# Family records often have only a type label; their recipe contains the
	# authored family name, without choosing one particular material.
	for key: String in catalog.entries:
		var entry: Dictionary = catalog.entries[key]
		if entry.kind == "item":
			var base := String(entry.value)
			var name := recipe_name(base)
			var info := Items.info(base)
			craftable[base] = Items.has_blueprint(info.table, info.row) and not name.is_empty() and not "_" in name
			if not craftable[base]:
				# Material types alone do not make an item craftable. Fixed story
				# items use their authored material, never the full builder range.
				var choices: Array[String] = []
				for id: String in catalog._families[base]:
					if authored_name(id): choices.append(id)
				if choices.is_empty(): choices.assign(worn_items.get(base, []))
				if choices.is_empty(): choices.append(catalog._families[base][0])
				catalog._families[base] = [choices[0]] as Array[String]
				fixed[base] = choices[0]
				var authored := authored_name(choices[0])
				if authored: entry.title = authored
			if "_" in name:
				unnamed += 1
				entry.title = RemakeText.t("%s (variant %d)") % [entry.title, unnamed]
				placeholder_names[name] = entry.title
				for token in RegEx.create_from_string("[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+").search_all(Items.flavor("bp:" + String(entry.value))):
					placeholder_names[token.get_string()] = entry.title
				unlisted[key] = true
			elif name:
				entry.title = name
			elif not owners.get(base, []).is_empty() and " special " in base:
				# Named NPC costumes have no item text. Pair the actual wearer's
				# localized name with the corresponding authored garment name.
				name = recipe_name(base.replace(" special ", " "))
				if name and not "_" in name: entry.title = ", ".join(owners[base]) + " · " + name
			elif entry.title == Items.type_text(base):
				unnamed += 1
				entry.title = RemakeText.t("%s (variant %d)") % [entry.title, unnamed]
				unlisted[key] = true
			family_names[base] = String(entry.title)
	# Creature equipment can introduce authored rune combinations lazily.
	# Materialize the transitive reference set before writing the static index.
	var visited := {}
	while visited.size() < catalog.entries.size():
		for key: String in catalog.entries.keys():
			if visited.has(key): continue
			visited[key] = true
			var choices := public_variants(catalog, key)
			if choices.is_empty(): choices.append("")
			for choice: String in choices: catalog.page(key, choice)
	catalog.ordered.assign(catalog.entries.keys())
	catalog.ordered.sort_custom(func(a: String, b: String): return String(catalog.entries[a].title).naturalnocasecmp_to(catalog.entries[b].title) < 0)
	var all_keys := catalog.ordered.duplicate()
	# Keep every article addressable by equipment/spell links, while the
	# contents and browsing counts cover only finished items and base spells.
	for key: String in all_keys:
		var entry: Dictionary = catalog.entries[key]
		if entry.kind == "spell" and ("{" in String(entry.value) or unnamed_spells.has(String(entry.value).get_slice("{", 0))): unlisted[key] = true
	catalog.ordered = catalog.ordered.filter(func(key: String): return not unlisted.has(key))
	var directory := output.path_join(RemakeText.lang)
	DirAccess.make_dir_recursive_absolute(directory.path_join("pages"))
	var index := {"language": RemakeText.lang, "version": "1.6.0", "campaign": GameData.campaign_id, "source": "Lost in Astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "GOG", "entries": [], "categories": {}}
	var images := {}
	var variants := 0
	for category: String in WikiCatalog.CATEGORIES:
		index.categories[category] = RemakeText.t(category)
	for key: String in all_keys:
		var entry: Dictionary = catalog.entries[key]
		var file := key.sha256_text().substr(0, 20) + ".json"
		var index_entry := {"key": key, "title": entry.title, "category": entry.category, "kind": entry.kind, "file": file, "search": "", "listed": not unlisted.has(key)}
		if entry.kind == "item":
			index_entry.fixed = fixed.has(entry.value)
			index_entry.subcategory = item_subcategory(entry.value)
		index.entries.append(index_entry)
		var choices := public_variants(catalog, key)
		if choices.is_empty(): choices.append("")
		var pages := []
		for choice: String in choices:
			var page := catalog.page(key, choice)
			var html: String = page.html
			var figure := RegEx.create_from_string("<figure>.*?</figure>")
			html = figure.sub(html, "", true)
			# The public edition has precomputed material/blueprint versions.
			# Interactive rune construction and live models remain in the game.
			html = html.replace(WikiCatalog.paragraph(RemakeText.t("Use the rune selector to explore legal variants. The preview uses the inventory's spell builder; your character and inventory are unchanged.")), "")
			html = html.replace(WikiCatalog.paragraph(RemakeText.t("Explore the items, spells and creatures in your installed game. Values and variants come from the loaded game data, including active data mods.")), "")
			if entry.kind == "item" and not craftable[entry.value]:
				html = html.replace(WikiCatalog.paragraph(WikiCatalog.item_link("bp:" + String(entry.value), RemakeText.t("Blueprint and materials")), true), "")
			var title := public_item_title(choice) if choice else String(entry.title)
			if choice: html = html.replace("<h1>" + WikiCatalog.esc(entry.title) + "</h1>", "<h1>" + WikiCatalog.esc(title) + "</h1>")
			html = rename_item_links(html)
			for internal: String in placeholder_names:
				html = html.replace(WikiCatalog.esc(internal), WikiCatalog.esc(placeholder_names[internal]))
				title = title.replace(internal, placeholder_names[internal])
			var image := ""
			var preview := public_preview(page.preview)
			if not preview.is_empty():
				var identity := String(preview.kind) + ":" + String(preview.value)
				if preview.has("layer"): identity += ":" + preview.mask + ":" + preview.layer
				if GameData.campaign_id == CampaignProfile.ASTRAL: identity = GameData.campaign_id + ":" + identity
				image = identity.sha256_text().substr(0, 24)
				images[image] = preview
			pages.append({"id": choice, "title": title, "html": html, "image": image, "representative_image": preview.get("representative", false)})
			if choice: index_entry.search += " " + title
			variants += 1
		write_json(directory.path_join("pages").path_join(file), {"key": key, "versions": pages})
		if index.entries.size() % 100 == 0: await get_tree().process_frame
	write_json(directory.path_join("index.json"), index)
	if plan_path: write_json(plan_path, images)
	print("PUBLIC_WIKI ", JSON.stringify({"language": RemakeText.lang, "entries": index.entries.size(), "versions": variants, "images": images.size()}))
	get_tree().quit()


func recipe_name(base: String) -> String:
	return GameData.text("instr " + base.replace(" ", "_")).get_slice("\n", 0).strip_edges()


func authored_name(id: String) -> String:
	var info := Items.info(id)
	var prefix: String = {"weapons": "weapon", "armors": "armor", "quick_items": "qitem", "quest_items": "questitem", "loot_items": "litem"}.get(info.table, "")
	var base := String(info.base).replace(" ", "_")
	var material := String(info.material).replace(" ", "_")
	for key: String in ["%s %s %s" % [prefix, base, material], "%s %s" % [prefix, base]]:
		var title := GameData.text(key).get_slice("\n", 0).strip_edges()
		if title and not "_" in title: return title
	return ""


func public_variants(catalog: WikiCatalog, key: String) -> Array[String]:
	var choices := catalog.variants_for(key)
	if catalog.entries[key].kind == "item" and fixed.has(catalog.entries[key].value):
		choices = choices.filter(func(id: String): return not id.begins_with("bp:"))
	return choices


func item_subcategory(id: String) -> String:
	var info := Items.info(id)
	if info.table == "armors": return "armor_" + Items.slot(id)
	if info.table == "weapons":
		var types := ["sword", "axe", "dagger", "spear", "hammer", "bow", "crossbow"]
		var type := int(info.row.get("type_id", -1))
		return "weapon_" + types[type] if type >= 0 and type < types.size() else "other"
	if info.table == "quest_items": return "quest"
	if info.table == "loot_items": return "loot"
	if Items.is_wand(id): return "wand"
	if info.table == "quick_items": return "potion"
	return "other"


func public_item_title(id: String) -> String:
	if id.begins_with("bp:"):
		return RemakeText.t("Blueprint: %s") % family_names.get(id.substr(3), WikiCatalog.item_title(id.substr(3)))
	var info := Items.info(id)
	if fixed.has(info.base) and family_names.has(info.base): return family_names[info.base]
	var title := WikiCatalog.item_title(id)
	var generic := Items.type_text(id)
	if family_names.has(info.base) and (title == generic or title.begins_with(generic + " · ")):
		title = family_names[info.base]
		if not info.material.is_empty(): title += " · " + WikiCatalog.item_title(Items.material_unit(info.material))
	return title


func rename_item_links(html: String) -> String:
	var pattern := RegEx.create_from_string('<a href="wiki://item/[^"?]+\\?version=([^"&]+)">([^<]+)</a>')
	for found: RegExMatch in pattern.search_all(html):
		var id := found.get_string(1).uri_decode()
		if found.get_string(2) != WikiCatalog.esc(WikiCatalog.item_title(id)): continue
		var old := found.get_string()
		html = html.replace(old, old.replace(">" + found.get_string(2) + "</a>", ">" + WikiCatalog.esc(public_item_title(id)) + "</a>"))
	return html


func public_preview(descriptor: Dictionary) -> Dictionary:
	if descriptor.is_empty() or descriptor.kind != "item": return descriptor
	var look := Items.look(descriptor.value)
	if not look.has("layer"): return descriptor
	var layer := String(look.layer)
	for mask: String in ["unhuma", "unhufe"]:
		if has_layer(mask, layer):
			return descriptor if mask == "unhuma" else with_skin(descriptor, mask, layer, false)
	# Some NPC/unique items exist in the builder for multiple materials but
	# ship with one authored costume. Reuse only that same prototype's skin;
	# report the representative appearance instead of drawing a white mesh.
	var info := Items.info(descriptor.value)
	for material: Dictionary in Items.materials_for("bp:" + String(info.base)):
		var candidate := Items.look(String(info.base) + "." + String(material.name).to_lower())
		if candidate.get("model", "") != look.model: continue
		for mask: String in ["unhuma", "unhufe"]:
			var skin := String(candidate.get("layer", ""))
			if skin and has_layer(mask, skin): return with_skin(descriptor, mask, skin, true)
	return {}


func has_layer(mask: String, layer: String) -> bool:
	return GameData.redress.has(mask + layer + ".mmp") or GameData.textures.has(layer + ".mmp")


func with_skin(descriptor: Dictionary, mask: String, layer: String, representative: bool) -> Dictionary:
	var result := descriptor.duplicate()
	result.merge({"mask": mask, "layer": layer, "representative": representative})
	return result


func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(JSON.stringify(value))
	file.close()
