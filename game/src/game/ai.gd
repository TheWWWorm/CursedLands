class_name UnitAI
extends RefCounted
## Behaviour of idle units. AI units follow the script unit modes (UMStandard,
## UMSentry, UMGuard, UMFollow, UMFear, UMAggression, UMPlayer); player units
## the original's "Player" motivation with their Aggressive / Defensive mode.

var world: GameWorld


func _init(w: GameWorld) -> void:
	world = w


## Calm motivations (Guard, Patrol, Sentry and
## the base one): every tick they run first. Map units
## are Sentries at their guard point (.mob logic model 3, case 3
## ) under the remake's "standard".
const CALM_MODES := ["standard", "sentry", "guard"]
const AI_MODES := ["standard", "sentry", "guard", "aggression", "follow"]


## The AI tick of a unit with nothing to do. the original runs the AI of every
## unit every 55 ms logic tick (creature
## no stagger); the remake runs it once
## logic tick while the unit is idle, and while it is busy rechoose() (AI
## attack / cast orders) or calm_tick() (other orders of a calm motivation).
func think(u: GameUnit) -> void:
	var now := world.time
	if now < u.ai_next:
		return
	u.ai_next = now + GameUnit.TICK - 0.0001
	if u.controller >= 0:
		_player(u)
		return
	if u.mode == "fear":
		var threat := nearest_enemy(u, u.stats.sight)
		if threat:
			call_for_help(u, threat.pos)
			var away := u.pos + (u.pos - threat.pos).normalized() * 8.0
			u.move_to(world.nav.nearest_walkable(away), true)
		else:
			# standing still it may cast a protective buff or
			# heal (with no enemies, p5 = 1: types 5 and 7).
			var ch := choose(u, [], true)
			if not ch.is_empty():
				_act(u, ch)
		return
	if not u.mode in AI_MODES:
		return
	# Aggression (priority 10000 while a hostile is noticed), then Suspection
	# (its level), then the calm motivation (50 + 100 while current).
	var home: Vector2 = u.mode_data.point if u.mode_data.has("point") else _home(u)
	_alarm_check(u)
	var lg := logic(u)
	if u.mode == "aggression" or int(lg.get("aggression", 0)) != 1:
		var leash: float = float(lg.get("guard_radius", 30.0)) + 15.0
		var foes := enemies(u)
		if u.mode != "aggression":
			foes = foes.filter(func(e: GameUnit): return e.pos.distance_to(home) < leash)
		if not foes.is_empty():
			var ch := choose(u, foes)
			if ch.is_empty() and options(u).a.is_empty():
				ch = {"opt": {"type": 0, "slot": ""}, "t": foes[0]}   # Approx., see choose()
			if not ch.is_empty():
				if u.order.get("type", "") != "attack":
					_react(u, EIAcks.NPC_AGGRESSION)
				u.remove_meta("calm")
				_act(u, ch)
				return
	if _investigate(u):
		u.remove_meta("calm")
		return
	if calm_tick(u, true):
		return
	match u.mode:
		"follow":
			var t: GameUnit = u.mode_data.get("target")
			if t and is_instance_valid(t) and not t.dead and u.pos.distance_to(t.pos) > 3.0:
				u.command({"type": "follow", "target": t, "dist": 2.0, "once": true})
		"sentry":
			_sentry(u, home)
		"guard":
			var gp: Vector2 = u.mode_data.point
			_guard(u, Vector3(gp.x, gp.y, 0.0), float(u.mode_data.get("radius", -1.0)),
				float(u.mode_data.get("stay", -1.0)))
		"standard":
			# The.mob logic model of the current descriptor:
			# 3 Sentry at the guard point, 1 Guard at it with
			# the.mob radius (stay −1 -> GuardStayTime), 2
			# Patrol, 5 Guard at the point of the descriptor's
			# alarm (e8 + index · 16, AlarmPosX / Y; z 0).
			match int(lg.get("logic_model", 3)) if not u.has_meta("hero") else 0:
				3:
					_sentry(u, home)
				1:
					var gp3: Vector3 = lg.get("guard_point", Vector3(home.x, home.y, 0.0))
					_guard(u, gp3, float(lg.get("guard_radius", -1.0)), -1.0)
				2:
					_patrol(u, home)
				5:
					var ap: Vector2 = alarm(int(u.get_meta("logic_idx", 0))).pos
					_guard(u, Vector3(ap.x, ap.y, 0.0), float(lg.get("guard_radius", -1.0)), -1.0)
				_:
					# Remake-only: a hero whose player left keeps near its spot.
					home = _home(u)
					if u.pos.distance_to(home) > float(lg.get("guard_radius", 10.0)) + 2.0:
						u.move_to(home, u.get_meta("script_run", false))


## the first step of every calm motivation tick (
## Guard, Patrol, Sentry): with no
## enemies and p5 = 1 (list B on the caster and its friends, type 6 left out,
## the 30 m check) and, when the choice differs from the current action
## it is issued at once: a spell -> (cast at the
## unit, AI = the spell, state 4 unless). Run every tick
## the calm motivation is current, also while the unit walks. Returns true
## when it issued a cast.
func calm_tick(u: GameUnit, idle := false) -> bool:
	if u.controller >= 0 or u.dead or not u.mode in CALM_MODES:
		return false
	if not idle:
		var now := world.time
		if now < u.ai_next:
			return false
		u.ai_next = now + GameUnit.TICK - 0.0001
		if u.has_meta("suspect") and u.get_meta("suspect").get("active", false):
			return false
	if u.has_meta("hero") or _spell_list(u)[1].is_empty():
		return false
	var ch := choose(u, [], true)
	if ch.is_empty():
		return false
	var c := _current(u)
	if not c.is_empty() and c.slot == ch.opt.slot and c.t == ch.t:
		return false
	_act(u, ch)
	return true


## A player's unit was hit: the AI keeps its last attacker (unit AI
##  from the damage handlers; cleared at the end of every AI
## tick and when that unit goes away), which counts as noticed
## the next Player tick sees it once.
func on_player_attacked(u: GameUnit, by: GameUnit) -> void:
	if by == null or by == u:
		return
	u.set_meta("attacker", [by, world.time])
	hit_hook(u, by)
	#  (every tick, busy or not): defensive + AI -> ack 0x20
	# once per hit as lasts one tick.
	if not u.aggressive:
		u.ack(EIAcks.ATTACKED_IN_DEFENCE)


