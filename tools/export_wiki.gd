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
		index.entries.append({"key": key, "title": entry.title, "category": entry.category, "kind": entry.kind, "file": file})
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
			var image := ""
			if not page.preview.is_empty():
				image = (String(page.preview.kind) + ":" + String(page.preview.value)).sha256_text().substr(0, 24)
				images[image] = page.preview
			pages.append({"id": choice, "title": WikiCatalog.item_title(choice) if choice else entry.title, "html": html, "image": image})
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
