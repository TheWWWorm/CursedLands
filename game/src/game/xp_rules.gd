class_name XpRules
extends RefCounted
## Experience distribution: the original (party experience) and its
## callers, plus the remake's co-op option "Full experience for every party
## member" (GameData option "coop_full_xp").
##
## the original (player, amount) (nothing happens for amount 0):
## - player given (branch): the player's party list is
##   walked; every member that is alive (== 0) and a unit (
##   == 0x32: heroes, hired mercenaries, tamed animals) is counted, and each
##   gets amount / count (on the unit; a hero of the player's
##   roster also on its record).
## - player 0 / none (network games): every player of the server's
##   list with a connection and exactly one hero in its roster (
##   == 1) whose unit exists gets amount × sqrt(E) / max(ΣsqrtE
##   0.01), E = the hero's experience plus its (negative) death debt
##    — the more experienced hero gets more. Mercenaries and animals get
##   nothing; the players are told with net message 0x18.
## -: each share × 1.04^(Int − 25) (perks
##   included) is added to the death debt (≤ 0) first; whatever is
##   above 0 goes to the experience.
## Callers: kill (network game: none, else the killer's party
## ), script QuestComplete (network game: none — only for
## the LMP map's own mission quest, —, else player arg 0's
## party), conversation reward (the talking player), quest map
## reward (player 0).
## Remake: the network branch is used in online co-op for kills and
## QuestComplete of every campaign quest (the campaign has no LMP mission
## quest); "Full experience" (on by default, co-op only) gives every co-op
## player's hero and every living mercenary the whole amount instead. Single
## player always follows the original (equal split over the living party: heroes
## mercenaries and tamed animals. Animals keep their own unit XP record;
## only a matching hero also has a separate saved roster record.


## Host: `amount` experience from `source` ("kill", "quest", "talk", "side")
## for `player`'s party (the killer's / the talking player's / player 0).
static func give(s: Session, amount: float, source := "quest", player := 0) -> void:
	if amount == 0.0 or s.world == null:
		return
	var gains := []   # [unit, record, share]
	if s.online and full_experience() and s.lmp.is_empty():   # remake option: not in the original multiplayer game
		gains = _full(s, amount)
	elif s.online and source in ["kill", "quest"]:
		gains = _network_split(s, amount)
	else:
		gains = _party_split(s, amount, player, not s.online and GameData.option("sp_full_xp") != 0)
	for g: Array in gains:
		gain(s, g[0], g[1], g[2])
	# No text window line: the original shows a gain only as each hero's flying
	# "EXP" number (flag 8; `gain` sends it).
	if not gains.is_empty():
		s.sync_state()


## Remake option (co-op host): every party member gets the whole amount.
static func full_experience() -> bool:
	return GameData.option("coop_full_xp") != 0


## × 1.04 ^ (Int − 25) (constants), the
## death debt paid off first. Returns the experience actually added.
static func gain(s: Session, u: GameUnit, h: Dictionary, share: float) -> float:
	if s.lmp_travel and u and is_instance_valid(u) and u.world != s.world:
		return float(s.lmp_travel.with_world(u.world, gain.bind(s, u, h, share)))
	# The x87 computation stays double until the original FST/FSTP stores.
	# A share and both existing record fields enter as native floats.
	var intel := _f32(float(h.get("int", 25.0)) + Perks.attr_bonus(h, "int"))
	var g := _f32(share) * pow(1.04, intel - 25.0)
	var d := g - _f32(float(h.get("exp_debt", 0.0)))   # native is signed negative debt
	var added := 0.0
	if d > 0.0:
		h.exp_debt = 0.0
		var old := _f32(float(h.get("exp_total", h.get("exp", 0.0))))
		h.exp = _f32(_f32(float(h.get("exp", 0.0))) + d)
		h.exp_total = _f32(old + d)
		added = float(h.exp_total) - old
	else:
		h.exp_debt = -_f32(d)
	if u and is_instance_valid(u):
		if not u.dead:   # keep the remake's existing corpse-pool policy
			_refresh_pools(u, h)
		# the gain floats over the hero (cyan, flag 8, FlyingHP).
		var event := {"t": "hitnum", "uid": u.uid, "n": roundi(g), "f": 8}
		if not u.has_meta("hero"):
			h.pools_initialized = true
			event.xp_stats = h.duplicate(true)
		s.broadcast(event)
	return added


## Native unit record, including pets: 5136d0 supplies attributes from the
## NPC row, or HP/3, MP/3 and Int25 from the prototype without an NPC.
## It remains separate from hero metadata and from the victim's kill reward.
static func unit_record(u: GameUnit) -> Dictionary:
	if u.has_meta("hero"):
		return u.get_meta("hero")
	if u.has_meta("xp_stats") and u.get_meta("xp_stats") is Dictionary:
		return u.get_meta("xp_stats")
	var npc := GameData.db.find("npcs", String(u.proto.get("name", "")))
	var total := _f32(float(npc.get("experience", 0.0)))
	var h := {"exp": total, "exp_total": total, "exp_debt": 0.0,
		"str": _f32(float(npc.get("str", 25.0))) if not npc.is_empty() else _f32(_f32(float(u.proto.get("hp", 10.0))) * _f32(1.0 / 3.0)),
		"dex": _f32(float(npc.get("dex", 25.0))) if not npc.is_empty() else _f32(_f32(float(u.proto.get("mana", 0.0))) * _f32(1.0 / 3.0)),
		"int": _f32(float(npc.get("int", 25.0))),
		"perks": Array(npc.get("perks", [])).map(func(code): return String(code).to_lower()),
		"pools_initialized": false}
	u.set_meta("xp_stats", h)
	return h