## The "Player" motivation of player-controlled units (the original
## type 6, priority 10, so any order comes first; tamed units use
## the same tick under type 8). Its tick:
## - Defensive (unit != 1): while the AI remembers an attacker it asks
##   for ack 0x20 "attacked in defence" and does nothing else - no retaliation,
##   no engaging.
## - Aggressive (only when the unit is idle): candidates are
##    the enemies the unit notices that are themselves in the
##   Aggression motivation and no farther than 1.1 x their own sight
##   (min(x)), plus the units that the
##   player's own units within ai.reg [Logic] PlayerCallForHelp (16 m) are
##   fighting; the best one is attacked with ack 0x1c
##   "decide to attack" (command 6, i.e. chased like an attack
##   order). "Best" (over the unit's attack options):
##   the weapon option (type 0) scores a target (
##   _target_score); the highest is taken when finds it reachable
##   else the next. Approx.: only the weapon option is scored (the spell
##   options, types 1-7, are not modelled); "in Aggression" = an AI unit with an
##   attack order or UMAggression; the cap and the target re-choice while
##   already fighting (state 3) are left out; the original re-checks every 55 ms
##   tick, the remake every ~0.65 s.
func _player(u: GameUnit) -> void:
	var by: GameUnit = null
	if u.has_meta("attacker"):
		# AI holds the attacker for one AI tick (cleared at its end).
		var m: Array = u.get_meta("attacker")
		u.remove_meta("attacker")
		if is_instance_valid(m[0]) and not m[0].dead and world.time - float(m[1]) <= GameUnit.TICK + 0.001:
			by = m[0]
	if not u.aggressive:
		return
	var t := _player_target(u, by)
	if t:
		u.ack(EIAcks.DECIDE_TO_ATTACK)
		u.attack(t)


func _player_target(u: GameUnit, by: GameUnit) -> GameUnit:
	var cands := []
	var sight := float(u.stats.sight)
	for o: GameUnit in world.live_units_near(u.pos, sight * 2.0):
		if o.dead or o.hidden or o.is_invisible() or o.controller >= 0 or not world.is_enemy(u, o):
			continue
		if not (o.mode == "aggression" or o.order.get("type", "") == "attack"):
			continue
		if u.pos.distance_to(o.pos) > 1.1 * float(o.stats.sight) * o.sight_factor():
			continue
		if o == by or can_notice(u, o, sight):
			cands.append(o)
	var help := GameData.ai_value("Logic", "PlayerCallForHelp", 16.0)
	for a: GameUnit in world.live_units_near(u.pos, help):
		if a == u or a.dead or a.controller != u.controller or a.order.get("type", "") != "attack":
			continue
		var e: GameUnit = a.order.get("target")
		if e and is_instance_valid(e) and not e.dead and e.controller != u.controller and world.is_enemy(u, e) \
				and not e in cands:
			cands.append(e)
	var scored := []
	for o: GameUnit in cands:
		scored.append([_target_score(u, o), o])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	for e: Array in scored:
		if _reachable(u, e[1]):
			return e[1]
	return null


##  for the weapon option (type 0), see _score: D + 10 for the
## unit's current target - 25 x the distance - 2 x HP / D. The option's damage
##  = round((min + max) x the damage type's share), min + max =
## the weapon's or the creature's (prototype
## damage min and max, the remake's dmg_max), scaled (Approx.:
## its two stat factors, 0x1d / 0x1e, are taken as 0); the armour
##  = natural armour + the torso's worn layers.
func _target_score(u: GameUnit, o: GameUnit) -> float:
	return _score(u, o, _weapon_option(u), [o], u.order.get("target"), -INF)


## a path to the target (its search limited to 3 min(d, 10) +
## 10 for a party unit, with unit flag that
##  sets around the choice) must end where the option reaches it
## a failed search counts from the unit's own spot.
func _reachable(u: GameUnit, o: GameUnit) -> bool:
	var reach: float = u.stats.reach if u.stats.get("ranged", false) else u.melee_reach(o)
	if u.pos.distance_to(o.pos) <= reach:
		return true
	var path := world.nav.find_path(u.pos, o.pos, [u, o], [], 0.0, u.move_class())
	var d := u.dist3(o)
	var limit := 3.0 * d + 10.0 if u.controller < 0 else 3.0 * minf(d, 10.0) + 10.0
	var end := path[-1] if not path.is_empty() and u.path_fits(path, o.pos, limit) else u.pos
	return end.distance_to(o.pos) <= reach


# ------------------------------------------------------------ attack options

## Option type by spells.sdb index: 1 single-target damage
## 2 instant area damage, 3 lasting area damage, 4 debuff (list A, used on
## enemies), 5 protective buff, 6 other buff, 7 heal (list B, used on the
## caster and its allies). Every other spell (8) is never chosen.
const OPTION_TYPE := {0: 1, 1: 1, 2: 1, 40: 1, 41: 1, 3: 2, 4: 2, 5: 2, 6: 3, 7: 3, 8: 3,
	25: 4, 30: 4, 32: 4, 9: 5, 10: 5, 11: 5, 26: 5, 29: 5,
	12: 6, 13: 6, 14: 6, 15: 6, 16: 6, 17: 6, 31: 6, 33: 6, 24: 7}
const NO_SCORE := -1e30


## The unit's attack options (AI): list A = the weapon
## (type 0, left out for prototypes with weapon type 16, the spell-only
## monsters) and the spells of types 1-4, list B = types 5-7, in spell slot
## order; "power" = the highest over list A of the
## weapon's top damage, 1.3 x a damage spell's, 1 for a debuff. A spell's
## range is the prototype's attack range on a weapon-type-16 unit
## its damage vector = trunc(effect) at the school's damage
## type. Units whose id is a script-name hash ([1e9, 2e9),; the
## ids gives the heroes and hired mercenaries) get the weapon
## only. Approx.: that is taken as "a hero or mercenary" (has_meta("hero")).
func options(u: GameUnit) -> Dictionary:
	var a := []
	var b := []
	var only16 := int(u.proto.get("weapon_type_id", 0)) == 16
	if not only16 or u.has_meta("hero"):
		a.append(_weapon_option(u))
	if not u.has_meta("hero"):
		var cached := _spell_list(u)
		a.append_array(cached[0])
		b.append_array(cached[1])
	var power := 0.0
	for o: Dictionary in a:
		var m := 0
		for x in o.v:
			m = maxi(m, x)
		power = maxf(power, float(m) if o.type == 0 else (1.3 * m if o.type <= 3 else 1.0))
	return {"a": a, "b": b, "power": power}


## The spell options of a prototype ([list A spells, list B]); they depend on
## the prototype only (AI units' spells are its "spells" slots).
static var _spell_opts := {}
func _spell_list(u: GameUnit) -> Array:
	var key: String = u.proto.get("name", "")
	if not _spell_opts.has(key):
		_spell_opts[key] = _spell_options(u, int(u.proto.get("weapon_type_id", 0)) == 16)
	return _spell_opts[key]


