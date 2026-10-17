class_name ArenaRules
extends RefCounted
## Content shared by the playable expedition and its balance simulations.
## Original prototypes remain immutable. Elite ranks only scale Trials actors.

const VERSION := 10
const PREPARATION_SECONDS := 60.0
const BATTLE_SECONDS := 120.0
const WAVE_COUNT := 30
const OPENING_GOLD := 10
const MIN_RECRUIT_COST := 1
const BASE_INCOME := 5
const WIN_INCOME := 1
const INTEREST_CAP := 3
const TRAINING_COST := 5
const TRAINING_XP := 5
const MAX_TRAINING := 126
const MAX_ARMY := 9
# Cumulative XP from the opening level 3. Increasing costs make rolling versus
# leveling a continuing decision instead of a cheap slot on every third wave.
const LEVEL_XP := [0, 0, 0, 0, 6, 18, 36, 60, 90, 126]
const SHOP_ODDS := {
	3: [55, 45, 0, 0, 0], 4: [55, 45, 0, 0, 0],
	5: [40, 40, 20, 0, 0], 6: [30, 35, 27, 8, 0],
	7: [22, 28, 28, 20, 2], 8: [15, 20, 25, 30, 10],
	9: [10, 15, 25, 35, 15],
}
const COMPANIONS := ["orcfemalem3", "orcfemalem5", "octopuskaniam12", "octopushadaganm15"]
const FAMILIES := [
	{"name": "Boars", "role": "Melee", "cost": 1, "tier": 1, "forms": ["boarredf1", "boarredf3", "boardarkf6"]},
	{"name": "Tribal fighters", "role": "Melee", "cost": 1, "tier": 1, "forms": ["goblinf1", "orcmalef3", "orcmalef5"]},
	{"name": "Wolves", "role": "Melee", "cost": 1, "tier": 1, "forms": ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"]},
	{"name": "Tribal shooters", "role": "Ranged", "cost": 2, "tier": 2, "copies": [2, 3], "forms": ["goblina1", "goblina3", "orcfemalea5"]},
	{"name": "Bats", "role": "Magic", "cost": 2, "tier": 2, "copies": [2, 3], "forms": ["batredm1", "batredm3", "batlightm7"]},
	{"name": "Toads", "role": "Magic", "cost": 2, "tier": 2, "forms": ["toadm2", "toadm6", "toadm6"]},
	{"name": "White tigers", "role": "Melee", "cost": 4, "tier": 3, "region": 1, "copies": [2, 3], "forms": ["tigerwhitef6", "tigerwhitef10", "tigerwhitef10"]},
	{"name": "Blue trolls", "role": "Melee", "cost": 7, "tier": 4, "region": 1, "copies": [2, 3], "forms": ["trollbluef9", "trollbluef12", "trollbluef12"]},
	{"name": "Stony harpies", "role": "Magic", "cost": 6, "tier": 4, "region": 1, "copies": [2, 3], "forms": ["succubbluem10", "succubbluem17", "succubbluem17"]},
	{"name": "Sand ogres", "role": "Melee", "cost": 10, "tier": 5, "region": 2, "copies": [2, 3], "forms": ["ogrehadaganf13", "ogrehadaganf17", "ogrehadaganf17"]},
	{"name": "Spiders", "role": "Melee", "cost": 3, "tier": 3, "region": 2, "copies": [3, 3], "forms": ["spiderf10", "spiderf15", "spiderf15"]},
	{"name": "Grey harpies", "role": "Magic", "cost": 7, "tier": 5, "region": 2, "copies": [2, 3], "forms": ["succubgreym13", "succubgreym17", "succubgreym20"]},
	# Append families: saved companies store these indices. Island does not gate recruitment.
	{"name": "Skeletons", "role": "Melee", "cost": 2, "tier": 2, "copies": [2, 3], "forms": ["skeletonf2", "skeletonf4", "skeletonwarriorf7"]},
	{"name": "Wisps", "role": "Magic", "health_multiplier": 2.4, "cost": 1, "tier": 1, "copies": [3, 3], "forms": ["willowispm1", "willowispm3", "willowispm5"]},
	{"name": "Red tigers", "role": "Melee", "cost": 1, "tier": 1, "copies": [3, 3], "forms": ["tigerredf2", "tigerredf4", "tigerredf6"]},
	{"name": "Banshees", "role": "Melee", "cost": 2, "tier": 2, "copies": [3, 3], "forms": ["bansheelightf2", "bansheelightf4", "bansheedarkf12"]},
	{"name": "Lizardfolk", "role": "Melee", "cost": 2, "tier": 2, "copies": [3, 3], "forms": ["dragonkinbeastmenf3", "dragonkingreenf7", "dragonkinjunf11"]},
	{"name": "Orc shamans", "role": "Magic", "cost": 3, "tier": 2, "copies": [3, 3], "forms": ["orcfemalem3", "orcfemalem5", "orcfemalem7"]},
	{"name": "Evil eyes", "role": "Magic", "cost": 3, "tier": 3, "copies": [3, 3], "forms": ["evileyesimplem5", "evileyegreenm13", "evileyegreenm17"]},
	{"name": "Armadillos", "role": "Melee", "cost": 3, "tier": 3, "copies": [3, 3], "forms": ["scrabbluef5", "scrabmotherpoisonedf6", "scrabmotherpoisonedf6"]},
	{"name": "Woodsfolk archers", "role": "Ranged", "cost": 3, "tier": 3, "copies": [2, 3], "forms": ["driadgreena7", "driadgreena9", "driadgreena11"]},
	{"name": "Hill ogres", "role": "Melee", "cost": 3, "tier": 3, "copies": [2, 3], "forms": ["ogregipatf5", "ogregipatf7", "ogregipatf9"]},
	{"name": "Red harpies", "role": "Magic", "cost": 4, "tier": 3, "copies": [2, 3], "forms": ["succubredm9", "succubredm10", "succubredm11"]},
	{"name": "Wormheads", "role": "Magic", "cost": 5, "tier": 4, "copies": [2, 3], "forms": ["octopuskaniam11", "octopuskaniam12", "octopuskaniam15"]},

]
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
	["The ridge hunters", "tigerwhitef6", "tigerwhitef6", "wolfwhitef6", "goblina3", "goblina3"],
	["The Ogre's court", "ogregipatf9", "wolfwhitef6", "batlightm7", "wolfwhitef6", "goblina3"],
	["The white pack", "tigerwhitef8", "tigerwhitef8", "batlightm8", "toadm6", "goblina3"],
	["The war council", "trollbluef9", "trollbluef9", "tigerwhitef6", "batlightm8"],
	["The ancient guard", "succubbluem10", "tigerwhitef8", "tigerwhitef8", "batlightm8", "wolfwhitef6"],
	["The last hunt", "trollbluef11", "tigerwhitef10", "batlightm10", "orcfemalem7", "batlightm8"],
	["At the gates", "spiderf10", "spiderf10", "trollbluef9", "succubbluem10", "wolfwhitef6"],
	["The lord of the ruins", "trollbluef12", "tigerwhitef10", "tigerwhitef10", "succubbluem11", "octopuskaniam12", "goblina3"],
	["Tracks in the snow", "ogrehadaganf13", "tigerwhitef10", "batlightm10", "trollbluef9", "batlightm8", "tigerwhitef8"],
	["The frozen pass", "spiderf13", "spiderf13", "succubbluem11", "batlightm10", "tigerwhitef10", "trollbluef9"],
	["Stone wings", "ogrehadaganf13", "spiderf14", "succubgreym13", "trollbluef9", "spiderf10", "batlightm10"],
	["The silk road", "spiderf13", "spiderf13", "tigerwhitef10", "batlightm10", "ogrehadaganf13", "succubgreym13"],
	["Desert raiders", "ogrehadaganf13", "spiderf13", "succubgreym13", "trollbluef12", "spiderf13", "succubgreym13"],
	["The winter council", "trollbluef12", "ogrehadaganf13", "succubbluem11", "octopushadaganm13", "spiderf14", "succubbluem17"],
	["Giants at dusk", "ogrehadaganf15", "ogrehadaganf15", "spiderf14", "succubgreym13", "spiderf15", "succubgreym15", "tigerwhitef10"],
	["The hollow voices", "bansheedarkf14", "bansheedarkf14", "spiderf15", "succubgreym15", "trollbluef12", "succubbluem17", "tigerwhitef10"],
	["The high priest", "ogrehadaganf17", "trollbluef12", "succubgreym15", "spiderf15", "octopushadaganm15", "ogrehadaganf15", "succubgreym17"],
	["Ash and ice", "ogrehadaganf15", "ogrehadaganf15", "bansheedarkf16", "succubgreym17", "spiderf15", "ogrehadaganf15", "batlightm10"],
	["The last watch", "ogrehadaganf17", "ogrehadaganf17", "spiderf15", "spiderf15", "succubgreym15", "octopushadaganm17", "succubbluem17", "tigerwhitef10"],
	["The siege of winter", "ogrehadaganf17", "ogrehadaganf17", "trollbluef12", "succubgreym17", "succubgreym17", "bansheedarkf16", "succubgreym20", "octopushadaganm17"],
]
const BOONS := {
	"merchant": ["Quartermaster", "Shop refreshes cost 1 gold instead of 2."],
	"reserve": ["Pack train", "Three more reserve slots."],
	"purse": ["War chest", "8 gold for your company."],
	"life": ["Second wind", "Recover one life, up to three."],
	"scout": ["Well connected", "Every new shop has a sixth recruit offer."],
	"companion": ["A new ally", "A spellcaster joins your reserves."],
	"experience": ["Field experience", "Gain 10 experience toward your next company level."],
	"supplies": ["Travel supplies", "Gain 6 gold for your next recruits."],
}


