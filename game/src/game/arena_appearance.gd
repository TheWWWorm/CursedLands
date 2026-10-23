class_name ArenaAppearance
extends RefCounted
## Synthetic Trials actors have no MOB record. Restore the original creature
## palettes that normally live in OBJPRIMTXTR (0xB007), not prototype.skin.
## Never apply these defaults to campaign actors with authored map appearances.
const PALETTES := {
	"boarred":"boar00", "boardark":"boar01", "wolfgrey":"wolf00", "wolfwhite":"wolf01",
	"tigerred":"tiger00", "tigerwhite":"tiger01", "doggrey":"dog00", "dogred":"dog01",
	"goblin":"goblin00", "dragonbrown":"dragon02", "dragonblue":"dragon01", "dragongreen":"dragon00",
	"driadsnow":"driad01", "driadgreen":"driad00", "driaddark":"driad02",
	"succubred":"succubus00", "succubblue":"succubus01", "succubgrey":"succubus02",
	"bansheedark":"banshee01", "bansheelight":"banshee00", "scrabmotherpoisoned":"crab02",
	"evileyesimple":"beholder02", "evileyegreen":"beholder01", "evileyered":"beholder00",
	"unicornwhite":"unicorn00", "unicornblack":"unicorn01",
}

## Only palettes authored for the recruit's own rig. The combat prototype,
## complexion, equipment, animation cadence and spell kit remain unchanged.
## Two-palette species reserve their contrasting appearance for three stars.
const RANK_PALETTES := {
	0: ["boar00", "boar00", "boar01"],
	1: ["wolf00", "wolf00", "wolf01"],
	3: ["bat00", "bat01", "bat02"],
	4: ["goblin00", "goblin00", "goblin00l"],
	6: ["skeleton00", "skeleton00", "skeleton01"],
	7: ["tiger00", "tiger00", "tiger01"],
	9: ["crab01", "crab00", "crab02"],
	10: ["lizardman00", "lizardman01", "lizardman02"],
	11: ["driad00", "driad01", "driad02"],
	14: ["troll01", "troll00", "troll02"],
	15: ["ogre00", "ogre00", "ogre01"],
	16: ["succubus00", "succubus01", "succubus02"],
	18: ["beholder02", "beholder02", "beholder01"],
	19: ["banshee00", "banshee00", "banshee01"],
	20: ["unicorn00", "unicorn00", "unicorn01"],
	23: ["dragon00", "dragon01", "dragon02"],
}

## Use original localized variant names where the old name specifies a colour
## or clan. Empty entries keep the recruit's existing age/rank name.
const RANK_NAMES := {
	0: ["", "", "boardarkf6"],
	1: ["", "", "wolfwhitef6"],
	3: ["", "batlightm7", "batdarkm12"],
	7: ["", "", "tigerwhitef10"],
	11: ["", "driadsnowa9", "driaddarka11"],
	14: ["trollgreenf10", "", "trollblackslowf16"],
	16: ["", "succubbluem10", "succubgreym13"],
	18: ["", "", "evileyegreenm17"],
	19: ["bansheelightm5", "bansheelightm7", ""],
	20: ["", "", "unicornblackm15"],
	23: ["dragongreenm12", "dragonbluem14", ""],
}

static func _recruit(id: String, family: int, rank: int) -> bool:
	return family >= 0 and rank >= 0 and rank < 3 and ArenaRules.prototype(family, rank) == id.to_lower()

static func info(id: String, family := -1, rank := 0) -> Dictionary:
	var result := {"prototype":id}
	for prefix: String in PALETTES:
		if id.to_lower().begins_with(prefix):
			result.texture = PALETTES[prefix]
			# Original woodsfolk leader textures distinguish their caster role.
			if prefix.begins_with("driad") and id.to_lower().trim_prefix(prefix).contains("m"):
				result.texture += "l"
			break
	if _recruit(id, family, rank) and RANK_PALETTES.has(family):
		result.texture = RANK_PALETTES[family][rank]
	return result

static func preview(id: String, family := -1, rank := 0) -> Dictionary:
	return {"kind":"creature", "value":id, "appearance":info(id, family, rank)}

static func name_prototype(id: String, family := -1, rank := 0) -> String:
	if _recruit(id, family, rank) and RANK_NAMES.has(family):
		var variant: String = RANK_NAMES[family][rank]
		if not variant.is_empty(): return variant
	return id

static func placement_info(placement: Dictionary) -> Dictionary:
	return info(placement.id, int(placement.get("family", -1)), int(placement.get("rank", 0)))
