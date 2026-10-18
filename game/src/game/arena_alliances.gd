class_name ArenaAlliances
extends RefCounted
## Automatic, overlapping traits. Unique deployed families count, not copies,
## stars, reserves or old camp guests. Bonuses are isolated to expedition actors.
const RULES := {
	"beast": {"name": "Beasts", "families": [0, 2, 4, 5, 8, 9, 10, 14, 16], "thresholds": [2, 4, 6], "help": "All allies deal 10/20/30% more attack damage."},
	"horde": {"name": "Horde", "families": [1, 3, 9, 11, 12, 16, 19, 21, 25, 28], "thresholds": [2, 4], "help": "Horde creatures gain 15/30% maximum health."},
	"warrior": {"name": "Warriors", "families": [0, 1, 9, 15, 16, 19, 20, 21, 25, 26, 27, 28, 29], "thresholds": [2, 4], "help": "Warriors gain 20/40% physical armor, plus 2/4 armor."},
	"hunter": {"name": "Hunters", "families": [2, 3, 7, 13, 14, 17, 20, 23, 26, 29], "thresholds": [2, 4], "help": "Hunters gain 15/30% attack accuracy and act 10/20% faster."},
	"mage": {"name": "Mages", "families": [4, 5, 6, 7, 8, 11, 12, 13, 18, 22, 24], "thresholds": [2, 4], "help": "Enemies lose 20/40% fire, acid and lightning armor."},
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
	match key:
		"beast": return RemakeText.t("All allies: +%d%% attack damage.") % (level * 10)
		"horde": return RemakeText.t("Horde: +%d%% health.") % (level * 15)
		"warrior": return RemakeText.t("Warriors: +%d%% physical armor and +%d armor.") % [level * 20, level * 2]
		"hunter": return RemakeText.t("Hunters: +%d%% accuracy, +%d%% action speed.") % [level * 15, level * 10]
		"mage": return RemakeText.t("Enemies: −%d%% elemental armor.") % (level * 20)
	return ""

static func apply(world: GameWorld, army: Array, opponents: Array = []) -> void:
	var companies := [army, opponents]
	var totals := [counts(army), counts(opponents)]
	for unit: GameUnit in world.unit_rows():
		if not unit.has_meta("alliance_base"):
			unit.set_meta("alliance_base", {"stats": unit.stats.duplicate(true), "hp": unit.max_hp, "proto": unit.proto})
		var base: Dictionary = unit.get_meta("alliance_base")
		unit.proto = base.get("proto", unit.proto)
		var stats: Dictionary = base.stats.duplicate(true)
		var health := float(base.hp)
		var placement: Dictionary = unit.get_meta("arena_placement", {})
		var team := int(placement.get("team", 1))
		var count: Dictionary = totals[team]
		if not companies[team].is_empty():
			var family := -1
			for entry: Dictionary in companies[team]:
				if int(entry.uid) == int(placement.get("run_uid", placement.get("source_uid", -1))): family = int(entry.family); break

			health = ArenaRules.recruit_health(family, health, int(placement.get("rank", 0)))
			ArenaRules.recruit_stats(family, int(placement.get("rank", 0)), stats)
			unit.proto = ArenaRules.recruit_prototype(family, int(placement.get("rank", 0)), unit.proto)
			var member := traits(family)
			var beasts := rank("beast", count.beast)
			stats.dmg_min *= 1.0 + beasts * 0.1
			stats.dmg_max *= 1.0 + beasts * 0.1
			if "horde" in member: health *= 1.0 + rank("horde", count.horde) * 0.15
			if "warrior" in member:
				var warriors := rank("warrior", count.warrior)
				for type in 3: stats.armor[type] = stats.armor[type] * (1.0 + warriors * 0.2) + warriors * 2.0
			if "hunter" in member:
				var hunters := rank("hunter", count.hunter)
				stats.to_hit *= 1.0 + hunters * 0.15
				stats.actions = float(stats.get("actions", 15.0)) * (1.0 + hunters * 0.1)
		elif team==1 and int(world.get_meta("arena_wave",0))>0:
			ArenaRules.creep_stats(int(world.get_meta("arena_wave")),stats)
		var mages := rank("mage", totals[1 - team].mage)
		for type in range(3, 6): stats.armor[type] *= 1.0 - mages * 0.2
		unit.stats = stats
		unit.max_hp = health
		unit.hp = health
