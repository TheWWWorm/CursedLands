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
}

static func info(id: String) -> Dictionary:
	var result := {"prototype":id}
	for prefix: String in PALETTES:
		if id.to_lower().begins_with(prefix):
			result.texture = PALETTES[prefix]
			# Original woodsfolk leader textures distinguish their caster role.
			if prefix.begins_with("driad") and id.to_lower().trim_prefix(prefix).contains("m"):
				result.texture += "l"
			break
	return result

static func preview(id: String) -> Dictionary:
	return {"kind":"creature", "value":id, "appearance":info(id)}
