class_name Spells
extends RefCounted
## Spells from spells.sdb. A spell is "<code>{mod;mod;...}" (e.g.
## "acid_ray{e1;e1}"): a prototype plus modifiers that scale range, area,
## effect, duration and mana. The effect formulas approximate the original.

const TARGET_POINT := 116
const DAMAGE_TYPES := ["fire", "lightning", "acid"]
## Damage type slot (piercing .. general) of each elemental school.
const DAMAGE_TYPE_INDEX := {"fire": 3, "acid": 4, "lightning": 5}
const PROTECTS := {"prot_fire": "fire", "prot_electro": "lightning", "prot_acid": "acid"}

static var _cache := {}


static func parse(spell: String) -> Dictionary:
	spell = spell.strip_edges().to_lower()
	if _cache.has(spell):
		return _cache[spell]
	var code := spell.get_slice("{", 0).strip_edges()
	var mods := PackedStringArray()
	if "{" in spell:
		mods = spell.get_slice("{", 1).trim_suffix("}").replace(",", ";").split(";", false)
	var proto := {}
	for row in GameData.db.table("spell_prototypes"):
		if String(row.get("code", "")).to_lower() == code:
			proto = row
			break
	var p := {"id": spell, "code": code, "proto": proto, "name": String(proto.get("name", code.capitalize())),
		"subtype": String(proto.get("subtype", "")).to_lower(),
		"mana": float(proto.get("mana", 10.0)), "range": float(proto.get("range", 10.0)),
		"area": float(proto.get("area", 0.0)), "effect": float(proto.get("effect", 5.0)),
		"duration": float(proto.get("duration", 10.0)), "targets": int(proto.get("targets", 1)),
		"complex": float(proto.get("complex", 0.0)), "price": float(proto.get("price", 0.0)),
		"point": int(proto.get("target", 117)) == TARGET_POINT,
		# Spell flags (builder): prototype target 0x75
		# 0x74 (point) ->; item runes ic / it ->; the
		# low word is the filter mask, "filter" below.
		"flags": {117: 0x10000000, 116: 0x20000000}.get(int(proto.get("target", 117)), 0),
		"filter": 0}
	# the original spell builder: a rune whose code starts with e / a
	# r / d / t / m adds value x the prototype's effect / area / range / duration /
	# targets / mana; every rune adds its own mana, complexity and price. The area
	# becomes a radius sqrt(area / pi); the cost never drops below the prototype's.
	for m in mods:
		var row := mod_row(m.strip_edges())
		if row.is_empty():
			continue
		var v := float(row.get("value", 0.0))
		match m.strip_edges().substr(0, 1):
			"a": p.area = maxf(0.0, p.area + v * float(proto.get("area", 0.0)))
			"e": p.effect = maxf(0.0, p.effect + v * float(proto.get("effect", 0.0)))
			"r": p.range = maxf(0.0, p.range + v * float(proto.get("range", 0.0)))
			"m": p.mana = maxf(0.0, p.mana + v * float(proto.get("mana", 0.0)))
			"d": p.duration = maxf(0.0, p.duration + int(v * float(proto.get("duration", 0.0))))
			"t": p.targets += int(v * float(proto.get("targets", 0.0)))
			"f":
				#  case 'f': fe 2, ff 1, fg 8, fh 4, fl 0x20, fo 0x10.
				p.filter |= int({"e": 2, "f": 1, "g": 8, "h": 4, "l": 0x20, "o": 0x10}.get(m.strip_edges().substr(1, 1), 0))
			"i":
				p.flags |= int({"c": 0x20000, "t": 0x10000}.get(m.strip_edges().substr(1, 1), 0))
		p.mana += float(row.get("mana", 0.0))
		p.complex += float(row.get("complex", 0.0))
		p.price += float(row.get("price", 0.0))
	p.radius = sqrt(p.area / PI) if p.area > 0.0 else 0.0
	p.mana = maxf(p.mana, float(proto.get("mana", 0.0)))
	_cache[spell] = p
	return p


