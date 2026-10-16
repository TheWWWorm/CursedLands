class_name ArenaRules
extends RefCounted
## Content shared by the playable expedition and its balance simulations.
## Every fighter resolves to an unmodified original-game prototype.

const VERSION := 2
const WAVE_COUNT := 18
const VICTORY_GOLD := 7
const FAMILIES := [
	{"name": "Boars", "role": "Melee", "cost": 3, "forms": ["boarredf1", "boarredf3", "boardarkf6"]},
	{"name": "Tribal fighters", "role": "Melee", "cost": 3, "forms": ["goblinf1", "orcmalef3", "orcmalef5"]},
	{"name": "Wolves", "role": "Melee", "cost": 3, "forms": ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"]},
	{"name": "Tribal shooters", "role": "Ranged", "cost": 4, "copies": [2, 3], "forms": ["goblina1", "goblina3", "orcfemalea5"]},
	{"name": "Bats", "role": "Magic", "cost": 4, "copies": [2, 3], "forms": ["batredm1", "batredm3", "batlightm7"]},
	{"name": "Toads", "role": "Magic", "cost": 4, "forms": ["toadm2", "toadm6"]},
]
# One pact per expedition. Only owned, deployed creatures meet its condition;
# the guest never counts toward its own pact, occupies no army/bench slot and
# cannot be sold or evolved. Support uses the same native spawn path as everyone.
const PACTS := {
	"hunt": {"name": "Wild kin", "help": "Deploy three different families among boars, wolves, bats and toads to call a wolf ally.",
		"families": [0, 2, 4, 5], "needed": 3, "min_rank": 0, "forms": ["wolfgreyf1", "wolfgreyf3", "wolfwhitef6"]},
	"tribe": {"name": "Tribal council", "help": "Deploy an evolved tribal fighter and an evolved tribal shooter to call an orc seer ally.",
		"families": [1, 3], "needed": 2, "min_rank": 1, "forms": ["orcfemalem3", "orcfemalem5", "orcfemalem7"]},
	"vanguard": {"name": "The vanguard", "help": "Deploy boars, tribal fighters and wolves together to call a tribal shooter ally.",
		"families": [0, 1, 2], "needed": 3, "min_rank": 0, "forms": ["goblina3", "orcfemalea5", "orcfemalea7"]},
}
const STARTERS := [
	{"name": "The warband", "help": "Two fighters protect a sling thrower. A reliable opening formation.", "families": [0, 1, 3]},
	{"name": "The wild hunt", "help": "A boar and a wolf close in while a bat attacks with magic.", "families": [0, 2, 4]},
	{"name": "The marsh pact", "help": "A goblin holds the front while a sling thrower and a toad attack from range.", "families": [1, 3, 5]},
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
	["The ridge hunters", "tigerredf4", "tigerredf4", "orcfemalea3", "orcfemalea3"],
	["The Ogre's court", "ogregipatf5", "orcmalef3", "goblina3", "orcfemalea3"],
	["The white pack", "wolfwhitef6", "wolfgreyf3", "wolfgreyf3", "batredm3", "toadm4"],
	["The war council", "orcmalef5", "orcmalef5", "orcfemalea5", "orcfemalem3", "goblinf3"],
	["The ancient guard", "skeletonf4", "skeletonf4", "orcfemalem5", "orcfemalea5", "goblinf3"],
	["The last hunt", "tigerredf6", "tigerredf6", "wolfwhitef6", "batredm5", "toadm4"],
	["At the gates", "ogregipatf5", "boardarkf6", "orcmalef5", "orcfemalea5"],
	["The lord of the ruins", "ogregipatf5", "orcmalef5", "orcmalef5", "orcfemalea5", "orcfemalem5", "boardarkf6"],
]
const BOONS := {
	"merchant": ["Quartermaster", "Shop refreshes cost 1 gold instead of 2."],
	"reserve": ["Pack train", "Gain 3 extra bench spaces for this expedition."],
	"purse": ["War chest", "Gain 12 gold to recruit and evolve your army."],
	"life": ["Second wind", "Recover one life, up to three."],
	"scout": ["Well connected", "Every new shop has a sixth recruit offer."],
	"companion": ["A new ally", "A seer joins your reserves. Deploy it in a normal army slot."],
	"pact": ["Company pact", "Commit to one pact for this expedition. Meet its deployment condition to call a temporary ally each battle."],
	"pact_upgrade": ["Strengthen the pact", "Replace your pact ally with its next original form for the rest of this expedition. The deployment condition stays the same."],
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
	var map := EIResArchive.open_path(GameData.root.path_join("maps/basegipat.mpr"))
	if map == null or map.read("basegipat.mp").size() < 38: return false
	for family: Dictionary in FAMILIES:
		for id: String in family.forms:
			if GameData.db.find("monster_prototypes", id).is_empty(): return false
	for pact: Dictionary in PACTS.values():
		for id: String in pact.forms:
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
		ids.append("orcmalef5" if wave > 12 else "orcmalef3" if wave > 6 else "goblinf1")
	if challenge > 1 and wave >= 6:
		ids.append("orcfemalea5" if wave > 12 else "goblina3" if wave > 9 else "goblina2")
	var flip := -1 if (run_seed + wave) % 2 else 1
	for id: String in ids:
		var proto := GameData.db.find("monster_prototypes", id)
		var ranged := float(proto.get("attack_range", 0)) > 0 or not Array(proto.get("spells", [])).is_empty()
		var index := back if ranged else front
		var lane: float = [0.0, -4.0, 4.0, -8.0, 8.0][mini(index, 4)]
		out.append({"id": id, "team": 1, "point": Vector2(40.5 if ranged else 36.5, 32 + flip * lane)})
		if ranged: back += 1
		else: front += 1
	return out
