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
var pack := {}
var pack_ready := {}
var chorus := [{}, {}]
var chorus_ready := [0.0, 0.0]
var rallies := [{}, {}]
var spirit_used := [false, false]
var echoes := {}
var notices := {}
## Useful to native combat tests/benchmarks; not persisted or sent to clients.
var totals := {}

func _init(battle_world: GameWorld, army: Array, opponents: Array) -> void:
	world = battle_world
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
			"item": item, "hits": 0, "casts": 0, "used": false, "thorn_at": 0.0,
			"guard": u.max_hp * (0.12 if levels[team].warrior == 1 else 0.20)}
		if item == "berserker":
			u.buffs["arena_berserker"] = {"until": INF, "actions_add": float(u.stats.get("actions", 15.0)) * 0.25, "no_cast": true}

func stop() -> void:
	active = false
	for u: GameUnit in world.unit_rows(): u.buffs.erase("arena_berserker")

func tick() -> void:
	if not active: return
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

func _notice(key: String, u: GameUnit, amount := 0.0) -> void:
	totals[key] = int(totals.get(key, 0)) + 1
	var gate := "%s:%d" % [key, u.uid]
	if world.time < float(notices.get(gate, -1.0)): return
	notices[gate] = world.time + 0.8
	if world.session: world.session.broadcast({"t": "arena_proc", "uid": u.uid, "effect": key, "amount": amount})

func _shield(u: GameUnit, amount: float, effect: String) -> void:
	# Shields replace a weaker remainder rather than creating multiplicative stacks.
	var current: Dictionary = shields.get(u.uid, {})
	var remaining := float(current.get("amount", 0.0)) if world.time < float(current.get("until", 0.0)) else 0.0
	shields[u.uid] = {"amount": maxf(remaining, amount), "until": world.time + 5.0}
	_notice(effect, u, amount)

func _shield_left(u: GameUnit) -> float:
	var shield: Dictionary = shields.get(u.uid, {})
	return float(shield.get("amount", 0.0)) if world.time < float(shield.get("until", 0.0)) else 0.0

func before_damage(target: GameUnit, source: GameUnit, amount: float, context: Dictionary, part := -1) -> float:
	if not active or amount <= 0.0 or not alive(target): return amount
	# Native part damage is not necessarily HP damage (a head is smaller than
	# a torso). Shield and guard budgets are consistently measured in whole HP.
	var health_scale := 1.0
	var part_cap := INF
	if part >= 0 and part < target.parts.size():
		var body_part: UnitBodyPart = target.parts[part]
		health_scale = body_part.lethal * target.max_hp / maxf(0.001, body_part.max)
		part_cap = maxf(0.0, body_part.cur) * health_scale
		if body_part.state < 2 or health_scale <= 0.0: return amount
	var left := amount * health_scale
	# One nearby guard per impact; spending its finite pool never causes a hit.
	if not context.get("proc", false):
		for guard: GameUnit in _near(target, true, 3.0):
			var level := _member(guard, "warrior")
			if level == 0 or (context.get("kind", "") != "attack" and not (level >= 2 and context.get("kind", "") == "spell")): continue
			var r: Dictionary = rows[guard.uid]
			var blocked := minf(left * 0.4, float(r.guard))
			if blocked <= 0.0: continue
			r.guard -= blocked
			left -= blocked
			_notice("guard", target, blocked)
			break
	var exposed := maxf(0.0, left - _shield_left(target))
	if exposed > 0.0 and target.hp - minf(exposed, part_cap) <= target.max_hp * 0.35:
		if _item(target) == "ward" and not rows[target.uid].used and target.max_hp * 0.25 > _shield_left(target):
			rows[target.uid].used = true
			_shield(target, target.max_hp * 0.25, "ward")
		for ally: GameUnit in _near(target, true, 5.0):
			exposed = maxf(0.0, left - _shield_left(target))
			if exposed <= 0.0 or target.hp - minf(exposed, part_cap) > target.max_hp * 0.35: break
			if _item(ally) == "guardian" and not rows[ally.uid].used and ally.max_hp * 0.20 > _shield_left(target):
				rows[ally.uid].used = true
				_shield(target, ally.max_hp * 0.20, "guardian")
				break
	if shields.has(target.uid):
		var shield: Dictionary = shields[target.uid]
		if world.time < float(shield.until):
			var absorbed := minf(left, float(shield.amount))
			shield.amount -= absorbed
			left -= absorbed
	return maxf(0.0, left / health_scale)

func healing_multiplier(u: GameUnit) -> float:
	return 0.5 if active and world.time < float(venom.get(u.uid, -1.0)) else 1.0

