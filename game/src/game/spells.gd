class_name Spells
extends RefCounted
## Spells from spells.sdb. A spell is "<code>{mod;mod;...}" (e.g.
## "acid_ray{e1;e1}"): a prototype plus modifiers that scale range, area,
## effect, duration and mana (builder); the effects follow the
## dispatcher and the stat fold (see apply).

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


## The spell constructor's rune check (camp mode 3, the spell
## builder): fewer than 8 runes so far, and a rune of type 0..4
## (range, targets, area, effect, duration) only where the keystone allows that
## type (prototype..); mana, filter and other runes always fit.
## Unlike can_add, a filter rune is not limited to area spells here.
static func constr_rune_fits(key: String, n_runes: int, code: String) -> bool:
	var row := mod_row(code)
	if row.is_empty() or n_runes >= MAX_MODS:
		return false
	var type := int(row.get("type", 9))
	if type >= 5:
		return true
	var allowed = parse(key).proto.get("mods", [])
	return type < allowed.size() and int(allowed[type]) == 1


## The spell constructor's pile sums (mode 3, the limit lines
## ): x = the keystone's complexity + each rune's
## y = the keystone's stamina + each rune's.
static func constr_sums(key: String, runes: Array) -> Vector2:
	var proto: Dictionary = parse(key.get_slice("{", 0)).proto
	var c := float(int(proto.get("complex", 0)))
	var m := float(proto.get("mana", 0.0))
	for r: String in runes:
		var row := mod_row(r.trim_prefix("rune:"))
		c += float(int(row.get("complex", 0)))
		m += float(row.get("mana", 0.0))
	return Vector2(c, m)


## The spell constructor's limits (camp): over the
## party's members, the best round(knowledge) of `subtype`'s school
##  and the best whole stamina (__ftol of the max stamina
## ); both start at 0.
static func party_limits(units: Array, subtype: String) -> Vector2i:
	var k := 0
	var s := 0
	for u: GameUnit in units:
		if u == null or not u.has_meta("hero"):
			continue
		k = maxi(k, roundi(Skills.knowledge(u.get_meta("hero"), subtype)))
		s = maxi(s, int(u.max_mana))
	return Vector2i(k, s)


##  check of the built spell: party knowledge ≥ its complexity
##  and party stamina ≥ __ftol(its stamina cost).
static func constr_buildable(units: Array, spell: String) -> bool:
	var p := parse(spell)
	var lim := party_limits(units, String(p.subtype))
	return float(lim.x) >= complexity(spell) and lim.y >= int(p.mana)


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
static func apply(world: GameWorld, caster: GameUnit, spell: String, target: GameUnit, point: Vector2, from := Vector2(INF, INF), auto_heal := false) -> Dictionary:
	var p := parse(spell)
	var audio := {}
	var at := target.pos if target else point
	# Spell power comes from its runes [allods.gipat.ru FAQ]; skills and school
	# perks only raise the allowed complexity.
	var power: float = p.effect
	var radius: float = p.radius
	#  applies each non-area effect to this spell object's
	# target. creates any additional target objects; radius
	# belongs to area damage and never substitutes for the target count.
	var victims: Array = [target] if target else []
	# Durations count 55 ms logic ticks; each effect has its own cleanup
	# counter. Lasting effects are "magic effects" whose type is the
	# spell index; fold them into stats.
	var secs: float = float(p.duration) * GameUnit.TICK
	if p.code in ["firewall", "litnwall", "acid_fog"] and world.ai:
		# the effect's cells become dangerous
		# until counter-1 at duration+2. Campfire creates no figure, so it
		# never registers a danger layer despite the helper's type0x27 case.
		var wall: bool = p.code in ["firewall", "litnwall"]
		var span := _wall_span(world, caster, at, radius, from, p.code == "litnwall") if wall else Vector3.ZERO
		world.ai.add_danger(at, maxf(radius, 0.0), secs + 2.0 * GameUnit.TICK, span, wall)
	if p.code == "fireworks":
		#  case 0x12: every logic tick of its duration (counter
		#  from duration - 1 down to 0), the units within the effect
		# radius (the light reaches 5 m further) suspect the point
		# trunc(counter / duration x 250 + 50), -1 a tick, replacing only a
		# lower level.
		_fireworks_tick(world, at, maxf(radius, 0.0), int(p.duration), int(p.duration) - 1)
	# Lasting spells show a magic effect on each unit (visual only).
	# Every lasting effect is sent, also those with no particles (their
	# start / end sounds, SpellSounds.EFFECT_DIRS).
	if world.session and (ParticleFx.MAGIC_TYPES.has(p.code) or p.code in ["lichdom", "strength", "weak",
			"invisibility", "stun", "enlarge", "shrink"]):
		for u: GameUnit in victims:
			world.session.broadcast({"t": "magicfx", "uid": u.uid, "code": p.code, "secs": secs,
				"s": ParticleFx.strength(p), "warn": not auto_heal})
	match String(p.code):
		"healing":   # Heal(effect)
			audio.sound_units = []
			for u: GameUnit in victims:
				u.heal(power)
				# Spell object is set only by the periodic charged-item
				# check: a heal that fills HP is silent there.
				# The two packed HP shorts use CRT __ftol.
				if not auto_heal or int(u.hp) != int(u.max_hp):
					audio.sound_units.append(u.uid)
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
				_buff(u, "stun", secs, {})   # effect 0x19: shown, read by nothing (see GameUnit)
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
			audio.sound_units = []
			for u: GameUnit in victims:
				if caster == null:
					continue
				var ok := true
				#  is the owning side: for a hero, its player's party.
				while ok and (u.faction != caster.faction or u.controller != caster.controller):
					ok = tame(world, caster, u, power)
				if not ok and world.session:
					world.session.failed(caster, 7)   # "Can't charm"
				elif ok:
					audio.sound_units.append(u.uid)
		"vision_fog":   #  case 0x17: needs a caster and a target unit
			if target and caster and world.session:
				world.session.broadcast({"t": "vision_fog", "uid": target.uid, "caster": caster.uid,
					"to": caster.controller, "secs": secs})
		"teleport":
			# 67f830/682610: the destination is tested and the caster moves on
			# tick30. The duration counter continues after that move.
			audio.light_id = _teleport_later(world, caster, at, maxi(int(p.duration), 1) + 30,
				-1, maxi(int(p.duration), 1))
		"eagle_sight", "infravision", "detect_life":   # effect added to sight / night sight / life sense
			for u: GameUnit in victims:
				_buff(u, p.code, secs, {"sense": [["eagle_sight", "infravision", "detect_life"].find(p.code), power]})
		_:
			if p.subtype in DAMAGE_TYPES:
				_damage_spell(world, caster, p, target, at, from)
	return audio


