class_name CampaignProfile
extends RefCounted
## Campaign identity comes from the installed story data, independently of
## its language or folder name. Original saves retain their historical path.

const ORIGINAL := "cursed_lands"
const ASTRAL := "lost_in_astral"


static func detect(texts: EIResArchive) -> String:
	if texts:
		var campaign := CampaignMap.load_from(texts)
		if campaign.zone("gz1g").get("mpr", "") == "zonezero" and campaign.allods.has("jigran"):
			return ASTRAL
	return ORIGINAL


static func matches(stored: Variant, expected: String) -> bool:
	return stored is String and stored in [ORIGINAL, ASTRAL] and stored == expected


static func save_directory(id: String) -> String:
	return "user://saves/lost_in_astral" if id == ASTRAL else "user://saves"
