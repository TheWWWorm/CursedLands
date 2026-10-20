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
		if GameData.campaign_id == CampaignProfile.ASTRAL:
			check_astral(catalog,locale)
			continue
		for key: String in WikiQuestText.TEXTS:
			var record: Dictionary = WikiQuestText.TEXTS[key]
			check(WikiWorldText.text(key) == record[locale],"native quest description in " + locale + ": " + key)
			for original: String in [record.en,record.ru,record.de]:
				check(WikiQuestText.text(key,original) == record[locale],"all original source editions translate " + key)
			check(WikiQuestText.text(key,"Edited quest\nCustom summary") == "Edited quest\nCustom summary","edited quest description survives")
			var entry := "quest/" + key.trim_prefix("quest ")
			check(catalog.entries.has(entry),"installed base quest has a catalog entry")
			if not catalog.entries.has(entry): continue
			check(catalog.entries[entry].title == String(record[locale]).get_slice("\n",0).strip_edges(),"catalog uses original localized quest title")
			check(catalog.page(entry).html.contains(WikiCatalog.esc(catalog.entries[entry].title)),"localized title reaches article: " + locale + ": " + key)
	GameData._text_cache = cache; RemakeText.lang = language
	print("WIKI_QUEST_LOCALES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)

func check_astral(catalog: WikiCatalog,locale: String) -> void:
	var exercised := 0
	for key: String in WikiWorldText.TEXTS:
		if not key.begins_with("quest "): continue
		var record: Dictionary = WikiWorldText.TEXTS[key]
		var original := GameData.text(key)
		check(not original.is_empty(),"installed expansion has quest source: "+key)
		if original.is_empty(): continue
		exercised+=1
		var expected: String=record[locale] if original==record.ru else original
		check(WikiWorldText.text(key)==expected,"expansion quest follows its actual source edition: "+locale+": "+key)
		var entry := "quest/"+key.trim_prefix("quest ")
		check(catalog.entries.has(entry),"installed expansion quest has a catalog entry")
		if catalog.entries.has(entry):
			check(catalog.entries[entry].title==expected.get_slice("\n",0).strip_edges(),"expansion catalog title is localized")
			check(catalog.page(entry).html.contains(WikiCatalog.esc(catalog.entries[entry].title)),"expansion localized title reaches article")
		# Existing translated archives and edited mod prose must take priority
		# over the fallback table, which recognizes the original Russian text.
		for source: String in [record.en,record.de,"Edited quest\nCustom summary"]:
			GameData._text_cache[key]=source
			check(WikiWorldText.text(key)==source,"localized or edited expansion source survives")
		GameData._text_cache[key]=original
	check(exercised>0,"expansion uses its own quest archive, not base-only optional quests")