##  for a unit caster (manual, belt and charged equipment).
## Its single unfiltered path is deliberately direct, even for a corpse.
## Filter / multi-target casts use the player's noticed list (not the
## render relevance radius), then terrain / spell filters, and only a
## successful dispatch spends one of the target count.
static func cast_unit(world: GameWorld, caster: GameUnit, spell: String, target: GameUnit,
		point: Vector2, auto_heal := false) -> void:
	var p := parse(spell)
	if caster == null or not is_instance_valid(caster) or p.proto.is_empty() \
			or p.code in ["possession", "link", "charm"]:
		return
	if (world.session and world.session.shop_available()) or (not world.session and bool(world.zone.get("village", false))):
		return
	var n := int(p.targets)
	var flags := int(p.flags)
	if int(p.filter) == 0 and n < 2:
		_cast_unit_one(world, caster, spell, p, target, point, auto_heal)
		return
	if flags & 0x20000000 and not flags & 0x20000:
		n -= 1
		_cast_unit_one(world, caster, spell, p, target, point, auto_heal)
	var pool: Array = world.units_near(caster.pos, float(p.range))
	if target:
		pool.erase(target)
		pool.push_front(target)
	var noticed := {}
	if caster.controller >= 0 and world.session:
		for u: GameUnit in UnitFog.noticed_for(world.session, caster.controller):
			noticed[u.uid] = true
	var point_z := world.ground_at(target.pos.x, target.pos.y) if target else 0.0
	while n > 0:
		var pick := _cast_pick(world, pool, target, point, point_z)
		if pick == null:
			break
		pool.erase(pick)
		var known := noticed.has(pick.uid) if caster.controller >= 0 and world.session else \
				pick.uid in (caster.get_meta("noticed", {}) as Dictionary) \
				or world.relation(pick.faction, caster.faction) == 0
		if known and _trace_ok(world, p, caster.pos, caster.eye_z(), pick) \
				and passes_filter(world, caster, pick, int(p.filter)):
			_cast_unit_one(world, caster, spell, p, pick, pick.pos, auto_heal)
			n -= 1


static func _cast_unit_one(world: GameWorld, caster: GameUnit, spell: String, p: Dictionary,
		target: GameUnit, point: Vector2, auto_heal: bool) -> void:
	#  clears the spell object's target for a point spell
	# the target's current coordinates still supply its fixed destination.
	var at := target.pos if target else point
	var tu: GameUnit = null if int(p.flags) & 0x20000000 else target
	var audio := apply(world, caster, spell, tu, at, Vector2.INF, auto_heal)
	if world.session:
		var fx := {"t": "spellfx", "code": p.code, "sub": p.subtype, "spell": spell,
			"x": at.x, "y": at.y, "a": caster.uid, "tu": tu.uid if tu else -1,
			"hold": light_time(spell)}
		fx.merge(audio)
		world.session.broadcast(fx)