## the original: spells a belt item casts at an enemy, by prototype
## index (spells.sdb order): the elemental attacks 0-8 and 17, 19, 25, 30, 32,
## 34, 36, 38 (Stench, Stun, Weaken, Feeblemind, Slow, Charm, Shrink ...).
const OFFENSIVE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 17, 19, 25, 30, 32, 34, 36, 38]


static func offensive(spell: String) -> bool:
	var proto: Dictionary = parse(spell).proto
	return not proto.is_empty() and GameData.db.table("spell_prototypes").find(proto) in OFFENSIVE


static func title(spell: String) -> String:
	var p := parse(spell)
	var t := GameData.text("spell " + String(p.code))
	var base := t.get_slice("\n", 0).strip_edges() if t else String(p.name)
	var mods := mods_of(spell)
	if mods.is_empty():
		return base
	var counts := {}
	for m in mods:
		counts[m] = int(counts.get(m, 0)) + 1
	var parts := []
	for m: String in counts:
		parts.append(mod_title(m) + (" x%d" % counts[m] if counts[m] > 1 else ""))
	return "%s (%s)" % [base, ", ".join(parts)]


static func mods_of(spell: String) -> PackedStringArray:
	spell = spell.strip_edges().to_lower()
	if not "{" in spell:
		return PackedStringArray()
	var out := PackedStringArray()
	for m in spell.get_slice("{", 1).trim_suffix("}").replace(",", ";").split(";", false):
		out.append(m.strip_edges())
	return out


static func mod_row(code: String) -> Dictionary:
	for r in GameData.db.table("spell_modifiers"):
		if String(r.get("code", "")).to_lower() == code.to_lower():
			return r
	return {}


static func mod_title(code: String) -> String:
	var t := GameData.text("modifier " + code.to_lower()).get_slice("\n", 0).strip_edges()
	return t if t else String(mod_row(code).get("name", code))


const MAX_MODS := 8   # original: up to 8 runes per spell


## Complexity: the keystone's plus each rune's (spells.sdb "complex"; builder).
static func complexity(spell: String) -> float:
	return float(parse(spell).complex)


## A hero can take a spell only with enough knowledge of its school and enough
## stamina for its cost (camphelp 106).
static func usable_by(h: Dictionary, max_stamina: float, spell: String) -> bool:
	var p := parse(spell)
	return Skills.knowledge(h, String(p.subtype)) >= complexity(spell) and max_stamina >= float(p.mana)


## Whether rune `code` fits spell `spell` (the prototype's mods flags allow its
## type: range, targets, area, effect, duration; mana runes always fit).
static func can_add(spell: String, code: String) -> bool:
	var row := mod_row(code)
	if row.is_empty() or mods_of(spell).size() >= MAX_MODS:
		return false
	var type := int(row.get("type", 9))
	if type == 5:
		return true
	if type == 6:
		# Target filters: one per area spell.
		return code.to_lower().begins_with("f") and float(parse(spell).area) > 0.0 \
			and int(parse(spell).get("filter", 0)) == 0
	if type > 4:
		return false
	var allowed = parse(spell).proto.get("mods", [])
	return type < allowed.size() and int(allowed[type]) == 1


static func with_mod(spell: String, code: String) -> String:
	var mods := mods_of(spell)
	mods.append(code.to_lower())
	return "%s{%s}" % [parse(spell).code, ";".join(mods)]


## Spells whose effect lights the target point for their duration
## (cases 0x12 fireworks, 0x14 clairvoyance, 0x27 campfire).
static func light_time(spell: String) -> float:
	var p := parse(spell)
	return float(p.duration) * GameUnit.TICK if p.code in ["fireworks", "clairvoyence", "campfire"] else 0.0


static func is_hostile(spell: String) -> bool:
	var p := parse(spell)
	return p.subtype in DAMAGE_TYPES or p.code in ["weak", "slow", "stun", "feeblemind", "silence"]


