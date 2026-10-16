extends Node
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	var language := RemakeText.lang
	var cache := GameData._text_cache.duplicate()
	for locale: String in ["en","ru","de"]:
		RemakeText.lang = locale
		var catalog := WikiCatalog.new(); catalog.rebuild()
		for key: String in WikiQuestText.TEXTS:
			var record: Dictionary = WikiQuestText.TEXTS[key]
			check(WikiWorldText.text(key) == record[locale],"native quest description in " + locale + ": " + key)
			for original: String in [record.en,record.ru,record.de]:
				check(WikiQuestText.text(key,original) == record[locale],"all original source editions translate " + key)
			check(WikiQuestText.text(key,"Edited quest\nCustom summary") == "Edited quest\nCustom summary","edited quest description survives")
			var entry := "quest/" + key.trim_prefix("quest ")
			check(catalog.entries[entry].title == String(record[locale]).get_slice("\n",0).strip_edges(),"catalog uses original localized quest title")
			check(catalog.page(entry).html.contains(WikiCatalog.esc(catalog.entries[entry].title)),"localized title reaches article: " + locale + ": " + key)
	GameData._text_cache = cache; RemakeText.lang = language
	print("WIKI_QUEST_LOCALES ",checks," checks ",failures)
	get_tree().quit(1 if failures else 0)
