class_name ArenaCombatEffects
extends RefCounted
## A bell-time snapshot. No campaign item records, wall-clock timers or global RNG.
## Generated hits never trigger on-hit/cast bonuses. Original creatures can still
## trigger death traits, bounded independently by their per-battle limits.
const PROC := {"kind": "effect", "proc": true}
var world: GameWorld
var active := true
var rows := {}
var levels: Array[Dictionary] = []
var shields := {}
var venom := {}
var marks := {}
var spirit_used := [false, false]
var echoes := {}
var notices := {}
## Useful to native combat tests/benchmarks; not persisted or sent to clients.
var totals := {}

func _init(battle_world: GameWorld, army: Array, opponents: Array, preview := false) -> void:
	world = battle_world
	active = not preview
	for company in [army, opponents]:
		var count := ArenaAlliances.counts(company)
		var ranks := {}
		for key: String in ArenaAlliances.RULES: ranks[key] = ArenaAlliances.rank(key, count[key])
		levels.append(ranks)
	for u: GameUnit in world.unit_rows():
		var p: Dictionary = u.get_meta("arena_placement", {})
		var family := int(p.get("family", -1))
		var team := clampi(int(p.get("team", 1)), 0, 1)
		var item := String(p.get("item", ""))
		if not ArenaItems.RULES.has(item): item = ""
		rows[u.uid] = {"team": team, "family": family, "traits": ArenaAlliances.traits(family),
			"item": item, "hits": 0, "casts": 0, "used": false, "thorn_at": 0.0}
		_apply_stats(u)
		if not preview and ArenaItems.effect(item) == "berserker":
			u.buffs["arena_berserker"] = {"until": INF, "no_cast": true}
			_notice("berserker", u)

## Preparation and the bell use the same budget. Reapplying is idempotent.
## Alliances scale recruit stats; equipment adds a fixed amount afterwards.
func _apply_stats(u: GameUnit) -> void:
	if not u.has_meta("arena_combat_base"):
		u.set_meta("arena_combat_base", {"stats": u.stats.duplicate(true), "hp": u.max_hp})
	var base: Dictionary = u.get_meta("arena_combat_base")
	var stats: Dictionary = base.stats.duplicate(true)
	var gear: Dictionary = ArenaItems.RULES.get(_item(u), {})
	var damage := _member(u, "beast") * 0.10
	stats.dmg_min = float(stats.dmg_min) * (1.0 + damage) + float(gear.get("damage", 0.0))
	stats.dmg_max = float(stats.dmg_max) * (1.0 + damage) + float(gear.get("damage", 0.0))
	stats.actions = float(stats.get("actions", 15.0)) + float(gear.get("actions", 0.0)) + float(gear.get("frenzy", 0.0))
	var armor: PackedFloat32Array = stats.armor
	for type in 3: armor[type] = armor[type] * (1.0 + _member(u, "warrior") * 0.30) + float(gear.get("physical_armor", 0.0))
	for type in range(3, 6): armor[type] += float(gear.get("elemental_armor", 0.0))
	stats.armor = armor
	u.stats = stats
	u.max_hp = float(base.hp) * (1.0 + _member(u, "horde") * 0.15) + float(gear.get("health", 0.0))
	u.hp = u.max_hp

func spell_damage_multiplier(caster: GameUnit) -> float:
	if not active or not is_instance_valid(caster) or not rows.has(caster.uid): return 1.0
	return 1.0 + _member(caster, "mage") * 0.15

func spell_damage_bonus(caster: GameUnit) -> float:
	if not active or not is_instance_valid(caster) or not rows.has(caster.uid): return 0.0
	return float(_gear(caster).get("spell", 0.0))

## A preview applies stats without registering procs, buffs or combat timers.
static func preview(battle_world: GameWorld, army: Array, opponents: Array) -> void:
	ArenaCombatEffects.new(battle_world, army, opponents, true)

func stop() -> void:
	for uid: int in shields.keys(): _end_shield(uid)
	active = false
	for u: GameUnit in world.unit_rows(): u.buffs.erase("arena_berserker")