## Restoring an optional pet record must not change a legacy pet's pools.
static func restore_unit_record(u: GameUnit, record: Dictionary) -> void:
	var h := record.duplicate(true)
	u.set_meta("xp_stats", h)
	if h.get("pools_initialized", false):
		_refresh_pools(u, h)


## 5239b0 recomputes only XP-dependent pools, preserving each body's wounds.
## Ordinary skill, equipment and prototype combat ratings are unchanged by XP.
static func _refresh_pools(u: GameUnit, h: Dictionary) -> void:
	var hp_fraction := u.hp / u.max_hp if u.max_hp > 0.0 else 1.0
	var mp_fraction := u.mana / u.max_mana if u.max_mana > 0.0 else 1.0
	var total := _f32(float(h.get("exp_total", h.get("exp", 0.0))))
	u.max_hp = maxf(1.0, _pool(total, _f32(float(h.get("str", 25.0)) + Perks.attr_bonus(h, "str")), h, "HP"))
	if u.parts.is_empty():
		u.hp = _f32(u.max_hp * hp_fraction)
	u.max_mana = _pool(total, _f32(float(h.get("dex", 25.0)) + Perks.attr_bonus(h, "dex")), h, "MP")
	u.mana = _f32(u.max_mana * mp_fraction)


static func _pool(total: float, attr: float, h: Dictionary, prefix: String) -> float:
	var values := []
	for i in 5:
		values.append(_f32(GameData.ai_value("RPG", "%s Val %d" % [prefix, i + 1], [25.0,30.0,50.0,1.1,1.61][i])))
	var scale := pow(float(values[3]), log(total / float(values[2])) / log(float(values[4]))) if total > 0.0 else 0.0
	var base := attr / float(values[0]) * float(values[1]) * scale
	return _f32(base * (1.0 + Perks.best(h, "health" if prefix == "HP" else "mana") * _f32(0.01)))


static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


## The player whose party `u` belongs to (the original unit), -1 = none.
## A disconnected co-op player's units keep their party ("orphan_of").
static func party_of(u: GameUnit) -> int:
	if u == null or not is_instance_valid(u):
		return -1
	var pet := int(u.get_meta("tame_stage", 0)) >= 3
	if not (u.has_meta("hero") or pet or u.controller >= 0):
		return -1
	if u.controller >= 0:
		return u.controller
	return int(u.get_meta("orphan_of", -1))


## the original: a blow that kills gives the victim prototype's
## experience when the killer is in a party and the victim is not
## (no hostility test).
static func on_kill(s: Session, victim: GameUnit, killer: GameUnit) -> void:
	var p := party_of(killer)
	if p < 0 or party_of(victim) >= 0 or victim.has_meta("hero"):
		return
	give(s, float(victim.proto.get("experience", 1.0)), "kill", p)


## Branch "player given": equal shares over the player's living party units.
## Remake option "sp_full_xp" (`full`): each hero / mercenary gets all of it.
static func _party_split(s: Session, amount: float, player: int, full := false) -> Array:
	var members := []
	var w: GameWorld = s.lmp_travel.owner_world(player) if s.lmp_travel else s.world
	if w == null:
		return []
	for u: GameUnit in w.units.values():
		if not u.dead and party_of(u) == player:
			members.append(u)
	var out := []
	if members.is_empty():
		return out
	var share := _f32(amount) if full else _f32(_f32(amount) / members.size())
	for u: GameUnit in members:
		out.append([u, unit_record(u), share])
	return out


## Branch "network game": players with exactly one hero, weighted by sqrt of
## the hero's experience less its debt.
static func _network_split(s: Session, amount: float) -> Array:
	var rows := []
	var total := 0.0
	for p: Dictionary in s.players.values():
		# The native WorldServer distributes combat / script quest XP only
		# among its registered players. Explicit side rewards use party_split.
		if s.lmp_travel and s.lmp_travel.owner_world(int(p.index)) != s.world:
			continue
		var roster: Array = s.state.heroes.get(int(p.index), [])
		if roster.size() != 1:
			continue
		var h: Dictionary = roster[0]
		var unit := _unit_of(s, h)
		if unit == null:
			continue
		# Approx.: E < 0 (a debt above the experience) would be a NaN in the
		# original's FSQRT; taken as 0 here.
		var w := sqrt(maxf(_f32(float(h.get("exp_total", 0.0))) - _f32(float(h.get("exp_debt", 0.0))), 0.0))
		total = _f32(total + w)
		rows.append([unit, h, w])
	var floor_value := _f32(0.01)
	var denom := total if total >= floor_value else floor_value
	for r: Array in rows:
		r[2] = _f32(float(r[2]) * _f32(amount) / denom)
	return rows


## Remake "Full experience": every connected player's heroes (alive or not,
## as the original's network branch) and every living mercenary get it all.
static func _full(s: Session, amount: float) -> Array:
	var out := []
	for u: GameUnit in s.world.units.values():
		if not u.has_meta("hero"):
			continue
		var h: Dictionary = u.get_meta("hero")
		if h.has("merc"):
			if not u.dead:
				out.append([u, h, amount])
		elif u.controller >= 0 and s.players_include(u.controller):
			out.append([u, h, amount])
	return out


static func _unit_of(s: Session, h: Dictionary) -> GameUnit:
	var worlds: Array = [s.world]
	if s.lmp_travel:
		worlds = s.lmp_travel.contexts.values().map(func(ctx: Dictionary): return ctx.world)
	for w: GameWorld in worlds:
		for u: GameUnit in w.units.values():
			if u.has_meta("hero") and is_same(u.get_meta("hero"), h):
				return u
	return null
