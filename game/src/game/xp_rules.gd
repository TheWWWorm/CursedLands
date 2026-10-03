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
## mercenaries and tamed animals, whose share is lost as they keep no record).


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
	var g := share * pow(1.04, float(h.get("int", 25.0)) + Perks.attr_bonus(h, "int") - 25.0)
	var d := g - float(h.get("exp_debt", 0.0))   #  holds the debt as a negative value
	var added := 0.0
	if d > 0.0:
		h.exp_debt = 0.0
		added = d
		h.exp = float(h.get("exp", 0.0)) + d
		h.exp_total = float(h.get("exp_total", 0.0)) + d
	else:
		h.exp_debt = -d
	if u and is_instance_valid(u):
		if not u.dead:   # a corpse keeps its pools (hero_stats would refill them)
			Combat.hero_stats(u, h)
		# the gain floats over the hero (cyan, flag 8, FlyingHP).
		s.broadcast({"t": "hitnum", "uid": u.uid, "n": roundi(g), "f": 8})
	return added


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
	for u: GameUnit in s.world.units.values():
		if not u.dead and party_of(u) == player:
			members.append(u)
	var out := []
	if members.is_empty():
		return out
	var share := amount if full else amount / members.size()
	for u: GameUnit in members:
		if u.has_meta("hero"):
			out.append([u, u.get_meta("hero"), share])
	return out


## Branch "network game": players with exactly one hero, weighted by sqrt of
## the hero's experience less its debt.
static func _network_split(s: Session, amount: float) -> Array:
	var rows := []
	var total := 0.0
	for p: Dictionary in s.players.values():
		var roster: Array = s.state.heroes.get(int(p.index), [])
		if roster.size() != 1:
			continue
		var h: Dictionary = roster[0]
		var unit := _unit_of(s, h)
		if unit == null:
			continue
		# Approx.: E < 0 (a debt above the experience) would be a NaN in the
		# original's FSQRT; taken as 0 here.
		var w := sqrt(maxf(float(h.get("exp_total", 0.0)) - float(h.get("exp_debt", 0.0)), 0.0))
		total += w
		rows.append([unit, h, w])
	var denom := total if total >= 0.01 else 0.01
	for r: Array in rows:
		r[2] = float(r[2]) * amount / denom
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
	for u: GameUnit in s.world.units.values():
		if u.has_meta("hero") and is_same(u.get_meta("hero"), h):
			return u
	return null
