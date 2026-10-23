class_name ArenaRules
extends RefCounted
## Content shared by the playable expedition and its balance simulations.
## Original prototypes remain immutable. Budgets apply only to Trials actors.

const VERSION := 13
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
const MAX_ARMY := 9
# Cumulative XP from the opening level 3. Increasing costs make rolling versus
# leveling a continuing decision instead of a cheap slot on every third wave.
const LEVEL_XP := [0, 0, 0, 0, 6, 18, 36, 55, 80, 110]
const MAX_TRAINING: int = LEVEL_XP[MAX_ARMY]
# Older schema-11 saves may have paid toward the previous level-nine threshold.
# Accept their accumulated training without allowing further purchases at nine.
const MAX_SAVED_TRAINING := 126
const SHOP_ODDS := {
	3: [55, 45, 0, 0, 0], 4: [55, 45, 0, 0, 0],
	5: [40, 40, 20, 0, 0], 6: [30, 35, 27, 8, 0],
	7: [22, 28, 28, 20, 2], 8: [15, 20, 25, 30, 10],
	9: [10, 15, 25, 35, 15],
}
const COMPANIONS := ["orcfemalem3", "orcfemalem5", "octopuskaniam12", "octopushadaganm15"]
const ACTIVE_FAMILIES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]
# A species occupies one price tier. All ranks retain its silhouette and role.
const FAMILIES := [
	{"name":"Boars","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["boarredf1","boarredf2","boarredf3"],"health":1.25,"damage":0.85,"armor":1.2,"hook":"A sturdy frontline with a heavy hide."},
	{"name":"Wolves","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["wolfgreyf1","wolfgreyf2","wolfgreyf3"],"health":1.03,"damage":1.2,"armor":0.8,"hook":"A fast melee hunter with strong sustained damage."},
	{"name":"Rats","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["ratsmallf1","ratgiantf9","ratgiantf11"],"health":1.0,"damage":1.32,"armor":0.6,"hook":"A fragile attacker that rewards a protected approach."},
	{"name":"Bats","role":"Magic","cost":1,"tier":1,"copies":[3,3],"forms":["batredm1","batredm3","batredm5"],"health":0.9,"damage":1.05,"armor":0.7,"hook":"A fragile ranged source of fire damage."},
	{"name":"Goblins","role":"Ranged","cost":1,"tier":1,"copies":[3,3],"forms":["goblina1","goblina2","goblina3"],"health":1,"damage":0.94,"armor":1,"hook":"A sling attacker that needs a frontline."},
	{"name":"Toads","role":"Magic","cost":1,"tier":1,"copies":[3,3],"forms":["toadm2","toadm4","toadm6"],"health":1.12,"damage":0.92,"armor":0.85,"hook":"Acid damage with natural acid resistance."},
	{"name":"Skeletons","role":"Melee","cost":1,"tier":1,"copies":[3,3],"forms":["skeletonf2","skeletonf3","skeletonwarriorf7"],"health":1.05,"damage":1.05,"armor":1.1,"hook":"A defensive fighter resistant to lightning."},
	{"name":"Tigers","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["tigerredf2","tigerredf4","tigerredf6"],"health":0.95,"damage":1.15,"armor":0.8,"hook":"A slashing hunter that punishes exposed targets."},
	{"name":"Spiders","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["spiderf10","spiderf13","spiderf15"],"health":1.03,"damage":1.12,"armor":1,"hook":"A quick attacker resistant to fire and acid."},
	{"name":"Armadillos","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["scrabbluef5","scrabgreyf5","scrabmotherpoisonedf6"],"health":1.2,"damage":0.9,"armor":1.4,"hook":"An armored frontline with modest damage."},
	{"name":"Lizardmen","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["dragonkinbeastmenf3","dragonkingreenf7","dragonkinjunf11"],"health":1,"damage":1.05,"armor":1,"hook":"A reliable tribal fighter."},
	{"name":"Woodsfolk","role":"Ranged","cost":2,"tier":2,"copies":[3,3],"forms":["driadgreena7","driadgreena9","driadgreena11"],"health":0.9,"damage":1.1,"armor":0.75,"hook":"A piercing ranged hunter that needs protection."},
	{"name":"Zombies","role":"Melee","cost":2,"tier":2,"copies":[3,3],"forms":["zombiemalef10","zombiemalef12","zombiemalef16"],"health":1.12,"damage":1.0,"armor":1.1,"hook":"A durable spirit resistant to crushing blows."},
	{"name":"Orc shamans","role":"Magic","cost":3,"tier":3,"copies":[3,3],"forms":["orcfemalem3","orcfemalem5","orcfemalem7"],"health":1.05,"damage":0.9,"armor":0.9,"hook":"Fire magic and strength for nearby allies."},
	{"name":"Trolls","role":"Melee","cost":3,"tier":3,"copies":[3,3],"forms":["trollbluef9","trollbluef11","trollbluef12"],"health":1.15,"damage":1.0,"armor":1,"hook":"A regenerating frontline resistant to piercing."},
	{"name":"Ogres","role":"Melee","cost":3,"tier":3,"copies":[3,3],"forms":["ogregipatf5","ogregipatf7","ogregipatf9"],"health":1.05,"damage":1.05,"armor":1,"hook":"Heavy crushing blows and natural recovery."},
	{"name":"Harpies","role":"Magic","cost":3,"tier":3,"copies":[3,3],"forms":["succubredm9","succubredm10","succubredm11"],"health":0.9,"damage":0.96,"armor":0.8,"hook":"Fire walls punish enemies that gather together."},
	{"name":"Hyenas","role":"Melee","cost":3,"tier":3,"copies":[3,3],"forms":["hyenaf6","hyenaf6","hyenaf6"],"health":1.08,"damage":1.38,"armor":0.75,"hook":"An aggressive hunter with little protection."},
	{"name":"Evileyes","role":"Magic","cost":4,"tier":4,"copies":[3,3],"forms":["evileyesimplem5","evileyesimplem6","evileyesimplem7"],"health":0.9,"damage":1.08,"armor":0.8,"hook":"Split fire bolts pressure several enemies."},
	{"name":"Banshees","role":"Magic","cost":4,"tier":4,"copies":[3,3],"forms":["bansheedarkm12","bansheedarkm14","bansheedarkm16"],"health":1.1,"damage":1.18,"armor":0.85,"hook":"Lightning damage and lightning resistance."},
	{"name":"Unicorns","role":"Magic","cost":4,"tier":4,"copies":[3,3],"forms":["unicornwhitem15","unicornwhitem15","unicornwhitem15"],"health":1.0,"damage":0.95,"armor":0.8,"hook":"Lightning and healing support a protected team."},
	{"name":"Wisps","role":"Magic","cost":4,"tier":4,"copies":[3,3],"forms":["willowispm1","willowispm3","willowispm5"],"health":0.8,"damage":1.1,"armor":0.6,"hook":"A fragile spirit with powerful fire bolts."},
	{"name":"Elementals","role":"Melee","cost":4,"tier":4,"copies":[3,3],"forms":["elementalicef9","elementalicef11","elementalicef15"],"health":1.2,"damage":0.85,"armor":1.2,"hook":"A durable spirit with steady crushing damage."},
	{"name":"Dragons","role":"Magic","cost":5,"tier":5,"copies":[3,3],"forms":["dragonbrownm16","dragonbrownm16","dragonbrownm16"],"health":1.08,"damage":0.96,"armor":1,"hook":"Fireballs reward protecting a costly caster."},
	{"name":"Golems","role":"Melee","cost":5,"tier":5,"copies":[3,3],"forms":["golemverticalf20","golemverticalf20","golemverticalf20"],"health":1.3,"damage":1.1,"armor":1.45,"hook":"A heavily armored anchor with limited damage."},
	{"name":"Horrors","role":"Magic","cost":5,"tier":5,"copies":[3,3],"forms":["ancientcursem25","ancientcursem25","ancientcursem25"],"health":1.05,"damage":1,"armor":0.75,"hook":"A powerful lightning strike with a long windup."},
	{"name":"Wormheads","role":"Magic","cost":5,"tier":5,"copies":[3,3],"forms":["octopuskaniam11","octopuskaniam12","octopuskaniam15"],"health":1.0,"damage":1.02,"armor":0.8,"hook":"Area lightning and haste support the company."},
	{"name":"Cyclopes","role":"Ranged","cost":5,"tier":5,"copies":[3,3],"forms":["cyclopsa16","cyclopsa18","cyclopsa20"],"health":1.25,"damage":1.15,"armor":1,"hook":"Heavy ranged crushing damage with slow attacks."},
]
# Exact schema-12 contents remain available for validating and migrating saves.
const EXPERIMENT_FORMS := [["boarredf1","trollbluef9","golemverticalf20"],["goblinf1","orcmalef5","cyclopsa20"],["wolfgreyf1","tigerwhitef10","unicornwhitem15"],["human hadagan students a10","orcfemalea5","human mercenary kania archer"],["batredm1","succubredm9","dragonbrownm16"],["toadm2","scrabmotherpoisonedf6","elementalearthf8"],["willowispm1","bansheedarkm12","dragonbluem14"],["driadsnowa7","human hadagan students m10","elementalicef15"],["evileyesimplem5","succubgreym13","dragongreenm12"],["hyenaf6","ogrehadaganf17","golemhorizontalf20"],["ratsmallf1","spiderf10","evileyeredm16"],["orcfemalem3","succubbluem10","octopushadaganm17"],["skeletonf2","bansheelightf4","shadowm20"],["driadgreena7","human hadagan citizens a1","human kania npc sorceress m11"],["doggreyf6","human kania hunter f7","human mercenary bodyguard"],["human gipath warlord f2","human kania sorceress bodyguard f9","human mercenary kania paladin"],["dragonkinbeastmenf3","ogregipatf9","trollblackslowf16"],["human gipath brigand a1","human kania ranger f9","human mercenary hadagan rogue"],["human hadagan guards m14","evileyegreenm17","ancientcursem25"],["human gipath brigand f1","human kania gang f9","human mercenary hadagan warrior"],["human kania police f8","human hadagan guards a14","human kania npc captain f14"],["zombiemalef10","undeadf17","elementallavaf12"],["human hadagan peasants a1","human gipath npc wife m3","human mercenary hadagan thief"],["human kania citizen a7","driaddarka7","human mercenary thief"],["human mercenary shaivar","driaddarkm9","human hadagan necromancer m17"],["human gipath brigand deputy f1","human kania police karansul f8","human mercenary warrior"],["human kania woodcutter f8","human kania police f10","human hadagan overseerba f14"],["human kania goldminer f7","human hadagan students f10","human gipath npc expeditor f15"],["human kania gang spear f10","human kania gang f11","human mercenary kania thief"],["human kania police a8","human hadagan overseer f14","human hadagan npc lieutenant f15"]]
# Schema 11 used these visually ambiguous forms. Keep saves' family, rank,
# investment and placement when replacing a recruit, never silently reject them.
const PREVIOUS_FORMS := {
	3: ["goblina1", "orcfemalea5", "human mercenary kania archer"],
	7: ["driadsnowa7", "driadsnowqm9", "elementalicef15"],
	8: ["batdarkm12", "succubgreym13", "dragongreenm12"],
	13: ["driadgreena7", "driadgreenm7", "human kania npc sorceress m11"],
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
const HEALTH_BUDGET := [44.0, 60.0, 78.0, 99.0, 122.0]
const DAMAGE_BUDGET := [13.0, 16.0, 20.0, 24.0, 29.0]
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

static func star_health(family: int, rank: int) -> float:
	var scale: float = [1.0, 2.1, 5.0][clampi(rank,0,2)]
	if rank == 2:
		if family == 6: scale *= 1.08
		elif family == 22: scale *= 0.92
	return scale

static func star_damage(family: int, rank: int) -> float:
	var scale: float = [1.0, 1.75, 4.0][clampi(rank,0,2)]
	if rank == 2:
		if family == 27: scale *= 1.12
		elif family == 23: scale *= 0.92
	return scale

static func recruit_role(family: int, rank: int) -> String:
	var proto := GameData.db.find("monster_prototypes",prototype(family,rank))
	# Scouting/invisibility do not turn a dagger fighter into a fragile caster.
	for spell: String in proto.get("spells",[]):
		if Spells.DAMAGE_SCHOOLS.has(Spells.parse(spell).code): return "Magic"
	if float(proto.get("attack_range",0.0))>0.0: return "Ranged"
	return "Ranged" if bow_user(proto) else "Melee"

static func bow_user(proto: Dictionary) -> bool:
	var type:=int(proto.get("weapon_type_id",-1))
	if type==8:
		type=int(Items.info(str(proto.get("weapon",""))).get("row",{}).get("type_id",-1))
	return type in [5,6]

static func recruit_health(family: int, health: float, rank := 0) -> float:
	if family < 0 or family >= FAMILIES.size(): return health
	var role := recruit_role(family,rank)
	var bow:=bow_user(GameData.db.find("monster_prototypes",prototype(family,rank)))
	# Bow casters cannot parry, including natural blowpipes. They retain the
	# ranged health budget instead of paying for a caster's missing defense.
	var body := 0.9 if bow or role=="Ranged" else 0.78 if role=="Magic" else 1.0
	return ceilf(HEALTH_BUDGET[int(FAMILIES[family].tier)-1] * body * float(FAMILIES[family].health) * star_health(family,rank))

static func recruit_stats(family: int, rank: int, stats: Dictionary) -> void:
	if family < 0 or family >= FAMILIES.size(): return
	var tier := int(FAMILIES[family].tier)
	var proto := GameData.db.find("monster_prototypes",prototype(family,rank))
	var race := GameData.db.find("race_models",str(proto.get("base_race","")))
	var role := recruit_role(family,rank)
	var mean: float = DAMAGE_BUDGET[tier-1] * star_damage(family,rank) * float(FAMILIES[family].damage)
	# Native swings/shots range from 49 to 130 ticks. Price damage per cadence,
	# keeping slow heavy blows and quick light attacks instead of equal hits.
	if role != "Magic":
		mean *= clampf(float(proto.get("tuning_actions",55.0))/55.0,0.85,2.5)
		if role == "Ranged": mean *= 1.3
		else: mean *= 1.15
	var preview := stats.has("min")
	stats["min" if preview else "dmg_min"] = mean * 0.73
	stats["max" if preview else "dmg_max"] = mean * 1.27
	stats["attack" if preview else "to_hit"] = 28.0 + tier * 4.0 + rank * 8.0 + (14.0 if role == "Ranged" else 6.0 if role == "Melee" else 0.0)
	stats["defense" if preview else "parry"] = 18.0 + tier * 3.0 + rank * 4.0
	var armor: PackedFloat32Array = stats.armor
	var native_general := maxf(1.0,armor[6])
	# Bound native resistance ratios: soft counters, not campaign immunities.
	# A final-rank frontline still needs armor to matter against larger hits.
	# Casters/ranged bodies retain their lighter promotion curve; the native
	# per-type 80% cap continues to prevent invulnerable tanks.
	var armor_growth := 1.65 if rank==2 and role=="Melee" else 1.0+rank*0.15
	for type in armor.size():
		armor[type] = clampf(armor[type] / native_general, 0.6, 1.8) * (3.0 + tier * 2.0) * float(FAMILIES[family].armor) * armor_growth
	stats.armor = armor
	stats.actions = float(stats.get("actions",15.0)) * float(recruit_prototype(family,rank,proto).get("_trials_cast_rate",1.0))
	# Campaign bosses recover as much as 10% HP every 15 ticks. Their native
	# advantage remains, within the damage budget of a ninety-second round.
	stats.health_regen = minf(float(race.get("health_regen",0.0)),0.02)*0.25
	stats["trials_budget"] = true
	if role=="Ranged" or bow_user(proto): stats["defense" if preview else "parry"] = 0.0

static func spell_target_budget(parsed: Dictionary) -> float:
	var area := 1.45 if float(parsed.get("area",0.0))>0.0 else 1.0
	# Native effect is the TOTAL over the duration, including scaled armor
	# (Spells._spell_damage), not the damage of each four-tick pulse. A moving
	# enemy is unlikely to remain inside for the complete lifetime.
	if parsed.code in ["firewall", "litnwall", "acid_fog", "campfire"]: area *= 0.65
	# Extra-target runes launch separate effects, including separate fireballs.
	return area * (1.0 + maxi(0,int(parsed.get("targets",1))-1)*0.6)

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
	# Preserve the species' action set at every star, even where a native
	# age variant added a different spell. Only flat spell power scales.
	var base_proto := GameData.db.find("monster_prototypes",prototype(family,0))
	var spells: Array = base_proto.get("spells",[]).duplicate()
	if family == 20: spells.append("healing")
	var desired := (16.0 + (int(FAMILIES[family].tier)-1) * 6.0) * star_damage(family,rank) * float(FAMILIES[family].damage)
	var cast_rate := 1.0
	for i in spells.size():
		var parsed := Spells.parse(spells[i])
		if parsed.code == "strength":
			spells[i] = "strength{e0;d2}" # +15% damage / +25% health, not +30% / +50%.
			continue
		if parsed.code == "speed" and family == 26:
			spells[i] = "speed{e1;e1;d2;ff;t2}" # +3 actions to three allies.
			continue
		if not Spells.DAMAGE_SCHOOLS.has(parsed.code) and parsed.code!="healing": continue
		var mods := Spells.mods_of(spells[i])
		var retained := PackedStringArray()
		for mod: String in mods:
			if not mod.begins_with("e"): retained.append(mod)
		var area := spell_target_budget(parsed)
		if parsed.code=="healing": area/=0.5
		var base := float(parsed.proto.get("effect",1.0))
		var half_step := maxf(0.1, -base * float(Spells.mod_row("e0").get("value", -0.5)))
		var target := desired / area
		if Spells.DAMAGE_SCHOOLS.has(parsed.code) and area > 1.0:
			# Every target/contact pays flat armor separately. Budget the split
			# after representative absorption, not as if armor were a percentage.
			var expected_armor := (3.0 + int(FAMILIES[family].tier) * 2.0) * (1.0 + rank * 0.15)
			target += expected_armor * (1.0 - 1.0 / area)
		# Combining Add Effect with Cut Effect also permits half steps. Whole
		# runes alone made a cheap acid bolt stronger than a higher-budget fire
		# bolt solely through rounding. Use the same builder/combat definitions.
		var halves := maxi(1, roundi(target / half_step))
		if halves % 2 == 1: retained.append("e0")
		for rune in maxi(0, ceili(float(halves) / 2.0) - 1): retained.append("e1")
		# Curse's smallest positive native effect is still a heavy strike.
		# Pay for its excess through the caster's action rate.
		cast_rate = minf(cast_rate, minf(1.0, target / half_step))
		spells[i] = "%s{%s}" % [parsed.code,";".join(retained)]
	tuned.spells = spells
	tuned["_trials_cast_rate"] = cast_rate
	tuned["_spell_cache_key"] = "%s:trials:%d:%d" % [proto.name,family,rank]
	return tuned


static func title(id: String, family := -1, rank := 0) -> String:
	return RemakeText.t(GameUnit.unit_title(ArenaAppearance.name_prototype(id, family, rank)))


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
	return prototype(13,1)


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


static func saved_family_count(version: int) -> int:
	return LEGACY_FORMS.size() if version < 11 else EXPERIMENT_FORMS.size() if version < 13 else FAMILIES.size()

static func saved_prototype(version: int, family: int, rank: int) -> String:
	if version < 11: return LEGACY_FORMS[family][rank]
	if version == 11 and PREVIOUS_FORMS.has(family): return PREVIOUS_FORMS[family][rank]
	if version < 13: return EXPERIMENT_FORMS[family][rank]
	return prototype(family, rank)

static func migrated_family(id: String, fallback := 0) -> int:
	var key := id.to_lower()
	if key.begins_with("boar"): return 0
	if key.begins_with("wolf") or key.begins_with("dog"): return 1
	if key.begins_with("rat"): return 2
	if key.begins_with("bat"): return 3
	if key.begins_with("goblin"): return 4
	if key.begins_with("toad"): return 5
	if key.begins_with("skeleton"): return 6
	if key.begins_with("tiger"): return 7
	if key.begins_with("spider"): return 8
	if key.begins_with("scrab"): return 9
	if key.begins_with("dragonkin"): return 10
	if key.begins_with("driad"): return 11
	if key.begins_with("zombie") or key.begins_with("undead"): return 12
	if key.begins_with("orc"): return 13
	if key.begins_with("troll"): return 14
	if key.begins_with("ogre"): return 15
	if key.begins_with("succub"): return 16
	if key.begins_with("hyena"): return 17
	if key.begins_with("evileye"): return 18
	if key.begins_with("banshee"): return 19
	if key.begins_with("unicorn"): return 20
	if key.begins_with("willowisp"): return 21
	if key.begins_with("elemental"): return 22
	if key.begins_with("dragon"): return 23
	if key.begins_with("golem"): return 24
	if key.begins_with("ancientcurse") or key.begins_with("shadow"): return 25
	if key.begins_with("octopus"): return 26
	if key.begins_with("cyclops"): return 27
	if key.begins_with("human"):
		var row := GameData.db.find("monster_prototypes",key)
		if not Array(row.get("spells",[])).is_empty(): return 13
		return 11 if bow_user(row) else 10
	return clampi(fallback,0,FAMILIES.size()-1)
