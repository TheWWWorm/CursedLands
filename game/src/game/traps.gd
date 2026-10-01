class_name MagicTraps
extends RefCounted
## The zone's magic traps (.mob MAGIC_TRAP records), the original CMagicTrapObject
## (type 0x61): set up from the record, run
## the object update on every 55 ms server tick. Host only; the
## casts reach the clients as "spellfx" events.
##
## - Active = object flag (+8), set by the constructor
##   script ActivateTrap(trap, 0 / 1) clears / sets it.
## - Interval < 1: the trap remembers the units it has seen; a
##   unit that is dead or outside every area is forgotten, a new unit in an
##   area is cast at once.
## - Interval >= 1: a countdown runs down by one per tick; at < 1
##    casts at the units in the areas, and a cast restarts it
##   the interval. With nobody there it stays at 0 (the next unit is hit at once).
## - Units in an area: alive, within the radius of the area's
##   centre, and whose player's bit is set in the trap's player mask (-1 = all).
##   A unit standing in two areas is listed twice.
## - The cast: a spell that does not target a unit (spells.sdb
##   target != 117), on a trap with target points, goes from the trap to each
##   point; otherwise at each listed unit (with LEVER_CAST_ONCE only the last
##   one). Every cast is with no caster (Spells.cast_from).

var world: GameWorld
var traps := {}   # nid -> {pos, spell, mask, areas, targets, interval, once, active, timer, seen}


func _init(w: GameWorld) -> void:
	world = w


## Registers a MAGIC_TRAP record; the defaults are those of the
## record constructor (all players, interval 15).
func add(o: Dictionary) -> void:
	var nid := int(o.get("nid", 0))
	var p: Vector3 = o.get("position", Vector3.ZERO)
	traps[nid] = {"pos": p, "spell": String(o.get("trap_spell", "")), "mask": int(o.get("trap_players", -1)),
		"areas": Array(o.get("trap_areas", [])), "targets": Array(o.get("trap_targets", [])),
		"interval": int(o.get("trap_interval", 15)), "once": int(o.get("cast_once", 0)) != 0,
		"active": true, "timer": 0, "seen": []}


## Script ActivateTrap (builtin 0x95): flag on / off.
func set_active(nid: int, on: bool) -> void:
	if traps.has(nid):
		traps[nid].active = on


func save_state() -> Dictionary:
	var out := {}
	for nid in traps:
		out[nid] = [traps[nid].active, traps[nid].timer]
	return out


func restore_state(s: Dictionary) -> void:
	for nid in s:
		if traps.has(int(nid)):
			traps[int(nid)].active = bool(s[nid][0])
			traps[int(nid)].timer = int(s[nid][1])


## One 55 ms server tick.
func tick() -> void:
	for nid in traps:
		var t: Dictionary = traps[nid]
		if String(t.spell).is_empty():
			continue
		if int(t.interval) < 1:
			_tick_on_entry(t)
			continue
		if int(t.timer) > 0:
			t.timer = int(t.timer) - 1
		if int(t.timer) < 1 and t.active:
			_fire(t, _units_in(t))


func _tick_on_entry(t: Dictionary) -> void:
	var seen: Array = t.seen
	for u in seen.duplicate():
		if not is_instance_valid(u) or u.dead or not _in_areas(t, u):
			seen.erase(u)
	if not t.active:
		return
	var fresh := []
	for u: GameUnit in _units_in(t):
		if not u in seen:
			seen.append(u)
			fresh.append(u)
	if not fresh.is_empty():
		_fire(t, fresh)


func _units_in(t: Dictionary) -> Array:
	var out := []
	var mask := int(t.mask)
	for a: Vector3 in t.areas:
		for u: GameUnit in world.units_near(Vector2(a.x, a.y), a.z):
			if not u.dead and u.faction >= 0 and u.faction < 32 and (mask & (1 << u.faction)) != 0:
				out.append(u)
	return out


func _in_areas(t: Dictionary, u: GameUnit) -> bool:
	for a: Vector3 in t.areas:
		if u.pos.distance_squared_to(Vector2(a.x, a.y)) < a.z * a.z:
			return true
	return false


func _fire(t: Dictionary, list: Array) -> void:
	if list.is_empty():
		return
	var from := Vector2(t.pos.x, t.pos.y)
	# The source height: the trap's z + the map's height there (map
	# ), as objects stand on the ground.
	var from_z: float = t.pos.z + (world.terrain.height_at(from.x, from.y) if world.terrain else 0.0)
	var sp := Spells.parse(String(t.spell))
	var unit_spell := int(sp.proto.get("target", 117)) == 117
	if not unit_spell and not t.targets.is_empty():
		for p: Vector2 in t.targets:
			Spells.cast_from(world, String(t.spell), from, null, p, from_z)
	else:
		if t.once:
			list = [list[-1]]
		for u: GameUnit in list:
			Spells.cast_from(world, String(t.spell), from, u, u.pos, from_z)
	t.timer = int(t.interval)
