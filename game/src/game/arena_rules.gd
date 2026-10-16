class_name ArenaRules
extends RefCounted
## Content shared by the playable expedition and its balance simulations.
## Every fighter resolves to an unmodified original-game prototype.

const VERSION := 6
const WAVE_COUNT := 30
const OPENING_GOLD := 16
const MIN_RECRUIT_COST := 3
const BASE_INCOME := 5
const WIN_INCOME := 1
const INTEREST_CAP := 3
const TRAINING_COST := 5
const TRAINING_XP := 3
const MAX_TRAINING := 18
const MAX_ARMY := 9
const COMPANIONS := ["orcfemalem3", "orcfemalem5", "octopuskaniam12", "octopushadaganm15"]
const FAMILIES := [
	{"name": "Boars", "role": "Melee", "cost": 3, "forms": ["boarredf1", "boarredf3", "boardarkf6"]},
	{"name": "Tribal fighters", "role": "Melee", "cost": 3, "forms": ["goblinf1", "orcmalef3", "orcmalef5"]},
	{"name": "Wolves", "role": "Melee", "cost": 3, "forms": ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"]},
	{"name": "Tribal shooters", "role": "Ranged", "cost": 4, "copies": [2, 3], "forms": ["goblina1", "goblina3", "orcfemalea5"]},
	{"name": "Bats", "role": "Magic", "cost": 4, "copies": [2, 3], "forms": ["batredm1", "batredm3", "batlightm7"]},
	{"name": "Toads", "role": "Magic", "cost": 4, "forms": ["toadm2", "toadm6"]},
	{"name": "White tigers", "role": "Melee", "cost": 5, "prices": [5, 9], "unlock": 10, "region": 1, "copies": [2], "forms": ["tigerwhitef6", "tigerwhitef10"]},
	{"name": "Blue trolls", "role": "Melee", "cost": 7, "prices": [7, 12], "unlock": 13, "region": 1, "copies": [2], "forms": ["trollbluef9", "trollbluef12"]},
	{"name": "Stony harpies", "role": "Magic", "cost": 7, "prices": [7, 14], "unlock": 13, "region": 1, "copies": [2], "forms": ["succubbluem10", "succubbluem17"]},
	{"name": "Sand ogres", "role": "Melee", "cost": 9, "prices": [9, 16], "unlock": 19, "region": 2, "copies": [2], "forms": ["ogrehadaganf13", "ogrehadaganf17"]},
	{"name": "Spiders", "role": "Melee", "cost": 8, "prices": [8, 14], "unlock": 19, "region": 2, "copies": [2], "forms": ["spiderf10", "spiderf15"]},
	{"name": "Grey harpies", "role": "Magic", "cost": 9, "prices": [9, 16], "unlock": 19, "region": 2, "copies": [2], "forms": ["succubgreym13", "succubgreym17"]},
]
# One pact per expedition. Only owned, deployed creatures meet its condition;
# the guest never counts toward its own pact, occupies no army/bench slot and
# cannot be sold or evolved. Support uses the same native spawn path as everyone.
const PACTS := {
	"hunt": {"name": "Wild kin", "help": "Three different beast families call an extra beast to your side.",
		"families": [0, 2, 4, 5, 6, 8, 10, 11], "needed": 3, "min_rank": 0, "forms": ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"],
		"later_forms": [["tigerwhitef6", "tigerwhitef8", "tigerwhitef10"], ["spiderf13", "spiderf14", "spiderf15"]]},
	"tribe": {"name": "Tribal council", "help": "Two evolved families among tribes, trolls, ogres and harpies call a spellcaster ally.",
		"families": [1, 3, 7, 8, 9, 11], "needed": 2, "min_rank": 1, "forms": ["orcfemalem3", "orcfemalem5", "orcfemalem7"],
		"later_forms": [["batlightm7", "batlightm9", "batlightm10"], ["octopushadaganm13", "octopushadaganm15", "octopushadaganm17"]]},
	"vanguard": {"name": "The vanguard", "help": "Three different melee families call a ranged ally to cover your front line.",
		"families": [0, 1, 2, 6, 7, 9, 10], "needed": 3, "min_rank": 0, "forms": ["goblina3", "orcfemalea5", "orcfemalea7"],
		"later_forms": [["batlightm7", "batlightm9", "batlightm10"], ["succubgreym13", "succubgreym15", "succubgreym17"]]},
}
# Ordered encounters. Different seeds mirror the enemy formation; all details
# are visible before commitment. Counts/composition are tuning inputs, not stats.
const WAVES := [
	["First tracks", "boarredf1"],
	["The hunting pack", "wolfgreyf1", "wolfgreyf1"],
	["Sling ambush", "goblinf1", "goblina1"],
	["The old tusk", "boarredf3", "boarredf1", "boarredf1"],
	["Marsh guardians", "goblinf2", "goblinf2", "toadm2", "goblina1"],
	["The tribal champion", "orcmalef3", "goblinf2", "goblina1", "goblina2"],
	["White tracks", "wolfgreyf3", "wolfgreyf3", "wolfgreyf2", "goblina2"],
	["The bone guard", "skeletonf2", "skeletonf2", "goblina3", "toadm2"],
	["The seer's escort", "orcmalef3", "orcfemalem3", "goblina3"],
	["Black tusks", "boardarkf5", "boarredf3", "boarredf3", "toadm4"],
	["The ridge hunters", "tigerwhitef6", "tigerwhitef6", "wolfwhitef6", "goblina3"],
	["The Ogre's court", "ogregipatf9", "wolfwhitef6", "batlightm7"],
	["The white pack", "tigerwhitef8", "tigerwhitef8", "batlightm8", "toadm6"],
	["The war council", "trollbluef9", "trollbluef9", "tigerwhitef6", "batlightm8"],
	["The ancient guard", "succubbluem10", "tigerwhitef8", "tigerwhitef8", "batlightm8"],
	["The last hunt", "trollbluef11", "tigerwhitef10", "batlightm10", "orcfemalem7"],
	["At the gates", "spiderf10", "spiderf10", "trollbluef9", "succubbluem10"],
	["The lord of the ruins", "trollbluef12", "tigerwhitef10", "tigerwhitef10", "succubbluem11", "octopuskaniam12"],
	["Tracks in the snow", "ogrehadaganf13", "tigerwhitef10", "batlightm10"],
	["The frozen pass", "spiderf13", "spiderf13", "succubbluem11", "batlightm10"],
	["Stone wings", "ogrehadaganf13", "spiderf14", "succubgreym13", "trollbluef9"],
	["The silk road", "spiderf13", "spiderf13", "tigerwhitef10", "batlightm10"],
	["Desert raiders", "ogrehadaganf13", "spiderf13", "succubgreym13"],
	["The winter council", "trollbluef12", "ogrehadaganf13", "succubbluem11", "octopushadaganm13"],
	["Giants at dusk", "ogrehadaganf15", "ogrehadaganf15", "spiderf14", "succubgreym13"],
	["The hollow voices", "bansheedarkf14", "bansheedarkf14", "spiderf15", "succubgreym15"],
	["The high priest", "ogrehadaganf17", "trollbluef12", "succubgreym15", "spiderf15", "octopushadaganm15"],
	["Ash and ice", "ogrehadaganf15", "ogrehadaganf15", "bansheedarkf16", "succubgreym17"],
	["The last watch", "ogrehadaganf17", "ogrehadaganf17", "spiderf15", "spiderf15", "succubgreym15", "octopushadaganm17"],
	["The siege of winter", "ogrehadaganf17", "ogrehadaganf17", "trollbluef12", "succubgreym17", "succubgreym17", "bansheedarkf16"],
]
const BOONS := {
	"merchant": ["Quartermaster", "Shop refreshes cost 1 gold instead of 2."],
	"reserve": ["Pack train", "Three more reserve slots."],
	"purse": ["War chest", "12 gold for your company."],
	"life": ["Second wind", "Recover one life, up to three."],
	"scout": ["Well connected", "Every new shop has a sixth recruit offer."],
	"companion": ["A new ally", "A spellcaster joins your reserves."],
	"pact": ["Company pact", "Choose a pact for your company. Its families fight together to call an extra ally."],
	"pact_upgrade": ["Strengthen the pact", "Your pact calls a stronger ally for the rest of this expedition."],
	"supplies": ["Travel supplies", "Gain 6 gold for your next recruits."],
}


static func prototype(family: int, rank: int) -> String:
	if family < 0 or family >= FAMILIES.size() or rank < 0 or rank >= FAMILIES[family].forms.size(): return ""
	return FAMILIES[family].forms[rank]


static func evolution_copies(family: int, rank: int) -> int:
	if prototype(family, rank + 1).is_empty(): return 0
	return int(FAMILIES[family].get("copies", [3, 3])[rank])


static func title(id: String) -> String:
	return RemakeText.t(GameUnit.unit_title(id))


static func available() -> bool:
	var map := EIResArchive.open_path(GameData.root.path_join("maps/zone11.mpr"))
	if map == null or map.read("zone11.mp").size() < 38: return false
	for family: Dictionary in FAMILIES:
		for id: String in family.forms:
			if GameData.db.find("monster_prototypes", id).is_empty(): return false
	for pact: Dictionary in PACTS.values():
		for id: String in Array(pact.forms) + Array(pact.later_forms[0]) + Array(pact.later_forms[1]):
			if GameData.db.find("monster_prototypes", id).is_empty(): return false
	for id: String in COMPANIONS:
		if GameData.db.find("monster_prototypes", id).is_empty(): return false
	for wave: Array in WAVES:
		for i in range(1, wave.size()):
			if GameData.db.find("monster_prototypes", wave[i]).is_empty(): return false
	return true


static func enemies(wave: int, run_seed: int, challenge := 0) -> Array[Dictionary]:
	var row: Array = WAVES[clampi(wave - 1, 0, WAVE_COUNT - 1)]
	var out: Array[Dictionary] = []
	var front := 0
	var back := 0
	var ids := row.slice(1)
	if challenge > 0 and wave >= 3:
		ids.append("ogrehadaganf15" if wave >= 25 else "trollbluef9" if wave >= 19 else "orcmalef5" if wave > 12 else "orcmalef3" if wave > 6 else "goblinf1")
	if challenge > 1 and wave >= 6:
		ids.append("succubgreym15" if wave >= 25 else "batlightm8" if wave >= 19 else "orcfemalea5" if wave > 12 else "goblina3" if wave > 9 else "goblina2")
	var flip := -1 if (run_seed + wave) % 2 else 1
	for id: String in ids:
		var proto := GameData.db.find("monster_prototypes", id)
		var ranged := float(proto.get("attack_range", 0)) > 0 or not Array(proto.get("spells", [])).is_empty()
		var index := back if ranged else front
		var lane: float = [0.0, -4.0, 4.0, -8.0, 8.0][index % 5] + (2.0 if index >= 5 else 0.0)
		out.append({"id": id, "team": 1, "point": Vector2((40.5 if ranged else 36.5) + (3.0 if index >= 5 else 0.0), 32 + flip * lane)})
		if ranged: back += 1
		else: front += 1
	return out


static func region(wave: int) -> int:
	return 2 if wave >= 19 else 1 if wave >= 10 else 0


static func region_name(index: int) -> String:
	return RemakeText.t(["Gipath", "Ingos", "Suslanger"][clampi(index, 0, 2)])


static func companion(wave: int) -> String:
	return COMPANIONS[clampi(wave / 6 - 1, 0, COMPANIONS.size() - 1)]


static func recruit_pool(wave: int) -> Array[int]:
	var pool: Array[int] = []
	for family in FAMILIES.size():
		if wave < int(FAMILIES[family].get("unlock", 1)): continue
		var origin := int(FAMILIES[family].get("region", 0))
		var weight := 1 if origin < region(wave) else 5
		if region(wave) == 2 and origin == 1: weight = 2
		for copy in weight: pool.append(family)
	return pool