## Damage spells, the original (cast) / (effect tick)
##  (missile hit). Each hit is the damage struct:
## value = effect, x 4 / duration when the duration is over 1, all of the
## school's type (fire 3, acid 4, lightning 5), dealt through the unit's
## damage method (armour per type) after the filter
##  when there is a caster. Area hits take every
## unit within the radius — the caster too — but flyers
## (: move class = 0 and altitude >= 0.5):
##   arrow / acid_ray / rick_magic: a missile homing on the target unit at
##     0.6667 m a tick (CEffectArrow; the sdb speed is unused)
##     hitting only that unit on arrival;
##   lightning / curse_magic: the target unit at once;
##   fireball: creation counter round(d / range x 15) - 2, but the wrapper
##     decrements then tests the old negative value: damage at
##     max(1, round(d / range x 15))
##   inv_lit: the area at once; acid_column: the area once, 15 ticks after
##     the cast (counter 30, hit at 15);
##   firewall / litnwall: counter = duration, -1 a tick; while it is >= 0,
##     every tick with counter & 3 = 0 the strip — units within
##     the radius of the centre and 0.5 m of the wall line (the wall runs
##     across the cast direction, 2 x radius long), flyers excepted;
##   acid_fog: the same ticks, the whole area;
##   campfire: counter = duration, +1 a tick, the area every tick with
##     counter & 3 = 0; it never ends through this counter.
static func _damage_spell(world: GameWorld, caster: GameUnit, p: Dictionary, target: GameUnit, at: Vector2, from: Vector2) -> void:
	var src := caster.pos if caster else from
	var dur := int(p.duration)
	match String(p.code):
		"arrow", "acid_ray", "rick_magic":
			if src.x == INF:
				_hit(world, caster, p, target)
			else:
				_missile_tick(world, caster, p, target, src, at, 0)
		"fireball":
			if src.x == INF:
				_area_hit(world, caster, p, at)
			else:
				_area_later(world, caster, p, at, fireball_ticks(src, at, float(p.range)))
		"inv_lit":
			_area_hit(world, caster, p, at)
		"acid_column":
			_area_later(world, caster, p, at, 15)
		"firewall", "litnwall":
			_start_lasting(world, caster, p, at, _wall_direction(caster, at, from), dur, -1)
		"acid_fog":
			_start_lasting(world, caster, p, at, Vector2.ZERO, dur, -1)
		"campfire":
			_start_lasting(world, caster, p, at, Vector2.ZERO, dur, -2)
		_:   # lightning, curse_magic
			_hit(world, caster, p, target)


##  stores both the XY distance and the tick ratio in float32
## then FISTP uses the default nearest-even mode. A nonpositive range is5m.
static func fireball_ticks(from: Vector2, at: Vector2, range: float) -> int:
	var d := float(PackedFloat32Array([from.distance_to(at)])[0])
	var r := float(PackedFloat32Array([range])[0])
	var v := float(PackedFloat32Array([d / (r if r > 0.0 else 5.0) * 15.0])[0])
	var lower := floori(v)
	var fraction := v - float(lower)
	var ticks := lower if fraction < 0.5 or (fraction == 0.5 and lower % 2 == 0) else lower + 1
	return maxi(1, ticks)


static func _wall_direction(caster: GameUnit, at: Vector2, from: Vector2) -> Vector2:
	var source := caster.pos if is_instance_valid(caster) else from
	var delta := at - source if source.x != INF else Vector2.ZERO
	#  uses the east axis when both horizontal components are0.
	return delta.normalized() if delta != Vector2.ZERO else Vector2.RIGHT


static func _wall_span(world: GameWorld, caster: GameUnit, at: Vector2, radius: float, from: Vector2, lightning: bool) -> Vector3:
	var dir := _wall_direction(caster, at, from)
	var half := Vector2(-dir.y, dir.x) * radius
	var z := 0.0
	if lightning:
		#  stores ground+1 at both ends; takes
		# their half difference, including terrain slope in the outer circle.
		z = (world.ground_at(at.x + half.x, at.y + half.y) - world.ground_at(at.x - half.x, at.y - half.y)) * 0.5
	return Vector3(half.x, half.y, z)


## Creation registers the effect; its first damage update is the next
## server tick, not the creation call (state0 -> state2).
static func _start_lasting(world: GameWorld, caster, p: Dictionary, at: Vector2, dir: Vector2, counter: int, left: int) -> void:
	var id := _keep_lasting(world, -1, {"k": "tick", "spell": String(p.id), "caster": _caster_ref(caster),
		"at": [at.x, at.y], "dir": [dir.x, dir.y], "counter": counter, "left": left, "hit": false})
	var cw = _ref(caster)
	_after(world, GameUnit.TICK, func():
		_lasting_tick(world, _deref(cw), p, at, dir, counter, left, false, id))


