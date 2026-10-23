class_name ObjectActivity
extends RefCounted
## The original's active-object set in campaign zones. In a zone of type
## "game" (map.txt; base 57c460 sets world mode 1) the server updates only
## the objects in its active set (world +0x104, loop 58d670); the other modes
## (edge, brief) update every object. Traced 2026-10-22:
##
## - Wake pass (58dff0), every server tick before the objects update: around
##   each unit of every player, 58d3d0 wakes every object in the 32 m grid
##   cells at offset (dx, dy), |dx|, |dy| <= 10, for which
##   sqrt(max(|dx|-1, 0)^2 + max(|dy|-1, 0)^2) < r / 32, with
##   r = 2 * max(sight x sight factor, life sense) + 20. There is no
##   per-object distance test. Waking sets the object's counter (+0x174) to
##   128 + ((object >> 5) & 15) ticks and adds it to the set.
## - Update loop: every member is updated. A unit's counter runs down by one
##   a tick; at 0 it stays (counter re-armed) while it is alert (attack
##   stance), its MOB logic has always-active (flags bit 3) or its noticed
##   list holds a living enemy; otherwise it leaves the set and is frozen
##   until woken again. Other objects (magic traps) never leave once woken.
## - Other wakes: an attacked unit (553f40 -> 58d5d0); every tick of
##   fireworks and clairvoyance, the objects within the spell's radius + 5 m
##   (6830d3, 6832d2); possession (683456, case 0x15) is not cast in the
##   remake.
## - Loading: a zone's .mob arms its always-active units and its levers
##   (record kind 8; the remake updates levers always); a saved zone (game
##   load, zone revisit) arms those units and every non-unit object.
##   Objects created during play start awake. A revisited zone first runs
##   the absence simulation (57a48a, Session._simulate_absence).
##
## Frozen units do nothing: no movement, decisions, chatter, step noise or
## regeneration. A far patrol keeps its post until the party comes near.
## The remake keeps party units, corpses and conversation actors updating.

## Counter cell size and maximum cell offset of the wake pass.
const CELL := 32.0
const REACH := 10
const AWAKE := 128

var world: GameWorld
var enabled := false
## A saved zone: its magic traps start awake.
var restored := false
var _armed := false
var _timer := {}         # uid -> ticks left
var _traps := {}         # nid -> true (awake)


func _init(w: GameWorld) -> void:
	world = w


## Native counter spread ((object >> 5) & 15); the uid stands in for the
## object address.
static func _rearm(u: GameUnit) -> int:
	return AWAKE + ((u.uid * 7) & 15)


## Whether this world keeps an active set (a campaign "game" zone on the
## authority).
func applies() -> bool:
	return world.authority and String(world.zone.get("type", "")) == "game"


## On the first server tick, once the zone is built: the zone's own units
## are frozen unless always active.
func _arm() -> void:
	_armed = true
	enabled = applies()
	if not enabled:
		return
	for u: GameUnit in world.unit_rows():
		if bool(u.info.get("always_active", false)):
			_timer[u.uid] = _rearm(u)
	if restored and world.traps:
		for nid in world.traps.traps:
			_traps[nid] = true
	world.unit_spawned.connect(_on_spawned)


func _on_spawned(u: GameUnit) -> void:
	_timer[u.uid] = _rearm(u)


## True when the unit is updated this tick.
func is_awake(u: GameUnit) -> bool:
	if not enabled or u.controller >= 0 or u.dead:
		return true
	return _timer.has(u.uid) or world.dialog_movers.has(u) or world.dialog_actors.has(u)


func trap_awake(nid: int) -> bool:
	return not enabled or _traps.has(nid)


## The wake pass of one server tick.
func wake() -> void:
	if not _armed:
		_arm()
	if not enabled:
		return
	var cells := {}
	for u: GameUnit in world.unit_rows():
		if u.controller >= 0:
			_add_cells(cells, u.pos, wake_radius(u))
	_wake_cells(cells)


## 58d3d0 around a point: the absence simulation and area effects.
func wake_at(p: Vector2, r: float) -> void:
	if not _armed:
		_arm()
	if not enabled:
		return
	var cells := {}
	_add_cells(cells, p, r)
	_wake_cells(cells)


## 58d5d0: one object, as an attacked unit (UnitAI.hit_hook).
func wake_unit(u: GameUnit) -> void:
	if not _armed:
		_arm()
	if enabled:
		_timer[u.uid] = _rearm(u)


func wake_radius(u: GameUnit) -> float:
	var sight := (float(u.stats.get("sight", 0.0)) + u.sense_bonus(0)) * u.sight_factor()
	return 2.0 * maxf(sight, u.sense(2)) + 20.0


## The included cell offsets for a radius (they depend on r / 32 only).
static var _offsets := {}

static func _add_cells(cells: Dictionary, p: Vector2, r: float) -> void:
	var c := _cell(p)
	var offs: Array = _offsets.get(r, [])
	if not _offsets.has(r):
		var lim := r / CELL
		for dy in range(-REACH, REACH + 1):
			var ey := maxf(absf(dy) - 1.0, 0.0)
			for dx in range(-REACH, REACH + 1):
				var ex := maxf(absf(dx) - 1.0, 0.0)
				if sqrt(ex * ex + ey * ey) < lim:
					offs.append(Vector2i(dx, dy))
		if _offsets.size() > 256: _offsets.clear()
		_offsets[r] = offs
	for o: Vector2i in offs:
		cells[c + o] = true


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _wake_cells(cells: Dictionary) -> void:
	if cells.is_empty():
		return
	for u: GameUnit in world.unit_rows():
		if cells.has(_cell(u.pos)):
			_timer[u.uid] = _rearm(u)
	if world.traps:
		for nid in world.traps.traps:
			if not _traps.has(nid):
				var p: Vector3 = world.traps.traps[nid].pos
				if cells.has(_cell(Vector2(p.x, p.y))):
					_traps[nid] = true


## After the objects updated: run the units' counters down; a unit at 0
## stays only while it is alert, always active or knows a living enemy.
func expire() -> void:
	if not enabled or _timer.is_empty():
		return
	for uid in _timer.keys():
		var u: GameUnit = world.units.get(uid)
		if u == null:
			_timer.erase(uid)
			continue
		var left := int(_timer[uid]) - 1
		if left > 0:
			_timer[uid] = left
		elif u.alert or bool(u.info.get("always_active", false)) or _knows_enemy(u):
			_timer[uid] = _rearm(u)
		else:
			_timer.erase(uid)
			# The figure is drawn on the world clock: a unit frozen mid-step
			# stands instead of walking in place. Its order and path remain,
			# and the next move step sets the walk again.
			if u.action in ["walk", "run", "crawl"]:
				u._set_action("idle")


func _knows_enemy(u: GameUnit) -> bool:
	for o in u.get_meta("noticed", {}).values():
		if is_instance_valid(o) and o is GameUnit and not o.dead and world.is_enemy(u, o):
			return true
	return false


## Test and console view: the uids of the awake units.
func awake_uids() -> Array:
	return _timer.keys()
