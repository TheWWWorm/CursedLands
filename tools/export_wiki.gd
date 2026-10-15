extends Node
## Run through --tool with an installed GOG edition and --wiki-output=/directory.
## Exports reference articles only; never copies game archives or player data.

func _ready() -> void:
	var output := ""
	var plan_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-output="): output = arg.trim_prefix("--wiki-output=")
		if arg.begins_with("--wiki-image-plan="): plan_path = arg.trim_prefix("--wiki-image-plan=")
	if output.is_empty():
		printerr("Missing --wiki-output")
		get_tree().quit(1)
		return
	var catalog := WikiCatalog.new()
	catalog.rules = {"armor_formula": 0}
	catalog.rebuild()
	var placeholder_names := {}
	var unnamed := 0
	# Family records often have only a type label; their recipe contains the
	# authored family name, without choosing one particular material.
	for key: String in catalog.entries:
		var entry: Dictionary = catalog.entries[key]
		if entry.kind == "item":
			var name := GameData.text("instr " + String(entry.value).replace(" ", "_")).get_slice("\n", 0).strip_edges()
			if "_" in name:
				unnamed += 1
				entry.title = RemakeText.t("%s (variant %d)") % [entry.title, unnamed]
				placeholder_names[name] = entry.title
				for token in RegEx.create_from_string("[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+").search_all(Items.flavor("bp:" + String(entry.value))):
					placeholder_names[token.get_string()] = entry.title
			elif name:
				entry.title = name
	# Creature equipment can introduce authored rune combinations lazily.
	# Materialize the transitive reference set before writing the static index.
	var visited := {}
	while visited.size() < catalog.entries.size():
		for key: String in catalog.entries.keys():
			if visited.has(key): continue
			visited[key] = true
			var choices := catalog.variants_for(key)
			if choices.is_empty(): choices.append("")
			for choice: String in choices: catalog.page(key, choice)
	catalog.ordered.assign(catalog.entries.keys())
	catalog.ordered.sort_custom(func(a: String, b: String): return String(catalog.entries[a].title).naturalnocasecmp_to(catalog.entries[b].title) < 0)
	var directory := output.path_join(RemakeText.lang)
	DirAccess.make_dir_recursive_absolute(directory.path_join("pages"))
	var index := {"language": RemakeText.lang, "version": "1.6.0", "source": "GOG", "entries": [], "categories": {}}
	var images := {}
	var variants := 0
	for category: String in WikiCatalog.CATEGORIES:
		index.categories[category] = RemakeText.t(category)
	for key: String in catalog.ordered:
		var entry: Dictionary = catalog.entries[key]
		var file := key.sha256_text().substr(0, 20) + ".json"
		var index_entry := {"key": key, "title": entry.title, "category": entry.category, "kind": entry.kind, "file": file, "search": ""}
		index.entries.append(index_entry)
		var choices := catalog.variants_for(key)
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
			var title := WikiCatalog.item_title(choice) if choice else String(entry.title)
			for internal: String in placeholder_names:
				html = html.replace(WikiCatalog.esc(internal), WikiCatalog.esc(placeholder_names[internal]))
				title = title.replace(internal, placeholder_names[internal])
			var image := ""
			if not page.preview.is_empty():
				image = (String(page.preview.kind) + ":" + String(page.preview.value)).sha256_text().substr(0, 24)
				images[image] = page.preview
			pages.append({"id": choice, "title": title, "html": html, "image": image})
			if choice: index_entry.search += " " + title
			variants += 1
		write_json(directory.path_join("pages").path_join(file), {"key": key, "versions": pages})
		if index.entries.size() % 100 == 0: await get_tree().process_frame
	write_json(directory.path_join("index.json"), index)
	if plan_path: write_json(plan_path, images)
	print("PUBLIC_WIKI ", JSON.stringify({"language": RemakeText.lang, "entries": index.entries.size(), "versions": variants, "images": images.size()}))
	get_tree().quit()


func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(JSON.stringify(value))
	file.close()