## The world's spell timers (delayed hits, lasting effects, missiles) are
## connected through a child node of the world, so a timer still pending when
## the world goes (zone change, load, return to the menu) never fires: the
## connection ends with the node. The callbacks hold the world (which then
## outlives them) and weak references to units, which can leave the world
## first (RemoveObject, summons) — so no callback meets a freed capture.
class WorldTimers extends Node:
	var pending: Array[Dictionary] = []
	func queue(secs: float, f: Callable) -> void:
		var w := get_parent() as GameWorld
		pending.append({"left": secs, "f": f, "created_step": w._logic_step if w else -1})
	func _tick(dt: float, world_step := false) -> void:
		# One authoritative world can be hidden or temporarily unoccupied.
		# Its delays consume only that world's running time, never base time.
		var w := get_parent() as GameWorld
		for p: Dictionary in pending.duplicate():
			# A wrapper created by an object in this very tick first enters
			# its running state on the next completed server tick. A callback
			# queued by another callback also waits for the next iteration.
			if world_step and w and int(p.get("created_step", -1)) >= w._logic_step:
				continue
			p.left = float(p.left) - dt
			if float(p.left) <= 0.000000001:
				pending.erase(p)
				_timed_fire(p.f)
	func fire(f: Callable) -> void:
		if is_inside_tree():
			_timed_fire(f)
	func _timed_fire(f: Callable) -> void:
		var w := get_parent() as GameWorld
		var started := Time.get_ticks_usec() if w and w.profile_simulation else 0
		f.call()
		if is_instance_valid(w): w.profile_record("spell_callback",started)


static func _after(world: GameWorld, secs: float, f: Callable, always := false) -> void:
	if not is_instance_valid(world) or not world.is_inside_tree():
		return
	var n = world.get_node_or_null("SpellTimers")
	if n == null:
		n = WorldTimers.new()
		n.name = "SpellTimers"
		world.add_child(n)
	if world.authority:
		n.queue(secs, f)
		return
	world.get_tree().create_timer(secs, always).timeout.connect(n.fire.bind(f))


static func _ref(o) -> WeakRef:
	return weakref(o) if o is Object and is_instance_valid(o) else null


static func _deref(r: WeakRef):
	return r.get_ref() if r else null


## One tick of a lasting damage effect: `left` < 0 counts the wall / fog
## counter down to0; -2 is campfire's indefinite count-up. Positive left
## retains compatibility with older saves that gave campfire a finite life.
## `id`: its entry in the world's running lasting effects (save_lasting).
static func _lasting_tick(world: GameWorld, caster, p: Dictionary, at: Vector2, dir: Vector2, counter: int, left: int, hit := false, id := -1) -> void:
	if not is_instance_valid(world):
		return
	if (left == -1 and counter < 0) or left == 0:
		_lasting(world).erase(id)
		return
	if counter & 3 == 0:
		# Walls and fog set the effect's flag bit 0 after their first
		# hit; from then passes no attacker (campfire never).
		_area_hit(world, caster, p, at, dir, hit)
		hit = left == -1
	var next := counter - 1 if left == -1 else counter + 1
	var nleft := left - 1 if left > 0 else left
	id = _keep_lasting(world, id, {"k": "tick", "spell": String(p.id), "caster": _caster_ref(caster),
		"at": [at.x, at.y], "dir": [dir.x, dir.y], "counter": next, "left": nleft, "hit": hit})
	var cw = _ref(caster)
	_after(world, GameUnit.TICK, func():
		_lasting_tick(world, _deref(cw), p, at, dir, next, nleft, hit, id))


## The lasting ground effects running in `world` (walls, fog, camp fire,
## fireworks): id -> the arguments of their next tick. the original keeps them as
## spell objects in the world's list and writes each one with the
## world (: point, caster and target ids, target
## point, the spell record, counter, state), so a save game or a
## zone left and entered again finds them where they were.
static func _lasting(world: GameWorld) -> Dictionary:
	if not world.has_meta("lasting_spells"):
		world.set_meta("lasting_spells", {})
	return world.get_meta("lasting_spells")


static func _keep_lasting(world: GameWorld, id: int, rec: Dictionary) -> int:
	var l := _lasting(world)
	if id < 0:
		id = int(world.get_meta("lasting_next", 1))
		world.set_meta("lasting_next", id + 1)
	l[id] = rec
	return id


## A caster as the save keeps it: a party unit by its record's name and
## player (party units get new ids when they are deployed), others by id.
static func _caster_ref(caster) -> Array:
	if caster == null or not is_instance_valid(caster) or not (caster is GameUnit):
		return []
	var u: GameUnit = caster
	if u.has_meta("hero"):
		var h: Dictionary = u.get_meta("hero")
		return ["hero", String(h.get("unit_name", h.get("name", ""))), u.controller]
	return ["uid", u.uid]


