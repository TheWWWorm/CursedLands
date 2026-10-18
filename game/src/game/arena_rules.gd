class_name ArenaRules
extends RefCounted
## Content shared by the playable expedition and its balance simulations.
## Original prototypes remain immutable. Budgets apply only to Trials actors.

const VERSION := 11
const PREPARATION_SECONDS := 60.0
const BATTLE_SECONDS := 90.0
const WAVE_COUNT := 30
const OPENING_GOLD := 10
const MIN_RECRUIT_COST := 1
const BASE_INCOME := 5
const WIN_INCOME := 1
const INTEREST_CAP := 5
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
const ACTIVE_FAMILIES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]
# Each original combat archetype belongs to exactly one evolution chain.
const FAMILIES := [
	{"name":"Ironhide","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["boarredf1","trollbluef9","golemverticalf20"],"archetypes":["boar","troll","walking-golem"]},
	{"name":"Warband","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["goblinf1","orcmalef5","cyclopsa20"],"archetypes":["goblin-spearman","orc-warrior","cyclops"]},
	{"name":"Wild hunt","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["wolfgreyf1","tigerwhitef10","unicornwhitem15"],"archetypes":["wolf","tiger","unicorn"]},
	{"name":"Sureshots","role":"Ranged","cost":1,"tier":1,"copies":[3,3],"forms":["goblina1","orcfemalea5","human mercenary kania archer"],"archetypes":["goblin-slinger","orc-archer","mairana"]},
	{"name":"Skyfire","role":"Magic","cost":1,"tier":1,"copies":[3,3],"forms":["batredm1","succubredm9","dragonbrownm16"],"archetypes":["fire-bat","fire-harpy","fire-dragon"]},
	{"name":"Marsh brood","role":"Magic","cost":2,"tier":2,"copies":[3,3],"forms":["toadm2","scrabmotherpoisonedf6","elementalearthf8"],"archetypes":["toad","armadillo","earth-elemental"]},
	{"name":"Moonwatch","role":"Magic","cost":2,"tier":2,"copies":[3,3],"forms":["willowispm1","bansheedarkm12","dragonbluem14"],"archetypes":["wisp","storm-banshee","storm-dragon"]},
	{"name":"Frostbound","role":"Ranged","cost":3,"tier":3,"copies":[3,3],"forms":["driadsnowa7","driadsnowqm9","elementalicef15"],"archetypes":["white-clan-archer","white-clan-jailer","ice-elemental"]},
	{"name":"Venom wings","role":"Magic","cost":3,"tier":3,"copies":[3,3],"forms":["batdarkm12","succubgreym13","dragongreenm12"],"archetypes":["storm-foxbat","acid-harpy","acid-dragon"]},
	{"name":"Sand stalkers","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["hyenaf6","ogrehadaganf17","golemhorizontalf20"],"archetypes":["hyena","sand-ogre","crawling-golem"]},
	{"name":"Night swarm","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["ratsmallf1","spiderf10","evileyeredm16"],"archetypes":["rat","spider","red-evileye"]},
	{"name":"Thunder court","role":"Magic","cost":2,"tier":2,"copies":[3,3],"forms":["orcfemalem3","succubbluem10","octopushadaganm17"],"archetypes":["orc-shaman","storm-harpy","wormhead"]},
	{"name":"Restless dead","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["skeletonf2","bansheelightf4","shadowm20"],"archetypes":["skeleton","melee-banshee","shadow"]},
	{"name":"Green covenant","role":"Ranged","cost":3,"tier":3,"copies":[3,3],"forms":["driadgreena7","driadgreenm7","human kania npc sorceress m11"],"archetypes":["green-clan-archer","green-clan-mage","diera"]},
	{"name":"Huntmasters","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["doggreyf6","human kania hunter f7","human mercenary bodyguard"],"archetypes":["dog","spear-hunter","rint"]},
	{"name":"Oathkeepers","role":"Melee","cost":3,"tier":3,"copies":[3,3],"forms":["human gipath warlord f2","human kania sorceress bodyguard f9","human mercenary kania paladin"],"archetypes":["village-fighter","sorceress-bodyguard","brissen"]},
	{"name":"Ravagers","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["dragonkinbeastmenf3","ogregipatf9","trollblackslowf16"],"archetypes":["lizardman","hill-ogre","slow-troll"]},
	{"name":"Outriders","role":"Ranged","cost":2,"tier":2,"copies":[3,3],"forms":["human gipath brigand a1","human kania ranger f9","human mercenary hadagan rogue"],"archetypes":["gipath-bow-brigand","ranger","sahilia"]},
	{"name":"Elemental pact","role":"Magic","cost":5,"tier":5,"copies":[3,3],"forms":["human hadagan guards m14","evileyegreenm17","ancientcursem25"],"archetypes":["battle-mage","green-evileye","curse"]},
	{"name":"Rebellion","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["human gipath brigand f1","human kania gang f9","human mercenary hadagan warrior"],"archetypes":["gipath-spear-brigand","kania-mace-brigand","harad"]},
	{"name":"Sentinels","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["human kania police f8","human hadagan guards a14","human kania npc captain f14"],"archetypes":["kania-sword-guard","imperial-crossbow-guard","ringlin"]},
	{"name":"Revenants","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["zombiemalef10","undeadf17","elementallavaf12"],"archetypes":["zombie","ghoul","lava-elemental"]},
	{"name":"Storm disciples","role":"Magic","cost":1,"tier":1,"copies":[3,3],"forms":["human hadagan peasants a1","human gipath npc wife m3","human mercenary hadagan thief"],"archetypes":["peon-caster","brigand-chieftess","fairakh"]},
	{"name":"Pathfinders","role":"Ranged","cost":3,"tier":3,"copies":[3,3],"forms":["human kania citizen a7","driaddarka7","human mercenary thief"],"archetypes":["commoner-archer","black-clan-archer","naya"]},
	{"name":"Arcane pilgrims","role":"Magic","cost":5,"tier":5,"copies":[3,3],"forms":["human mercenary shaivar","driaddarkm9","human hadagan necromancer m17"],"archetypes":["shaivar","black-clan-mage","necromancer"]},
	{"name":"Mercenaries","role":"Melee","cost":3,"tier":3,"copies":[3,3],"forms":["human gipath brigand deputy f1","human kania police karansul f8","human mercenary warrior"],"archetypes":["brigand-hammer-deputy","hired-swordsman","rowdy"]},
	{"name":"Wardens","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["human kania woodcutter f8","human kania police f10","human hadagan overseerba f14"],"archetypes":["woodcutter","guard-spearman","axe-overseer"]},
	{"name":"Iron company","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["human kania goldminer f7","human hadagan students f10","human gipath npc expeditor f15"],"archetypes":["goldminer","saber-recruit","expedition-leader"]},
	{"name":"Outlaws","role":"Melee","cost":5,"tier":5,"copies":[3,3],"forms":["human kania gang spear f10","human kania gang f11","human mercenary kania thief"],"archetypes":["deserter","killer","rinas"]},
	{"name":"Taskmasters","role":"Ranged","cost":5,"tier":5,"copies":[3,3],"forms":["human kania police a8","human hadagan overseer f14","human hadagan npc lieutenant f15"],"archetypes":["kania-guard-archer","club-overseer","kardaur"]},
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


## All Trials recruits use a price/star budget. Native bodies, attack cadence,
## reach, damage types and resistance ratios retain their identities; campaign
## levels cannot silently turn a one-star shop offer into an endgame boss.
const HEALTH_BUDGET := [35.0, 48.0, 66.0, 90.0, 120.0]
const DAMAGE_BUDGET := [11.0, 14.0, 17.5, 21.0, 25.0]
const LEGACY_FORMS := {
	0: ["boarredf1", "boarredf3", "boardarkf6"],
	1: ["goblinf1", "orcmalef3", "orcmalef5"],
	2: ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"],
	3: ["goblina1", "goblina3", "orcfemalea5"],
	4: ["batredm1", "batredm3", "batlightm7"],
	5: ["toadm2", "toadm6", "toadm6"],
	6: ["tigerwhitef6", "tigerwhitef10", "tigerwhitef10"],
	7: ["trollbluef9", "trollbluef12", "trollbluef12"],
	8: ["succubbluem10", "succubbluem17", "succubbluem17"],
	9: ["ogrehadaganf13", "ogrehadaganf17", "ogrehadaganf17"],
	10: ["spiderf10", "spiderf15", "spiderf15"],
	11: ["succubgreym13", "succubgreym17", "succubgreym20"],
	12: ["skeletonf2", "skeletonf4", "skeletonwarriorf7"],
	13: ["willowispm1", "willowispm3", "willowispm5"],
	14: ["tigerredf2", "tigerredf4", "tigerredf6"],
	15: ["bansheelightf2", "bansheelightf4", "bansheedarkf12"],
	16: ["dragonkinbeastmenf3", "dragonkingreenf7", "dragonkinjunf11"],
	17: ["orcfemalem3", "orcfemalem5", "orcfemalem7"],
	18: ["evileyesimplem5", "evileyegreenm13", "evileyegreenm17"],
	19: ["scrabbluef5", "scrabmotherpoisonedf6", "scrabmotherpoisonedf6"],
	20: ["driadgreena7", "driadgreena9", "driadgreena11"],
	21: ["ogregipatf5", "ogregipatf7", "ogregipatf9"],
	22: ["succubredm9", "succubredm10", "succubredm11"],
	23: ["octopuskaniam11", "octopuskaniam12", "octopuskaniam15"],
	24: ["human gipath brigand f1", "human gipath brigand f3", "human kania gang f8"],
	25: ["human gipath brigand a1", "human gipath brigand a3", "human kania citizen a7"],
	26: ["human hadagan students m10", "human hadagan guards m14", "human hadagan guards m17"],
	27: ["zombiemalef10", "zombiefemalef14", "zombiemalef16"],
	28: ["human kania police f10", "human hadagan guards f14", "human hadagan guards f17"],
	29: ["elementalicef9", "elementalicef11", "elementalicef15"],
	30: ["human hadagan peasants a1", "human gipath npc wife m3", "driaddarkm9"],
	31: ["doggreyf6", "doggreyf8", "dogredf14"],
	32: ["driadgreenm7", "driaddarkm9", "unicornwhitem15"],
	33: ["undeadf13", "undeadf15", "undeadf17"],
	34: ["evileyeredm12", "evileyeredm14", "evileyeredm16"],
	35: ["dragongreenm12", "dragonbluem14", "dragonbrownm16"],
	36: ["cyclopsa16", "cyclopsa18", "cyclopsa20"],
	37: ["shadowm13", "shadowm17", "shadowm20"],
	38: ["human hadagan guards a14", "human hadagan guards a17", "human hadagan guards a20"],
	39: ["bansheedarkm12", "bansheedarkm14", "bansheedarkm16"],
}
const LEGACY_FAMILIES := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 2, 7: 0, 8: 11, 9: 9, 10: 10, 11: 8, 12: 12, 13: 6, 14: 2, 15: 12, 16: 16, 17: 11, 18: 18, 19: 5, 20: 13, 21: 16, 22: 4, 23: 11, 24: 19, 25: 17, 26: 18, 27: 21, 28: 20, 29: 7, 30: 22, 31: 14, 32: 24, 33: 21, 34: 10, 35: 8, 36: 1, 37: 12, 38: 20, 39: 6}

static func star_health(_family: int, rank: int) -> float:
	return [1.0, 2.2, 5.0][clampi(rank,0,2)]

static func star_damage(_family: int, rank: int) -> float:
	return [1.0, 1.6, 2.8][clampi(rank,0,2)]

static func recruit_role(family: int, rank: int) -> String:
	var proto := GameData.db.find("monster_prototypes",prototype(family,rank))
	if not Array(proto.get("spells",[])).is_empty(): return "Magic"
	if float(proto.get("attack_range",0.0))>0.0: return "Ranged"
	var weapon := Items.info(str(proto.get("weapon","")))
	return "Ranged" if int(weapon.get("row",{}).get("type_id",-1)) in [5,6] else "Melee"

static func recruit_health(family: int, health: float, rank := 0) -> float:
	if family < 0 or family >= FAMILIES.size(): return health
	var role := recruit_role(family,rank)
	var body := 0.78 if role == "Magic" else 0.9 if role == "Ranged" else 1.0
	return ceilf(HEALTH_BUDGET[int(FAMILIES[family].tier)-1] * body * star_health(family,rank))

static func recruit_stats(family: int, rank: int, stats: Dictionary) -> void:
	if family < 0 or family >= FAMILIES.size(): return
	var tier := int(FAMILIES[family].tier)
	var mean: float = DAMAGE_BUDGET[tier-1] * star_damage(family,rank)
	var preview := stats.has("min")
	stats["min" if preview else "dmg_min"] = mean * 0.73
	stats["max" if preview else "dmg_max"] = mean * 1.27
	stats["attack" if preview else "to_hit"] = 28.0 + tier * 4.0 + rank * 12.0
	stats["defense" if preview else "parry"] = 18.0 + tier * 3.0 + rank * 8.0
	var armor: PackedFloat32Array = stats.armor
	var native_general := maxf(1.0,armor[6])
	for type in armor.size(): armor[type] = armor[type] / native_general * (5.0 + tier * 2.0) * (1.0 + rank * 0.2)
	stats.armor = armor
	stats.actions = float(stats.get("actions",15.0)) * (1.0 + rank * 0.08)
	stats["trials_budget"] = true
	if recruit_role(family,rank)=="Ranged": stats["defense" if preview else "parry"] = 0.0

## Campaign skill ratings otherwise overwhelm the bounded recruit economy.
## Keep authored creep bodies, damage, spells and weaknesses; only cap their
## accuracy, avoidance and exceptional boss armor to the encounter's wave.
static func creep_stats(wave: int, stats: Dictionary) -> void:
	stats.to_hit=minf(float(stats.to_hit),30.0+wave*1.4)
	stats.parry=minf(float(stats.parry),20.0+wave)
	var armor: PackedFloat32Array=stats.armor
	var general := maxf(1.0,armor[6])
	var factor := minf(1.0,(10.0+wave)/general)
	for type in armor.size(): armor[type]*=factor
	stats.armor=armor
	stats.trials_budget=true

## Use real spell-builder runes, so inspected spells, AI and damage share one
## definition. Area magic spends part of its budget on hitting several enemies.
static func recruit_prototype(family: int, rank: int, proto: Dictionary) -> Dictionary:
	if family < 0 or family >= FAMILIES.size(): return proto
	var tuned := proto.duplicate(true)
	var spells: Array = proto.get("spells",[]).duplicate()
	var desired := (14.0 + (int(FAMILIES[family].tier)-1) * 5.5) * star_damage(family,rank)
	for i in spells.size():
		var parsed := Spells.parse(spells[i])
		if not Spells.DAMAGE_SCHOOLS.has(parsed.code): continue
		var mods := Spells.mods_of(spells[i])
		var retained := PackedStringArray()
		for mod: String in mods:
			if not mod.begins_with("e"): retained.append(mod)
		var area := 1.45 if parsed.code in ["firewall","litnwall","acid_fog","fireball"] else 1.0
		var base := float(parsed.proto.get("effect",1.0))
		var step := maxf(0.1,base * float(Spells.mod_row("e1").get("value",0.5)))
		var count := maxi(0,roundi((desired/area-base)/step))
		for rune in count: retained.append("e1")
		spells[i] = "%s{%s}" % [parsed.code,";".join(retained)]
	tuned.spells = spells
	tuned["_spell_cache_key"] = "%s:trials:%d:%d" % [proto.name,family,rank]
	return tuned


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


static func companion(_wave: int) -> String:
	return prototype(11,1)


static func level_for_xp(xp: int) -> int:
	var level := 3
	while level < MAX_ARMY and xp >= int(LEVEL_XP[level + 1]): level += 1
	return level


static func recruit_pool(level: int) -> Array[int]:
	var pool: Array[int] = []
	var odds: Array = SHOP_ODDS[clampi(level, 3, MAX_ARMY)]
	for family in ACTIVE_FAMILIES:
		if int(odds[int(FAMILIES[family].tier) - 1]) > 0: pool.append(family)
	return pool


static func preparation_seconds(challenge: int) -> float:
	return [60.0, 45.0, 30.0][clampi(challenge, 0, 2)]


static func tier_price_label(tier: int) -> String:
	var prices: Array[int] = []
	for family: Dictionary in FAMILIES:
		if not family.get("retired",false) and int(family.tier) == tier: prices.append(int(family.cost))
	prices.sort()
	return str(prices[0]) if prices[0] == prices[-1] else "%d-%d" % [prices[0], prices[-1]]
