class_name ArenaItems
extends RefCounted
## One item per creature. Stats add to alliance bonuses; triggered effects use
## the same bounded combat hooks at every tier. Old pending rewards keep pool 1.
const MAX_ITEMS := 32
const MAX_REWARD_ROUND := 100
const ORIGINAL_KINDS := ["fang", "storm", "venom", "ward", "guardian", "echo", "thorn", "berserker"]
const OFFER_VERSION := 2
const RULES := {
	"vitality": {"name": "Vitality Amulet", "tier": 1, "health": 0.25},
	"blade": {"name": "Iron Sword", "tier": 1, "damage": 0.2},
	"haste": {"name": "Swift Boots", "tier": 1, "actions": 0.15},
	"mail": {"name": "Iron Mail", "tier": 1, "physical_armor": 0.35},
	"prism": {"name": "Prismatic Gem", "tier": 1, "elemental_armor": 0.35},
	"focus": {"name": "Sage's Wand", "tier": 1, "spell": 0.2},
	"fang": {"name": "Vampiric Fang", "tier": 1, "effect": "fang", "leech": 0.2, "leech_cap": 0.02},
	"venom": {"name": "Venom Seal", "tier": 1, "effect": "venom", "healing_reduction": 0.5},
	"greatblade": {"name": "Steel Saber", "tier": 2, "damage": 0.35},
	"ironheart": {"name": "Amber Heart", "tier": 2, "health": 0.45},
	"quicksilver": {"name": "Mercury Gloves", "tier": 2, "actions": 0.25},
	"runemail": {"name": "Runic Mail", "tier": 2, "physical_armor": 0.55, "elemental_armor": 0.2},
	"opal": {"name": "Wisp Stone", "tier": 2, "elemental_armor": 0.65},
	"staff": {"name": "Seer Staff", "tier": 2, "spell": 0.35},
	"ward": {"name": "Ward Stone", "tier": 2, "effect": "ward", "shield": 0.7},
	"thorn": {"name": "Thorn Shell", "tier": 2, "effect": "thorn", "reflect": 0.35, "reflect_cap": 0.06},
	"warhammer": {"name": "Stone Cleaver", "tier": 3, "damage": 0.55},
	"bulwark": {"name": "Sentinel Plate", "tier": 3, "health": 0.3, "physical_armor": 0.65},
	"sage": {"name": "Sage Tome", "tier": 3, "spell": 0.55},
	"windrunner": {"name": "Windrunner Boots", "tier": 3, "actions": 0.35},
	"storm": {"name": "Storm Shard", "tier": 3, "effect": "storm", "storm_damage": 0.2, "storm_targets": 1},
	"guardian": {"name": "Guardian Knot", "tier": 3, "effect": "guardian", "shield": 0.5},
	"echo": {"name": "Echo Rune", "tier": 3, "effect": "echo", "echo_damage": 1.5, "echo_every": 3},
	"berserker": {"name": "Berserker Charm", "tier": 3, "effect": "berserker", "frenzy": 0.55},
	"bloodblade": {"name": "Bloodfang", "tier": 4, "damage": 0.35, "effect": "fang", "leech": 0.3, "leech_cap": 0.04},
	"stormheart": {"name": "Storm Heart", "tier": 4, "health": 0.25, "effect": "storm", "storm_damage": 0.3, "storm_targets": 1},
	"plague": {"name": "Plague Sting", "tier": 4, "damage": 0.5, "effect": "venom", "healing_reduction": 0.75},
	"aegis": {"name": "Ancient Aegis", "tier": 4, "health": 0.3, "effect": "ward", "shield": 1.0},
	"mirror": {"name": "Spiked Mantle", "tier": 4, "physical_armor": 0.5, "effect": "thorn", "reflect": 0.5, "reflect_cap": 0.1},
	"archmage": {"name": "Archmage Scepter", "tier": 4, "spell": 0.6, "actions": 0.15},
	"titan": {"name": "Titan Plate", "tier": 4, "health": 0.7, "physical_armor": 0.5},
	"duelist": {"name": "Duelist Blade", "tier": 4, "damage": 0.6, "actions": 0.2},
	"sunblade": {"name": "Sunblade", "tier": 5, "damage": 1.2},
	"worldheart": {"name": "Heart of the World", "tier": 5, "health": 1.5},
	"crown": {"name": "Dragon Scepter", "tier": 5, "spell": 1.1},
	"starweave": {"name": "Starweave", "tier": 5, "spell": 0.75, "elemental_armor": 0.85},
	"bloodmoon": {"name": "Blood Moon", "tier": 5, "damage": 0.6, "effect": "fang", "leech": 0.4, "leech_cap": 0.06},
	"thunderbolt": {"name": "Tempest Orb", "tier": 5, "actions": 0.3, "effect": "storm", "storm_damage": 0.25, "storm_targets": 2},
	"covenant": {"name": "Sacred Covenant", "tier": 5, "health": 0.5, "effect": "guardian", "shield": 1.4},
	"chronicle": {"name": "Echo Chronicle", "tier": 5, "spell": 0.5, "effect": "echo", "echo_damage": 3.0, "echo_every": 2},
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
	if r.has("health"): lines.append(RemakeText.t("+%d%% maximum health.") % roundi(r.health * 100))
	if r.has("damage"): lines.append(RemakeText.t("+%d%% attack damage.") % roundi(r.damage * 100))
	if r.has("actions"): lines.append(RemakeText.t("+%d%% action speed, including attacks and spells.") % roundi(r.actions * 100))
	if r.has("physical_armor"): lines.append(RemakeText.t("+%d%% armor against physical damage.") % roundi(r.physical_armor * 100))
	if r.has("elemental_armor"): lines.append(RemakeText.t("+%d%% armor against fire, acid and lightning.") % roundi(r.elemental_armor * 100))
	if r.has("spell"): lines.append(RemakeText.t("+%d%% spell damage.") % roundi(r.spell * 100))
	match effect(kind):
		"fang": lines.append(RemakeText.t("Basic attacks heal for %d%% of damage dealt, up to %d%% of maximum health per hit.") % [roundi(r.leech * 100), roundi(r.leech_cap * 100)])
		"storm": lines.append(RemakeText.t("Every third successful basic attack strikes up to %d other enemies within 4 m. Each takes lightning damage equal to %d%% of the wearer's maximum health before armor.") % [r.storm_targets, roundi(r.storm_damage * 100)])
		"venom": lines.append(RemakeText.t("Basic attacks reduce the target's healing by %d%% for 5 seconds.") % roundi(r.healing_reduction * 100))
		"ward": lines.append(RemakeText.t("Once per battle, a hit that would take the wearer below 35%% health triggers a shield worth %d%% of maximum health for 5 seconds.") % roundi(r.shield * 100))
		"guardian": lines.append(RemakeText.t("Once per battle, shield another ally within 5 m when a hit would take it below 35%% health. The shield lasts 5 seconds and equals %d%% of the wearer's maximum health.") % roundi(r.shield * 100))
		"echo": lines.append(RemakeText.t("Every %d completed offensive spells, strike the target again for %d%% of attack damage using the spell's element. Echoes cannot trigger echoes.") % [r.echo_every, roundi(r.echo_damage * 100)])
		"thorn": lines.append(RemakeText.t("Retaliate against melee attacks once per second for %d%% of damage received, up to %d%% of maximum health.") % [roundi(r.reflect * 100), roundi(r.reflect_cap * 100)])
		"berserker": lines.append(RemakeText.t("The wearer acts %d%% faster but cannot cast spells.") % roundi(r.frenzy * 100))
	if effect(kind) in ["ward", "guardian"]:
		lines.append(RemakeText.t("Shields do not stack; the strongest remaining shield applies."))
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
