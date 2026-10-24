class_name ArenaCommanders
extends RefCounted
## Authored protagonists and companions with native expression paintings.
const IDS := ["hero", "merc1", "merc2", "merc3", "merc4", "merc5", "merc6", "merc7", "merc8", "merc9"]

static func valid(id: String) -> String:
	return id if id in IDS else "hero"

static func prototype(id: String) -> String:
	var row: Dictionary = WikiLoreData.DATA.campaigns.cursed_lands["character/" + valid(id)]
	return row.prototypes[0]

static func title(id: String) -> String:
	var row: Dictionary = WikiLoreData.DATA.campaigns.cursed_lands["character/" + valid(id)]
	return String(row.names.get(RemakeText.lang, row.names.en))

static func opponents(chosen: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in IDS:
		if id != valid(chosen): result.append(id)
	return result.slice(0, 8)