## Host: apply a spell cast by `caster` at a unit or ground point.
static func apply(world: GameWorld, caster: GameUnit, spell: String, target: GameUnit, point: Vector2) -> void:
	var p := parse(spell)
	var at := target.pos if target else point
	# Spell power comes from its runes [allods.gipat.ru FAQ]; skills and school
	# perks only raise the allowed complexity.
	var power: float = p.effect
	var radius: float = p.radius
	var victims: Array = []
	if radius > 0.2:
		var filter := int(p.get("filter", 0))
		victims = world.units_near(at, radius).filter(func(u): return not u.dead and u != caster \
			and (u == target or caster == null or passes_filter(world, caster, u, filter)))
	elif target:
		victims = [target]
	# Durations count 55 ms logic ticks (the effect object lives max(duration, n) + 30
	# ticks). Lasting effects are "magic effects" whose type is the
	# spell index; fold them into stats.
	var secs: float = float(p.duration) * GameUnit.TICK
	if p.code == "fireworks":
		#  case 0x12: every tick of its duration, the units within
		# the effect radius (the light reaches 5 m further) suspect the
		# point at trunc(counter / duration x 250 + 50), -1 a tick, replacing
		# lower levels. Approx.: once at the cast (300, -1)
		# the same while the duration is at most 250 ticks, as the decayed
		# level then stays above the later ones, for units already there.
		for u: GameUnit in world.units_near(at, maxf(radius, 0.0)):
			world.ai.suspect(u, at, 300.0, -1.0)
	# Lasting spells show a magic effect on each unit (visual only).
	# Every lasting effect is sent, also those with no particles (their
	# start / end sounds, SpellSounds.EFFECT_DIRS).
	if world.session and (ParticleFx.MAGIC_TYPES.has(p.code) or p.code in ["lichdom", "strength", "weak",
			"invisibility", "stun", "enlarge", "shrink"]):
		for u: GameUnit in victims:
			world.session.broadcast({"t": "magicfx", "uid": u.uid, "code": p.code, "secs": secs,
				"s": ParticleFx.strength(p)})
	match String(p.code):
		"healing":   # Heal(effect)
			for u: GameUnit in victims:
				u.heal(power)
		"regeneration":   # health regeneration x effect
			for u: GameUnit in victims:
				_buff(u, "regeneration", secs, {"regen_mul": power})
		"strength":   # damage x (1 + 0.003 s) / (1 + 0.003 w); HP likewise with 0.005
			for u: GameUnit in victims:
				_buff(u, "strength", secs, {"dmg_mul": 1.0 + 0.003 * power, "hp_mul": 1.0 + 0.005 * power})
		"weak":
			for u: GameUnit in victims:
				_buff(u, "weak", secs, {"dmg_mul": 1.0 / (1.0 + 0.003 * power), "hp_mul": 1.0 / (1.0 + 0.005 * power)})
		"speed":   # speed - slow is added to actions (attack rate)
			for u: GameUnit in victims:
				_buff(u, "speed", secs, {"actions_add": power})
		"slow":
			for u: GameUnit in victims:
				_buff(u, "slow", secs, {"actions_add": -power})
		"prot_fire", "prot_electro", "prot_acid":
			#  adds protection effects to the armour of that type.
			for u: GameUnit in victims:
				_buff(u, p.code, secs, {"resist": PROTECTS[p.code], "armor": power})
		"antimagic":   # protects against all three elements (max with the single ones)
			for u: GameUnit in victims:
				_buff(u, "antimagic", secs, {"resist": "all", "armor": power})
		"stun":
			for u: GameUnit in victims:
				_buff(u, "stun", secs, {"stun": true})
		"feeblemind":   # a flag that refuses spell-casting orders
			for u: GameUnit in victims:
				_buff(u, "feeblemind", secs, {"no_cast": true})
		# senses and detectability (GameUnit.sense / detect).
		"invisibility":   # sight detectability - effect / 100
			for u: GameUnit in victims:
				_buff(u, "invisible", secs, {"detect": [0, -power * 0.01]})
		"lichdom":   # life-sense detectability - effect
			for u: GameUnit in victims:
				_buff(u, "lichdom", secs, {"detect": [2, -power]})
		"silence":   # hearing detectability - effect
			for u: GameUnit in victims:
				_buff(u, "silence", secs, {"detect": [3, -power]})
		"stench":   # smell detectability + effect
			for u: GameUnit in victims:
				_buff(u, "stench", secs, {"detect": [4, power]})
		"charm":   #  case 0x24: repeated until the target is on the caster's side
			for u: GameUnit in victims:
				var ok := true
				#  is the owning side: for a hero, its player's party.
				while ok and (u.faction != caster.faction or u.controller != caster.controller):
					ok = tame(world, caster, u, power)
				if not ok and world.session:
					world.session.failed(caster, 7)   # "Can't charm"
		"vision_fog":   #  case 0x17: needs a caster and a target unit
			if target and caster and world.session:
				world.session.broadcast({"t": "vision_fog", "uid": target.uid, "to": caster.controller, "secs": secs})
		"teleport":
			#  case 0x1c: effects at the destination (the target unit or
			# point) and at the caster; the effect lives duration + 30 ticks, then
			# the caster arrives (the move at the effect's end is inferred).
			var dest := world.nav.nearest_walkable(at)
			world.get_tree().create_timer((float(p.duration) + 30.0) * GameUnit.TICK).timeout.connect(func():
				if is_instance_valid(caster) and not caster.dead:
					caster.pos = dest
					caster.path = PackedVector2Array()
					caster.order = {}
					caster.orders.clear())
		"eagle_sight", "infravision", "detect_life":   # effect added to sight / night sight / life sense
			for u: GameUnit in victims:
				_buff(u, p.code, secs, {"sense": [["eagle_sight", "infravision", "detect_life"].find(p.code), power]})
		_:
			if p.subtype in DAMAGE_TYPES:
				for u: GameUnit in victims:
					# Same per-type armour as weapons: fire is
					# thermal, acid chemical, lightning electrical.
					var t := int(DAMAGE_TYPE_INDEX.get(p.subtype, 6))
					var armour: PackedFloat32Array = u.stats.get("armor", PackedFloat32Array())
					var dmg := power - (armour[t] * world.combat.difficulty(u, "Absorption") if t < armour.size() else 0.0)
					var prot := 0.0
					for b in u.buffs.values():
						if b.get("resist", "") in [p.subtype, "all"]:
							prot = maxf(prot, float(b.get("armor", 0.0)))
					dmg -= prot
					if dmg > 0.0:
						u.take_damage(dmg, caster)