static func _caster_of(world: GameWorld, ref: Array) -> GameUnit:
	if ref.size() >= 2 and ref[0] == "uid":
		return world.units.get(int(ref[1]))
	if ref.size() >= 3 and ref[0] == "hero":
		for u: GameUnit in world.units.values():
			if u.has_meta("hero") and u.controller == int(ref[2]):
				var h: Dictionary = u.get_meta("hero")
				if String(h.get("unit_name", h.get("name", ""))) == String(ref[1]):
					return u
	return null


## For CampaignState.store_zone. Arrows and bolts in flight (Projectile, the
## host's: they carry their strike) go with them: the original keeps a missile as
## a world object with its hit record, written with
## the world like the spell objects.
static func save_lasting(world: GameWorld) -> Array:
	if world == null:
		return []
	var out: Array = _lasting(world).values().duplicate(true) if world.has_meta("lasting_spells") else []
	if world.ai:
		out.append_array(world.ai.save_dangers())
	for c in world.get_children():
		if c is Projectile and c.apply_hit and not c.is_queued_for_deletion() and is_instance_valid(c.target) \
				and not c.target.dead:
			var gp: Vector3 = c.global_position
			out.append({"k": "shot", "source": _caster_ref(c.source), "target": _caster_ref(c.target),
				"pos": [gp.x, gp.y, gp.z], "roll": c.roll.duplicate(true), "at": [0.0, 0.0], "counter": 0})
	return out


## Host (CampaignState.replay_restored): saved lasting effects run on from
## their next tick.
## `shown` "fireball": the fireballs' visuals come back on their own (a save
## that kept them with their age, CampaignState.replay_restored).
static func restore_lasting(world: GameWorld, list: Array, shown := {}) -> void:
	var has_dangers := list.any(func(r): return r is Dictionary and String(r.get("k", "")) == "danger")
	for r in list:
		if not r is Dictionary:
			continue
		var rec: Dictionary = r
		if String(rec.get("k", "")) == "danger":
			if world.ai:
				world.ai.restore_danger(rec)
			continue
		var at := Vector2(float(rec.at[0]), float(rec.at[1]))
		var cw = _ref(_caster_of(world, rec.get("caster", [])))
		var id := _keep_lasting(world, -1, rec.duplicate(true))
		var counter := int(rec.counter)
		match String(rec.get("k", "")):
			"tick":
				var p := parse(String(rec.spell))
				var dir := Vector2(float(rec.dir[0]), float(rec.dir[1]))
				var left := int(rec.left)
				var hit := bool(rec.hit)
				if not has_dangers and world.ai and p.code in ["firewall", "litnwall", "acid_fog"] and counter >= -1:
					# Old saves lack separate danger records. Their saved next
					# damage counter still determines the remaining registration.
					var wall: bool = p.code != "acid_fog"
					var half := Vector2(-dir.y, dir.x) * float(p.radius)
					var z := (world.ground_at(at.x + half.x, at.y + half.y) - world.ground_at(at.x - half.x, at.y - half.y)) * 0.5 if p.code == "litnwall" else 0.0
					world.ai.add_danger(at, float(p.radius), float(counter + 2) * GameUnit.TICK, Vector3(half.x, half.y, z), wall)
				_after(world, GameUnit.TICK, func():
					_lasting_tick(world, _deref(cw), p, at, dir, counter, left, hit, id))
			"fireworks":
				var radius := float(rec.radius)
				var duration := int(rec.duration)
				_after(world, GameUnit.TICK, func():
					_fireworks_tick(world, at, radius, duration, counter, id))
			"missile":   # a magic arrow / acid ray in flight: on from where it was
				var p := parse(String(rec.spell))
				var tw = _ref(_caster_of(world, rec.get("target", [])))
				var pos := Vector2(float(rec.pos[0]), float(rec.pos[1]))
				_after(world, GameUnit.TICK, func():
					_missile_tick(world, _deref(cw), p, _deref(tw), pos, at, counter, id))
				var tu: GameUnit = _deref(tw)
				if world.session:   # its visual from there (no cast sound / flash)
					world.session.broadcast({"t": "spellfx", "code": String(p.code), "spell": String(p.id), "sub": "",
						"x": at.x, "y": at.y, "fx": pos.x, "fy": pos.y, "tu": tu.uid if tu else -1, "replay": true})
			"area":   # a fireball on its way / an acid column rising
				var p := parse(String(rec.spell))
				_after(world, GameUnit.TICK, func():
					_area_later(world, _deref(cw), p, at, counter - 1, id))
				if world.session and String(p.code) == "fireball" and not shown.has("fireball"):
					world.session.broadcast({"t": "spellfx", "code": "fireball", "spell": String(p.id), "sub": "",
						"x": at.x, "y": at.y, "fx": at.x, "fy": at.y, "replay": true})
			"teleport":
				var duration := maxi(int(rec.get("duration", maxi(counter - 30, 1))), 1)
				var light_id := String(rec.get("light_id", ""))
				_after(world, GameUnit.TICK, func():
					_teleport_later(world, _deref(cw), at, counter - 1, id, duration, light_id))
			"shot":   # an arrow / bolt in flight (save_lasting): on from where it was
				_lasting(world).erase(id)
				var tu := _caster_of(world, rec.get("target", []))
				if tu and not tu.dead:
					var pr := Projectile.new()
					pr.world = world
					pr.target = tu
					pr.roll = Dictionary(rec.get("roll", {}))   # (before the shooter: kept as it was)
					pr.source = _caster_of(world, rec.get("source", []))
					world.add_child(pr)
					pr.global_position = Vector3(float(rec.pos[0]), float(rec.pos[1]), float(rec.pos[2]))
					if pr.source and world.session:
						world.session.broadcast({"t": "arrow", "a": pr.source.uid, "b": tu.uid})
			_:
				_lasting(world).erase(id)


