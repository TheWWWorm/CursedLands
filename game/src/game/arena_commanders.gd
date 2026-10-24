class_name ArenaCommanders
extends RefCounted
## Authored protagonists and companions with native expression paintings.
const IDS := ["hero", "merc1", "merc2", "merc3", "merc4", "merc5", "merc6", "merc7", "merc8", "merc9"]
## Character identity stays separate in the picker. The saved/network choice
## carries a validated optional suffix, preserving old unsuffixed selections.
const SKINS := {
	"hero": [["", "Original appearance", "Human Hero"],
		["hadagan", "Khadagan outfit", "Human Hero Hadagan"],
		["jun", "Joon appearance", "Jun Male Hero"]],
	"lia_hero": [["", "Transformed", "arena-lia/lia_hero"],
		["unmasked", "Original appearance", "arena-lia/lia_hero_unmasked"],
		["wrapped", "Face wrap", "arena-lia/lia_hero_wrapped"],
		["armored", "Armored outfit", "arena-lia/lia_hero_armored"]],
	"lia_merc2": [["", "Original appearance", "arena-lia/lia_merc2"],
		["armored", "Armored outfit", "arena-lia/lia_merc2_armored"]],
}

static func character(id: String) -> String:
	return id.get_slice(":", 0)

static func skins(id: String) -> Array:
	var who := character(id)
	var result := []
	for row: Array in SKINS.get(who, [["", "Original appearance", ""]]):
		result.append(who if row[0].is_empty() else who + ":" + row[0])
	return result

static func skin_title(id: String) -> String:
	var who := character(valid(id))
	var rows: Array = SKINS.get(who, [["", "Original appearance", ""]])
	return RemakeText.t(rows[maxi(0, skins(who).find(id))][1])

static func choices(expansion := false) -> Array:
	return IDS + ArenaExpansion.CHARACTERS.keys() if expansion else IDS

static func valid(id: String, expansion := true) -> String:
	var who := character(id)
	if who not in choices(expansion): return "hero"
	return id if id in skins(who) else who

static func prototype(id: String) -> String:
	id = valid(id)
	var who := character(id)
	if SKINS.has(who): return SKINS[who][skins(who).find(id)][2]
	if ArenaExpansion.CHARACTERS.has(id): return ArenaExpansion.PREFIX + id
	var row: Dictionary = WikiLoreData.DATA.campaigns.cursed_lands["character/" + valid(id)]
	return row.prototypes[0]

static func title(id: String) -> String:
	id = character(valid(id))
	if ArenaExpansion.CHARACTERS.has(id):
		var extra: Dictionary = WikiLoreData.DATA.campaigns.lost_in_astral["character/" + ArenaExpansion.CHARACTERS[id][1]]
		return String(extra.names.get(RemakeText.lang, extra.names.en))
	var row: Dictionary = WikiLoreData.DATA.campaigns.cursed_lands["character/" + valid(id)]
	return String(row.names.get(RemakeText.lang, row.names.en))

static func opponents(chosen: String, expansion := false) -> Array[String]:
	var result: Array[String] = []
	for id: String in (ArenaExpansion.CHARACTERS.keys() + IDS if expansion else IDS):
		if id != character(valid(chosen)): result.append(id)
	return result.slice(0, 8)
