class_name ArenaItems
extends RefCounted
## One item per creature makes the carrier part of the build. Inventory UIDs
## belong to the company; the combat placement receives only its frozen kind.
const MAX_ITEMS := 32
const MAX_REWARD_ROUND := 100
const RULES := {
	"fang": {"name":"Vampiric Fang", "help":"Basic attacks heal the wearer for 20% of damage dealt, up to 2% of its maximum health per hit."},
	"storm": {"name":"Storm Shard", "help":"Every third successful basic attack strikes another enemy within 4 m of the wearer with lightning for 10% of the wearer's maximum health before armor."},
	"venom": {"name":"Venom Seal", "help":"Successful basic attacks halve the target's healing for 5 seconds."},
	"ward": {"name":"Ward Stone", "help":"Once per battle, a hit that would take the wearer below 35% health triggers a shield worth 25% of maximum health for 5 seconds."},
	"guardian": {"name":"Guardian Knot", "help":"Once per battle, shield another ally within 5 m when a hit would take it below 35% health. The shield lasts 5 seconds and equals 20% of the wearer's maximum health."},
	"echo": {"name":"Echo Rune", "help":"Every third completed offensive spell strikes its target again for 35% of the wearer's attack damage, using the spell's element. Echoes cannot trigger another echo."},
	"thorn": {"name":"Thorn Shell", "help":"Retaliate against melee attacks once per second, dealing 15% of damage received, up to 3% of the wearer's maximum health."},
	"berserker": {"name":"Berserker Charm", "help":"The wearer acts 25% faster but cannot cast spells."},
}


static func title(kind: String) -> String:
	return RemakeText.t(String(RULES[kind].name)) if RULES.has(kind) else ""


static func description(kind: String) -> String:
	if not RULES.has(kind): return ""
	var result := RemakeText.t(String(RULES[kind].help))
	if kind in ["ward", "guardian"]:
		result += "\n\n" + RemakeText.t("Shields do not stack; the strongest remaining shield applies.")
	return result


static func reward_round(completed_round: int) -> bool:
	return completed_round == 3 or (completed_round >= 5 and completed_round % 5 == 0)


## A reward cannot reveal or advance the shop's random stream. Recreating a
## company from a save produces the same three distinct choices for the round.
static func offers(seed_value: int, completed_round: int) -> Array[String]:
	var choices: Array[String] = []
	choices.assign(RULES.keys())
	var random := RandomNumberGenerator.new()
	random.seed = seed_value * 15485863 + completed_round * 32452843 + 49979687
	for index in range(choices.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := choices[index]
		choices[index] = choices[other]; choices[other] = held
	return choices.slice(0, 3)