## CEffectArrow: steps 0.6667 m a tick toward the target unit (or the point),
## arriving within one step or after 400 ticks (as `ParticleFx._missile_tick`).
## `id`: its entry in the world's running spells (save_lasting).
static func _missile_tick(world: GameWorld, caster, p: Dictionary, target, pos: Vector2, point: Vector2, ticks: int, id := -1) -> void:
	if not is_instance_valid(world):
		return
	var t: GameUnit = target if target != null and is_instance_valid(target) else null
	var dest := t.pos if t else point
	if pos.distance_to(dest) < 0.6667 or ticks + 1 > 400:
		_lasting(world).erase(id)
		_hit(world, caster, p, t)
		return
	pos += (dest - pos).normalized() * 0.6667
	id = _keep_lasting(world, id, {"k": "missile", "spell": String(p.id), "caster": _caster_ref(caster),
		"target": _caster_ref(t), "pos": [pos.x, pos.y], "at": [point.x, point.y], "counter": ticks + 1})
	var cw = _ref(caster)
	var tw = _ref(t)
	_after(world, GameUnit.TICK, func():
		_missile_tick(world, _deref(cw), p, _deref(tw), pos, point, ticks + 1, id))


## A delayed area hit (fireball on arrival, acid column at its 15th tick)
## `ticks` logic ticks from now, kept with the world's running spells.
static func _area_later(world: GameWorld, caster, p: Dictionary, at: Vector2, ticks: int, id := -1) -> void:
	if not is_instance_valid(world):
		return
	if ticks <= 0:
		_lasting(world).erase(id)
		_area_hit(world, caster, p, at)
		return
	id = _keep_lasting(world, id, {"k": "area", "spell": String(p.id), "caster": _caster_ref(caster),
		"at": [at.x, at.y], "counter": ticks})
	var cw = _ref(caster)
	_after(world, GameUnit.TICK, func():
		_area_later(world, _deref(cw), p, at, ticks - 1, id))


## Teleport's current counter, not its arrival delay (67f830/682610).
## Old saves omitted duration; their remaining counter is migrated below.
static func _teleport_later(world: GameWorld, caster, dest: Vector2, ticks: int,
		id := -1, duration := -1, light_id := "") -> String:
	if not is_instance_valid(world):
		return light_id
	if duration < 0:
		duration = maxi(ticks - 30, 1)
	if ticks <= -3:
		_lasting(world).erase(id)
		return light_id
	var c: GameUnit = caster if caster != null and is_instance_valid(caster) else null
	if id >= 0 and (c == null or c.dead):
		_lasting(world).erase(id)
		if world.session:
			world.session.broadcast({"t": "spell_light", "id": light_id, "ok": false, "cancel": true})
		return light_id
	if id >= 0 and ticks == duration and c:
		# Native5b7a40 lifts the mover's stamp and tests the exact destination;
		# a blocked point fails, rather than snapping to another nearby point.
		var lifted := c._occ_cell.x >= 0
		if lifted:
			world.nav._stamp(c._occ_cell, c._occ_r, -1)
		var ok := world.nav.is_walkable(dest, c.move_class())
		if lifted:
			world.nav._stamp(c._occ_cell, c._occ_r, 1)
		if ok:
			c.pos = dest
			c.path = PackedVector2Array()
			c.order = {}
			c.orders.clear()
		elif world.session:
			world.session.failed(c, 16)   # native 552780(0x10)
		if world.session:
			world.session.broadcast({"t": "spell_light", "id": light_id, "ok": ok})
	id = _keep_lasting(world, id, {"k": "teleport", "caster": _caster_ref(caster),
		"at": [dest.x, dest.y], "counter": ticks, "duration": duration, "light_id": light_id})
	if light_id == "":
		light_id = "%d:%d" % [world.get_instance_id(), id]
		_lasting(world)[id].light_id = light_id
	var cw = _ref(caster)
	_after(world, GameUnit.TICK, func():
		_teleport_later(world, _deref(cw), dest, ticks - 1, id, duration, light_id))
	return light_id


