class_name SmileFaces
extends RefCounted
## Remake option "smile_faces" (on by default, user request): the party
## portraits' smile (texture suffix "a", 4 s, ui/portrait.gd) also after
##   * a won fight: the last hostile that was fighting a player's party dies
##     or flees and none is engaged any more — that player's living party
##     members smile;
##   * loot taken from a body or chest (items or money) — the looting hero; a
##     co-op player who gets a shared copy (coop_share_loot) — their hero;
##   * a successful theft (Session.steal took items or money) — the thief;
##   * a finished quest (its journal var set to 2, script QuestComplete) — the
##     whole party; a briefing's reward — the talking player's party.
## Off: as the original, the smile comes only with the Kill acknowledgement
## 0x30, which this file does not touch.
## The host finds the moments and broadcasts {"t": "smile", "to": player
## (-1 every player)} or {"t": "smile", "uid": hero}; each peer's faces are
## local, so the receiving peer's own option decides (Game.on_event).
## A hit still shows pain ("c") at once (Portrait._update_expression).

const OPTION := "smile_faces"
const CODE := 0x30          # the Kill acknowledgement's face (Portrait.acknowledge)
const CHECK := 0.25         # s between the host's fight checks (Session tick)
const QUIET := 2            # checks without an engaged hostile that end a fight
const NEAR := 15.0          # m: a foe of the fight still this close, not fleeing, is not beaten


static func on() -> bool:
	return GameData.option(OPTION) != 0


# ------------------------------------------------------------------ host

## Host: the party of `player` (-1 every player's) smiles.
static func party(s: Session, player := -1) -> void:
	if s:
		s.broadcast({"t": "smile", "to": player})


## Host: one hero smiles.
static func unit(s: Session, u: GameUnit) -> void:
	if s and u and is_instance_valid(u) and u.controller >= 0:
		s.broadcast({"t": "smile", "uid": u.uid})


## Host, every CHECK s: per player, the hostiles engaged with its party (an
## attack / cast order on one of its units, or one of its units' target).
## A fight ends after QUIET checks with none; it is won when a foe of the
## fight died or flees and no other foe stands near the party unbeaten.
static func battle_tick(s: Session) -> void:
	var w := s.world
	if w == null or not w.authority:
		return
	var fights: Dictionary = w.get_meta("smile_fights", {})
	var engaged := {}   # player -> {uid: unit}
	for o: GameUnit in w.units.values():
		if not is_instance_valid(o) or o.dead:
			continue
		var t := GameSound._act_target(o)
		if t == null or t.dead:
			continue
		if o.controller < 0 and t.controller >= 0 and w.is_enemy(o, t) and not UnitAI.fearful(o):
			(engaged.get_or_add(t.controller, {}) as Dictionary)[o.uid] = o
		elif o.controller >= 0 and t.controller < 0 and w.is_enemy(o, t):
			(engaged.get_or_add(o.controller, {}) as Dictionary)[t.uid] = t
	for p in engaged:
		var f: Dictionary = fights.get_or_add(p, {"foes": {}, "quiet": 0})
		f.foes.merge(engaged[p])
		f.quiet = 0
	for p in fights.keys():
		if engaged.has(p):
			continue
		var f: Dictionary = fights[p]
		f.quiet += 1
		if f.quiet < QUIET:
			continue
		fights.erase(p)
		if _won(w, int(p), f.foes):
			party(s, int(p))
	w.set_meta("smile_fights", fights)


static func _won(w: GameWorld, p: int, foes: Dictionary) -> bool:
	var beaten := false
	var mine: Array = w.units.values().filter(func(u: GameUnit): return u.controller == p and not u.dead)
	if mine.is_empty():
		return false
	for id in foes:
		var o = foes[id]
		if not is_instance_valid(o) or o.dead or w.units.get(id) != o or UnitAI.fearful(o):
			beaten = true
			continue
		for m: GameUnit in mine:
			if m.pos.distance_to(o.pos) <= NEAR and w.is_enemy(o, m):
				return false   # the party broke off; the foe is still there
	return beaten


# ------------------------------------------------------------------ peers

## Game.on_event "smile": this peer's own faces, with its own option.
static func show(game: Game, e: Dictionary) -> void:
	if not on() or game == null or game.hud == null or game.hud._faces == null:
		return
	if e.has("uid"):
		var u: GameUnit = game.world.units.get(int(e.uid)) if game.world else null
		if u and not u.dead:
			game.hud._faces.acknowledge(u, CODE)
		return
	var to := int(e.get("to", -1))
	if to >= 0 and to != game.session.my_index:
		return
	for u in game.my_units():
		game.hud._faces.acknowledge(u, CODE)


## Session "loot_copy" for this peer: its main hero smiles at the copy.
static func copy(game: Game) -> void:
	if game == null or game.world == null:
		return
	for u in game.my_units():
		if u.has_meta("hero") and not (u.get_meta("hero") as Dictionary).has("merc"):
			show(game, {"uid": u.uid})
			return