func after_damage(target: GameUnit, source: GameUnit, actual: float, context: Dictionary) -> void:
	if not active or actual <= 0.0 or context.get("proc", false) or not alive(source): return
	if not world.is_enemy(source, target): return
	var basic: bool = context.get("kind", "") == "attack"
	if basic and rows.has(source.uid):
		var r: Dictionary = rows[source.uid]
		r.hits += 1
		match String(r.item):
			"fang":
				var before := source.hp
				source.heal(minf(actual * 0.20, source.max_hp * 0.02))
				if source.hp > before: _notice("fang", source, source.hp - before)
			"storm":
				if int(r.hits) % 3 == 0:
					var nearby := _near(source, false, 4.0, target)
					if not nearby.is_empty(): _packet(source, nearby[0], source.max_hp * 0.10, 5, "storm")
			"venom":
				venom[target.uid] = world.time + 5.0
				_notice("venom", target)
	if basic and not context.get("ranged", false) and alive(target) and _item(target) == "thorn":
		var r: Dictionary = rows[target.uid]
		if world.time >= float(r.thorn_at):
			r.thorn_at = world.time + 1.0
			_packet(target, source, minf(actual * 0.15, target.max_hp * 0.03), 2, "thorn")
	if not context.get("periodic", false) and (basic or context.get("kind", "") == "spell"):
		_pack_hit(source, target)

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
	_notice(effect, target, reduced)
	target.take_damage(reduced, source, -1, PackedFloat32Array(), 4 if school == 5 else 0, Callable(), false, PROC)

func _budget(u: GameUnit) -> float:
	return (float(u.stats.get("dmg_min", 1.0)) + float(u.stats.get("dmg_max", 1.0))) * 0.5

func _pack_hit(source: GameUnit, target: GameUnit) -> void:
	var level := _member(source, "beast")
	if level == 0: return
	var family := int(rows[source.uid].family)
	var key := "%d:%d" % [int(rows[source.uid].team), target.uid]
	var previous: Dictionary = pack.get(key, {})
	pack[key] = {"family": family, "until": world.time + 2.0, "target": target.uid, "team": int(rows[source.uid].team)}
	if previous.is_empty() or int(previous.family) == family or world.time >= float(previous.until): return
	if world.time < float(pack_ready.get(key, -1.0)): return
	pack_ready[key] = world.time + 2.0
	_packet(source, target, _budget(source) * 0.45, -1, "pack")
	if level >= 3:
		var others := _near(target, true, 3.0)
		if not others.is_empty(): _packet(source, others[0], _budget(source) * 0.45, -1, "pack")

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
	if _item(caster) == "echo":
		var r: Dictionary = rows[caster.uid]
		r.casts += 1
		if int(r.casts) % 3 == 0: _packet(caster, target, _budget(caster) * 0.35, school, "echo")
	var level := _member(caster, "mage")
	if level == 0: return
	var team := _team(caster)
	var last: Dictionary = chorus[team]
	chorus[team] = {"uid": caster.uid, "until": world.time + 4.0, "power": _budget(caster)}
	if last.is_empty() or int(last.uid) == caster.uid or world.time >= float(last.until) or world.time < float(chorus_ready[team]): return
	chorus_ready[team] = world.time + 2.0
	var power := (_budget(caster) + float(last.power)) * 0.25
	_packet(caster, target, power, school, "reaction")
	if level >= 2 and is_instance_valid(target):
		var others := _near(target, true, 3.0)
		if not others.is_empty(): _packet(caster, others[0], power, school, "reaction")

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
	var key := "%d:%d" % [team, candidate.uid]
	var prey: Dictionary = pack.get(key, {})
	if _member(u, "beast") >= 2 and not prey.is_empty() and world.time < float(prey.until): return 500.0
	return 0.0

func on_death(fallen: GameUnit, killer: GameUnit) -> void:
	if not active or not rows.has(fallen.uid): return
	var team := _team(fallen)
	var level := _member(fallen, "horde")
	var family := int(rows[fallen.uid].family)
	if level > 0 and rallies[team].size() < level and not rallies[team].has(family):
		rallies[team][family] = true
		for ally: GameUnit in _near(fallen, true, 5.0):
			if _member(ally, "horde") == 0: continue
			var targets := _near(ally, false, float(ally.stats.get("reach", 1.3)) + 0.8)
			if not targets.is_empty(): _packet(ally, targets[0], _budget(ally) * 0.45, -1, "rally")
	level = _member(fallen, "spirit")
	if level > 0 and not spirit_used[team]:
		spirit_used[team] = true
		var helped := 0
		for ally: GameUnit in _near(fallen, true, 5.0):
			if ally.hp >= ally.max_hp: continue
			ally.heal(fallen.max_hp * 0.12)
			_notice("spirit", ally)
			helped += 1
			if helped >= level: break
		if level >= 2: _spawn_echo(fallen)
	# Deeper packs carry a defeated target's focus to the nearest surviving foe.
	var opposing := 1 - team
	var key := "%d:%d" % [opposing, fallen.uid]
	if levels[opposing].beast >= 2 and pack.has(key) and world.time < float(pack[key].until):
		var nearby := _near(fallen, true, 5.0)
		if not nearby.is_empty():
			var next: Dictionary = pack[key].duplicate()
			next.target = nearby[0].uid; next.until = world.time + 4.0
			pack["%d:%d" % [opposing, nearby[0].uid]] = next

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