## one unit, after the filter when there is a caster.
static func _hit(world: GameWorld, caster, p: Dictionary, u) -> void:
	if u == null or not is_instance_valid(u) or u.dead:
		return
	var c: GameUnit = caster if caster != null and is_instance_valid(caster) else null
	if c and not passes_filter(world, c, u, int(p.get("filter", 0))):
		return
	_spell_damage(world, c, p, u)


## The area hits (with a wall
## direction `dir`).
static func _area_hit(world: GameWorld, caster, p: Dictionary, at: Vector2, dir := Vector2.ZERO, owner_only := false) -> void:
	var c: GameUnit = caster if caster != null and is_instance_valid(caster) else null
	for u: GameUnit in world.units_near(at, maxf(float(p.radius), 0.0)):
		if u.dead or _flyer(u):
			continue
		if dir != Vector2.ZERO and absf((u.pos - at).dot(dir)) > 0.5:
			continue
		if c and not passes_filter(world, c, u, int(p.get("filter", 0))):
			continue
		_spell_damage(world, c, p, u, owner_only)


## a unit of move class 0 whose altitude is 0.5 m or more.
static func _flyer(u: GameUnit) -> bool:
	return u.has_meta("flying") or (u.move_class() == 0 and float(u.proto.get("altitude", 0.0)) >= 0.5)


## The hit record: value = effect and armour factor
## = 1, both x 4 / duration when the duration is over 1; body part = 6
## (the whole body). subtracts the natural armour of the type x
## the factor x the difficulty's absorption (fire thermal, acid chemical,
## lightning electrical), then spreads the rest over the living parts
## (`GameUnit.body_damage`), where a character's worn layers come off each
## part's share (x the factor). The hit always lands
## the struck armour spells fire first; when the natural
## armour stops it all, the struck path still runs without damage
## (`Combat.blank_hit`: "0" hit number, hostility, AI hit hook); a unit that
## lives on after damage gets the healing armour spell.
## Layer wear as for a strike:
## the items of each layer lose what is left after it, on that part's record.
##  whole-body loop gives part i the value
## D · r_i and the armour factor af · r_i, r_i = part max / (Σ living
## parts' lethality × max HP) — `body_damage`'s split — so the left
## damage, and the wear, is r_i × (D − af × layers so far). When every part's
## layers stop it all, returns 0: the blank struck path. The
## caster's weapon in hand wears by what the armour absorbed, as a striker's.
static func _spell_damage(world: GameWorld, caster: GameUnit, p: Dictionary, u: GameUnit, owner_only := false) -> void:
	var power := float(p.effect)
	var af := 1.0
	if int(p.duration) > 1:
		af = 4.0 / float(p.duration)
		power *= af
	var t := int(DAMAGE_TYPE_INDEX.get(p.subtype, 6))
	# Native record electric type factor sets bit4 before absorption
	# zero-damage struck hits retain the electrical flash.
	var hit_flags := 4 if t == 5 else 0
	var armour: PackedFloat32Array = u.stats.get("armor", PackedFloat32Array())
	# Protection effects are folded into that armour.
	var prot := 0.0
	for b in u.buffs.values():
		if b.get("resist", "") in [p.subtype, "all"]:
			prot = maxf(prot, float(b.get("armor", 0.0)))
	var arm := (armour[t] if t < armour.size() else 0.0) + prot
	var dmg := power - arm * af * world.combat.difficulty(u, "Absorption")
	# the record's roll (= FLT_MAX) always lands; the
	# struck armour spells fire before the damage ((1)).
	world.combat.armor_spells(u, true)
	if u.dead:
		return
	#  passes the attacker's weapon in hand ((attacker
	# )) to as param_4; names the caster as the
	# attacker except on a lasting spell's later ticks (`owner_only`). That
	# weapon loses what the natural armour absorbed (first loop) and
	# per part, what the layers absorbed — (…, 0x24, 0x26).
	var att_ws: Array = caster.get_meta("hero").get("weapons", []) \
		if is_instance_valid(caster) and caster.has_meta("hero") and not owner_only else []
	var absorbed := [power - maxf(dmg, 0.0)]
	var wear_weapon := func() -> void:
		if not att_ws.is_empty() and absorbed[0] > 0.0:
			world.combat.wear_item(caster, att_ws, 0, absorbed[0], true)
	if dmg <= 0.0:
		#  returned 0: the struck path without damage.
		wear_weapon.call()
		world.combat.blank_hit(u, caster, owner_only, hit_flags)
		return
	# a character's (script-name id, `has_meta("hero")`) worn
	# layers on each part, outer first, each x the armour factor, on that
	# part's share (`GameUnit.body_damage`).
	var layers := Callable()
	if u.has_meta("hero") and not u.parts.is_empty():
		var armors: Array = u.get_meta("hero").get("armors", [])
		if not armors.is_empty():
			var lethal := 0.0
			for pt: Dictionary in u.parts:
				if int(pt.state) > 1:
					lethal += float(pt.lethal)
			# `wear`: false = only what is left (the test for a blank hit).
			var walk := func(i: int, amount: float, wear: bool) -> float:
				var r := float(u.parts[i].max) / maxf(lethal * u.max_hp, 0.0001)
				var d := amount
				for l: Array in Combat.worn_layers(armors, u.part_group(i)):
					d -= float((l[1] as PackedFloat32Array)[t]) * af
					if wear:
						for it in (l[0] as Array).map(func(j: int) -> String: return armors[j]):
							var j := armors.find(it)   # a broken piece left the list
							if j >= 0:
								world.combat.wear_item(u, armors, j, maxf(d, 0.0) * r, false)
					if d <= 0.0:
						d = 0.0
						break
				if wear:
					absorbed[0] += (amount - d) * r
				return d
			var full := dmg * float(caster.get_meta("coop_dmg_mul", 1.0)) if is_instance_valid(caster) else dmg
			var stopped := true
			for i in u.parts.size():
				if int(u.parts[i].state) > 1 and float(walk.call(i, full, false)) > 0.0:
					stopped = false
			if stopped and lethal > 0.0:
				for i in u.parts.size():
					if int(u.parts[i].state) > 1:
						walk.call(i, full, true)
				wear_weapon.call()
				world.combat.blank_hit(u, caster, owner_only, hit_flags)
				return
			layers = func(i: int, amount: float) -> float:
				return walk.call(i, amount, true)
	u.take_damage(dmg, caster, -1, PackedFloat32Array(), hit_flags, layers, owner_only)
	wear_weapon.call()
	# a unit that lives on after the damage (healing armour).
	if not u.dead:
		world.combat.armor_spells(u, false)


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
## those casts count. Ranking uses the full 3D point: a unit's feet, or z=0
## for CastSpellPoint / a trap's point target. The range pool itself is 2D.
## `from_z` is the source height (scripts pass 0).
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
	var point_z := world.ground_at(target.pos.x, target.pos.y) if target else 0.0
	while n > 0:
		var pick := _cast_pick(world, pool, target, point, point_z)
		if pick == null:
			break
		pool.erase(pick)
		if _trace_ok(world, p, from, from_z, pick) and passes_filter(world, null, pick, mask):
			_cast_one(world, spell, p, from, pick, pick.pos)
			n -= 1


