class_name ArenaItems
extends RefCounted
## One item per creature. Flat bonuses are independent of stars; triggered effects use
## the same bounded combat hooks at every tier. Old pending rewards keep pool 1.
const MAX_ITEMS := 32
const MAX_REWARD_ROUND := 100
const ORIGINAL_KINDS := ["fang", "storm", "venom", "ward", "guardian", "echo", "thorn", "berserker"]
const OFFER_VERSION := 2
const RULES := {
	"vitality": {"name": "Vitality Amulet", "tier": 1, "health": 40},
	"blade": {"name": "Iron Sword", "tier": 1, "damage": 5},
	"haste": {"name": "Swift Boots", "tier": 1, "actions": 3},
	"mail": {"name": "Iron Mail", "tier": 1, "physical_armor": 4},
	"prism": {"name": "Prismatic Gem", "tier": 1, "elemental_armor": 5},
	"focus": {"name": "Sage's Wand", "tier": 1, "spell": 8},
	"fang": {"name": "Vampiric Fang", "tier": 1, "effect": "fang", "leech": 4},
	"venom": {"name": "Venom Seal", "tier": 1, "effect": "venom", "healing_reduction": 0.5},
	"greatblade": {"name": "Steel Saber", "tier": 2, "damage": 10},
	"ironheart": {"name": "Amber Heart", "tier": 2, "health": 80},
	"quicksilver": {"name": "Mercury Gloves", "tier": 2, "actions": 5},
	"runemail": {"name": "Runic Mail", "tier": 2, "physical_armor": 8, "elemental_armor": 3},
	"opal": {"name": "Wisp Stone", "tier": 2, "elemental_armor": 10},
	"staff": {"name": "Seer Staff", "tier": 2, "spell": 16},
	"ward": {"name": "Ward Stone", "tier": 2, "effect": "ward", "shield": 60},
	"thorn": {"name": "Thorn Shell", "tier": 2, "effect": "thorn", "reflect": 8},
	"warhammer": {"name": "Stone Cleaver", "tier": 3, "damage": 18},
	"bulwark": {"name": "Sentinel Plate", "tier": 3, "health": 80, "physical_armor": 10},
	"sage": {"name": "Sage Tome", "tier": 3, "spell": 24},
	"windrunner": {"name": "Windrunner Boots", "tier": 3, "actions": 7},
	"storm": {"name": "Storm Shard", "tier": 3, "effect": "storm", "storm_damage": 25, "storm_targets": 1},
	"guardian": {"name": "Guardian Knot", "tier": 3, "effect": "guardian", "shield": 90},
	"echo": {"name": "Echo Rune", "tier": 3, "effect": "echo", "echo_damage": 30, "echo_every": 3},
	"berserker": {"name": "Berserker Charm", "tier": 3, "effect": "berserker", "frenzy": 10},
	"bloodblade": {"name": "Bloodfang", "tier": 4, "damage": 18, "effect": "fang", "leech": 8},
	"stormheart": {"name": "Storm Heart", "tier": 4, "health": 100, "effect": "storm", "storm_damage": 40, "storm_targets": 1},
	"plague": {"name": "Plague Sting", "tier": 4, "damage": 24, "effect": "venom", "healing_reduction": 0.75},
	"aegis": {"name": "Ancient Aegis", "tier": 4, "health": 100, "effect": "ward", "shield": 120},
	"mirror": {"name": "Spiked Mantle", "tier": 4, "physical_armor": 10, "effect": "thorn", "reflect": 16},
	"archmage": {"name": "Archmage Scepter", "tier": 4, "spell": 32, "actions": 3},
	"titan": {"name": "Titan Plate", "tier": 4, "health": 160, "physical_armor": 10},
	"duelist": {"name": "Duelist Blade", "tier": 4, "damage": 24, "actions": 4},
	"sunblade": {"name": "Sunblade", "tier": 5, "damage": 40},
	"worldheart": {"name": "Heart of the World", "tier": 5, "health": 280},
	"crown": {"name": "Dragon Scepter", "tier": 5, "spell": 50},
	"starweave": {"name": "Starweave", "tier": 5, "spell": 35, "elemental_armor": 16},
	"bloodmoon": {"name": "Blood Moon", "tier": 5, "damage": 24, "effect": "fang", "leech": 14},
	"thunderbolt": {"name": "Tempest Orb", "tier": 5, "actions": 6, "effect": "storm", "storm_damage": 50, "storm_targets": 2},
	"covenant": {"name": "Sacred Covenant", "tier": 5, "health": 140, "effect": "guardian", "shield": 180},
	"chronicle": {"name": "Echo Chronicle", "tier": 5, "spell": 24, "effect": "echo", "echo_damage": 60, "echo_every": 2},
}