func tick() -> void:
	if not active: return
	for uid: int in shields.keys():
		if world.time >= float(shields[uid].until) or not alive(world.units.get(uid)): _end_shield(uid)
	for uid: int in echoes.keys():
		if world.time < float(echoes[uid]): continue
		echoes.erase(uid)
		var u: GameUnit = world.units.get(uid)
		if alive(u): u.die()

static func alive(u: GameUnit) -> bool:
	return is_instance_valid(u) and not u.dead and not GameUnit.is_dying_hp(u.hp)

func _member(u: GameUnit, trait_key: String) -> int:
	if not is_instance_valid(u) or not rows.has(u.uid): return 0
	var r: Dictionary = rows[u.uid]
	return int(levels[r.team][trait_key]) if trait_key in r.traits else 0

func _item(u: GameUnit) -> String:
	return String(rows.get(u.uid, {}).get("item", "")) if is_instance_valid(u) else ""

func _effect(u: GameUnit) -> String:
	return ArenaItems.effect(_item(u))

func _gear(u: GameUnit) -> Dictionary:
	return ArenaItems.RULES.get(_item(u), {})

func _near(origin: GameUnit, allies: bool, radius: float, except: GameUnit = null) -> Array[GameUnit]:
	var found: Array[GameUnit] = []
	for u: GameUnit in world.unit_rows():
		if u == origin or u == except or not alive(u): continue
		if world.is_enemy(origin, u) == allies: continue
		if origin.pos.distance_squared_to(u.pos) <= radius * radius: found.append(u)
	found.sort_custom(func(a: GameUnit, b: GameUnit):
		var da := origin.pos.distance_squared_to(a.pos)
		var db := origin.pos.distance_squared_to(b.pos)
		return a.uid < b.uid if is_equal_approx(da, db) else da < db)
	return found

func _notice(key: String, u: GameUnit, amount := 0.0, source: GameUnit = null) -> void:
	totals[key] = int(totals.get(key, 0)) + 1
	var gate := "%s:%d" % [key, u.uid]
	if world.time < float(notices.get(gate, -1.0)): return
	notices[gate] = world.time + 0.8
	if world.session: world.session.broadcast({"t": "arena_proc", "uid": u.uid, "effect": key, "amount": amount, "source":source.uid if is_instance_valid(source) else 0})

func _shield(u: GameUnit, amount: float, effect: String) -> void:
	# Shields replace a weaker remainder rather than creating multiplicative stacks.
	var current: Dictionary = shields.get(u.uid, {})
	var remaining := float(current.get("amount", 0.0)) if world.time < float(current.get("until", 0.0)) else 0.0
	shields[u.uid] = {"amount": maxf(remaining, amount), "until": world.time + 5.0}
	_notice(effect, u, amount)

func _end_shield(uid: int, broken := false) -> void:
	shields.erase(uid)
	if world.session:
		world.session.broadcast({"t":"arena_proc", "uid":uid, "effect":"shield_end", "broken":broken})

## Full board snapshots restore ongoing shields when scouting or reconnecting.
func shield_visual_state() -> Array:
	var state := []
	if active:
		for uid: int in shields:
			if alive(world.units.get(uid)) and world.time < float(shields[uid].until):
				state.append({"uid":uid, "secs":float(shields[uid].until) - world.time})
	return state

func _shield_left(u: GameUnit) -> float:
	var shield: Dictionary = shields.get(u.uid, {})
	return float(shield.get("amount", 0.0)) if world.time < float(shield.get("until", 0.0)) else 0.0