func _spell_options(u: GameUnit, only16: bool) -> Array:
	var a := []
	var b := []
	if true:
		var sp_table: Array = GameData.db.table("spell_prototypes")
		for s in Array(u.proto.get("spells", [])):
			var id := String(s).strip_edges().to_lower()
			if id.is_empty():
				continue
			var sp := Spells.parse(id)
			var idx: int = sp_table.find(sp.proto) if not sp.proto.is_empty() else -1
			var ty := int(OPTION_TYPE.get(idx, 8))
			if ty == 8:
				continue
			var v := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
			if ty <= 3:
				v[int(Spells.DAMAGE_TYPE_INDEX.get(sp.subtype, 6))] = int(sp.effect)
			var o := {"type": ty, "slot": id, "idx": idx, "v": v,
				"range": float(u.proto.get("attack_range", 0.0)) if only16 else float(sp.range),
				"n1": maxi(int(sp.targets), 1) - 1, "radius": float(sp.radius),
				"dur": int(sp.duration), "effect": float(sp.effect), "point": bool(sp.point),
				"key": "invisible" if sp.code == "invisibility" else String(sp.code)}
			(a if ty <= 4 else b).append(o)
	return [a, b]


func _weapon_option(u: GameUnit) -> Dictionary:
	var dsum := maxf(1.0, float(u.stats.get("dmg_max", 1.0)))
	var f: PackedFloat32Array = u.stats.get("dmg_types", PackedFloat32Array([0, 0, 1, 0, 0, 0, 0]))
	var v := PackedInt32Array()
	for t in 7:
		v.append(roundi(dsum * (f[t] if t < f.size() else 0.0)))
	return {"type": 0, "slot": "", "v": v, "range": 0.0, "n1": 0}


## The target's armour per damage type as reads it.
func _armour(o: GameUnit) -> PackedInt32Array:
	var arm: PackedFloat32Array = o.stats.get("armor", PackedFloat32Array())
	var torso: PackedFloat32Array = o.stats.get("part_armor", {}).get("torso", PackedFloat32Array())
	var out := PackedInt32Array()
	for t in 7:
		out.append(roundi((arm[t] if t < arm.size() else 0.0) + (torso[t] if t < torso.size() else 0.0)))
	return out


## the sum over the 7 damage types of max(0, damage - armour).
func _damage(opt: Dictionary, o: GameUnit) -> int:
	var arm := _armour(o)
	var d := 0
	for t in 7:
		d += maxi(0, int(opt.v[t]) - arm[t])
	return d & 0xffff


## option `opt` of `u` against candidate `c`, out of the
## candidate list `list` (enemies for list A, friends for list B); n = its
## size, k = the option's targets - 1, bonus = 10 for the current target `cur`.
##   0 weapon:    bonus + D
##   1 bolt:      1.3 D + bonus + 3 + D min(n - 1, k)
##   2 area:      S = the D of every candidate within the radius of c;
##                1.3 S + bonus + 3 + S min(n, k)
##   3 lasting:   as 2 with S x floor(duration / 8); never at a unit walking a path
##   4-6 effects: bonus + 1 + min(n - 1, k); never at a unit that has the effect
##   7 heal:      never above round(effective max HP) - 2 HP; below a third of
##                it 3 x c's power (+ its power again while the caster is
##                unhurt), else bonus + 5 + 2 min(n - 1, k).
## Then, unless already under `thr`: - 25 x the distance (types 0-4) or - 250 x
## the distance beyond the option's range (5-7), and for 0-3, if still not
## under `thr`, - 2 x (HP / Dd, integer division; 20 when Dd = 0), Dd = the
## damage term (D, S or S x duration / 8).
func _score(u: GameUnit, c: GameUnit, opt: Dictionary, list: Array, cur, thr: float) -> float:
	var bonus := 10.0 if c == cur else 0.0
	var n := list.size()
	var k := int(opt.n1)
	var ty := int(opt.type)
	var score := 0.0
	var dd := 0
	match ty:
		0:
			dd = _damage(opt, c)
			score = bonus + dd
		1:
			dd = _damage(opt, c)
			score = 1.3 * dd + bonus + 3.0 + dd * mini(n - 1, k)
		2, 3:
			if ty == 3 and not c.path.is_empty():
				return NO_SCORE
			var r2: float = opt.radius * opt.radius
			for o: GameUnit in list:
				if o.pos.distance_squared_to(c.pos) <= r2:
					dd += _damage(opt, o)
			dd &= 0xffff
			if ty == 3:
				dd = ((int(opt.dur) / 4) >> 1) * dd & 0xffff
			score = 1.3 * dd + bonus + 3.0 + dd * mini(n, k)
		4, 5, 6:
			if c.buffs.has(opt.key):
				return NO_SCORE
			score = bonus + 1.0 + mini(n - 1, k)
		7:
			var eff := c.max_hp
			for p in c.parts:
				if p.state == 1:
					eff -= c.max_hp * float(p.lethal)
			var hp := int(c.hp)
			if hp > roundi(eff) - 2:
				return NO_SCORE
			if 3 * hp < roundi(eff):
				var pw: float = options(c).power
				score = 3.0 * pw + (pw if u.hp >= u.max_hp else 0.0)
			else:
				score = bonus + 5.0 + 2.0 * mini(n - 1, k)
	if score < thr:
		return score
	var d := u.pos.distance_to(c.pos)
	if ty <= 4:
		score -= 25.0 * d
	else:
		score -= 250.0 * maxf(0.0, d - float(opt.range))
	if ty <= 3 and score >= thr:
		score -= 2.0 * (int(c.hp) / dd if dd != 0 else 20)
	return score


## The enemies an AI unit picks from (: the ones it notices
## hostile, alive, not on its ignore list).
func enemies(u: GameUnit) -> Array:
	var out := []
	var sight: float = u.stats.sight
	var f := u.faction
	for o: GameUnit in world.live_units_near(u.pos, sight):
		if o.faction == f or o.dead or o.hidden or not world.is_enemy(u, o) or o.is_invisible():
			continue
		if ignored(u, o) or not can_notice(u, o, sight):
			continue
		out.append(o)
	if out.size() > 1:
		out.sort_custom(func(x, y): return u.pos.distance_squared_to(x.pos) < u.pos.distance_squared_to(y.pos))
	return out


## The caster and the allies list B is tried on (
## ): the caster first, then the AI's nearby list filtered
## choice time — alive, not on the ignore list
## and a friend by the diplomacy mask ([side] bit target side
## the remake's relation 0). The list itself (
## ) holds every unit in the 16 m grid cells round the unit, with
## no side / visibility test, and is rebuilt when its countdown (AI
## -1 per AI tick) falls below 1, then reset to (rand() & 3) + 8 ticks.
## **Approx.**: the cells are taken as a circle of the unit's sight (the original:
## max(sight x factor) / 16 m through the cell table
## whose shape is not decoded).
func _friends(u: GameUnit) -> Array:
	var near: Array = u.get_meta("ai_near", [])
	if world.time >= float(u.get_meta("ai_near_t", -1.0)):
		near = world.live_units_near(u.pos, u.stats.sight).filter(func(o: GameUnit): return o != u)
		u.set_meta("ai_near", near)
		u.set_meta("ai_near_t", world.time + float((randi() & 3) + 8) * GameUnit.TICK)
	var out := [u]
	for o in near:
		if is_instance_valid(o) and not o.dead and not o.hidden and world.relation(u.faction, o.faction) == 0 \
				and not ignored(u, o):
			out.append(o)
	return out