static func title(kind: String) -> String:
	return RemakeText.t(String(RULES[kind].name)) if RULES.has(kind) else ""

static func tier(kind: String) -> int:
	return int(RULES.get(kind, {}).get("tier", 0))

static func effect(kind: String) -> String:
	return String(RULES.get(kind, {}).get("effect", ""))

static func tier_label(kind: String) -> String:
	return RemakeText.t("Tier %d") % tier(kind)

static func description(kind: String, include_tier := true) -> String:
	if not RULES.has(kind): return ""
	var r: Dictionary = RULES[kind]
	var lines: Array[String] = []
	if include_tier: lines.append(tier_label(kind))
	if r.has("health"): lines.append(RemakeText.t("+%d health.") % r.health)
	if r.has("damage"): lines.append(RemakeText.t("+%d attack damage.") % r.damage)
	if r.has("actions"): lines.append(RemakeText.t("+%d action speed.") % r.actions)
	if r.has("physical_armor"): lines.append(RemakeText.t("+%d physical armor.") % r.physical_armor)
	if r.has("elemental_armor"): lines.append(RemakeText.t("+%d fire, acid and lightning armor.") % r.elemental_armor)
	if r.has("spell"): lines.append(RemakeText.t("+%d spell damage.") % r.spell)
	match effect(kind):
		"fang": lines.append(RemakeText.t("Attacks restore %d health.") % r.leech)
		"storm":
			if r.storm_targets == 1: lines.append(RemakeText.t("Every third hit deals %d lightning damage to another enemy within 4 m.") % r.storm_damage)
			else: lines.append(RemakeText.t("Every third hit deals %d lightning damage to %d other enemies within 4 m.") % [r.storm_damage, r.storm_targets])
		"venom": lines.append(RemakeText.t("Attacks reduce healing received by %d%% for 5 s.") % roundi(r.healing_reduction * 100))
		"ward": lines.append(RemakeText.t("Below 35%% health: gain a %d-point shield for 5 s. Once per battle.") % r.shield)
		"guardian": lines.append(RemakeText.t("An ally within 5 m falls below 35%% health: shield it for %d damage for 5 s. Once per battle.") % r.shield)
		"echo": lines.append(RemakeText.t("Every %d offensive spells: deal %d extra damage in the spell's element.") % [r.echo_every, r.echo_damage])
		"thorn": lines.append(RemakeText.t("Retaliate for %d damage against melee hits. Once per second.") % r.reflect)
		"berserker": lines.append(RemakeText.t("+%d action speed. Cannot cast spells.") % r.frenzy)
	return "\n".join(lines)

static func reward_round(completed_round: int) -> bool:
	return completed_round == 3 or (completed_round >= 5 and completed_round % 5 == 0)

## Every player chooses among equally rare items. Late loot always advances,
## rather than diluting the choice with an obsolete early-game item.
static func offer_tier(completed_round: int) -> int:
	return clampi(completed_round / 5 + 1, 1, 5)

## Reward RNG never consumes the shop stream. Preserve the original ordering
## and shuffle for pool 1, including a legacy reward saved again by this build.
static func offers(seed_value: int, completed_round: int, pool_version := OFFER_VERSION) -> Array[String]:
	var choices: Array[String] = []
	if pool_version == 1: choices.assign(ORIGINAL_KINDS)
	else:
		for kind: String in RULES:
			if tier(kind) == offer_tier(completed_round): choices.append(kind)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value * 15485863 + completed_round * 32452843 + 49979687
	for index in range(choices.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := choices[index]
		choices[index] = choices[other]; choices[other] = held
	return choices.slice(0, 3)
