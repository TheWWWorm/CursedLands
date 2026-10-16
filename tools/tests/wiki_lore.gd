extends Node
## Dialogue inventory, provenance, localization, imagery and read-only regressions.
var failures: Array[String] = []
var checks := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); printerr("FAIL ", message)

func _ready() -> void:
	var database := hash(GameData.db.tables)
	var original_language := RemakeText.lang
	var previous_cache := GameData._text_cache.duplicate()
	var campaign := GameData.campaign_id
	var expected := 47 if campaign == CampaignProfile.ASTRAL else 45
	var inventory: Dictionary = WikiLoreData.DATA.coverage[campaign]
	var known := {}
	for row: Dictionary in WikiLoreData.DATA.campaigns[campaign].values():
		for actor: String in row.get("actors", []): known[actor] = true
	# Read actual archive speakers: adding a dialogue without an article or a
	# specific documented non-story exclusion makes the inventory test fail.
	var pattern := RegEx.create_from_string("(?im)^#phrase\\s+(\\S+)\\s+\\d+")
	for key: String in GameData.texts.entries:
		if not key.begins_with("briefing "): continue
		for found: RegExMatch in pattern.search_all(GameData.text(key)):
			var actor := found.get_string(1).to_lower()
			check(known.has(actor) or inventory.excluded.has(actor), "uncovered dialogue speaker " + actor)
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		GameData._text_cache = previous_cache.duplicate()
		WikiReferenceText.apply()
		var catalog := WikiCatalog.new()
		catalog.rebuild()
		check(catalog.search("", "Characters").size() == expected, language + " character inventory")
		check(catalog.search("", "Allods").size() == (4 if campaign == CampaignProfile.ASTRAL else 3), language + " island inventory")
		var hero := catalog.page("character/hero")
		check(not hero.preview.is_empty(), language + " protagonist illustration")
		if campaign == CampaignProfile.ORIGINAL:
			check(catalog.entries["character/hero"].title == {"en":"Zak","ru":"Зак","de":"Kiran"}[language], language + " original localized protagonist name")
			check(catalog.search({"en":"At-Zako","ru":"Ат-Зако","de":"At-Kira"}[language])[0] == "character/hero", language + " revealed identity finds protagonist first")
		check(catalog.search(catalog.entries["character/hero"].title)[0] == "character/hero", language + " biography before stats")
		for key: String in catalog.lore.records:
			check(catalog.entries.has(key), "article indexed " + key)
			for section: Dictionary in catalog.lore.records[key].sections:
				check(catalog.lore.matches(section), language + " source matches " + key + " " + section.heading)
				for text: String in [section.heading, section.text]:
					check(language == "en" or RemakeText.t(text) != text, language + " translated story " + key)
			var page := catalog.page(key)
			check(not "[[" in page.html, "resolved prose references " + key)
			check(not page.preview.is_empty(), "illustrated lore " + key)
			for link: RegExMatch in RegEx.create_from_string('href="wiki://([^"?]+)').search_all(page.html):
				check(catalog.entries.has(link.get_string(1)), "valid lore link " + link.get_string(1))
		for key: String in catalog.search("", "Maps"):
			check(not catalog.page(key).preview.is_empty(), "map illustration " + key)
		# One changed source suppresses its own claims, preserving unrelated
		# supported prose and leaving mod text untouched.
		var section: Dictionary = catalog.lore.records["character/hero"].sections[0]
		var source: String = section.sources[0]
		var before := GameData.text(source)
		GameData._text_cache[source] = before + "\nchanged scene"
		check(not catalog.lore.matches(section), "changed source rejected")
		check(not catalog.page("character/hero").html.contains(catalog.lore.prose(RemakeText.t(section.text))), "stale biography hidden")
		check(GameData.text(source).ends_with("changed scene"), "mod dialogue preserved")
		GameData._text_cache[source] = before
	check(hash(GameData.db.tables) == database, "database remains unchanged")
	GameData._text_cache = previous_cache
	RemakeText.lang = original_language
	print("WIKI_LORE_TEST ", JSON.stringify({"campaign":campaign,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