## The AI's ignore list (AI: {unit, ticks} pairs). (t, n)
## adds t with n ticks, or raises an entry to max(ticks, n);
## the start of every AI tick, takes 1 off every entry and drops it below 0.
## Added during tick T's choice with n = 0x14, the unit is left out of the
## 20 choices T + 1 .. T + 20 and back at T + 21 (1.1 s).
func ignore(u: GameUnit, t: GameUnit, n: int) -> void:
	var ign: Dictionary = u.get_meta("ai_ignore", {})
	var until := world.time + (float(n) + 0.5) * GameUnit.TICK
	ign[t.uid] = maxf(float(ign.get(t.uid, -1.0)), until)
	u.set_meta("ai_ignore", ign)


func ignored(u: GameUnit, t: GameUnit) -> bool:
	return world.time < float((u.get_meta("ai_ignore", {}) as Dictionary).get(t.uid, -1.0))


func _flying(o: GameUnit) -> bool:
	return o.has_meta("flying") or (o.move_class() == 0 and float(o.proto.get("altitude", 0.0)) >= 0.5)


## The unit's current AI action: (option slot, target) of an attack or cast
## order the AI gave it (AI states 3 / 4).
func _current(u: GameUnit) -> Dictionary:
	if not u.order.get("ai", false):
		return {}
	var t = u.order.get("target")
	if not (is_instance_valid(t) and t is GameUnit) or t.dead:
		return {}
	match u.order.get("type", ""):
		"attack": return {"slot": "", "t": t}
		"cast": return {"slot": String(u.order.spell), "t": t}
	return {}


## the best (option, target) for `u`. The current action is
## scored first (threshold -1e20) and kept when nothing beats it; every
## enemy x list-A option (unless `friendly_only`) and every friend x list-B
## option (type 6 left out when `friendly_only`) that scores higher is a
## candidate; from the highest down, the first that passes the area check
##  and is reachable is taken; a target that
## fails goes on the ignore list. No random rolls, no mana check.
## Returns {opt, t} or {}.
func choose(u: GameUnit, foes: Array, friendly_only := false) -> Dictionary:
	var os := options(u)
	if os.b.is_empty() and (foes.is_empty() or os.a.is_empty()):
		return {}
	var friends := _friends(u) if not os.b.is_empty() else []
	var best := -1e20
	var cur := {}
	var c := _current(u)
	if not c.is_empty():
		for lst: Array in [os.a, os.b]:
			for o: Dictionary in lst:
				if o.slot == c.slot and cur.is_empty():
					cur = {"opt": o, "t": c.t, "list": foes if lst == os.a else friends}
		if not cur.is_empty() and not _area_safe(u, cur.opt, cur.t):
			cur = {}
		if not cur.is_empty():
			if foes.size() == 1 and os.b.is_empty():
				return cur
			var s := _score(u, cur.t, cur.opt, cur.list, cur.t, -1e20)
			if s < -1e20:
				cur = {}
			else:
				best = s
	var cur_t = cur.get("t")
	var kept := []
	if not friendly_only:
		for e: GameUnit in foes:
			for o: Dictionary in os.a:
				var s := _score(u, e, o, foes, cur_t, best)
				if s > best:
					kept.append([s, o, e])
	for f: GameUnit in friends:
		for o: Dictionary in os.b:
			if friendly_only and o.type == 6:
				continue
			var s := _score(u, f, o, friends, cur_t, best)
			if s > best:
				kept.append([s, o, f])
	kept.sort_custom(func(x, y): return x[0] > y[0])
	for i in kept.size():
		var e: Array = kept[i]
		if not cur.is_empty() and e[1].slot == cur.opt.slot and e[2] == cur.t:
			return cur
		if _area_safe(u, e[1], e[2]) and (not friendly_only or _near_post(u, e[1], e[2])) \
				and _reach_option(u, e[1], e[2]):
			return {"opt": e[1], "t": e[2]}
		var again := false
		for j in range(i + 1, kept.size()):
			again = again or kept[j][2] == e[2]
		if not again and e[2] != cur_t:
			ignore(u, e[2], 0x14)   # (target, 0x14)
	return cur


##  p5 test (the fear tick and): a
## target 30 m or more from the AI's segment (: 2D
## distance to the segment AI.., see set_post) passes only when
## the action can be done from where the unit stands (
## no walking); a unit with no segment yet (the sentinel x =
## -1313) has every target that far.
func _near_post(u: GameUnit, opt: Dictionary, t: GameUnit) -> bool:
	var seg: Array = u.get_meta("ai_post", [])
	if not seg.is_empty():
		var a: Vector2 = seg[1]
		var b: Vector2 = seg[0]
		var q := Geometry2D.get_closest_point_to_segment(t.pos, a, b)
		if q.distance_to(t.pos) < 30.0:
			return true
	if opt.type == 0:
		return u.pos.distance_to(t.pos) <= u.melee_reach(t)
	return t == u or u.pos.distance_to(t.pos) <= float(opt.range)


## The AI's segment: each Guard / Patrol / Sentry tick puts
## its point and moves the old one to (the first one fills
## both). Remake: the guard home and the sentry point.
func set_post(u: GameUnit, p: Vector2) -> void:
	var seg: Array = u.get_meta("ai_post", [])
	if seg.is_empty():
		u.set_meta("ai_post", [p, p])
	elif seg[0] != p or seg[1] != p:
		u.set_meta("ai_post", [seg[1], p])


## an area spell (types 2 / 3) is not cast where an allied
## walking unit stands within 7 m of the target or the caster is inside the
## radius (a flying caster skips this).
func _area_safe(u: GameUnit, opt: Dictionary, t: GameUnit) -> bool:
	if not opt.type in [2, 3] or _flying(u):
		return true
	if u.pos.distance_to(t.pos) < float(opt.radius):
		return false
	for o: GameUnit in world.live_units_near(t.pos, 7.0):
		if o != u and not o.dead and world.relation(u.faction, o.faction) == 0 and not _flying(o) \
				and o.pos.distance_squared_to(t.pos) < 49.0:
			return false
	return true


##  for an option: the weapon as _reachable; a spell reaches
## its range centre to centre, a point spell never a flyer.
func _reach_option(u: GameUnit, opt: Dictionary, t: GameUnit) -> bool:
	if opt.type == 0:
		return _reachable(u, t)
	if opt.get("point", false) and _flying(t):
		return false
	var reach := float(opt.range)
	if t == u or u.pos.distance_to(t.pos) <= reach:
		return true
	var path := world.nav.find_path(u.pos, t.pos, [u, t], [], 0.0, u.move_class())
	var limit := 3.0 * u.dist3(t) + 10.0
	var end := path[-1] if not path.is_empty() and u.path_fits(path, t.pos, limit) else u.pos
	return end.distance_to(t.pos) <= reach


