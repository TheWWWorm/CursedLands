extends Node
## Private translation input from the installed edition. Never publish this audit.

func _ready() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-text-audit="): output = arg.trim_prefix("--wiki-text-audit=")
	if output.is_empty():
		printerr("Missing --wiki-text-audit (use a private output path)")
		get_tree().quit(1)
		return
	var catalog := WikiCatalog.new()
	GameData._text_cache.clear()
	catalog.rebuild()
	var visited := {}
	while visited.size() < catalog.entries.size():
		for key: String in catalog.entries.keys():
			if visited.has(key): continue
			visited[key] = true
			var choices := catalog.variants_for(key)
			if choices.is_empty(): choices.append("")
			for choice: String in choices: catalog.page(key, choice)
	var used := GameData._text_cache.keys()
	var text := {}
	for archive: EIResArchive in [GameData.texts_lmp, GameData.texts]:
		if archive == null: continue
		for key: String in archive.entries:
			if key.get_slice(" ", 0) in ["spell", "modifier", "instr", "armor", "weapon", "qitem", "questitem", "litem", "material", "unit", "perk", "pers", "string", "matshort"]:
				text[key] = GameData.text(key)
	var data := {"campaign": GameData.campaign_id, "language": RemakeText.lang, "used": used, "entries": catalog.entries, "texts": text}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("WIKI_TEXT_AUDIT ", GameData.campaign_id, " ", RemakeText.lang, " entries=", catalog.entries.size(), " texts=", text.size())
	get_tree().quit()
