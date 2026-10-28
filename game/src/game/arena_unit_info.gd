class_name ArenaUnitInfo
extends RefCounted
## Combat values, including Trials price and star budgets. Weaknesses compare armor with
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
		"armor": armor, "types": types, "actions": 15.0}

	result.hp = int(ArenaRules.recruit_health(family, result.hp, rank)); result.max_hp = result.hp
	ArenaRules.recruit_stats(family, rank, result)
	# Bow-using spellcasters still cannot parry with their bow. Their budget
	# role is Magic, but the preview follows the native equipped weapon rule.
	if ArenaRules.bow_user(row): result.defense=0
	if is_instance_valid(unit):
		result.hp = maxi(0, ceili(unit.hp)); result.max_hp = ceili(unit.max_hp)
		result.attack = unit.world.combat.attack_value(unit)
		result.defense = unit.world.combat.defence_value(unit)
		result.min = int(unit.stats.get("dmg_min", 0)); result.max = int(unit.stats.get("dmg_max", 0))
		result.armor = unit.stats.get("armor", armor)
		result.types = Array(unit.stats.get("dmg_types", PackedFloat32Array(types)))
		result.actions = unit.actions()
	var source: Dictionary = unit.stats if is_instance_valid(unit) else result
	result.regeneration = float(result.max_hp)*float(source.get("health_regen",race.get("health_regen",0.0)))/(GameUnit.TICK*15.0)*(1.0+float(source.get("regen_hp",0.0))/100.0)
	if is_instance_valid(unit):
		for buff: Dictionary in unit.buffs.values(): result.regeneration*=float(buff.get("regen_mul",1.0))
	return result


## Rank comparisons keep the same equipment and deployed alliance context. The
## selected rank reads the actual actor, including current combat effects.
static func rank_values(family: int, rank: int, unit: GameUnit = null, army: Array = [], item := "") -> Array[Dictionary]:
	var levels := {}
	var counts := ArenaAlliances.counts(army)
	for key: String in ArenaAlliances.RULES:
		levels[key] = ArenaAlliances.rank(key, counts[key]) if family in ArenaAlliances.RULES[key].families else 0
	if is_instance_valid(unit):
		item = String(unit.get_meta("arena_placement", {}).get("item", item))
		var fx := unit.world.arena_effects
		if fx and fx.active and fx.rows.has(unit.uid):
			for key: String in levels: levels[key] = fx._member(unit, key)
	var gear: Dictionary = ArenaItems.RULES.get(item, {})
	var rows: Array[Dictionary] = []
	for star in 3:
		var id := ArenaRules.prototype(family, star)
		var stats := values(id, null, family, star)
		stats.max_hp = ceili(stats.max_hp * (1.0 + levels.horde * 0.15) + float(gear.get("health", 0)))
		stats.hp = stats.max_hp
		stats.min = int(stats.min * (1.0 + levels.beast * 0.10) + float(gear.get("damage", 0)))
		stats.max = int(stats.max * (1.0 + levels.beast * 0.10) + float(gear.get("damage", 0)))
		stats.actions += float(gear.get("actions", 0)) + float(gear.get("frenzy", 0))
		for type in 3: stats.armor[type] = stats.armor[type] * (1.0 + levels.warrior * 0.30) + float(gear.get("physical_armor", 0))
		for type in range(3, 6): stats.armor[type] += float(gear.get("elemental_armor", 0))
		stats.regeneration *= float(stats.max_hp) / maxf(1.0, float(values(id, null, family, star).max_hp))
		if star == rank and is_instance_valid(unit): stats = values(id, unit, family, star)
		var proto := unit.proto if star == rank and is_instance_valid(unit) else ArenaRules.recruit_prototype(family, star, GameData.db.find("monster_prototypes", id))
		stats.spells = damaging_spells(proto, 1.0 + levels.mage * 0.15, float(gear.get("spell", 0)))
		stats.casting_disabled = ArenaItems.effect(item) == "berserker"
		if star == rank and is_instance_valid(unit):
			for buff: Dictionary in unit.buffs.values():
				if buff.get("no_cast", false): stats.casting_disabled = true
		rows.append(stats)
	return rows


## These are pre-armor hit/pulse amounts from the same parsed runes used by
## Spells._spell_damage. Do not add splash targets or triggered item damage.
static func damaging_spells(proto: Dictionary, multiplier := 1.0, bonus := 0.0) -> Array[Dictionary]:
	var spells: Array[Dictionary] = []
	for spell: String in proto.get("spells", []):
		var parsed := Spells.parse(spell)
		if not Spells.DAMAGE_SCHOOLS.has(parsed.code): continue
		var damage := float(parsed.effect) * multiplier + bonus
		var pulsed := int(parsed.duration) > 1
		if pulsed: damage *= 4.0 / float(parsed.duration)
		spells.append({"code":parsed.code, "damage":damage, "pulsed":pulsed,
			"school":Spells.DAMAGE_SCHOOLS[parsed.code]})
	return spells


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value)


## A group's common value: most of its three damage types share it. The
## other types are named, e.g. a troll's piercing hide, instead of a range.
static func _armor_base(armor: PackedFloat32Array, start: int) -> int:
	var values := [roundi(armor[start]), roundi(armor[start + 1]), roundi(armor[start + 2])]
	for value: int in values:
		if values.count(value) > 1: return value
	return values.min()