## Carries out a choice: the weapon -> an attack order
## (command 6), a spell -> a cast at the target unit.
func _act(u: GameUnit, ch: Dictionary) -> void:
	var t: GameUnit = ch.t
	if ch.opt.slot == "":
		_attack(u, t)
	else:
		u.command({"type": "cast", "spell": ch.opt.slot, "target": t, "range": float(ch.opt.range), "ai": true})


func _attack(u: GameUnit, t: GameUnit) -> void:
	u.command({"type": "attack", "target": t, "aim": -1, "ai": true})


## The Aggression motivation chooses every 55 ms AI tick (its evaluation
## run for every unit each tick unless no
## living hostile unit is noticed, AI); its tick issues
## the choice at once when it differs from the current action.
## No counter or cooldown. Remake: while an AI attack / cast order runs, once
## per logic tick. Returns true when the order changed.
func rechoose(u: GameUnit) -> bool:
	if u.controller >= 0 or not u.order.get("ai", false) or u.mode == "fear":
		return false
	var now := world.time
	if now < float(u.get_meta("ai_rechoose", 0.0)):
		return false
	u.set_meta("ai_rechoose", now + GameUnit.TICK - 0.0001)
	var foes := enemies(u)
	if foes.is_empty():
		return false
	var ch := choose(u, foes)
	if ch.is_empty():
		return false
	var c := _current(u)
	if not c.is_empty() and ch.opt.slot == c.slot and ch.t == c.t:
		return false
	if ch.opt.slot == "":
		u.order = {"type": "attack", "target": ch.t, "aim": -1, "ai": true}
	else:
		u.order = {"type": "cast", "spell": ch.opt.slot, "target": ch.t, "range": float(ch.opt.range),
			"ai": true, "then": u.order}
	u.path = PackedVector2Array()
	return true


func on_attacked(u: GameUnit, by: GameUnit) -> void:
	if by == null or u.mode == "fear":
		return
	# hit by a unit that is not a diplomacy friend -> suspicion
	# 1000 (-2 a tick) at the attacker.
	if world.relation(u.faction, by.faction) != 0:
		suspect(u, by.pos, 1000.0)
	if not u.order.get("type", "") in ["attack", "cast"]:
		_attack(u, by)
	hit_hook(u, by)


## The unit's reaction line (acks.db section 2; state 6 "to
## Aggression" -> (0x2e)), heard by the players the original finds
## the unit visible to (approx.: a hero of theirs within 30 m).
func _react(u: GameUnit, code: int) -> void:
	if world.session and not EIAcks.lines([u.proto.get("name", ""), u.proto.get("base_race", "")], code).is_empty():
		world.session.broadcast({"t": "ack", "uid": u.uid, "code": code, "near": 30.0})


## Idle chatter: every motivation tick of the calm motivations (the original
## ) posts AI message 1 -> line 0x31
## when rand % 1001 == 1, and the Aggression motivation's tick (
## ) message 2 -> line 0x32 the same way. Approx.: one
## roll per 1/20 s game tick.
func chatter(u: GameUnit, dt: float) -> void:
	if u.controller >= 0 or u.dead or u.has_meta("hero") or u.mode == "fear":
		return
	if randf() < dt / GameWorld.TICK / 1001.0:
		_react(u, EIAcks.NPC_IN_AGGRESSION if u.order.get("type", "") == "attack" else EIAcks.NPC_REST)


## Suspicion (the original "Suspection" motivation,: priority
## tick, enter, leave).
## The perception (AI) keeps one suspected point with a level and a
## per-tick delta (: level += delta every
## tick, no clamp); a new point replaces it only when its level is higher
## . Sources: an attack target the unit no longer notices
## (: 1000, -2), being hit by a non-friend (
## 1000, -2 at the attacker), Fireworks (case 0x12).
## The motivation keeps its own level M: a new point copies the
## perception's, else M = min(M, P) each tick; it is its priority. The current
## motivation gets +100 and calm ones are 50
## so it takes over above 150 and ends below -50. Aggression (10000) comes
## first (think()).
func suspect(u: GameUnit, at: Vector2, level: float, delta := -2.0) -> void:
	if u.controller >= 0 or u.dead:
		return
	var old: Dictionary = u.get_meta("suspect", {})
	if not old.is_empty() and level <= _susp_level(old):
		return
	u.set_meta("suspect", {"pos": at, "l0": level, "d": delta, "t0": world.time, "last": world.time,
		"m": level, "active": old.get("active", false), "look": [], "busy": false})


## The perception's level now (: +delta per 55 ms tick).
func _susp_level(s: Dictionary) -> float:
	return float(s.l0) + float(s.d) * floorf((world.time - float(s.t0)) / GameUnit.TICK)


## The Suspection motivation's tick, run from think:
## entering posts AI message 5 -> reaction 0x2f "to
## Suspection", sets the combat stance (creature) and
## walks to the exact point (order = 0), then looks round 1 - 4 times
## (rand & 3) + 1 in random directions for 10 - 40 ticks each (
## ). While going to or looking at the point it loses 5 a tick
## within 5 m of it; idle, it picks a spot within 5 m of the point
## (10 tries; failing loses 5) and goes there, every new move
## copying the perception's level into M. Taken literally the tick then sends
## the unit back to the point at once (the spot is not within sqrt 0.2 of it),
## so the remake keeps it at the point looking round again. Leaving
##  clears the combat stance; there is no line.
## Idle, it loses 50 a tick while its last order failed (creature
## set with the failure acks, cleared by a new order).
## Approx.: run on the unit's AI tick while idle with the ticks elapsed; the
## spot's path-cost test is left out (see find_spot).
func _investigate(u: GameUnit) -> bool:
	if not u.has_meta("suspect") or u.mode in ["fear", "follow"]:
		return false
	var s: Dictionary = u.get_meta("suspect")
	var at: Vector2 = s.pos
	var p := _susp_level(s)
	var k := floorf((world.time - float(s.last)) / GameUnit.TICK)
	s.last = float(s.last) + k * GameUnit.TICK
	if not s.active:
		s.m = minf(float(s.m), p)
		if float(s.m) > 150.0:
			s.active = true
			_react(u, EIAcks.NPC_SUSPICION)
			u.alert = true
			_susp_go(u, s, at, p)
			return true
		if p < -50.0:
			u.remove_meta("suspect")
		return false
	if bool(s.busy) and u.pos.distance_to(at) < 5.0:
		s.m = float(s.m) - 5.0 * k
	s.m = minf(float(s.m), p)
	if float(s.m) < -50.0:
		u.remove_meta("suspect")
		u.alert = false
		return false
	var look: Array = s.look
	# Idle: -50 while the last order failed (creature).
	if not s.busy and u.order_failed:
		s.m = float(s.m) - 50.0
	if u.pos.distance_to(at) > 1.0 and s.busy == false:
		_susp_go(u, s, at, p)
		return true
	# the look round stops when the walk failed more
	# than 1 m from its destination.
	if u.order_failed and u.pos.distance_to(at) > 1.0:
		look.clear()
	if not look.is_empty():
		var g: Array = look.pop_front()
		u.command({"type": "wait", "t": float(g[1]) * GameUnit.TICK, "face": float(g[0])})
		return true
	if s.busy:
		s.busy = false
		return true
	# Idle at the point: a spot within 5 m of it.
	var spot := find_spot(u, at, 5.0)
	if spot == Vector2.INF:
		s.m = float(s.m) - 5.0
		return true
	_susp_go(u, s, at, p)
	return true


