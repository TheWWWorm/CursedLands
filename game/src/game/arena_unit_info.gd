class_name ArenaUnitInfo
extends RefCounted
## Combat values, including Trials elite bonuses. Weaknesses compare armor with
## general armor, as in the campaign panel; they are not invented multipliers.

static func rank_of(id: String) -> int:
	for family: Dictionary in ArenaRules.FAMILIES:
		var rank := Array(family.forms).find(id)
		if rank >= 0: return rank
	return 0


static func values(id: String, unit: GameUnit = null, family := -1, rank := 0) -> Dictionary:
	var row := GameData.db.find("monster_prototypes", id)
	var race := GameData.db.find("race_models", String(row.get("base_race", "")))
	var armor := PackedFloat32Array()
	var factors: Array = race.get("defence", [])
	for i in 7: armor.append(float(row.get("absorption", 0)) * (float(factors[i]) if i < factors.size() else 1.0))
	var types: Array = race.get("attack", [])
	var result := {"hp": int(row.get("hp", 0)), "max_hp": int(row.get("hp", 0)),
		"attack": int(row.get("to_hit", 0)), "defense": 0 if int(row.get("weapon_type_id", -1)) in [5, 6] else int(row.get("parry", 0)),
		"min": int(row.get("damage_min", 0)), "max": int(row.get("damage_min", 0)) + int(row.get("damage_max", 0)),
		"armor": armor, "types": types}
	if ArenaRules.is_elite(family, rank):
		result.hp = int(ArenaRules.elite_health(result.hp)); result.max_hp = result.hp
		result.attack = int(result.attack * 1.2)
		result.min = int(result.min * 1.5); result.max = int(result.max * 1.5)
		for i in armor.size(): armor[i] *= 1.2
		result.armor = armor
	result.hp = int(ArenaRules.recruit_health(family, result.hp)); result.max_hp = result.hp
	if is_instance_valid(unit):
		result.hp = maxi(0, ceili(unit.hp)); result.max_hp = ceili(unit.max_hp)
		result.attack = unit.world.combat.attack_value(unit)
		result.defense = unit.world.combat.defence_value(unit)
		result.min = int(unit.stats.get("dmg_min", 0)); result.max = int(unit.stats.get("dmg_max", 0))
		result.armor = unit.stats.get("armor", armor)
		result.types = Array(unit.stats.get("dmg_types", PackedFloat32Array(types)))
	return result


static func summary(id: String, unit: GameUnit = null, family := -1, rank := 0) -> String:
	var stats := values(id, unit, family, rank)
	var best := 6
	var types: Array = stats.types
	for i in mini(types.size(), 7):
		if best >= types.size() or float(types[i]) > float(types[best]): best = i
	var armor: PackedFloat32Array = stats.armor
	var general := float(armor[6]) if armor.size() > 6 else 0.0
	var weak: Array[String] = []
	var strong: Array[String] = []
	for i in mini(armor.size(), 6):
		if armor[i] < general: weak.append(RemakeText.t(WikiCatalog.DAMAGE_TYPES[i]))
		elif armor[i] > general: strong.append(RemakeText.t(WikiCatalog.DAMAGE_TYPES[i]))
	var text := RemakeText.t("Health %d/%d\nAttack %d    Defense %d\nDamage %d–%d · %s\nArmor %d") % [stats.hp, stats.max_hp, stats.attack, stats.defense, stats.min, stats.max, RemakeText.t(WikiCatalog.DAMAGE_TYPES[best]), roundi(general)]
	text += "\n" + (RemakeText.t("Weaknesses: %s") % ", ".join(weak) if not weak.is_empty() else RemakeText.t("Weaknesses: none"))
	if not strong.is_empty(): text += "\n" + RemakeText.t("Resistant to: %s") % ", ".join(strong)
	return text
