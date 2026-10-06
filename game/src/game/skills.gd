class_name Skills
extends RefCounted
## The original six skills (0..100), bought with experience in towns and camps:
## Melee, Archery, Use/Steal ("science"), Elemental, Sense and Astral magic
## (perks.pdb "skills" table, texts.res "perk <code>").
## Sourced rules:
##   * skill price: see curve (the original), 0 -> 100 costs ~685 000
##   * magic knowledge = skill + school perk (max +15) + (Int - 25, max +13), max 128;
##   * without modifiers HP = stamina = 13.627 * exp^(1/4.99) (exp = total experience);
##     Strength scales HP, Dexterity stamina (25 = 100 %);
##   * each point of Dexterity above/below 25 adds/removes one Attack and Defence.

const LIST := ["melee", "archery", "science", "elemental", "sense", "astral"]
const TrainingRefund := preload("res://src/game/training_refund.gd")
## npcs.skills2 slot of each skill. the original GiveSkill (case 0xcd):
## 0 melee, 1 archery, 2 backstab, 3 elemental, 4 sense, 5 astral, 6 stealth,
## 7 awareness; "science" (Use/Steal) has its own setter, read here
## from npcs.skills[0].
const SKILLS2_SLOT := {"melee": 0, "archery": 1, "elemental": 3, "sense": 4, "astral": 5}
## Magic school of each spell subtype (perks.pdb "skill type").
const SCHOOL := {"fire": "elemental", "lightning": "elemental", "acid": "elemental",
	"illusion": "sense", "divination": "sense",
	"enchantments": "astral", "healing": "astral", "domination": "astral"}


static func title(skill: String) -> String:
	var t := GameData.text("perk " + skill)
	return t.get_slice("\n", 0).strip_edges() if t else skill.capitalize()


static func level(h: Dictionary, skill: String) -> int:
	return int(h.get("skills", {}).get(skill, 0))


## HUD skill byte: party characters have their current hero record;
## script-trained NPCs keep their mutable record too. Otherwise use the
## NPC's initial skills. Other creatures have 0.
static func unit_level(u: GameUnit, skill: String) -> int:
	var h := CampaignState.script_character(u)
	if not h.is_empty():
		return level(h, skill)
	if u.uid >= 1000000000 and u.uid < 2000000000:
		var npc := GameData.db.find("npcs", String(u.proto.get("name", "")))
		return int(from_npc(npc).get(skill, 0))
	return 0


## Experience curve of the original: v1 * 1.61 ^ (level / v2) with
## ai.reg [RPG] "Skill Val 1" = 50, "Skill Val 2" = 5.
static func curve(lvl: float) -> float:
	return GameData.ai_value("RPG", "Skill Val 1", 50.0) * pow(1.61, lvl / GameData.ai_value("RPG", "Skill Val 2", 5.0))


## Experience to raise a skill from `from` to `to` (truncated, as the original does).
static func span_cost(from: float, to: float) -> int:
	return int(curve(to) - curve(from))


## Experience to raise `skill` by one point (0 at 100).
static func cost(h: Dictionary, skill: String) -> int:
	var n := level(h, skill)
	return 0 if n >= 100 else maxi(1, span_cost(n, n + 1))


static func raise(h: Dictionary, skill: String) -> bool:
	if not skill in LIST:
		return false
	var c := cost(h, skill)
	if c <= 0 or float(h.get("exp", 0.0)) < c:
		return false
	TrainingRefund.record_skill(h, skill, c)
	h.exp = float(h.exp) - c
	var s: Dictionary = h.get_or_add("skills", {})
	s[skill] = level(h, skill) + 1
	return true


## Starting skills of an NPC record.
static func from_npc(npc: Dictionary) -> Dictionary:
	var out := {}
	var s2: Array = npc.get("skills2", [])
	for k: String in SKILLS2_SLOT:
		var i: int = SKILLS2_SLOT[k]
		if i < s2.size() and int(s2[i]) > 0:
			out[k] = int(s2[i])
	var s1: Array = npc.get("skills", [])
	if not s1.is_empty() and int(s1[0]) > 0:
		out.science = int(s1[0])
	return out


## Knowledge of the school a spell subtype belongs to, the original:
## (Int - 25) + school skill (elemental / sense / astral) + the subtype's perk
## modifier (perks.pdb rank row).
static func knowledge(h: Dictionary, subtype: String) -> float:
	var school := String(SCHOOL.get(subtype, subtype))
	var intel := float(h.get("int", 25.0)) + Perks.attr_bonus(h, "int")
	return level(h, school) + Perks.best(h, subtype) + intel - 25.0


## HP / stamina before perks, config/ai.reg [RPG] "HP Val 1..5" / "MP Val 1..5":
## (Attr/v1) * v2 * v4 ^ log_v5(EXP / v3)   (the file's own comment gives the formula).
static func base_pool(total_exp: float, attr: float, prefix := "HP") -> float:
	var v := []
	for i in 5:
		v.append(GameData.ai_value("RPG", "%s Val %d" % [prefix, i + 1], [25.0, 30.0, 50.0, 1.1, 1.61][i]))
	var e := maxf(total_exp, 1.0)
	return attr / v[0] * v[1] * pow(v[3], log(e / v[2]) / log(v[4]))