## A new move of the motivation: to the point, then the look round
## (with -1: (rand & 3) + 1 glances of 10 - 40 ticks).
func _susp_go(u: GameUnit, s: Dictionary, at: Vector2, p: float) -> void:
	s.m = p
	s.busy = true
	var look := []
	for i in (randi() & 3) + 1:
		look.append([randf() * TAU, randi_range(10, 40)])
	s.look = look
	u.move_to(world.nav.nearest_walkable(at), false)


## The AI hit hook (from the hit, a spell cast
## the unit and the death): unless the attacker is a
## unit that is a diplomacy friend, a call for help at the attacker's spot
## (no attacker: the unit's own).
func hit_hook(u: GameUnit, by: GameUnit) -> void:
	if by and is_instance_valid(by):
		if world.relation(u.faction, by.faction) != 0:
			call_for_help(u, by.pos)
	else:
		call_for_help(u, u.pos)


## every unit in the unit grid within the AI's help radius
## (AI: the.mob logic "help" radius, ai.reg [Logic] CallForHelpRadius
## when it is CallForHelpRadiusDefault) that is a diplomacy
## friend of the caller gets a delayed sound at `at` (
## its position entries of 26 ticks or more are dropped, the
## new one counts 26)., every AI tick: -1, and below 0 the unit
## becomes suspicious of the spot (900, -3 a tick) unless its level is 900
## or more.
func call_for_help(u: GameUnit, at: Vector2) -> void:
	var r := float(logic(u).get("help_radius", GameData.ai_value("Logic", "CallForHelpRadius", 7.0)))
	if r == GameData.ai_value("Logic", "CallForHelpRadiusDefault", 7.0):
		r = GameData.ai_value("Logic", "CallForHelpRadius", 7.0)
	for o: GameUnit in world.live_units_near(u.pos, r):
		if o == u or o.controller >= 0 or world.relation(u.faction, o.faction) != 0:
			continue
		_help = _help.filter(func(e: Array): return not (e[0] == o and int(e[2]) >= 26))
		_help.append([o, at, 26])


var _help := []   # delayed sounds: [unit, spot, ticks left]

## (source, loudness, ticks, point): a sound at the source unit.
## Every unit within 50 m that is hostile to the source's side
##  and whose perception level is below 900 hears it when its
## hearing factor × hearing sense × loudness exceeds the 3D
## distance; its delayed sounds (AI) of `ticks` or more are dropped
##  and one at the source's spot counting `ticks` is added
##  — the same delayed suspicion as a call for help
## (: 900, −3). Callers: a cast (: loudness = the
## caster's hearing detectability × 2, 26 ticks, unless the spell's
## record is 1).
func noise_event(src: GameUnit, loud: float, ticks := 26) -> void:
	var at := src.pos
	var z := world.ground_at(at.x, at.y)
	for o: GameUnit in world.live_units_near(at, 50.0):
		if o == src or o.dead or o.controller >= 0 or not world.is_enemy(o, src):
			continue
		if o.has_meta("suspect") and _susp_level(o.get_meta("suspect")) >= 900.0:
			continue
		var d := Vector3(o.pos.x - at.x, o.pos.y - at.y, world.ground_at(o.pos.x, o.pos.y) - z).length()
		if not o.hear_factor() * o.sense(3) * loud > d:
			continue
		_help = _help.filter(func(e: Array): return not (e[0] == o and int(e[2]) >= ticks))
		_help.append([o, at, ticks])



var _tick_n := 0

## Per 55 ms logic tick (GameWorld): the step noise, then the delayed sounds
func tick() -> void:
	_tick_n += 1
	#  (unit update): when (world tick & unit = 15) == 0
	# i.e. every 16th tick, makes the step noise:
	# with loudness = movement noise x hearing detectability
	# x the ground's StepSound (folded into GameUnit.noise), 26 ticks.
	if _tick_n & 15 == 0 and world.authority:
		for u: GameUnit in world.units.values():
			if not u.dead and not u.hidden:
				var loud := u.noise() * u.detect(3)
				if loud > 0.0:
					noise_event(u, loud)
	if _help.is_empty():
		return
	var keep := []
	for e: Array in _help:
		e[2] = int(e[2]) - 1
		if int(e[2]) >= 0:
			keep.append(e)
		elif is_instance_valid(e[0]) and not e[0].dead:
			suspect(e[0], e[1], 900.0, -3.0)
	_help = keep


## a unit that had noticed a diplomacy friend that is now dead
## ("sees corpse of unit") becomes suspicious (800, -3 a tick) unless its
## level is 800 or more. Approx.: "had noticed" = notices it at its death
## (can_notice); the spot is taken as the corpse's.
func on_corpse(dead: GameUnit) -> void:
	for o: GameUnit in world.live_units_near(dead.pos, 40.0):
		if o == dead or o.controller >= 0 or world.relation(o.faction, dead.faction) != 0:
			continue
		if can_notice(o, dead, o.stats.sight):
			suspect(o, dead.pos, 800.0, -3.0)


## The Sentry tick (motivation) when its state is
## 0 (idle): the segment moves on to the point (=
## 35 / 80), a look round is prepared at the point (with no
## direction bias; the stay is ai.reg [Logic] SentryStayTime, or GuardStayTime
## with the rest flag when the table random % 11 == 0) and the unit walks
## there ((point, 0, 0, 1e6), the unit's gait); state 2.
##  then runs the look round (`_look_tick`).
func _sentry(u: GameUnit, at: Vector2) -> void:
	if _calm_busy(u):
		return
	set_post(u, at)
	var rest := randi() % 11 == 0
	var stay := GameData.ai_value("Logic", "GuardStayTime" if rest else "SentryStayTime", 10.0)
	_calm_go(u, Vector3(at.x, at.y, 0.0), Vector3.ZERO, stay, rest)