func before_damage(target: GameUnit, source: GameUnit, amount: float, context: Dictionary, part := -1) -> float:
	if not active or amount <= 0.0 or not alive(target): return amount
	# Native part damage is not necessarily HP damage (a head is smaller than
	# a torso). Shield budgets are consistently measured in whole HP.
	var health_scale := 1.0
	var part_cap := INF
	if part >= 0 and part < target.parts.size():
		var body_part: UnitBodyPart = target.parts[part]
		health_scale = body_part.lethal * target.max_hp / maxf(0.001, body_part.max)
		part_cap = maxf(0.0, body_part.cur) * health_scale
		if body_part.state < 2 or health_scale <= 0.0: return amount
	var left := amount * health_scale
	var exposed := maxf(0.0, left - _shield_left(target))
	if exposed > 0.0 and target.hp - minf(exposed, part_cap) <= target.max_hp * 0.35:
		if _effect(target) == "ward" and not rows[target.uid].used and float(_gear(target).shield) > _shield_left(target):
			rows[target.uid].used = true
			_shield(target, float(_gear(target).shield), "ward")
		for ally: GameUnit in _near(target, true, 5.0):
			exposed = maxf(0.0, left - _shield_left(target))
			if exposed <= 0.0 or target.hp - minf(exposed, part_cap) > target.max_hp * 0.35: break
			if _effect(ally) == "guardian" and not rows[ally.uid].used and float(_gear(ally).shield) > _shield_left(target):
				rows[ally.uid].used = true
				_shield(target, float(_gear(ally).shield), "guardian")
				break
	if shields.has(target.uid):
		var shield: Dictionary = shields[target.uid]
		if world.time < float(shield.until):
			var absorbed := minf(left, float(shield.amount))
			shield.amount -= absorbed
			left -= absorbed
			if float(shield.amount) <= 0.0: _end_shield(target.uid, true)
	return maxf(0.0, left / health_scale)

func healing_multiplier(u: GameUnit) -> float:
	var result := 1.0
	if active:
		for multiplier: float in venom.get(u.uid, {}):
			if world.time < float(venom[u.uid][multiplier]): result = minf(result, multiplier)
	return result

func after_damage(target: GameUnit, source: GameUnit, actual: float, context: Dictionary) -> void:
	if not active or actual <= 0.0 or context.get("proc", false) or not alive(source): return
	if not world.is_enemy(source, target): return
	var basic: bool = context.get("kind", "") == "attack"
	if basic and rows.has(source.uid):
		var r: Dictionary = rows[source.uid]
		r.hits += 1
		var gear := _gear(source)
		match _effect(source):
			"fang":
				var before := source.hp
				source.heal(float(gear.leech))
				if source.hp > before: _notice("fang", source, source.hp - before)
			"storm":
				if int(r.hits) % 3 == 0:
					var nearby := _near(source, false, 4.0, target)
					for victim: GameUnit in nearby.slice(0, int(gear.storm_targets)):
						_packet(source, victim, float(gear.storm_damage), 5, "storm")
			"venom":
				if not venom.has(target.uid): venom[target.uid] = {}
				venom[target.uid][1.0 - float(gear.healing_reduction)] = world.time + 5.0
				_notice("venom", target)
	if basic and not context.get("ranged", false) and alive(target) and _effect(target) == "thorn":
		var r: Dictionary = rows[target.uid]
		if world.time >= float(r.thorn_at):
			r.thorn_at = world.time + 1.0
			_packet(target, source, float(_gear(target).reflect), 2, "thorn")

func _packet(source: GameUnit, target: GameUnit, amount: float, school: int, effect: String) -> void:
	if not alive(source) or not alive(target) or amount <= 0.0: return
	var types := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	if school < 0: types = source.stats.get("dmg_types", PackedFloat32Array([0,0,1,0,0,0,0]))
	else: types[clampi(school, 0, 6)] = 1.0
	var reduced := world.combat.absorb(target, amount, types)
	# Elemental procs respect the same protection buffs as native spells.
	if school in [3, 4, 5]:
		var element: String = ["fire", "acid", "lightning"][school - 3]
		var protection := 0.0
		for buff: Dictionary in target.buffs.values():
			if buff.get("resist", "") in [element, "all"]: protection = maxf(protection, float(buff.get("armor", 0.0)))
		reduced = maxf(Combat.armor_minimum(target, amount), reduced - protection * world.combat.difficulty(target, "Absorption"))
	_notice(effect, target, reduced, source)
	target.take_damage(reduced, source, -1, PackedFloat32Array(), 4 if school == 5 else 0, Callable(), false, PROC)