## Host: a cast without a caster (script CastSpellPoint / CastSpellUnit,
## magic traps), the original (spell, caster 0, , target, point):
## possession, link and charm (prototypes 0x15, 0x1b, 0x24) are never cast
## this way. A spell with one target and no filter runes (low word)
## is cast directly. Otherwise a point spell (flag
## not item-continuous) is first cast once at the point; then the
## candidates are the units within its range of `from`
## the target unit moved to the front. Until the spell has had its targets
## take the target unit if it lives, else the living unit nearest the
## point (dead ones are dropped), remove it, and cast at it when it passes the
## trace check (`_trace_ok`) and the filter; only
## those casts count. `from_z` is the source height (scripts pass 0).
static func cast_from(world: GameWorld, spell: String, from: Vector2, target: GameUnit, point: Vector2, from_z := 0.0) -> void:
	var p := parse(spell)
	if p.proto.is_empty() or p.code in ["possession", "link", "charm"]:
		return
	var n := int(p.targets)
	var mask := int(p.filter)
	var flags := int(p.flags)
	if mask == 0 and n < 2:
		_cast_one(world, spell, p, from, target, target.pos if target else point)
		return
	if flags & 0x20000000 and not flags & 0x20000:
		n -= 1
		_cast_one(world, spell, p, from, target, point)
	var pool: Array = world.units_near(from, float(p.range))
	if target:
		pool.erase(target)
		pool.push_front(target)
	while n > 0:
		var pick: GameUnit = null
		var best := INF
		for u: GameUnit in pool.duplicate():
			if u.dead:
				pool.erase(u)
				continue
			if u == target:
				pick = u
				break
			var d := u.pos.distance_squared_to(point)
			if d < best:
				best = d
				pick = u
		if pick == null:
			break
		pool.erase(pick)
		if _trace_ok(world, p, from, from_z, pick) and passes_filter(world, null, pick, mask):
			_cast_one(world, spell, p, from, pick, pick.pos)
			n -= 1