static func _armor_line(rows: Array[Dictionary], start: int, rank: int) -> String:
	var parts: Array[String] = []
	for stats: Dictionary in rows: parts.append(str(_armor_base(stats.armor, start)))
	var text := _series(parts, rank) if rows.size() == 3 else parts[0]
	for type in range(start, start + 3):
		var differs := rows.any(func(stats): return roundi(stats.armor[type]) != _armor_base(stats.armor, start))
		if not differs: continue
		var own: Array[String] = []
		for stats: Dictionary in rows: own.append(str(roundi(stats.armor[type])))
		text += " · " + RemakeText.t(WikiCatalog.DAMAGE_TYPES[type]) + " " + (_series(own, rank) if rows.size() == 3 else own[0])
	return text


static func _series(parts: Array[String], rank: int) -> String:
	var marked := parts.duplicate()
	marked[rank] = "[b]" + marked[rank] + "[/b]"
	return "/".join(marked)


static func summary(id: String, unit: GameUnit = null, family := -1, rank := 0, army: Array = [], item := "") -> String:
	if is_instance_valid(unit):
		var placement: Dictionary = unit.get_meta("arena_placement", {})
		family = -1 if placement.get("echo", false) else int(placement.get("family", family)); rank = int(placement.get("rank", rank))
	var rows: Array[Dictionary] = []
	if family >= 0: rows = rank_values(family, rank, unit, army, item)
	else: rows.append(values(id, unit))
	var current: Dictionary = rows[rank] if rows.size() == 3 else rows[0]
	if rows.size() == 1:
		current.spells = damaging_spells(unit.proto if is_instance_valid(unit) else GameData.db.find("monster_prototypes", id))
		current.casting_disabled = false
	var fields := {"Health":"max_hp", "Physical armor":"physical", "Elemental armor":"elemental", "Attack %s":"attack", "Defense":"defense", "Damage":"damage", "Action speed":"actions"}
	var lines: Array[String] = []
	for title: String in fields:
		var parts: Array[String] = []
		for stats: Dictionary in rows:
			match fields[title]:
				"damage": parts.append("%d–%d" % [stats.min, stats.max])
				"physical", "elemental": pass
				_: parts.append(_number(float(stats[fields[title]])))
		var value := _armor_line(rows, 0 if fields[title] == "physical" else 3, rank) if fields[title] in ["physical", "elemental"] \
			else _series(parts, rank) if rows.size() == 3 else parts[0]
		var line := RemakeText.t(title) % value if title.contains("%s") else RemakeText.t(title) + "  " + value
		if title == "Damage":
			var best := 6
			for type in current.types.size():
				if best >= current.types.size() or current.types[type] > current.types[best]: best = type
			line += " · " + RemakeText.t(WikiCatalog.DAMAGE_TYPES[best])
		lines.append(line)
	if int(current.hp) < int(current.max_hp): lines.insert(1, RemakeText.t("Remaining health: %d") % current.hp)
	if float(current.regeneration) > 0:
		var parts: Array[String] = []
		for stats: Dictionary in rows: parts.append("%.2f" % stats.regeneration)
		lines.append(RemakeText.t("Recovery: %s health/s") % (_series(parts, rank) if rows.size() == 3 else parts[0]))
	if not current.spells.is_empty():
		var names: Array[String] = []
		for index in current.spells.size():
			var spell: Dictionary = current.spells[index]
			var parts: Array[String] = []
			for stats: Dictionary in rows: parts.append(_number(stats.spells[index].damage))
			var title := RemakeText.t(WikiCatalog.spell_title(spell.code))
			names.append(title + " (" + (_series(parts, rank) if rows.size() == 3 else parts[0]) + (" · " + RemakeText.t("per pulse") if spell.pulsed else "") + ")")
		lines.append(RemakeText.t("Spells: ") + "; ".join(names))
		if current.casting_disabled: lines.append(RemakeText.t("Casting disabled"))
	var armor: PackedFloat32Array = current.armor
	var general := float(armor[6])
	var weak: Array[String] = []
	var strong: Array[String] = []
	for type in 6:
		if armor[type] < general: weak.append(RemakeText.t(WikiCatalog.DAMAGE_TYPES[type]))
		elif armor[type] > general: strong.append(RemakeText.t(WikiCatalog.DAMAGE_TYPES[type]))
	lines.append(RemakeText.t("Weaknesses: %s") % ", ".join(weak) if not weak.is_empty() else RemakeText.t("Weaknesses: none"))
	if not strong.is_empty(): lines.append(RemakeText.t("Resistant to: %s") % ", ".join(strong))
	return "\n".join(lines)


static func hook(family: int, rank: int) -> String:
	var text := RemakeText.t(ArenaRules.FAMILIES[family].hook)
	if family == ArenaExpansion.POPPER:
		var parts: Array[String] = []
		for damage in ArenaExpansion.POPPER_DAMAGE: parts.append(_number(float(damage)))
		text = text.replace("/".join(parts), _series(parts, rank))
	return text