func on_cast(caster: GameUnit, spell: String, target: GameUnit, point: Vector2) -> void:
	if not active or not alive(caster): return
	var parsed := Spells.parse(spell)
	if parsed.proto.is_empty(): return
	# One call at dispatch, outside multi-target and persistent-damage loops.
	for team in 2:
		if levels[team].hunter > 0 and _team(caster) != team:
			marks[team] = {"uid": caster.uid, "until": world.time + 3.0}
			_notice("marked", caster)
	if not Spells.DAMAGE_SCHOOLS.has(parsed.code): return
	var school := int(Spells.DAMAGE_TYPE_INDEX.get(Spells.DAMAGE_SCHOOLS[parsed.code], 6))
	if not is_instance_valid(target):
		var candidates := _near(caster, false, float(parsed.get("range", 12.0)))
		candidates.sort_custom(func(a: GameUnit, b: GameUnit):
			var da := a.pos.distance_squared_to(point)
			var db := b.pos.distance_squared_to(point)
			return a.uid < b.uid if is_equal_approx(da, db) else da < db)
		target = candidates[0] if not candidates.is_empty() else null
	if _effect(caster) == "echo":
		var r: Dictionary = rows[caster.uid]
		r.casts += 1
		if int(r.casts) % int(_gear(caster).echo_every) == 0: _packet(caster, target, float(_gear(caster).echo_damage), school, "echo")

func _team(u: GameUnit) -> int:
	return int(rows[u.uid].team) if rows.has(u.uid) else int(u.get_meta("arena_placement", {}).get("team", 1))

func target_bonus(u: GameUnit, candidate: GameUnit, option: Dictionary) -> float:
	if not active or not alive(candidate) or not rows.has(u.uid): return 0.0
	# A preference is never permission to shoot through a screen or cross the board.
	var reach := float(option.get("range", 0.0))
	if int(option.get("type", 0)) == 0:
		reach = float(u.stats.get("reach", 0.0)) if u.stats.get("ranged", false) else u.melee_reach(candidate)
	if u.pos.distance_to(candidate.pos) > reach: return 0.0
	var team := _team(u)
	var mark: Dictionary = marks.get(team, {})
	if not mark.is_empty() and int(mark.uid) == candidate.uid and world.time < float(mark.until):
		if levels[team].hunter >= 2 or _member(u, "hunter") > 0: return 1000.0
	return 0.0

func on_death(fallen: GameUnit, killer: GameUnit) -> void:
	if not active or not rows.has(fallen.uid): return
	var team := _team(fallen)
	var level := _member(fallen, "spirit")
	if level > 0 and not spirit_used[team]:
		spirit_used[team] = true
		var helped := 0
		for ally: GameUnit in _near(fallen, true, 5.0):
			if ally.hp >= ally.max_hp: continue
			var before := ally.hp
			ally.heal(fallen.max_hp * 0.12)
			_notice("spirit", ally, ally.hp - before, fallen)
			helped += 1
			if helped >= level: break
		if level >= 2: _spawn_echo(fallen)

func _spawn_echo(fallen: GameUnit) -> void:
	var placement := {"id": "willowispm1", "team": _team(fallen), "family": -1, "rank": 0,
		"point": fallen.pos, "echo": true, "item": ""}
	# Use the same factory as recruits: it fits the body and disables automatic
	# figure processing in headless simulations, which advance models explicitly.
	var arena := world.session as ArenaPveMatch
	if arena == null: return
	var u := arena._spawn(placement)
	if not is_instance_valid(u): return
	u.controller = -1; u.mode = "aggression"
	u.display_name = RemakeText.t("Spirit echo")
	ArenaRules.recruit_stats(21, 0, u.stats)
	u.proto = ArenaRules.recruit_prototype(21, 0, u.proto)
	u.max_hp = maxf(1.0, fallen.max_hp * 0.20); u.hp = u.max_hp
	world.ai.set_post(u, fallen.pos)
	u._sync_transform(); world.nav.track_unit(u)
	var known := {}
	for other: GameUnit in world.unit_rows():
		if world.is_enemy(u, other):
			known[other.get_instance_id()] = other
			var seen: Dictionary = other.get_meta("noticed", {})
			seen[u.get_instance_id()] = u
			other.set_meta("noticed", seen)
	u.set_meta("noticed", known)
	u.set_meta("arena_opening", true)
	echoes[u.uid] = world.time + 6.0
	_notice("spirit_echo", u)