static func _cast_one(world: GameWorld, spell: String, p: Dictionary, from: Vector2, tu: GameUnit, at: Vector2) -> void:
	apply(world, null, spell, tu, at)
	if world.session:
		world.session.broadcast({"t": "spellfx", "code": p.code, "sub": p.subtype, "x": at.x, "y": at.y,
			"a": -1, "tu": tu.uid if tu else -1, "spell": spell, "fx": from.x, "fy": from.y,
			"hold": light_time(spell)})


##  with no caster: a spell whose prototype needs a trace
## (spells.sdb require_trace) reaches a unit only when the terrain ray
##  from the source (, from_z) to the unit at ground + its
## height (: 1.8 x the figure's half z extent, x 0.7 kneeling)
## is at least 0.1.
static func _trace_ok(world: GameWorld, p: Dictionary, from: Vector2, from_z: float, u: GameUnit) -> bool:
	if int(p.proto.get("require_trace", 0)) == 0:
		return true
	var h := 1.8 * u.figure_half_z * (0.7 if u.stance == GameUnit.STANCE_KNEEL else 1.0)
	return world.terrain_ray(from, from_z, u.pos, world.ground_at(u.pos.x, u.pos.y) + h) >= 0.1


## Taming, the original: it works when `power` exceeds the target's
## level x 10 + its tame value (prototype "tame skills"; "base level" is taken
## as the level, inferred). Each success advances one stage: 1 the target stops
## being hostile to the tamer's side, 2 it takes the tamer's side, 3 it joins
## the tamer's party. On failure, or if a player already owns it, it attacks.
static func tame(world: GameWorld, tamer: GameUnit, u: GameUnit, power: float) -> bool:
	if u.dead or u.has_meta("hero") or u.controller >= 0:
		return false
	var need := float(u.proto.get("base_level", 0)) * 10.0 + float(u.proto.get("tame_skills", 0.0))
	if power <= need:
		world.ai.on_attacked(u, tamer)
		return false
	var stage := int(u.get_meta("tame_stage", 0)) + 1
	u.set_meta("tame_stage", stage)
	match stage:
		1:
			var peace: Array = u.get_meta("peace", [])
			peace.append(tamer.faction)
			u.set_meta("peace", peace)
			u.orders.clear()
			u.order = {}
			u.target = null
		2:
			u.faction = tamer.faction
		_:
			u.faction = tamer.faction
			u.controller = tamer.controller
			u.mode = "player"
	return true   # no text-window line (shows nothing)


## Spell filter, the original (spell flags low word, set
## the filter runes): no bits -> every unit. With a caster, ff
## (1) drops units hostile to or from the caster's side, fe (2) the ones that
## are not. The race runes drop that race by figure name: fh (4) unhuma /
## unhufe, fg (8) unmogo, fo (0x10) unorma / unorfe, fl (0x20) unmoli — they
## protect the race, though the rune texts say "only affects" it.
static func passes_filter(world: GameWorld, caster: GameUnit, u: GameUnit, mask: int) -> bool:
	if mask & 0xffff == 0:
		return true
	if caster:
		var hostile := world.is_enemy(caster, u) or world.is_enemy(u, caster)
		if (mask & 1 and hostile) or (mask & 2 and not hostile):
			return false
	var fig := String(u.model.template).to_lower() if u.model else ""
	for bit: int in RACE_FIGURES:
		if mask & bit and fig in RACE_FIGURES[bit]:
			return false
	return true


const RACE_FIGURES := {4: ["unhuma", "unhufe"], 8: ["unmogo"], 0x10: ["unorma", "unorfe"], 0x20: ["unmoli"]}


static func _buff(u: GameUnit, name: String, secs: float, data: Dictionary) -> void:
	data.until = u.world.time + secs
	u.buffs[name] = data
	u.refresh_max_hp()
