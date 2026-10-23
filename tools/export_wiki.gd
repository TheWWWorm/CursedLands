extends Node
## Run through --tool with an installed GOG edition and --wiki-output=/directory.
## Exports reference articles only; never copies game archives or player data.

var catalog: WikiCatalog
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
	WikiReferenceText.apply()
	# LiA adds alternate material records without separate text entries.
	# Use the named parent material and a localized variant label.
	for code: String in ["troll_green2", "troll_blue2", "tiger_hide2"]:
		if GameData.text("material " + code).strip_edges().is_empty():
			var original := GameData.text("material " + code.trim_suffix("2"))
			if original:
				var lines := original.split("\n", true, 1)
				GameData._text_cache["material " + code] = RemakeText.t("%s (variant %d)") % [lines[0], 2] + ("\n" + lines[1] if lines.size() > 1 else "")
	var unnamed_spells := {}
	for row: Dictionary in GameData.db.table("spell_prototypes"):
		var code := String(row.code).to_lower()
		if GameData.text("spell " + code).strip_edges().is_empty(): unnamed_spells[code] = true
	catalog = WikiCatalog.new()
	catalog.rules = {"armor_formula": 0}
	catalog.rebuild()
	var placeholder_names := catalog._placeholder_names
	family_names = catalog._family_names
	unlisted = catalog._unlisted.duplicate()
	fixed = catalog._fixed
	for key: String in catalog.entries:
		if catalog.entries[key].kind == "item": craftable[catalog.entries[key].value] = catalog.craftable(key)
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
	var index := {"schema":2,"language": RemakeText.lang, "version": str(ProjectSettings.get_setting("application/config/version")), "campaign": GameData.campaign_id, "source": "Lost in Astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "GOG", "entries": [], "categories": {}}
	var images := {}
	var page_images := {}
	var variants := 0
	for category: String in WikiCatalog.CATEGORIES:
		index.categories[category] = RemakeText.t(category)
	for key: String in all_keys:
		var entry: Dictionary = catalog.entries[key]
		var file := key.sha256_text().substr(0, 20) + ".json"
		var index_entry := {"key": key, "title": entry.title, "category": entry.category, "kind": entry.kind, "file": file, "search": catalog.lore.search_text(key), "listed": not unlisted.has(key), "subtitle":catalog.knowledge.subtitles.get(key,"")}
		if entry.has("aliases"): index_entry.aliases = entry.aliases
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
			# The public edition uses precomputed material versions and the
			# same numeric constructor inputs without loading the game engine.
			html = html.replace(WikiCatalog.paragraph(RemakeText.t("Use the rune selector to explore legal variants. The preview uses the inventory's spell builder; your character and inventory are unchanged.")), "")
			html = html.replace(WikiCatalog.paragraph(RemakeText.t("Explore the items, spells and creatures in your installed game. Values and variants come from the loaded game data, including active data mods.")), "")
			if entry.kind == "item" and not craftable[entry.value]:
				html = html.replace(WikiCatalog.paragraph(WikiCatalog.item_link("bp:" + String(entry.value), RemakeText.t("Blueprint and materials")), true), "")
			var title := public_item_title(choice) if choice else String(entry.title)
			if choice and entry.kind == "creature": title = String(entry.title) + " · " + catalog.cut.appearance_label(entry.value, choice)
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
				if preview.kind == "map": identity += ":" + str(preview.dimensions)
				if preview.has("identity"): identity += ":" + String(preview.identity)
				if GameData.campaign_id == CampaignProfile.ASTRAL: identity = GameData.campaign_id + ":" + identity
				image = identity.sha256_text().substr(0, 24)
				images[image] = preview
			var caption := String(preview.get("caption", ""))
			if preview.get("kind", "") == "allod": caption = RemakeText.t("Original travel map")
			var output_page := {"id":choice,"title":title,"html":html,"image":image,"representative_image":preview.get("representative",false),"pins":page.pins,"guide":page.guide}
			if preview.get("kind", "") in ["scene", "allod"] or entry.kind == "quest" and image:
				output_page.image_kind = preview.kind
			if caption: output_page.image_caption = caption
			if image and not page_images.has(key):
				page_images[key] = image
				index_entry.image = image
			if catalog.craftable(key) and choice and not choice.begins_with("bp:"): output_page.builder = catalog.item_builder_data(choice)
			if entry.kind=="item" and choice and not choice.begins_with("bp:"):
				output_page.plan={"weight":Items.weight(choice),"price":Items.price(choice)}
				var info := Items.info(choice)
				if not info.mat.is_empty():
					var material := Items.material_unit(info.material)
					output_page.plan.material={"key":WikiCatalog.item_key(material),"title":WikiCatalog.item_title(material)}
			pages.append(output_page)
			if choice: index_entry.search += " " + title
			variants += 1
		write_json(directory.path_join("pages").path_join(file), {"key": key,"relations":catalog.knowledge.groups(key), "versions": pages})
		if index.entries.size() % 100 == 0: await get_tree().process_frame
	write_json(directory.path_join("index.json"), index)
	var constructors := catalog.constructor_data()
	for code: String in constructors.runes: constructors.runes[code].image = page_images.get("rune/"+code.uri_encode(),"")
	for code: String in constructors.spells: constructors.spells[code].image = page_images.get("spell/"+code.uri_encode(),"")
	write_json(directory.path_join("constructors.json"),constructors)
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
	return WikiCatalog.item_subcategory(id)


func public_item_title(id: String) -> String:
	return catalog.display_item_title(id)


func rename_item_links(html: String) -> String:
	var pattern := RegEx.create_from_string('<a href="wiki://item/[^"?]+\\?version=([^"&]+)">([^<]+)</a>')
	for found: RegExMatch in pattern.search_all(html):
		var id := found.get_string(1).uri_decode()
		if found.get_string(2) != WikiCatalog.esc(WikiCatalog.item_title(id)): continue
		var old := found.get_string()
		html = html.replace(old, old.replace(">" + found.get_string(2) + "</a>", ">" + WikiCatalog.esc(public_item_title(id)) + "</a>"))
	return html


func public_preview(descriptor: Dictionary) -> Dictionary:
	return WikiCatalog.preview_descriptor(descriptor)


func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(JSON.stringify(value))
	file.close()