static func prototype(family: int, rank: int) -> String:
	if family < 0 or family >= FAMILIES.size() or rank < 0 or rank >= FAMILIES[family].forms.size(): return ""
	return FAMILIES[family].forms[rank]


static func evolution_copies(family: int, rank: int) -> int:
	if prototype(family, rank + 1).is_empty(): return 0
	return int(FAMILIES[family].get("copies", [3, 3])[rank])


## A three-star elite keeps the strongest original model when that creature
## has no higher authored form. These multipliers never patch the campaign DB.
static func is_elite(family: int, rank: int) -> bool:
	return rank == 2 and not prototype(family, rank).is_empty() and prototype(family, rank) == prototype(family, rank - 1)


static func elite_stats(stats: Dictionary) -> void:
	stats.dmg_min *= 1.5
	stats.dmg_max *= 1.5
	stats.to_hit *= 1.2
	stats.actions = float(stats.get("actions", 15.0)) * 1.15
	for i in stats.armor.size(): stats.armor[i] *= 1.2


## Lightweight native wisps need enough health to serve as an opening caster.
## Only recruited Trials actors receive this tuning; campaign data is unchanged.
static func recruit_health(family: int, health: float) -> float:
	if family < 0 or family >= FAMILIES.size(): return health
	return ceilf(health * float(FAMILIES[family].get("health_multiplier", 1.0)))