## ..: dead nodes leave the pool; an explicit
## living target wins, otherwise strict 3D squared-distance order. Each best
## value is stored as a float32, and unordered x87 comparisons also select.
static func _cast_pick(world: GameWorld, pool: Array, target: GameUnit, point: Vector2, point_z: float) -> GameUnit:
	var pick: GameUnit = null
	var best := float(PackedFloat32Array([1.0e38])[0])
	for u: GameUnit in pool.duplicate():
		if u.dead:
			pool.erase(u)
			continue
		if u == target:
			return u
		# Use authoritative ground height; Node3D.position may still hold the
		# preceding rendered pose after a script moved the simulation unit.
		var dx := float(point.x) - float(u.pos.x)
		var dy := float(point.y) - float(u.pos.y)
		var dz := point_z - world.ground_at(u.pos.x, u.pos.y)
		var d := dx * dx + dy * dy + dz * dz
		if is_nan(d) or is_nan(best) or d < best:
			best = float(PackedFloat32Array([d])[0])
			pick = u
	return pick


static func _cast_one(world: GameWorld, spell: String, p: Dictionary, from: Vector2, tu: GameUnit, at: Vector2) -> void:
	var audio := apply(world, null, spell, tu, at, from)
	if world.session:
		var fx := {"t": "spellfx", "code": p.code, "sub": p.subtype, "x": at.x, "y": at.y,
			"a": -1, "tu": tu.uid if tu else -1, "spell": spell, "fx": from.x, "fy": from.y,
			"hold": light_time(spell)}
		fx.merge(audio)
		world.session.broadcast(fx)


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


static func _fireworks_tick(world: GameWorld, at: Vector2, radius: float, duration: int, counter: int, id := -1) -> void:
	if not is_instance_valid(world):
		return
	if counter < 0 or duration <= 0 or world.ai == null:
		_lasting(world).erase(id)
		return
	var level := floorf(float(counter) / float(duration) * 250.0 + 50.0)
	for u: GameUnit in world.units_near(at, radius):
		world.ai.suspect(u, at, level, -1.0)
	id = _keep_lasting(world, id, {"k": "fireworks", "at": [at.x, at.y], "radius": radius,
		"duration": duration, "counter": counter - 1})
	_after(world, GameUnit.TICK, func():
		_fireworks_tick(world, at, radius, duration, counter - 1, id))


static func _buff(u: GameUnit, name: String, secs: float, data: Dictionary) -> void:
	data.until = u.world.time + secs
	u.buffs[name] = data
	u.refresh_max_hp()
