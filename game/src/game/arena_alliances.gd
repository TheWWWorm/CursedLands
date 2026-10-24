class_name ArenaAlliances
extends RefCounted
## Automatic, overlapping traits. Unique deployed families count, not copies,
## stars, reserves or old camp guests. Battle behaviors are isolated to Trials actors.
const RULES := {
	"beast": {"name": "Beasts", "families": [0, 1, 2, 3, 5, 7, 8, 9, 16, 17, 20, 23], "thresholds": [2, 4, 6], "help": "Beasts gain 10/20/30% attack damage at 2/4/6 different Beasts."},
	"horde": {"name": "Horde", "families": [4, 10, 13, 14, 15, 27, 28], "thresholds": [2, 4], "help": "Horde members gain 15/30% maximum health at 2/4 different Horde members."},
	"warrior": {"name": "Warriors", "families": [0, 6, 9, 12, 14, 15, 22, 24, 28], "thresholds": [2, 4], "help": "Warriors gain 30/60% armor against physical damage at 2/4 different Warriors."},
	"hunter": {"name": "Hunters", "families": [1, 2, 4, 7, 10, 11, 17, 27], "thresholds": [2, 4], "help": "An enemy completing a spell is marked for 3 seconds. Hunters prioritize the marked enemy when it is in reach. At 4 Hunters, all allies follow the mark."},
	"mage": {"name": "Mages", "families": [3, 5, 13, 16, 18, 19, 21, 23, 26, 29], "thresholds": [2, 4], "help": "Mages deal 15/30% more spell damage at 2/4 different Mages."},
	"spirit": {"name": "Spirits", "families": [6, 11, 12, 19, 20, 21, 22, 24, 25, 26, 29], "thresholds": [2, 4], "help": "The first Spirit death heals the nearest 1/2 wounded allies within 5 m for 12% of the fallen Spirit's maximum health. At 4 Spirits, it also leaves one wisp with 20% health for 6 seconds. Echoes carry no items and cannot trigger death effects."},
}
const EFFECTS := {
	"beast": ["+10% attack damage", "+20% attack damage", "+30% attack damage"],
	"horde": ["+15% maximum health", "+30% maximum health"],
	"warrior": ["+30% physical armor", "+60% physical armor"],
	"hunter": ["Hunters pursue marked casters", "All allies pursue marked casters"],
	"mage": ["+15% spell damage", "+30% spell damage"],
	"spirit": ["One spirit aid per battle", "Spirit aid and one temporary echo"],
}

static func traits(family: int) -> Array[String]:
	var found: Array[String] = []
	for key: String in RULES:
		if family in RULES[key].families: found.append(key)
	return found

static func counts(army: Array) -> Dictionary:
	var families := {}
	for entry: Dictionary in army:
		if entry.deployed and int(entry.family) >= 0: families[int(entry.family)] = true
	var result := {}
	for key: String in RULES:
		var count := 0
		for family: int in RULES[key].families:
			if families.has(family): count += 1
		result[key] = count
	return result

static func rank(key: String, count: int) -> int:
	var result := 0
	for threshold: int in RULES[key].thresholds:
		if count >= threshold: result += 1
	return result

static func target(key: String, count: int) -> int:
	for threshold: int in RULES[key].thresholds:
		if count < threshold: return threshold
	return RULES[key].thresholds.back()

static func names(family: int) -> String:
	var labels: Array[String] = []
	for key in traits(family): labels.append(RemakeText.t(RULES[key].name))
	return " · ".join(labels)

static func effect(key: String, level: int) -> String:
	if level == 0: return RemakeText.t("No bonus yet.")
	return RemakeText.t(EFFECTS[key][clampi(level - 1, 0, EFFECTS[key].size() - 1)])

static func apply(world: GameWorld, army: Array, opponents: Array = []) -> void:
	var companies := [army, opponents]
	for unit: GameUnit in world.unit_rows():
		if not unit.has_meta("alliance_base"):
			unit.set_meta("alliance_base", {"stats": unit.stats.duplicate(true), "hp": unit.max_hp, "proto": unit.proto})
		var base: Dictionary = unit.get_meta("alliance_base")
		unit.proto = base.get("proto", unit.proto)
		var stats: Dictionary = base.stats.duplicate(true)
		var health := float(base.hp)
		var placement: Dictionary = unit.get_meta("arena_placement", {})
		var team := clampi(int(placement.get("team", 1)), 0, 1)
		if not companies[team].is_empty():
			var family := -1
			for entry: Dictionary in companies[team]:
				if int(entry.uid) == int(placement.get("run_uid", placement.get("source_uid", -1))): family = int(entry.family); break

			health = ArenaRules.recruit_health(family, health, int(placement.get("rank", 0)))
			ArenaRules.recruit_stats(family, int(placement.get("rank", 0)), stats)
			unit.proto = ArenaRules.recruit_prototype(family, int(placement.get("rank", 0)), unit.proto)
		elif team==1 and int(world.get_meta("arena_wave",0))>0:
			ArenaRules.creep_stats(int(world.get_meta("arena_wave")),stats)
		unit.remove_meta("arena_combat_base")
		unit.stats = stats
		unit.max_hp = health
		unit.hp = health