## The Guard tick (motivation; point, radius
##  (GuardRadius when < 0), stay (GuardStayTime when < 0), failure
## count) when its state is 0: the segment moves on to the point (
## = radius + 35 / + 80); a spot within the radius of the point
## failing, the count + 1, and from 101 failures on also a
## spot within the radius round the unit itself (both failing: nothing this
## tick); found, the count is 0 and the look round at the spot is biased
## outwards: d = spot − point (3D, the spot at height 0) times
## |d| / radius · 0.5 (the rest flag when random % 11 == 0)
## the unit walks to the spot; state 2.
func _guard(u: GameUnit, point: Vector3, radius: float, stay: float) -> void:
	if _calm_busy(u):
		return
	if radius < 0.0:
		radius = GameData.ai_value("Logic", "GuardRadius", 10.0)
	if stay < 0.0:
		stay = GameData.ai_value("Logic", "GuardStayTime", 10.0)
	var at := Vector2(point.x, point.y)
	set_post(u, at)
	var c: Dictionary = u.get_meta("calm", {})
	var spot := find_spot(u, at, radius)
	if spot == Vector2.INF:
		c.fails = int(c.get("fails", 0)) + 1
		u.set_meta("calm", c)
		if int(c.fails) < 101:
			return
		spot = find_spot(u, u.pos, radius)
		if spot == Vector2.INF:
			return
	c.fails = 0
	u.set_meta("calm", c)
	var d := Vector3(spot.x - point.x, spot.y - point.y, -point.z)
	if radius != 0.0:
		d *= d.length() / radius * 0.5
	_calm_go(u, Vector3(spot.x, spot.y, 0.0), d, stay, randi() % 11 == 0)


##  + the move of a calm motivation: (rand & 3) + 1 glances
## each the first of up to six random directions (cos a, sin a) + `bias`
## whose terrain ray from 1.4 m over the ground at the destination to twice
## that vector is clear (= 1; else one more unchecked), for
## a random time between stay·15 / 4 and stay·15 ticks (40 when stay < 0).
## With the rest flag, a unit not in the combat stance whose figure is not a
## human ("unhu…") gets one glance of n × that time, resting (
## the Rest order 0xb). Approx.: the rest pose itself is not shown.
func _calm_go(u: GameUnit, dest: Vector3, bias: Vector3, stay: float, rest: bool, given := []) -> void:
	var n := (randi() & 3) + 1 if given.is_empty() else 0
	var at := Vector2(dest.x, dest.y)
	var eye := world.ground_at(at.x, at.y) + 1.4
	var tmax := stay * 15.0 if stay >= 0.0 else 40.0
	if rest:
		var fig := String(u.model.template).to_lower() if u.model else ""
		if u.alert or fig.begins_with("unhu"):
			rest = false
		else:
			tmax *= n
			n = 1
	var look := []
	for i in n:
		var v := Vector3.ZERO
		for k in 7:
			var a := randf() * TAU
			v = Vector3(cos(a) + bias.x, sin(a) + bias.y, bias.z)
			if k == 6 or world.terrain_ray(at, eye, at + Vector2(v.x, v.y) * 2.0, eye + v.z * 2.0) >= 1.0:
				break
		look.append([atan2(v.y, v.x), roundi((tmax - tmax * 0.25) * randf() + tmax * 0.25), rest])
	if not given.is_empty():
		look = given   # a patrol point's own glances
	var c: Dictionary = u.get_meta("calm", {})
	c.busy = true
	c.dest = at
	c.look = look
	c.until = -1.0
	u.set_meta("calm", c)
	var to := world.nav.nearest_walkable(at)
	if u.pos.distance_to(at) > 0.5 and u.pos.distance_to(to) > 0.5:   # there: the move ends at once
		u.command({"type": "move", "to": to, "run": u.get_meta("script_run", false), "calm": true})


## the look round of a calm motivation in state 2 (run every
## AI tick): nothing while the unit walks; a walk that failed (creature
## ) more than 1 m from the destination ends it (state 0); else each
## glance turns the unit, then holds for its ticks (the AI
## keeps running); no glance left -> state 0, the motivation's tick picks
## the next move. Returns true while the motivation is busy.
func _calm_busy(u: GameUnit) -> bool:
	var c: Dictionary = u.get_meta("calm", {})
	if not c.get("busy", false):
		return false
	if u.order.get("calm", false):
		return true
	var look: Array = c.look
	if u.order_failed and u.pos.distance_to(c.dest) > 1.0:
		look.clear()
	if float(c.until) >= 0.0:
		if world.time < float(c.until):
			return true
		c.until = -1.0
		look.pop_front()
		return true
	if not look.is_empty():
		var g: Array = look[0]
		if absf(wrapf(float(g[0]) - u.facing, -PI, PI)) > 0.001:
			u.command({"type": "rotate", "angle": float(g[0])})
			return true
		c.until = world.time + float(g[1]) * GameUnit.TICK
		return true
	c.busy = false
	return true


## The unit's current logic descriptor (AI = its index; 0 unless an
## alarm switched it); the unit record itself without any.
func logic(u: GameUnit) -> Dictionary:
	var ls: Array = u.info.get("logic", [])
	var i := int(u.get_meta("logic_idx", 0))
	return ls[i] if i < ls.size() else u.info


## The Patrol motivation. Built
##  case 2 from the descriptor's guard points: each point moved to
## the centre of its 0.5 m cell ((round(2x) + 0.5) / 2, same for y, z 0), its
## action points made into glances: direction = atan2 from the
## point to the look point (0 when equal), the wait (a short, ticks), the turn
## speed and the rest flag. Not cyclic (UNIT_LOGIC_CYCLIC 0): the points are
## appended once more in reverse order, the walk goes back.
## No points: priority -1000 ("Unit %i has no patrol points"
## ); the remake keeps the unit a Sentry then.
## Tick in state 0: index + 1 (wrapping; it starts at 0, so the first
## walk goes to point 1), the point's glances (none: look round
## with no bias and stay -1, i.e. 40 ticks, no rest), segment
## to the point (= 35 / 80), the walk (1e6), state
## 2; then runs the glances (`_calm_busy`).
## Approx.: a glance's turn speed is not applied (
## the shipped .mob files 9404 of 9434 action points have turn speed 0; 26
## have 5, 2 have 30, 2 have 450).
func _patrol(u: GameUnit, home: Vector2) -> void:
	if _calm_busy(u):
		return
	var pts := _patrol_points(u)
	if pts.is_empty():
		_sentry(u, home)
		return
	var c: Dictionary = u.get_meta("calm", {})
	var idx := (int(c.get("patrol_i", 0)) + 1) % pts.size()
	c.patrol_i = idx
	u.set_meta("calm", c)
	var pt: Array = pts[idx]
	var at: Vector2 = pt[0]
	set_post(u, at)
	if (pt[1] as Array).is_empty():
		_calm_go(u, Vector3(at.x, at.y, 0.0), Vector3.ZERO, -1.0, false)
		return
	_calm_go(u, Vector3(at.x, at.y, 0.0), Vector3.ZERO, -1.0, false, (pt[1] as Array).duplicate(true))


func _patrol_points(u: GameUnit) -> Array:
	var lg := logic(u)
	if lg.has("_patrol"):
		return lg._patrol
	var out := []
	for gp: Dictionary in lg.get("guard_points", []):
		var p: Vector3 = gp.get("position", Vector3.ZERO)
		var at := Vector2((roundf(p.x * 2.0) + 0.5) * 0.5, (roundf(p.y * 2.0) + 0.5) * 0.5)
		var look := []
		for ap: Dictionary in gp.get("actions", []):
			var lp: Vector3 = ap.get("look", p)
			var a := 0.0
			if lp.x - p.x != 0.0 or lp.y - p.y != 0.0:
				a = atan2(lp.y - p.y, lp.x - p.x)
			look.append([a, int(ap.get("wait", 0)), int(ap.get("action_flag", 0)) & 1 != 0])
		out.append([at, look])
	if int(lg.get("cyclic", 1)) == 0:
		for i in range(out.size() - 1, -1, -1):
			out.append(out[i])
	lg._patrol = out
	return out


