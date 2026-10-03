class_name Revive
extends RefCounted
## Remake option "revive" (off by default; the original has no way back for a
## dead party member in single player — no spell, scroll or script builtin
## raises the dead; only the network game's respawn at a zone change,
## makes a dead hero whole again).
##
## A living party member (any player's in co-op) is ordered onto the body of a
## dead hero or hired mercenary of the party (a left click on it, Game._click
## → command "revive", host-authoritative through Session.apply_command). It
## walks there like a loot approach, kneels and works at the body for SECS
## seconds (the use action with the science clip, GameUnit._do_use sub
## "revive"), then the body rises with 1 HP (GameUnit.rise). It stops when the
## reviver gets another order or dies, or when the body is removed or moved.
## Not in the multiplayer (LMP) game, which has its own respawn rules.

const OPTION := "revive"
const SECS := 5.0
## The total health the risen unit has (its parts set so, GameUnit.rise).
const RISE_HP := 1.0
## How far the body may have been moved before the work stops.
const MOVED := 0.75


## The option is on (the host's in co-op) and the game is not the multiplayer one.
static func enabled(s: Session) -> bool:
	if s == null or not s.lmp.is_empty():
		return false
	# A co-op client follows the host's setting (sent with Session.sync_state).
	return (GameData.option(OPTION) if s.is_host else int(s.get_meta("host_revive", 0))) == 1


## A dead party member (hero or hired mercenary of any player) that can be
## brought back.
static func revivable(s: Session, t: GameUnit) -> bool:
	return enabled(s) and t != null and is_instance_valid(t) and t.dead and t.controller >= 0 \
		and t.has_meta("hero") and not t.has_meta("lmp_owner") and s.world != null \
		and s.world.units.get(t.uid) == t


## Whether some living party unit could revive `t` (the death notice says so).
static func helper_present(s: Session, t: GameUnit) -> bool:
	if not revivable(s, t):
		return false
	for u: GameUnit in s.world.units.values():
		if can_help(u, t):
			return true
	return false


## A unit that can do the work: a living hero or mercenary of the party (not
## a tamed animal).
static func can_help(u: GameUnit, t: GameUnit) -> bool:
	return u != null and u != t and not u.dead and not u.hidden and u.controller >= 0 and u.has_meta("hero")


## Host: command "revive" — the selected unit nearest to the body walks to it
## and starts the work on arrival (ScriptVM._check_interactions).
static func order(s: Session, mine: Array, t: GameUnit, player: int, run := false) -> void:
	if not revivable(s, t):
		return
	var best: GameUnit = null
	for u: GameUnit in mine:
		if can_help(u, t) and (best == null or u.pos.distance_to(t.pos) < best.pos.distance_to(t.pos)):
			best = u
	if best == null:
		return
	var r := maxf(0.3, s.world.vm._interact_reach(best, t) - 0.1) if s.world.vm else 1.0
	s._double_stand(best, {"run": run}, t.pos, r)
	best.command({"type": "follow", "target": t, "dist": r, "once": true, "corpse": true, "run": run})
	best.set_meta("interact", [t, player, "revive"])


## Host: the reviver reached the body — the use action that holds the clip.
static func begin(s: Session, u: GameUnit, t: GameUnit) -> void:
	if not revivable(s, t):
		return
	var at := t.pos
	u.command({"type": "use", "sub": "revive", "at": at, "hold": SECS,
		"check": func() -> bool:
			return revivable(s, t) and t.pos.distance_to(at) <= MOVED,
		"done": func():
			if is_instance_valid(u) and not u.dead and revivable(s, t):
				finish(s, t)})


## Host: the body rises with RISE_HP. A mercenary is the party's again (its
## record kept while it lay dead, see GameWorld.on_death).
static func finish(s: Session, t: GameUnit) -> void:
	t.rise(RISE_HP)
	var h: Dictionary = t.get_meta("hero")
	if h.has("merc"):
		var n := int(h.merc)
		h.erase("fallen")
		s.state.set_var(0, "adeadn%d" % n, 0.0)
		s.state.mercs[n] = h
	h.hp = t.hp
	h.erase("dead")
	s.broadcast({"t": "revived", "uid": t.uid})
	s.broadcast({"t": "party"})
	s.sync_state()


## Host, a party member died: a mercenary's record stays while the option is
## on (GameWorld.on_death erases it otherwise), marked "fallen".
static func keep_fallen(s: Session, u: GameUnit) -> bool:
	if not enabled(s) or not u.has_meta("hero") or not u.get_meta("hero").has("merc"):
		return false
	u.get_meta("hero").fallen = true
	return true


## The progress 0..1 of a revive shown by a unit's action ("revive:<clip>:<n>",
## n of PROGRESS_STEPS), -1 when it is not reviving.
const PROGRESS_STEPS := 20

static func progress(u: GameUnit) -> float:
	if u == null or not u.action.begins_with("revive:"):
		return -1.0
	return clampf(float(u.action.get_slice(":", 2)) / PROGRESS_STEPS, 0.0, 1.0)
