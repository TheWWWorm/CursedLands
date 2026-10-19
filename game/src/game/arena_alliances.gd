class_name ArenaAlliances
extends RefCounted
## Automatic, overlapping traits. Unique deployed families count, not copies,
## stars, reserves or old camp guests. Bonuses are isolated to expedition actors.
const RULES := {
	"beast": {"name": "Beasts", "families": [0, 1, 2, 3, 5, 7, 8, 9, 16, 17, 20, 23], "thresholds": [2, 4, 6], "help": "Beasts deal 8/16/24% more attack damage."},
	"horde": {"name": "Horde", "families": [4, 10, 13, 14, 15, 27], "thresholds": [2, 4], "help": "Horde creatures gain 12/24% maximum health."},
	"warrior": {"name": "Warriors", "families": [0, 6, 9, 12, 14, 15, 22, 24], "thresholds": [2, 4], "help": "Warriors gain 2/4 physical armor."},
	"hunter": {"name": "Hunters", "families": [1, 2, 4, 7, 10, 11, 17, 27], "thresholds": [2, 4], "help": "Hunters gain 10/20% attack accuracy and act 8/16% faster."},
	"mage": {"name": "Mages", "families": [3, 5, 13, 16, 18, 19, 21, 23, 26], "thresholds": [2, 4], "help": "Enemies lose 15/30% fire, acid and lightning armor."},
	"spirit": {"name": "Spirits", "families": [6, 11, 12, 19, 20, 21, 22, 24, 25, 26], "thresholds": [2, 4], "help": "Spirits gain 3/6 fire, acid and lightning armor."},
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
		"beast": return RemakeText.t("Beasts: +%d%% attack damage.") % (level * 8)
		"horde": return RemakeText.t("Horde: +%d%% health.") % (level * 12)
		"warrior": return RemakeText.t("Warriors: +%d physical armor.") % (level * 2)
		"hunter": return RemakeText.t("Hunters: +%d%% accuracy, +%d%% action speed.") % [level * 10, level * 8]
		"mage": return RemakeText.t("Enemies: −%d%% elemental armor.") % (level * 15)
		"spirit": return RemakeText.t("Spirits: +%d elemental armor.") % (level * 3)
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
			if "beast" in member:
				stats.dmg_min *= 1.0 + beasts * 0.08
				stats.dmg_max *= 1.0 + beasts * 0.08
			if "horde" in member: health *= 1.0 + rank("horde", count.horde) * 0.12
			if "spirit" in member:
				for type in range(3, 6): stats.armor[type] += rank("spirit", count.spirit) * 3.0
			if "warrior" in member:
				var warriors := rank("warrior", count.warrior)
				for type in 3: stats.armor[type] += warriors * 2.0
			if "hunter" in member:
				var hunters := rank("hunter", count.hunter)
				stats.to_hit *= 1.0 + hunters * 0.1
				stats.actions = float(stats.get("actions", 15.0)) * (1.0 + hunters * 0.08)
		elif team==1 and int(world.get_meta("arena_wave",0))>0:
			ArenaRules.creep_stats(int(world.get_meta("arena_wave")),stats)
		var mages := rank("mage", totals[1 - team].mage)
		for type in range(3, 6): stats.armor[type] *= 1.0 - mages * 0.15
		unit.stats = stats
		unit.max_hp = health
		unit.hp = health