## World alarms 0..4 (world + n·16: set flag, raise tick, x, y; script
## IsAlarm 0x67, AlarmTime 0x8b, AlarmPosX / Y 0x8c / 0x8d).
func alarm(i: int) -> Dictionary:
	var al: Array = world.get_meta("alarms", [])
	return al[i] if i >= 0 and i < al.size() else {"on": false, "time": 0, "pos": Vector2.ZERO}


## (n, position, force): alarm n (0..4) is raised unless already
## set (force: script InvokeAlarm 0x43; alarm 0 forced clears all five first):
## set flag, the world tick, the position; then every AI unit (not a player's)
## switches to its descriptor n when that one is marked for use (UNIT_LOGIC
## ) or n is 0 (: the AI is rebuilt
## not alerted, the raise countdown back to 1).
func invoke_alarm(i: int, at: Vector2, force: bool) -> void:
	if i < 0 or i >= 5:
		return
	var al: Array = world.get_meta("alarms", [])
	while al.size() < 5:
		al.append({"on": false, "time": 0, "pos": Vector2.ZERO})
	if al[i].on and not force:
		return
	if i == 0 and force:
		for k in 5:
			al[k] = {"on": false, "time": 0, "pos": Vector2.ZERO}
	al[i] = {"on": true, "time": _tick_n, "pos": at}
	world.set_meta("alarms", al)
	for u: GameUnit in world.units.values():
		if u.dead or u.controller >= 0 or u.has_meta("hero"):
			continue
		var ls: Array = u.info.get("logic", [])
		if i < ls.size() and (int(ls[i].get("alarm_use", 0)) != 0 or i == 0):
			u.set_meta("logic_idx", i)
			u.remove_meta("calm")
			u.remove_meta("alerted")
			u.mode = "standard"
			u.mode_data = {}


## an AI that has noticed a hostile (its enemy list) is alerted
## (AI, descriptor field being 0 or 2); while alerted its
## countdown (AI, at least 1) runs out and, when its descriptor names an
## alarm, that alarm is raised at the unit (not forced).
## The countdown is set to max(1, descriptor) and counted
## down once per AI tick while alerted; raising posts AI message 8 ("ALARM
## ALARM ALARM",: debug text, no speech line).
## Approx.: the countdown is taken as reached at once (descriptor is not
## a.mob field, never writes it; its default is not traced).
func _alarm_check(u: GameUnit) -> void:
	var n := int(logic(u).get("alarm_raise", 0))
	if n == 0 or u.has_meta("alerted"):
		return
	if not enemies(u).is_empty():
		u.set_meta("alerted", true)
		invoke_alarm(n, u.pos, false)


## a random spot within `r` of `at` for a calm or suspicious
## unit (AI is a cooldown: while > 0 it is counted down by one per call
## and nothing is found). x, y uniform in ±r, re-rolled up to ten times while
## outside the circle (the last roll is kept); it fails where the ground's
## largest height step to the four neighbour cells exceeds 0.3 m
## where a diplomacy friend (the unit itself too) stands
## within 2.5 × the unit's radius, or where no path within
## 3 · d + 10 leads (d = the 3D distance from the unit to the
## spot taken at height 0) — then the cooldown is min(10, round(d / 3)).
## Approx.: the path cost test (cost > d · 10000) is left out.
func find_spot(u: GameUnit, at: Vector2, r: float) -> Vector2:
	var cool := int(u.get_meta("spot_cool", 0))
	if cool > 0:
		u.set_meta("spot_cool", cool - 1)
		return Vector2.INF
	var q := Vector2(randf_range(-r, r), randf_range(-r, r))
	for i in 10:
		if q.length_squared() <= r * r:
			break
		q = Vector2(randf_range(-r, r), randf_range(-r, r))
	var spot := at + q
	if world.nav.cell_slope(spot) > 0.3:
		return Vector2.INF
	var fr := u.body_radius() * 2.5
	for o: GameUnit in world.live_units_near(spot, fr):
		if o.pos.distance_squared_to(spot) < fr * fr and (o == u or world.relation(o.faction, u.faction) == 0):
			return Vector2.INF
	var d := Vector3(spot.x - u.pos.x, spot.y - u.pos.y, -world.ground_at(u.pos.x, u.pos.y)).length()
	var path := world.nav.find_path(u.pos, spot, [u], [], 0.0, u.move_class())
	if path.is_empty() or not u.path_fits(path, spot, d * 3.0 + 10.0):
		u.set_meta("spot_cool", mini(10, roundi(d / 3.0)))
		return Vector2.INF
	return spot


func _home(u: GameUnit) -> Vector2:
	var lg := logic(u)
	if lg.has("guard_point"):
		var gp: Vector3 = lg.guard_point
		return Vector2(gp.x, gp.y)
	if u.info.has("position"):
		var p: Vector3 = u.info.position
		return Vector2(p.x, p.y)
	return u.pos


func nearest_enemy(u: GameUnit, radius: float) -> GameUnit:
	var best: GameUnit = null
	var bd := radius
	for o: GameUnit in world.live_units_near(u.pos, radius):
		if o.dead or o.hidden or o.is_invisible() or not world.is_enemy(u, o):
			continue
		var d := u.pos.distance_to(o.pos)
		if not can_notice(u, o, radius):
			continue
		if d < bd:
			bd = d
			best = o
	return best


## Whether `u` notices `o` (the original; script UnitSee / GroupSee
## pass their own sight `radius`). By any of:
##   sight: distance <= radius x o.vis_factor x u.sight_factor x o.detect(sight)
##     inside u's vision cone (race vision arc) and times the terrain ray
##     (World.sight_ray)
##   peripheral vision: in front of u within its prototype "peripheral" range;
##   life sense: distance < o.detect(life) x u.sense(life).
## Hearing is not part of it: steps and casts are noise events (noise_event,
## ) that make the listener suspicious after their delay.
func can_notice(u: GameUnit, o: GameUnit, radius: float) -> bool:
	if o.hidden:
		return false
	var d := u.pos.distance_to(o.pos)
	var ang := absf(wrapf((o.pos - u.pos).angle() - u.facing, -PI, PI))
	var r := (radius + u.sense_bonus(0)) * o.vis_factor() * u.sight_factor() * o.detect(0)
	if d <= r and ang <= deg_to_rad(float(u.race.get("vision_arc", 180.0))) * 0.5 \
			and d < world.sight_ray(u, o) * r:
		return true
	if ang <= PI * 0.5 and d < float(u.proto.get("peripheral_skills", 0.0)) and o.detect(0) > 0.0:
		return true
	return d < o.detect(2) * u.sense(2)