static func elite_health(health: float) -> float:
	return ceilf(health * 1.75)


static func title(id: String) -> String:
	return RemakeText.t(GameUnit.unit_title(id))


static func available() -> bool:
	var map := EIResArchive.open_path(GameData.root.path_join("maps/zone11.mpr"))
	if map == null or map.read("zone11.mp").size() < 38: return false
	for family: Dictionary in FAMILIES:
		for id: String in family.forms:
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
		ids.append("ogrehadaganf17" if wave >= 25 else "trollbluef12" if wave >= 19 else "tigerwhitef10" if wave > 12 else "orcmalef5" if wave > 6 else "goblinf2")
	if challenge > 1 and wave >= 6:
		ids.append("succubgreym17" if wave >= 25 else "succubbluem17" if wave >= 19 else "batlightm10" if wave > 12 else "toadm6" if wave > 9 else "goblina3")
	# The larger shop pool makes finished upgrades less frequent. Standard
	# uses the authored late waves; Veteran retains its extra front line,
	# while Champion adds a caster instead of stacking both support groups.
	if challenge < 2 and wave >= 6 and (challenge == 1 or wave < 19):
		ids.append("ogrehadaganf15" if wave >= 25 else "trollbluef12" if wave >= 19 else "tigerwhitef10" if wave >= 15 else "wolfwhitef6" if wave >= 11 else "orcmalef5" if wave >= 9 else "goblinf2")
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


static func level_for_xp(xp: int) -> int:
	var level := 3
	while level < MAX_ARMY and xp >= int(LEVEL_XP[level + 1]): level += 1
	return level


static func recruit_pool(level: int) -> Array[int]:
	var pool: Array[int] = []
	var odds: Array = SHOP_ODDS[clampi(level, 3, MAX_ARMY)]
	for family in FAMILIES.size():
		if int(odds[int(FAMILIES[family].tier) - 1]) > 0: pool.append(family)
	return pool


static func preparation_seconds(challenge: int) -> float:
	return [60.0, 45.0, 30.0][clampi(challenge, 0, 2)]


static func tier_price_label(tier: int) -> String:
	var prices: Array[int] = []
	for family: Dictionary in FAMILIES:
		if int(family.tier) == tier: prices.append(int(family.cost))
	prices.sort()
	return str(prices[0]) if prices[0] == prices[-1] else "%d-%d" % [prices[0], prices[-1]]
