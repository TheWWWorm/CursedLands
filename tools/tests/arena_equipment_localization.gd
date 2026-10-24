extends Node
## Dynamic item, alliance and feedback keys are as important as literal UI text.
func _ready() -> void:
	var keys := {}
	for rule: Dictionary in ArenaItems.RULES.values():
		keys[rule.name] = true
	for rule: Dictionary in ArenaAlliances.RULES.values():
		keys[rule.name] = true; keys[rule.help] = true
	for tiers: Array in ArenaAlliances.EFFECTS.values():
		for key: String in tiers: keys[key] = true
	for family in [28, 29]:
		keys[ArenaRules.FAMILIES[family].name] = true
		keys[ArenaRules.FAMILIES[family].hook] = true
	var pattern := RegEx.new()
	pattern.compile('RemakeText\\.t\\("([^"\\n]*)"\\)')
	var files: Array[String] = ["res://src/ui/arena_pve_screen.gd", "res://src/game/arena_items.gd", "res://src/game/arena_run.gd"]
	# Include reward, tray, drag target and tooltip controls as the UI evolves.
	for filename: String in DirAccess.get_files_at("res://src/ui"):
		if filename.ends_with(".gd") and (filename.begins_with("arena_equipment_") or filename.begins_with("arena_item_")):
			files.append("res://src/ui/" + filename)
	for file: String in files:
		for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(file)):
			keys[found.get_string(1).c_unescape()] = true
	var failures: Array[String] = []
	var checks := 0
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		for key: String in keys:
			checks += 1
			var translated := RemakeText.t(key)
			var entries: Array = RemakeText.TEXTS.get(key, WikiLoreData.DATA.texts.get(key, []))
			var index := 0 if language == "ru" else 1
			# German legitimately shares words such as Horde and Reserve with English.
			if translated.is_empty() or (language != "en" and (entries.size() <= index or String(entries[index]).is_empty())): failures.append(language + ": " + key)
		for kind: String in ArenaItems.RULES:
			checks += 1
			if ArenaItems.title(kind).is_empty() or ArenaItems.description(kind).is_empty(): failures.append(language + ": item " + kind)
	print("ARENA_EQUIPMENT_LOCALIZATION checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
